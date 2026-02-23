import Foundation
import SwiftUI

enum AssignmentRuleExpirationOption: String, CaseIterable, Identifiable {
    case never = "never"
    case minutes15 = "minutes15"
    case minutes30 = "minutes30"
    case hour1 = "hour1"
    case hours4 = "hours4"
    case hours8 = "hours8"
    case day1 = "day1"
    case days7 = "days7"
    case days30 = "days30"
    case days60 = "days60"
    case days90 = "days90"

    var id: String { rawValue }

    var expirationInterval: TimeInterval? {
        switch self {
        case .minutes15:
            15 * 60
        case .minutes30:
            30 * 60
        case .hour1:
            60 * 60
        case .hours4:
            4 * 60 * 60
        case .hours8:
            8 * 60 * 60
        case .day1:
            24 * 60 * 60
        case .days7:
            7 * 24 * 60 * 60
        case .days30:
            30 * 24 * 60 * 60
        case .days60:
            60 * 24 * 60 * 60
        case .days90:
            90 * 24 * 60 * 60
        case .never:
            nil
        }
    }

    var label: String {
        switch self {
        case .minutes15:
            String(localized: "15 min")
        case .minutes30:
            String(localized: "30 min")
        case .hour1:
            String(localized: "1 hora")
        case .hours4:
            String(localized: "4 horas")
        case .hours8:
            String(localized: "8 horas")
        case .day1:
            String(localized: "1 día")
        case .days7:
            String(localized: "7 días")
        case .days30:
            String(localized: "30 días")
        case .days60:
            String(localized: "60 días")
        case .days90:
            String(localized: "90 días")
        case .never:
            String(localized: "Nunca")
        }
    }

    func cutoffDate(from date: Date = .now) -> Date? {
        guard let expirationInterval else { return nil }
        return date.addingTimeInterval(-expirationInterval)
    }
}

enum AppThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:
            String(localized: "Sistema")
        case .light:
            String(localized: "Claro")
        case .dark:
            String(localized: "Oscuro")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
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

    @Published var isFileTrackingEnabled: Bool {
        didSet {
            defaults.set(isFileTrackingEnabled, forKey: Keys.files)
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

    @Published var excludedFiles: [String] {
        didSet {
            let sanitized = TrackerSettings.sanitize(entries: excludedFiles)
            if sanitized != excludedFiles {
                excludedFiles = sanitized
                return
            }
            defaults.set(excludedFiles, forKey: Keys.excludedFiles)
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

    @Published var isRaycastIntegrationEnabled: Bool {
        didSet {
            defaults.set(isRaycastIntegrationEnabled, forKey: Keys.raycastIntegrationEnabled)
        }
    }

    @Published var themePreference: AppThemePreference {
        didSet {
            defaults.set(themePreference.rawValue, forKey: Keys.themePreference)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedInterval = defaults.double(forKey: Keys.detection)
        detectionInterval = storedInterval == 0 ? 5 : storedInterval
        let storedIdle = defaults.double(forKey: Keys.idle)
        idleThreshold = storedIdle == 0 ? TimeInterval(15 * 60) : storedIdle
        isDomainTrackingEnabled = defaults.object(forKey: Keys.domains) as? Bool ?? true
        isFileTrackingEnabled = defaults.object(forKey: Keys.files) as? Bool ?? true
        excludedApps = TrackerSettings.readList(for: Keys.excludedApps, defaults: defaults)
        excludedDomains = TrackerSettings.readList(for: Keys.excludedDomains, defaults: defaults, lowercaseStorage: true)
        excludedFiles = TrackerSettings.readList(for: Keys.excludedFiles, defaults: defaults)
        isDatabaseEncryptionEnabled = defaults.object(forKey: Keys.encryptionEnabled) as? Bool ?? false
        if let rawValue = defaults.string(forKey: Keys.assignmentRuleExpiration),
           let option = AssignmentRuleExpirationOption(rawValue: rawValue)
        {
            assignmentRuleExpiration = option
        } else {
            assignmentRuleExpiration = .never
        }
        isRaycastIntegrationEnabled = defaults.object(forKey: Keys.raycastIntegrationEnabled) as? Bool ?? false
        if let rawValue = defaults.string(forKey: Keys.themePreference),
           let option = AppThemePreference(rawValue: rawValue)
        {
            themePreference = option
        } else {
            themePreference = .system
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

    func isFileExcluded(_ filePath: String?) -> Bool {
        guard let filePath, !filePath.isEmpty else { return false }
        let normalized = filePath.normalizedFilePath
        if normalized.isEmpty { return false }
        let normalizedPath = normalized.lowercased()
        let fileName = URL(fileURLWithPath: normalized).lastPathComponent.lowercased()

        for entry in excludedFiles {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lowered = trimmed.lowercased()
            if lowered.contains("/") || lowered.hasPrefix("~") {
                let expanded = (lowered as NSString).expandingTildeInPath
                let normalizedEntry = expanded.normalizedFilePath.lowercased()
                if !normalizedEntry.isEmpty, normalizedPath == normalizedEntry {
                    return true
                }
                continue
            }

            let suffix = lowered.hasPrefix("*") ? String(lowered.dropFirst()) : lowered
            if !suffix.isEmpty, fileName.hasSuffix(suffix) || normalizedPath.hasSuffix(suffix) {
                return true
            }
        }

        return false
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
        static let files = "tracker.trackFiles"
        static let excludedApps = "tracker.excludedApps"
        static let excludedDomains = "tracker.excludedDomains"
        static let excludedFiles = "tracker.excludedFiles"
        static let encryptionEnabled = "tracker.encryptionEnabled"
        static let assignmentRuleExpiration = "assignmentRules.expiration"
        static let raycastIntegrationEnabled = "integrations.raycast.enabled"
        static let themePreference = "app.themePreference"
    }
}
