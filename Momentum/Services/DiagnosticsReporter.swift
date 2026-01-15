import Foundation

@MainActor
final class DiagnosticsReporter {
    private let interval: TimeInterval
    private let metricsSource: ResourceMetricsSource
    private let fileHandle: FileHandle
    private var timer: Timer?
    private var lastSnapshot: ResourceSnapshot?
    private var lastCounters: [CounterKey: Int] = [:]

    init(
        interval: TimeInterval = 15,
        metricsSource: ResourceMetricsSource = MachResourceMetricsSource()
    ) {
        self.interval = interval
        self.metricsSource = metricsSource

        let logURL = DiagnosticsReporter.makeLogURL()
        DiagnosticsReporter.ensureLogDirectory(for: logURL)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        fileHandle = try! FileHandle(forWritingTo: logURL)
        fileHandle.seekToEndOfFile()

        writeHeaderIfNeeded()
        lastSnapshot = metricsSource.snapshot()
        lastCounters = Diagnostics.snapshot()
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        writeSummary()
        try? fileHandle.close()
    }

    private func startTimer() {
        let safeInterval = max(1, interval)
        let timer = Timer.scheduledTimer(withTimeInterval: safeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        timer.tolerance = safeInterval * 0.1
        self.timer = timer
    }

    private func tick() {
        guard Diagnostics.isEnabled else { return }
        let snapshot = metricsSource.snapshot()
        let counters = Diagnostics.snapshot()
        defer {
            lastSnapshot = snapshot
            lastCounters = counters
        }
        guard let previous = lastSnapshot, snapshot.timestamp > previous.timestamp else { return }
        let duration = snapshot.timestamp.timeIntervalSince(previous.timestamp)
        guard duration > 0 else { return }

        let cpuDelta = max(0, snapshot.cpuTime - previous.cpuTime)
        let cpuLoad = cpuDelta / duration
        let ioDelta = snapshot.ioBytes >= previous.ioBytes ? snapshot.ioBytes - previous.ioBytes : 0
        let ioRate = Double(ioDelta) / duration

        var deltas: [CounterKey: Int] = [:]
        for key in CounterKey.allCases {
            let last = lastCounters[key, default: 0]
            let current = counters[key, default: 0]
            deltas[key] = max(0, current - last)
        }

        writeLine(
            timestamp: snapshot.timestamp.timeIntervalSince1970,
            duration: duration,
            cpuLoad: cpuLoad,
            ioRate: ioRate,
            deltas: deltas
        )
    }

    private func writeHeaderIfNeeded() {
        let path = DiagnosticsReporter.makeLogURL().path
        let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size == 0 else { return }

        let header = [
            "timestamp",
            "interval_s",
            "cpu_fraction",
            "io_bytes_per_s",
        ] + CounterKey.allCases.map(\.rawValue)
        writeString(header.joined(separator: ",") + "\n")
    }

    private func writeLine(
        timestamp: TimeInterval,
        duration: TimeInterval,
        cpuLoad: Double,
        ioRate: Double,
        deltas: [CounterKey: Int]
    ) {
        var columns: [String] = []
        columns.reserveCapacity(4 + CounterKey.allCases.count)
        columns.append(String(format: "%.3f", timestamp))
        columns.append(String(format: "%.3f", duration))
        columns.append(String(format: "%.6f", cpuLoad))
        columns.append(String(format: "%.3f", ioRate))
        for key in CounterKey.allCases {
            columns.append(String(deltas[key, default: 0]))
        }
        writeString(columns.joined(separator: ",") + "\n")
    }

    private func writeSummary() {
        guard Diagnostics.isEnabled else { return }
        let counters = Diagnostics.snapshot()
        var columns: [String] = ["#summary"]
        columns.append("timestamp=\(String(format: "%.3f", Date().timeIntervalSince1970))")
        for key in CounterKey.allCases {
            columns.append("\(key.rawValue)=\(counters[key, default: 0])")
        }
        writeString(columns.joined(separator: " ") + "\n")
    }

    private func writeString(_ string: String) {
        if let data = string.data(using: .utf8) {
            try? fileHandle.write(contentsOf: data)
        }
    }

    private static func makeLogURL() -> URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Logs/Momentum/diagnostics.csv")
    }

    private static func ensureLogDirectory(for url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
