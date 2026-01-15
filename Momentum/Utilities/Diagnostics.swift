import Foundation
import OSLog

enum Diagnostics {
    private static let envKey = "MOM_DIAG"
    private static let defaultsKey = "MOM_DIAG"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momentum", category: "Diagnostics")
    private static let signposter = OSSignposter(logger: logger)

    static var isEnabled: Bool {
        if let envValue = ProcessInfo.processInfo.environment[envKey] {
            return envValue == "1" || envValue.lowercased() == "true"
        }
        if let value = UserDefaults.standard.object(forKey: defaultsKey) {
            if let boolValue = value as? Bool {
                return boolValue
            }
            if let stringValue = value as? String {
                return stringValue == "1" || stringValue.lowercased() == "true"
            }
        }
        return false
    }

    @MainActor
    private static var counters: [CounterKey: Int] = [:]

    @MainActor
    static func increment(_ key: CounterKey) {
        guard isEnabled else { return }
        counters[key, default: 0] += 1
    }

    @MainActor
    static func snapshot() -> [CounterKey: Int] {
        guard isEnabled else { return [:] }
        var snapshot: [CounterKey: Int] = [:]
        for key in CounterKey.allCases {
            snapshot[key] = counters[key, default: 0]
        }
        return snapshot
    }

    @MainActor
    static func record(_ key: CounterKey, work: () -> Void) {
        guard isEnabled else {
            work()
            return
        }
        counters[key, default: 0] += 1
        let state = signposter.beginInterval(key.signpostName)
        work()
        signposter.endInterval(key.signpostName, state)
    }

    @MainActor
    static func record<T>(_ key: CounterKey, work: () throws -> T) rethrows -> T {
        guard isEnabled else {
            return try work()
        }
        counters[key, default: 0] += 1
        let state = signposter.beginInterval(key.signpostName)
        let value = try work()
        signposter.endInterval(key.signpostName, state)
        return value
    }
}

enum CounterKey: String, CaseIterable, Hashable {
    case idleCheckTick = "idle_check_tick"
    case heartbeatTick = "heartbeat_tick"
    case budgetPollTick = "budget_poll_tick"
    case backfillRun = "backfill_run"
    case crashRecoveryRun = "crash_recovery_run"
    case swiftDataFetch = "swiftdata_fetch"
    case swiftDataSave = "swiftdata_save"
    case overlayRefresh = "overlay_refresh"

    var signpostName: StaticString {
        switch self {
        case .idleCheckTick:
            "idle_check_tick"
        case .heartbeatTick:
            "heartbeat_tick"
        case .budgetPollTick:
            "budget_poll_tick"
        case .backfillRun:
            "backfill_run"
        case .crashRecoveryRun:
            "crash_recovery_run"
        case .swiftDataFetch:
            "swiftdata_fetch"
        case .swiftDataSave:
            "swiftdata_save"
        case .overlayRefresh:
            "overlay_refresh"
        }
    }
}
