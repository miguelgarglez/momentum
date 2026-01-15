import Foundation

enum RuntimeFlags {
    static func isDisabled(_ flag: RuntimeFlag) -> Bool {
        readBool(forKey: flag.rawValue)
    }

    private static func readBool(forKey key: String) -> Bool {
        if let envValue = ProcessInfo.processInfo.environment[key] {
            return parseBool(envValue)
        }
        if let value = UserDefaults.standard.object(forKey: key) {
            if let boolValue = value as? Bool {
                return boolValue
            }
            if let numberValue = value as? NSNumber {
                return numberValue.boolValue
            }
            if let stringValue = value as? String {
                return parseBool(stringValue)
            }
        }
        return false
    }

    private static func parseBool(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "1" || normalized == "true" || normalized == "yes"
    }
}

enum RuntimeFlag: String {
    case disableIdleCheck = "DISABLE_IDLE_CHECK"
    case disableHeartbeat = "DISABLE_HEARTBEAT"
    case disableBudgetMonitor = "DISABLE_BUDGET_MONITOR"
    case disableBackfill = "DISABLE_BACKFILL"
    case disableCrashRecovery = "DISABLE_CRASH_RECOVERY"
    case disableSwiftDataWrites = "DISABLE_SWIFTDATA_WRITES"
    case disableOverlayUpdates = "DISABLE_OVERLAY_UPDATES"
}
