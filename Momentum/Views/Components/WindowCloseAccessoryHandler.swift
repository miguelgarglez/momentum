#if os(macOS)
    import AppKit
    import SwiftUI

    struct WindowCloseAccessoryHandler: NSViewRepresentable {
        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async {
                context.coordinator.attach(to: view.window)
            }
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            DispatchQueue.main.async {
                context.coordinator.attach(to: nsView.window)
            }
        }

        final class Coordinator: NSObject, NSWindowDelegate {
            private weak var window: NSWindow?

            func attach(to window: NSWindow?) {
                guard self.window !== window else { return }
                self.window?.delegate = nil
                self.window = window
                window?.delegate = self
            }

            func windowShouldClose(_ sender: NSWindow) -> Bool {
                sender.orderOut(nil)
                notifyVisibilityChange()
                return false
            }

            func windowDidBecomeKey(_ notification: Notification) {
                notifyVisibilityChange()
            }

            func windowDidDeminiaturize(_ notification: Notification) {
                notifyVisibilityChange()
            }

            private func notifyVisibilityChange() {
                NotificationCenter.default.post(name: .momentumWindowVisibilityNeedsUpdate, object: nil)
            }
        }
    }
#endif
