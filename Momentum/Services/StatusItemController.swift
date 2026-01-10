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
        private var pendingConflictCount: Int
        private var isManualTrackingActive: Bool
        private weak var badgeView: NSView?
        private weak var manualBadgeView: NSView?

        private lazy var timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter
        }()

        @MainActor
        init(tracker: ActivityTracker) {
            self.tracker = tracker
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            latestSummary = tracker.statusSummary
            pendingConflictCount = tracker.pendingConflictCount
            isManualTrackingActive = tracker.isManualTrackingActive
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
                    self.rebuildMenu()
                }
                .store(in: &cancellables)
            tracker.$isManualTrackingActive
                .receive(on: RunLoop.main)
                .sink { [weak self] isActive in
                    guard let self else { return }
                    self.isManualTrackingActive = isActive
                    self.updateButtonBadge()
                    self.rebuildMenu()
                }
                .store(in: &cancellables)
            startClockTimer()
        }

        @MainActor
        private func configureButton() {
            statusItem.button?.image = NSImage(systemSymbolName: "flame", accessibilityDescription: "Momentum")
            statusItem.button?.imagePosition = .imageOnly
            statusItem.button?.appearsDisabled = false
            updateButtonBadge()
        }

        @MainActor
        private func updateButtonBadge() {
            guard let button = statusItem.button else { return }
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")

            if pendingConflictCount > 0, !isManualTrackingActive {
                if badgeView == nil {
                    let badgeSize: CGFloat = 6
                    let dot = NSView()
                    dot.wantsLayer = true
                    dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
                    dot.layer?.cornerRadius = badgeSize / 2
                    dot.translatesAutoresizingMaskIntoConstraints = false
                    button.addSubview(dot)
                    NSLayoutConstraint.activate([
                        dot.widthAnchor.constraint(equalToConstant: badgeSize),
                        dot.heightAnchor.constraint(equalToConstant: badgeSize),
                        dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -7),
                        dot.topAnchor.constraint(equalTo: button.topAnchor, constant: 4),
                    ])
                    badgeView = dot
                }
            } else {
                badgeView?.removeFromSuperview()
                badgeView = nil
            }

            if isManualTrackingActive {
                if manualBadgeView == nil {
                    let badgeSize: CGFloat = 6
                    let dot = NSView()
                    dot.wantsLayer = true
                    dot.layer?.backgroundColor = NSColor.systemTeal.cgColor
                    dot.layer?.cornerRadius = badgeSize / 2
                    dot.translatesAutoresizingMaskIntoConstraints = false
                    button.addSubview(dot)
                    NSLayoutConstraint.activate([
                        dot.widthAnchor.constraint(equalToConstant: badgeSize),
                        dot.heightAnchor.constraint(equalToConstant: badgeSize),
                        dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -7),
                        dot.topAnchor.constraint(equalTo: button.topAnchor, constant: 4),
                    ])
                    manualBadgeView = dot
                }
            } else {
                manualBadgeView?.removeFromSuperview()
                manualBadgeView = nil
            }
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

            if tracker.isManualTrackingActive {
                let stopManualItem = NSMenuItem(title: "Detener tracking manual", action: #selector(handleStopManualTracking), keyEquivalent: "")
                stopManualItem.target = self
                menu.addItem(stopManualItem)
            } else {
                let startManualItem = NSMenuItem(title: "Iniciar tracking manual", action: #selector(handleStartManualTracking), keyEquivalent: "")
                startManualItem.target = self
                menu.addItem(startManualItem)
            }

            if pendingConflictCount > 0, !tracker.isManualTrackingActive {
                let conflictTitle = "Resolver conflictos (\(pendingConflictCount))"
                let conflictItem = NSMenuItem(title: conflictTitle, action: #selector(handleShowApp), keyEquivalent: "")
                conflictItem.target = self
                menu.addItem(conflictItem)
            }

            if let projectName = latestSummary.projectName,
               latestSummary.projectID != nil
            {
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
                if let contextLine = contextLine(for: summary) {
                    menu.addItem(disabledItem(contextLine))
                } else {
                    menu.addItem(disabledItem("Registrando actividad"))
                }
                let projectLabel = summary.projectName ?? "Sin proyecto asignado"
                menu.addItem(disabledItem("Proyecto: \(projectLabel)"))
            case .trackingManual:
                if let contextLine = contextLine(for: summary) {
                    menu.addItem(disabledItem(contextLine))
                } else {
                    menu.addItem(disabledItem("Tracking manual activo"))
                }
                let projectLabel = summary.projectName ?? "Sin proyecto asignado"
                menu.addItem(disabledItem("Proyecto manual: \(projectLabel)"))
            case .pendingResolution:
                if let contextLine = contextLine(for: summary) {
                    menu.addItem(disabledItem(contextLine))
                } else {
                    menu.addItem(disabledItem("Pendiente de asignación"))
                }
                menu.addItem(disabledItem("Proyecto: pendiente de asignación"))
            case .pausedManual:
                menu.addItem(disabledItem("Tracking pausado manualmente"))
            case .pausedIdle:
                menu.addItem(disabledItem("Tracking pausado por inactividad"))
            case .pausedScreenLocked:
                menu.addItem(disabledItem("Tracking pausado por bloqueo de pantalla"))
            case .pausedExcluded:
                if let contextLine = contextLine(for: summary) {
                    menu.addItem(disabledItem("\(contextLine) (excluido)"))
                } else {
                    menu.addItem(disabledItem("Tracking desactivado por exclusión"))
                }
            case .inactive:
                menu.addItem(disabledItem("Esperando actividad..."))
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
                "Tracking activo"
            case .trackingManual:
                "Tracking manual activo"
            case .pendingResolution:
                "Pendiente de asignación"
            case .pausedManual:
                "Tracking pausado"
            case .pausedIdle:
                "Tracking pausado (idle)"
            case .pausedScreenLocked:
                "Tracking pausado (bloqueo)"
            case .pausedExcluded:
                "Actividad excluida"
            case .inactive:
                "Sin tracking"
            }
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
            NSApplication.shared.activate(ignoringOtherApps: true)
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
    }

    extension Notification.Name {
        static let statusItemOpenProject = Notification.Name("StatusItemOpenProject")
        static let statusItemStartManualTracking = Notification.Name("StatusItemStartManualTracking")
    }

    enum StatusItemUserInfoKey {
        static let projectID = "StatusItemProjectID"
    }
#endif
