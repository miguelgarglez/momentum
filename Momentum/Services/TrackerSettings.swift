import Foundation

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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedInterval = defaults.double(forKey: Keys.detection)
        self.detectionInterval = storedInterval == 0 ? 5 : storedInterval
        let storedIdle = defaults.double(forKey: Keys.idle)
        self.idleThreshold = storedIdle == 0 ? TimeInterval(15 * 60) : storedIdle
        self.isDomainTrackingEnabled = defaults.object(forKey: Keys.domains) as? Bool ?? true
    }

    var idleThresholdMinutes: Int {
        get { Int(idleThreshold / 60) }
        set { idleThreshold = TimeInterval(clamp(newValue, min: Self.minIdleMinutes, max: Self.maxIdleMinutes) * 60) }
    }

    private func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        Swift.min(Swift.max(value, min), max)
    }

    private enum Keys {
        static let detection = "tracker.detectionInterval"
        static let idle = "tracker.idleThreshold"
        static let domains = "tracker.trackDomains"
    }
}
