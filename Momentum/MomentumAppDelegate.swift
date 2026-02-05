#if os(macOS)
    import AppKit

    final class MomentumAppDelegate: NSObject, NSApplicationDelegate {
        func application(_: NSApplication, open urls: [URL]) {
            for url in urls {
                MomentumDeepLink.handle(url)
            }
        }
    }
#endif
