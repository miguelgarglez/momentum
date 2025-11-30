import Foundation
import OSLog
import Darwin

@MainActor
protocol PerformanceBudgetMonitoring: AnyObject {
    @discardableResult
    func measure<T>(_ operation: String, work: () throws -> T) rethrows -> T
    func recordSample(_ sample: PerformanceBudgetMonitor.MetricSample)
}

/// A performance guardrail component that continuously monitors Momentum’s
/// resource usage and records lightweight CPU/I/O samples.
///
/// `PerformanceBudgetMonitor` serves three primary responsibilities:
/// 1. **Operation-level measurement** — When code is wrapped with `measure(_:work:)`,
///    the monitor captures CPU time and I/O deltas before and after the operation,
///    producing a `MetricSample`.
/// 2. **Periodic polling** — A scheduled timer takes regular resource snapshots,
///    generating background `poll` samples so the app has a continuous view of its
///    own performance over time.
/// 3. **Budget enforcement** — Each sample is evaluated against a configurable
///    CPU and I/O budget. Any overages are recorded as `Violation` instances and
///    logged via `OSLog`, giving diagnostics and crash recovery layers visibility
///    into unexpected load.
///
/// This monitor is designed to be safe for production, lightweight, testable via
/// dependency injection, and replaceable with `NoopPerformanceBudgetMonitor` when
/// measurement is not desired (e.g., in unit tests).
@MainActor
final class PerformanceBudgetMonitor: ObservableObject, PerformanceBudgetMonitoring {
    struct Budget {
        let cpuFraction: Double
        let ioBytesPerSecond: Double

        static let `default` = Budget(cpuFraction: 0.03, ioBytesPerSecond: 32_000)
    }

    struct MetricSample: Identifiable, Equatable {
        enum Source: Equatable {
            case poll
            case operation(String)
        }

        let id = UUID()
        let timestamp: Date
        let duration: TimeInterval
        let cpuLoad: Double
        let ioBytesPerSecond: Double
        let source: Source
    }

    struct Violation: Identifiable, Equatable {
        enum Kind: Equatable {
            case cpu(Double)
            case io(Double)
        }

        let id = UUID()
        let sample: MetricSample
        let kind: Kind
    }

    @Published private(set) var recentSamples: [MetricSample] = []
    @Published private(set) var violations: [Violation] = []

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momentum", category: "PerformanceBudget")
    private let budget: Budget
    private let metricsSource: ResourceMetricsSource
    private let maxSamples = 60
    private let pollInterval: TimeInterval
    private var pollTimer: Timer?
    private var lastPollSnapshot: ResourceSnapshot?

    init(
        budget: Budget = .default,
        metricsSource: ResourceMetricsSource = MachResourceMetricsSource(),
        pollInterval: TimeInterval = 30
    ) {
        self.budget = budget
        self.metricsSource = metricsSource
        self.pollInterval = pollInterval
        schedulePolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    @discardableResult
    func measure<T>(_ operation: String, work: () throws -> T) rethrows -> T {
        let start = metricsSource.snapshot()
        let value = try work()
        let end = metricsSource.snapshot()
        recordSnapshot(start: start, end: end, label: operation)
        return value
    }

    func recordSample(_ sample: MetricSample) {
        recentSamples.append(sample)
        if recentSamples.count > maxSamples {
            recentSamples.removeFirst(recentSamples.count - maxSamples)
        }
    }

    private func schedulePolling() {
        pollTimer?.invalidate()
        guard pollInterval > 0 else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePollTick()
            }
        }
        if lastPollSnapshot == nil {
            lastPollSnapshot = metricsSource.snapshot()
        }
    }

    private func handlePollTick() {
        let snapshot = metricsSource.snapshot()
        defer { lastPollSnapshot = snapshot }
        guard let previous = lastPollSnapshot else { return }
        recordSnapshot(start: previous, end: snapshot, label: nil)
    }

    private func recordSnapshot(start: ResourceSnapshot, end: ResourceSnapshot, label: String?) {
        guard end.timestamp > start.timestamp else { return }
        let duration = end.timestamp.timeIntervalSince(start.timestamp)
        guard duration > 0 else { return }
        let cpuDelta = max(0, end.cpuTime - start.cpuTime)
        let cpuLoad = cpuDelta / duration
        let ioDelta = end.ioBytes >= start.ioBytes ? end.ioBytes - start.ioBytes : 0
        let ioRate = Double(ioDelta) / duration
        let sample = MetricSample(
            timestamp: end.timestamp,
            duration: duration,
            cpuLoad: cpuLoad,
            ioBytesPerSecond: ioRate,
            source: label.map { .operation($0) } ?? .poll
        )
        recordSample(sample)
        evaluate(sample)
    }

    private func evaluate(_ sample: MetricSample) {
        if sample.cpuLoad > budget.cpuFraction {
            let violation = Violation(sample: sample, kind: .cpu(sample.cpuLoad))
            violations.append(violation)
            logger.error("CPU budget exceeded by \(String(format: "%.2f", sample.cpuLoad * 100))%")
        }
        if sample.ioBytesPerSecond > budget.ioBytesPerSecond {
            let violation = Violation(sample: sample, kind: .io(sample.ioBytesPerSecond))
            violations.append(violation)
            logger.error("I/O budget exceeded: \(sample.ioBytesPerSecond, privacy: .public) B/s")
        }
    }
}

// MARK: - Metrics source

struct ResourceSnapshot {
    let timestamp: Date
    let cpuTime: TimeInterval
    let ioBytes: UInt64
}

protocol ResourceMetricsSource {
    func snapshot() -> ResourceSnapshot
}

struct MachResourceMetricsSource: ResourceMetricsSource {
    func snapshot() -> ResourceSnapshot {
        ResourceSnapshot(timestamp: Date(), cpuTime: cpuTime(), ioBytes: ioBytes())
    }

    private func cpuTime() -> TimeInterval {
        var info = task_thread_times_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let user = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
        let system = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
        return user + system
    }

    private func ioBytes() -> UInt64 {
        var usage = rusage_info_current()
        let result: Int32 = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { pointer in
                proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, pointer)
            }
        }
        guard result == 0 else { return 0 }
        return usage.ri_diskio_bytesread + usage.ri_diskio_byteswritten
    }
}

@MainActor
final class NoopPerformanceBudgetMonitor: PerformanceBudgetMonitoring {
    func measure<T>(_ operation: String, work: () throws -> T) rethrows -> T {
        try work()
    }

    func recordSample(_ sample: PerformanceBudgetMonitor.MetricSample) {
        // no-op
    }
}
