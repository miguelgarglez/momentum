import Foundation

enum AssignmentRuleExpirationOption: String, CaseIterable, Identifiable {
    case never
    case days30
    case days60
    case days90

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .never:
            return nil
        case .days30:
            return 30
        case .days60:
            return 60
        case .days90:
            return 90
        }
    }

    var label: String {
        switch self {
        case .never:
            return "Nunca"
        case .days30:
            return "30 días"
        case .days60:
            return "60 días"
        case .days90:
            return "90 días"
        }
    }

    func cutoffDate(from date: Date = .now) -> Date? {
        guard let days else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: date)
    }
}

@MainActor
final class TrackerSettings: ObservableObject {
    static let minDetectionInterval: Double = 5
    static let maxDetectionInterval: Double = 15
    static let minIdleMinutes: Int = 1
    static let maxIdleMinutes: Int = 60

    @Published var detectionInterval: Double {
        didSet {
            let clamped = clamp(detectionInterval, min: Self.minDetectionInterval, max: Self.maxDetectionInterval)
            if detectionInterval != clamped {
                detectionInterval = clamped
                return
            }
            defaults.set(detectionInterval, forKey: Keys.detection)
        }
    }

    @Published var idleThreshold: TimeInterval {
        didSet {
            let clampedMinutes = clamp(Int(idleThreshold / 60), min: Self.minIdleMinutes, max: Self.maxIdleMinutes)
            let clampedValue = TimeInterval(clampedMinutes * 60)
            if idleThreshold != clampedValue {
                idleThreshold = clampedValue
                return
            }
            defaults.set(idleThreshold, forKey: Keys.idle)
        }
    }

    @Published var isDomainTrackingEnabled: Bool {
        didSet {
            defaults.set(isDomainTrackingEnabled, forKey: Keys.domains)
        }
    }

    @Published var excludedApps: [String] {
        didSet {
            let sanitized = TrackerSettings.sanitize(entries: excludedApps)
            if sanitized != excludedApps {
                excludedApps = sanitized
                return
            }
            defaults.set(excludedApps, forKey: Keys.excludedApps)
        }
    }

    @Published var excludedDomains: [String] {
        didSet {
            let sanitized = TrackerSettings.sanitize(entries: excludedDomains, lowercaseStorage: true)
            if sanitized != excludedDomains {
                excludedDomains = sanitized
                return
            }
            defaults.set(excludedDomains, forKey: Keys.excludedDomains)
        }
    }

    @Published var isDatabaseEncryptionEnabled: Bool {
        didSet {
            defaults.set(isDatabaseEncryptionEnabled, forKey: Keys.encryptionEnabled)
        }
    }

    @Published var assignmentRuleExpiration: AssignmentRuleExpirationOption {
        didSet {
            defaults.set(assignmentRuleExpiration.rawValue, forKey: Keys.assignmentRuleExpiration)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedInterval = defaults.double(forKey: Keys.detection)
        self.detectionInterval = storedInterval == 0 ? 5 : storedInterval
        let storedIdle = defaults.double(forKey: Keys.idle)
        self.idleThreshold = storedIdle == 0 ? TimeInterval(15 * 60) : storedIdle
        self.isDomainTrackingEnabled = defaults.object(forKey: Keys.domains) as? Bool ?? true
        self.excludedApps = TrackerSettings.readList(for: Keys.excludedApps, defaults: defaults)
        self.excludedDomains = TrackerSettings.readList(for: Keys.excludedDomains, defaults: defaults, lowercaseStorage: true)
        self.isDatabaseEncryptionEnabled = defaults.object(forKey: Keys.encryptionEnabled) as? Bool ?? false
        if let rawValue = defaults.string(forKey: Keys.assignmentRuleExpiration),
           let option = AssignmentRuleExpirationOption(rawValue: rawValue) {
            self.assignmentRuleExpiration = option
        } else {
            self.assignmentRuleExpiration = .never
        }
    }

    var idleThresholdMinutes: Int {
        get { Int(idleThreshold / 60) }
        set { idleThreshold = TimeInterval(clamp(newValue, min: Self.minIdleMinutes, max: Self.maxIdleMinutes) * 60) }
    }

    func isAppExcluded(_ bundleIdentifier: String?) -> Bool {
        guard let value = bundleIdentifier?.lowercased() else { return false }
        return excludedApps.contains { $0.lowercased() == value }
    }

    func isDomainExcluded(_ domain: String?) -> Bool {
        guard let value = domain?.lowercased(), !value.isEmpty else { return false }
        return excludedDomains.contains { value.contains($0) }
    }

    private func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        Swift.min(Swift.max(value, min), max)
    }

    private static func sanitize(entries: [String], lowercaseStorage: Bool = false) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for entry in entries {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(lowercaseStorage ? key : trimmed)
            }
        }
        return result
    }

    private static func readList(for key: String, defaults: UserDefaults, lowercaseStorage: Bool = false) -> [String] {
        guard let list = defaults.array(forKey: key) as? [String] else { return [] }
        return sanitize(entries: list, lowercaseStorage: lowercaseStorage)
    }

    private enum Keys {
        static let detection = "tracker.detectionInterval"
        static let idle = "tracker.idleThreshold"
        static let domains = "tracker.trackDomains"
        static let excludedApps = "tracker.excludedApps"
        static let excludedDomains = "tracker.excludedDomains"
        static let encryptionEnabled = "tracker.encryptionEnabled"
        static let assignmentRuleExpiration = "assignmentRules.expiration"
    }
}
