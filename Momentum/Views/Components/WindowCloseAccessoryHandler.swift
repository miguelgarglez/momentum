#if os(macOS)
    import AppKit
    import SwiftUI

    struct WindowCloseAccessoryHandler: NSViewRepresentable {
        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            Task { @MainActor in
                context.coordinator.attach(to: view.window)
            }
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            Task { @MainActor in
                context.coordinator.attach(to: nsView.window)
            }
        }

        final class Coordinator: NSObject, NSWindowDelegate {
            private weak var window: NSWindow?
            private var observers: [NSObjectProtocol] = []

            func attach(to window: NSWindow?) {
                guard self.window !== window else { return }
                detachIfNeeded()
                self.window = window
                guard let window else { return }
                let center = NotificationCenter.default
                observers = [
                    center.addObserver(
                        forName: NSWindow.didBecomeKeyNotification,
                        object: window,
                        queue: .main,
                    ) { [weak self] _ in
                        Task { @MainActor in
                            self?.notifyVisibilityChange()
                        }
                    },
                    center.addObserver(
                        forName: NSWindow.didDeminiaturizeNotification,
                        object: window,
                        queue: .main,
                    ) { [weak self] _ in
                        Task { @MainActor in
                            self?.notifyVisibilityChange()
                        }
                    },
                    center.addObserver(
                        forName: NSWindow.willCloseNotification,
                        object: window,
                        queue: .main,
                    ) { [weak self] _ in
                        Task { @MainActor in
                            self?.notifyVisibilityChange()
                        }
                    },
                ]
            }

            private func detachIfNeeded() {
                let center = NotificationCenter.default
                for observer in observers {
                    center.removeObserver(observer)
                }
                observers.removeAll()
            }

            private func notifyVisibilityChange() {
                NotificationCenter.default.post(name: .momentumWindowVisibilityNeedsUpdate, object: nil)
            }
        }
    }
#endif
