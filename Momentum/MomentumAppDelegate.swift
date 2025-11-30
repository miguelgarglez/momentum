#if os(macOS)
import AppKit

@MainActor
final class MomentumAppDelegate: NSObject, NSApplicationDelegate {
    var trackerProvider: (() -> ActivityTracker)?

    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard statusItemController == nil, let tracker = trackerProvider?() else { return }
        statusItemController = StatusItemController(tracker: tracker)
    }
}
#endif
