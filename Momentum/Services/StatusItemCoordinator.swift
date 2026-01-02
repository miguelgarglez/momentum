#if os(macOS)
import AppKit

@MainActor
final class StatusItemCoordinator {
    private var controller: StatusItemController?

    func configure(with tracker: ActivityTracker) {
        guard controller == nil else { return }
        controller = StatusItemController(tracker: tracker)
    }
}
#endif
