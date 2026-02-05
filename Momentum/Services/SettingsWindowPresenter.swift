import Foundation

#if os(macOS)
    import AppKit
#endif

@MainActor
enum SettingsWindowPresenter {
    private static var lastOpenAt: Date?

    static func open(section: String?) {
        #if os(macOS)
            let visibleMainWindowIDsBeforeOpen = Set(visibleMainWindowIDs())
        #endif
        let now = Date()
        if let lastOpenAt, now.timeIntervalSince(lastOpenAt) < 2.0 {
            return
        }
        lastOpenAt = now
        if let section {
            UserDefaults.standard.set(section, forKey: RaycastSettingsRequest.sectionKey)
        }
        #if os(macOS)
            MainWindowSuppression.request()
            NotificationCenter.default.post(
                name: .momentumHoldDockVisibility,
                object: nil,
                userInfo: ["MomentumHoldDockVisibilityDuration": 2.0],
            )
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.unhide(nil)
            NSApp.setActivationPolicy(.regular)
            if let existingWindow = findSettingsWindow() {
                existingWindow.makeKeyAndOrderFront(nil)
                existingWindow.orderFrontRegardless()
                return
            }
            if !triggerMenuSettingsAction() {
                let selector = Selector(("showSettingsWindow:"))
                NSApplication.shared.sendAction(selector, to: nil, from: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                bringSettingsWindowToFront()
                cleanupUnexpectedMainWindows(visibleBeforeOpen: visibleMainWindowIDsBeforeOpen)
            }
        #endif
    }
}

#if os(macOS)
    private extension SettingsWindowPresenter {
        static func isSettingsWindow(_ window: NSWindow) -> Bool {
            let title = window.title.lowercased()
            if title.contains("configuración") || title.contains("settings") || title.contains("preferencias") {
                return true
            }
            return false
        }

        static func visibleMainWindowIDs() -> [Int] {
            NSApp.windows
                .filter { window in
                    guard window.isVisible, !window.isMiniaturized else { return false }
                    guard window.canBecomeKey || window.canBecomeMain else { return false }
                    return !isSettingsWindow(window)
                }
                .map(\.windowNumber)
        }

        static func findSettingsWindow() -> NSWindow? {
            NSApp.windows.first(where: isSettingsWindow)
        }

        static func triggerMenuSettingsAction() -> Bool {
            guard let menu = NSApp.mainMenu?.items.first?.submenu else { return false }
            if let index = menu.items.firstIndex(where: { item in
                if item.keyEquivalent == "," { return true }
                let title = item.title.lowercased()
                if title.contains("ajustes") || title.contains("settings") || title.contains("preferencias") {
                    return true
                }
                if item.action == Selector(("showSettingsWindow:")) { return true }
                return false
            }) {
                menu.performActionForItem(at: index)
                return true
            }
            return false
        }

        static func bringSettingsWindowToFront() {
            guard let window = findSettingsWindow() else { return }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }

        static func cleanupUnexpectedMainWindows(visibleBeforeOpen: Set<Int>) {
            let visibleMainWindows = NSApp.windows.filter { window in
                guard window.isVisible, !window.isMiniaturized else { return false }
                guard window.canBecomeKey || window.canBecomeMain else { return false }
                return !isSettingsWindow(window)
            }

            if visibleBeforeOpen.isEmpty {
                for window in visibleMainWindows {
                    window.orderOut(nil)
                }
                return
            }

            for window in visibleMainWindows where !visibleBeforeOpen.contains(window.windowNumber) {
                window.orderOut(nil)
            }
        }
    }
#endif
