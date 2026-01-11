#if os(macOS)
    import AppKit

    @MainActor
    final class DockVisibilityCoordinator {
        private var observers: [NSObjectProtocol] = []
        private var pendingEvaluation: DispatchWorkItem?
        private var hasStarted = false

        func start() {
            guard !hasStarted else { return }
            hasStarted = true

            let center = NotificationCenter.default
            let windowNotifications: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didBecomeMainNotification,
                NSWindow.didResignMainNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.willCloseNotification,
            ]

            for name in windowNotifications {
                let observer = center.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main,
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.handleWindowNotification(name)
                    }
                }
                observers.append(observer)
            }

            let didBecomeActive = center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main,
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleEvaluation(delay: 0.2)
                }
            }
            observers.append(didBecomeActive)

            let didResignActive = center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main,
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleEvaluation(delay: 0.1)
                }
            }
            observers.append(didResignActive)

            let manualUpdate = center.addObserver(
                forName: .momentumWindowVisibilityNeedsUpdate,
                object: nil,
                queue: .main,
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleEvaluation(delay: 0.1)
                }
            }
            observers.append(manualUpdate)

            scheduleEvaluation(delay: 0.1)
        }

        private func handleWindowNotification(_ name: Notification.Name) {
            let immediateNotifications: Set<Notification.Name> = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didBecomeMainNotification,
                NSWindow.didDeminiaturizeNotification,
            ]
            let delay: TimeInterval = immediateNotifications.contains(name) ? 0.0 : 0.12
            scheduleEvaluation(delay: delay)
        }

        private func scheduleEvaluation(delay: TimeInterval) {
            pendingEvaluation?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.applyVisibility()
            }
            pendingEvaluation = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        private func applyVisibility() {
            let hasVisibleWindow = NSApp.windows.contains(where: isUserFacingWindow)
            if hasVisibleWindow {
                if NSApp.activationPolicy() != .regular {
                    NSApp.setActivationPolicy(.regular)
                }
            } else {
                if NSApp.activationPolicy() != .accessory {
                    NSApp.setActivationPolicy(.accessory)
                }
                NSApp.hide(nil)
            }
        }

        private func isUserFacingWindow(_ window: NSWindow) -> Bool {
            guard window.isVisible, !window.isMiniaturized else { return false }
            if !window.canBecomeKey && !window.canBecomeMain { return false }
            if !window.styleMask.contains(.titled) { return false }
            if window.isExcludedFromWindowsMenu { return false }
            if window.level != .normal && window.level != .floating { return false }
            if !window.isOnActiveSpace { return false }
            return true
        }
    }

    extension Notification.Name {
        static let momentumWindowVisibilityNeedsUpdate = Notification.Name("MomentumWindowVisibilityNeedsUpdate")
    }
#endif
