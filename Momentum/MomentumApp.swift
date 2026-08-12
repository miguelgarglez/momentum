import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#endif

@MainActor
final class AppEnvironment {
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    let sessionController: FocusSessionController
    let settings: FocusSettings
    let dockVisibility = DockVisibilityCoordinator()

    #if os(macOS)
    private var statusItemController: StatusItemController?
    private let hotKeyController = HotKeyController()
    #endif

    init(inMemory: Bool = false) {
        let schema = Schema([Project.self, FocusSession.self])
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration(
                "MomentumFocusStore",
                isStoredInMemoryOnly: false
            )
        }
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("No se pudo abrir SwiftData: \(error)")
        }
        modelContext = ModelContext(modelContainer)
        settings = FocusSettings()
        sessionController = FocusSessionController(modelContext: modelContext)
        sessionController.isIdlePauseEnabled = settings.isIdlePauseEnabled
        sessionController.idleThreshold = settings.idleThreshold

        #if os(macOS)
        dockVisibility.start()
        statusItemController = StatusItemController(controller: sessionController)
        hotKeyController.onToggle = { [weak sessionController] in
            sessionController?.toggleLastProject()
        }
        hotKeyController.registerDefault()
        #endif
    }

    func applySettings() {
        sessionController.isIdlePauseEnabled = settings.isIdlePauseEnabled
        sessionController.idleThreshold = settings.idleThreshold
        if sessionController.isFocusing, settings.isIdlePauseEnabled == false {
            // Idle monitor is managed inside start/stop; flipping mid-session is ok via property.
        }
    }

    func handleWillTerminate() {
        sessionController.handleAppWillTerminate()
        #if os(macOS)
        statusItemController?.invalidate()
        hotKeyController.unregister()
        #endif
    }
}

#if os(macOS)
final class MomentumAppDelegate: NSObject, NSApplicationDelegate {
    var environment: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar is the product — don't leave a Dock window open on cold start.
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.handleWillTerminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
#endif

@main
struct MomentumApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MomentumAppDelegate.self) private var appDelegate
    #endif

    @State private var environment = AppEnvironment()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Momentum", id: "main") {
            ContentView(environment: environment)
                .onAppear {
                    #if os(macOS)
                    appDelegate.environment = environment
                    #endif
                    NotificationCenter.default.post(name: .momentumWindowVisibilityNeedsUpdate, object: nil)
                }
                .onReceive(NotificationCenter.default.publisher(for: .momentumShowMainWindow)) { _ in
                    openWindow(id: "main")
                    activateMainWindow()
                }
                .onReceive(NotificationCenter.default.publisher(for: .momentumShowNewProject)) { _ in
                    openWindow(id: "main")
                    activateMainWindow()
                    NotificationCenter.default.post(name: .momentumPresentNewProjectSheet, object: nil)
                }
                .onReceive(NotificationCenter.default.publisher(for: .momentumShowSettings)) { _ in
                    #if os(macOS)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                    #endif
                }
        }
        .defaultSize(width: 760, height: 520)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView(environment: environment)
        }
    }

    private func activateMainWindow() {
        #if os(macOS)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows where window.styleMask.contains(.titled) && window.title == "Momentum" {
                window.makeKeyAndOrderFront(nil)
            }
            NotificationCenter.default.post(name: .momentumWindowVisibilityNeedsUpdate, object: nil)
        }
        #endif
    }
}

extension Notification.Name {
    static let momentumPresentNewProjectSheet = Notification.Name("MomentumPresentNewProjectSheet")
}
