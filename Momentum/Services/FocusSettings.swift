import Foundation

@MainActor
@Observable
final class FocusSettings {
    private let defaults: UserDefaults

    private enum Key {
        static let idlePauseEnabled = "focus.idlePauseEnabled"
        static let idleThresholdMinutes = "focus.idleThresholdMinutes"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Key.idlePauseEnabled) == nil {
            defaults.set(true, forKey: Key.idlePauseEnabled)
        }
        if defaults.object(forKey: Key.idleThresholdMinutes) == nil {
            defaults.set(5, forKey: Key.idleThresholdMinutes)
        }
    }

    var isIdlePauseEnabled: Bool {
        get { defaults.bool(forKey: Key.idlePauseEnabled) }
        set { defaults.set(newValue, forKey: Key.idlePauseEnabled) }
    }

    var idleThresholdMinutes: Int {
        get {
            let value = defaults.integer(forKey: Key.idleThresholdMinutes)
            return value > 0 ? value : 5
        }
        set { defaults.set(max(1, newValue), forKey: Key.idleThresholdMinutes) }
    }

    var idleThreshold: TimeInterval {
        TimeInterval(idleThresholdMinutes * 60)
    }
}
