#if os(macOS)
import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private let tracker: ActivityTracker
    private let statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []
    private var clockTimer: Timer?
    private var currentTimeString: String = ""
    private var latestSummary: ActivityTracker.StatusSummary

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    init(tracker: ActivityTracker) {
        self.tracker = tracker
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.latestSummary = tracker.statusSummary
        super.init()
        configureButton()
        updateClockLabel()
        rebuildMenu()
        tracker.$statusSummary
            .receive(on: RunLoop.main)
            .sink { [weak self] summary in
                guard let self else { return }
                self.latestSummary = summary
                self.rebuildMenu()
            }
            .store(in: &cancellables)
        startClockTimer()
    }

    deinit {
        clockTimer?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureButton() {
        statusItem.button?.image = NSImage(systemSymbolName: "flame", accessibilityDescription: "Momentum")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.appearsDisabled = false
    }

    private func startClockTimer() {
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateClockLabel()
                self.rebuildMenu()
            }
        }
    }

    private func updateClockLabel() {
        currentTimeString = timeFormatter.string(from: Date())
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let header = disabledItem("Momentum — \(currentTimeString)")
        menu.addItem(header)

        let stateItem = disabledItem(stateDescription(for: latestSummary))
        menu.addItem(stateItem)
        appendContextDetails(to: menu, summary: latestSummary)
        menu.addItem(NSMenuItem.separator())

        let toggleTitle = tracker.isTrackingEnabled ? "Pausar tracking" : "Reanudar tracking"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(handleToggleTracking), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        if let projectName = latestSummary.projectName,
           latestSummary.projectID != nil {
            let projectItem = NSMenuItem(title: "Ir a \(projectName)", action: #selector(handleOpenActiveProject), keyEquivalent: "")
            projectItem.target = self
            menu.addItem(projectItem)
        }

        let showAppItem = NSMenuItem(title: "Abrir Momentum", action: #selector(handleShowApp), keyEquivalent: "")
        showAppItem.target = self
        menu.addItem(showAppItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Salir", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func appendContextDetails(to menu: NSMenu, summary: ActivityTracker.StatusSummary) {
        switch summary.state {
        case .tracking:
            if let appName = summary.appName {
                if let domain = summary.domain {
                    menu.addItem(disabledItem("\(appName) • \(domain)"))
                } else {
                    menu.addItem(disabledItem(appName))
                }
            } else {
                menu.addItem(disabledItem("Registrando actividad"))
            }
            let projectLabel = summary.projectName ?? "Sin proyecto asignado"
            menu.addItem(disabledItem("Proyecto: \(projectLabel)"))
        case .pausedManual:
            menu.addItem(disabledItem("Tracking pausado manualmente"))
        case .pausedIdle:
            menu.addItem(disabledItem("Tracking pausado por inactividad"))
        case .inactive:
            menu.addItem(disabledItem("Esperando actividad..."))
        }
    }

    private func stateDescription(for summary: ActivityTracker.StatusSummary) -> String {
        switch summary.state {
        case .tracking:
            return "Tracking activo"
        case .pausedManual:
            return "Tracking pausado"
        case .pausedIdle:
            return "Tracking pausado (idle)"
        case .inactive:
            return "Sin tracking"
        }
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func handleToggleTracking(_ sender: Any?) {
        tracker.toggleTracking()
    }

    @objc private func handleShowApp(_ sender: Any?) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func handleOpenActiveProject(_ sender: Any?) {
        guard let identifier = latestSummary.projectID else {
            handleShowApp(sender)
            return
        }
        handleShowApp(sender)
        NotificationCenter.default.post(name: .statusItemOpenProject, object: nil, userInfo: [
            StatusItemUserInfoKey.projectID: identifier
        ])
    }

    @objc private func handleQuit(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }
}

extension Notification.Name {
    static let statusItemOpenProject = Notification.Name("StatusItemOpenProject")
}

enum StatusItemUserInfoKey {
    static let projectID = "StatusItemProjectID"
}
#endif
