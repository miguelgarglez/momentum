#if os(macOS)
import AppKit

@MainActor
final class MomentumAppDelegate: NSObject, NSApplicationDelegate {
    var trackerProvider: (() -> ActivityTracker)? {
        didSet {
            if hasFinishedLaunching {
                configureStatusItemIfNeeded()
            }
        }
    }

    private var statusItemController: StatusItemController?
    private var hasFinishedLaunching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        hasFinishedLaunching = true
        configureStatusItemIfNeeded()
    }

    private func configureStatusItemIfNeeded() {
        guard statusItemController == nil, let tracker = trackerProvider?() else { return }
        statusItemController = StatusItemController(tracker: tracker)
    }
}
#endif
