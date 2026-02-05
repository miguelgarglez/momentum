import Foundation

enum MainWindowSuppression {
    private static let key = "MomentumSuppressMainWindowOnce"

    static func request() {
        UserDefaults.standard.set(true, forKey: key)
    }

    static func consume() -> Bool {
        let shouldSuppress = UserDefaults.standard.bool(forKey: key)
        if shouldSuppress {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return shouldSuppress
    }
}
