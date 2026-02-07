#if os(macOS)
    import AppKit
    import Combine
    import SwiftUI

    @MainActor
    final class StatusItemController: NSObject {
        private let tracker: ActivityTracker
        private let statusItem: NSStatusItem
        private var cancellables: Set<AnyCancellable> = []
        private var clockTimer: Timer?
        private var currentTimeString: String = ""
        private var latestSummary: ActivityTracker.StatusSummary
        private var pendingConflictCount: Int
        private var isManualTrackingActive: Bool
        private let symbolViewModel = StatusItemSymbolViewModel()
        private weak var symbolHostingView: NSHostingView<StatusItemSymbolView>?
        private var isConflictActive: Bool = false

        private lazy var timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter
        }()

        @MainActor
        init(tracker: ActivityTracker) {
            self.tracker = tracker
            statusItem = NSStatusBar.system.statusItem(withLength: 12)
            latestSummary = tracker.statusSummary
            pendingConflictCount = tracker.pendingConflictCount
            isManualTrackingActive = tracker.isManualTrackingActive
            isConflictActive = pendingConflictCount > 0 && !isManualTrackingActive
            symbolViewModel.isManualTrackingActive = isManualTrackingActive
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
            tracker.$pendingConflictCount
                .receive(on: RunLoop.main)
                .sink { [weak self] count in
                    guard let self else { return }
                    self.pendingConflictCount = count
                    self.updateButtonBadge()
                    self.updateSymbolView()
                    self.rebuildMenu()
                }
                .store(in: &cancellables)
            tracker.$isManualTrackingActive
                .receive(on: RunLoop.main)
                .sink { [weak self] isActive in
                    guard let self else { return }
                    self.isManualTrackingActive = isActive
                    self.updateButtonBadge()
                    self.updateSymbolView()
                    self.rebuildMenu()
                }
                .store(in: &cancellables)
            startClockTimer()
        }

        @MainActor
        private func configureButton() {
            installSymbolViewIfNeeded()
            statusItem.button?.imagePosition = .imageOnly
            statusItem.button?.appearsDisabled = false
            updateSymbolView()
            updateButtonBadge()
        }

        @MainActor
        private func updateButtonBadge() {
            guard let button = statusItem.button else { return }
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
        }

        @MainActor
        private func installSymbolViewIfNeeded() {
            guard let button = statusItem.button else { return }
            button.image = nil
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")

            if symbolHostingView == nil {
                let hostingView = NSHostingView(
                    rootView: StatusItemSymbolView(model: symbolViewModel))
                hostingView.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(hostingView)
                NSLayoutConstraint.activate([
                    hostingView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                    hostingView.widthAnchor.constraint(equalToConstant: 16),
                    hostingView.heightAnchor.constraint(equalToConstant: 16),
                ])
                symbolHostingView = hostingView
            }
        }

        @MainActor
        private func updateSymbolView() {
            let hasConflict = pendingConflictCount > 0 && !isManualTrackingActive
            if hasConflict != isConflictActive {
                isConflictActive = hasConflict
                symbolViewModel.isConflicting = hasConflict
                symbolViewModel.conflictChangeToken += 1
            } else {
                symbolViewModel.isConflicting = hasConflict
            }
            symbolViewModel.isManualTrackingActive = isManualTrackingActive
        }

        @MainActor
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

        @MainActor
        private func updateClockLabel() {
            currentTimeString = timeFormatter.string(from: Date())
        }

        private func rebuildMenu() {
            let menu = NSMenu()
            let header = disabledItem(localizedFormat("Momentum — %@", currentTimeString))
            menu.addItem(header)

            let stateItem = disabledItem(stateDescription(for: latestSummary))
            menu.addItem(stateItem)
            appendContextDetails(to: menu, summary: latestSummary)
            menu.addItem(NSMenuItem.separator())

            let showAppItem = NSMenuItem(
                title: localized("Abrir Momentum"),
                action: #selector(handleShowApp),
                keyEquivalent: ""
            )
            showAppItem.target = self
            menu.addItem(showAppItem)

            let toggleTitle = tracker.isTrackingEnabled ? localized("Pausar tracking") : localized("Reanudar tracking")
            let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(handleToggleTracking), keyEquivalent: "")
            toggleItem.target = self
            menu.addItem(toggleItem)

            if tracker.isManualTrackingActive {
                let stopManualItem = NSMenuItem(
                    title: localized("Detener tracking manual"),
                    action: #selector(handleStopManualTracking),
                    keyEquivalent: ""
                )
                stopManualItem.target = self
                menu.addItem(stopManualItem)
            } else {
                let startManualItem = NSMenuItem(
                    title: localized("Iniciar tracking manual"),
                    action: #selector(handleStartManualTracking),
                    keyEquivalent: ""
                )
                startManualItem.target = self
                menu.addItem(startManualItem)
            }

            if pendingConflictCount > 0, !tracker.isManualTrackingActive {
                let conflictTitle = localizedFormat("Resolver conflictos (%lld)", pendingConflictCount)
                let conflictItem = NSMenuItem(title: conflictTitle, action: #selector(handleShowApp), keyEquivalent: "")
                conflictItem.target = self
                menu.addItem(conflictItem)
            }

            if let projectName = latestSummary.projectName,
               latestSummary.projectID != nil
            {
                let projectItem = NSMenuItem(
                    title: localizedFormat("Ir a %@", projectName),
                    action: #selector(handleOpenActiveProject),
                    keyEquivalent: ""
                )
                projectItem.target = self
                menu.addItem(projectItem)
            }

            let settingsItem = NSMenuItem(title: localized("Ajustes…"), action: #selector(handleShowSettings), keyEquivalent: ",")
            settingsItem.target = self
            menu.addItem(settingsItem)

            menu.addItem(NSMenuItem.separator())

            let quitItem = NSMenuItem(title: localized("Salir"), action: #selector(handleQuit), keyEquivalent: "q")
            quitItem.target = self
            quitItem.keyEquivalentModifierMask = [.command]
            menu.addItem(quitItem)

            statusItem.menu = menu
        }

        private func appendContextDetails(to menu: NSMenu, summary: ActivityTracker.StatusSummary) {
            switch summary.state {
            case .tracking:
                if let contextLine = contextLine(for: summary) {
                    menu.addItem(disabledItem(contextLine))
                } else {
                    menu.addItem(disabledItem(localized("Registrando actividad")))
                }
                let projectLabel = summary.projectName ?? localized("Sin proyecto asignado")
                menu.addItem(disabledItem(localizedFormat("Proyecto: %@", projectLabel)))
            case .trackingManual:
                if let contextLine = contextLine(for: summary) {
                    menu.addItem(disabledItem(contextLine))
                } else {
                    menu.addItem(disabledItem(localized("Tracking manual activo")))
                }
                let projectLabel = summary.projectName ?? localized("Sin proyecto asignado")
                menu.addItem(disabledItem(localizedFormat("Proyecto manual: %@", projectLabel)))
            case .pendingResolution:
                if let contextLine = contextLine(for: summary) {
                    menu.addItem(disabledItem(contextLine))
                } else {
                    menu.addItem(disabledItem(localized("Pendiente de asignación")))
                }
                menu.addItem(disabledItem(localized("Proyecto: pendiente de asignación")))
            case .pausedManual:
                menu.addItem(disabledItem(localized("Tracking pausado manualmente")))
            case .pausedIdle:
                menu.addItem(disabledItem(localized("Tracking pausado por inactividad")))
            case .pausedScreenLocked:
                menu.addItem(disabledItem(localized("Tracking pausado por bloqueo de pantalla")))
            case .pausedExcluded:
                if let contextLine = contextLine(for: summary) {
                    menu.addItem(disabledItem(localizedFormat("%@ (excluido)", contextLine)))
                } else {
                    menu.addItem(disabledItem(localized("Tracking desactivado por exclusión")))
                }
            case .inactive:
                menu.addItem(disabledItem(localized("Esperando actividad...")))
            }
        }

        private func contextLine(for summary: ActivityTracker.StatusSummary) -> String? {
            guard let appName = summary.appName else { return nil }
            if let filePath = summary.filePath {
                return "\(appName) • \(filePath.filePathDisplayName)"
            }
            if let domain = summary.domain {
                return "\(appName) • \(domain)"
            }
            return appName
        }

        private func stateDescription(for summary: ActivityTracker.StatusSummary) -> String {
            switch summary.state {
            case .tracking:
                localized("Tracking activo")
            case .trackingManual:
                localized("Tracking manual activo")
            case .pendingResolution:
                localized("Pendiente de asignación")
            case .pausedManual:
                localized("Tracking pausado")
            case .pausedIdle:
                localized("Tracking pausado (idle)")
            case .pausedScreenLocked:
                localized("Tracking pausado (bloqueo)")
            case .pausedExcluded:
                localized("Actividad excluida")
            case .inactive:
                localized("Sin tracking")
            }
        }

        private func localized(_ key: String) -> String {
            NSLocalizedString(key, comment: "")
        }

        private func localizedFormat(_ format: String, _ args: CVarArg...) -> String {
            String(format: NSLocalizedString(format, comment: ""), locale: Locale.current, arguments: args)
        }

        private func disabledItem(_ title: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }

        @objc private func handleToggleTracking(_: Any?) {
            tracker.toggleTracking()
        }

        @objc private func handleStartManualTracking(_ sender: Any?) {
            handleShowApp(sender)
            NotificationCenter.default.post(name: .statusItemStartManualTracking, object: nil)
        }

        @objc private func handleStopManualTracking(_: Any?) {
            tracker.stopManualTracking(reason: .manual)
        }

        @objc private func handleShowApp(_: Any?) {
            NotificationCenter.default.post(name: .statusItemShowApp, object: nil)
        }

        @objc private func handleOpenActiveProject(_ sender: Any?) {
            guard let identifier = latestSummary.projectID else {
                handleShowApp(sender)
                return
            }
            handleShowApp(sender)
            NotificationCenter.default.post(name: .statusItemOpenProject, object: nil, userInfo: [
                StatusItemUserInfoKey.projectID: identifier,
            ])
        }

        @objc private func handleQuit(_: Any?) {
            NSApplication.shared.terminate(nil)
        }

        @objc private func handleShowSettings(_: Any?) {
            SettingsWindowPresenter.open(section: nil)
        }
    }

    extension Notification.Name {
        static let statusItemOpenProject = Notification.Name("StatusItemOpenProject")
        static let statusItemStartManualTracking = Notification.Name("StatusItemStartManualTracking")
        static let statusItemShowApp = Notification.Name("StatusItemShowApp")
        static let statusItemShowSettings = Notification.Name("StatusItemShowSettings")
        static let raycastShowConflicts = Notification.Name("RaycastShowConflicts")
        static let raycastStartManualTracking = Notification.Name("RaycastStartManualTracking")
    }

    enum StatusItemUserInfoKey {
        static let projectID = "StatusItemProjectID"
    }
#endif
