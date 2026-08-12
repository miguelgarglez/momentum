#if os(macOS)
import AppKit
import SwiftData

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let controller: FocusSessionController
    private var refreshTimer: Timer?
    private let menu = NSMenu()

    init(controller: FocusSessionController) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Momentum")
            button.imagePosition = .imageLeading
            button.image?.isTemplate = true
        }

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        startRefresh()
        updateButton()
    }

    func invalidate() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(into: menu)
    }

    private func startRefresh() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateButton()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        if controller.isFocusing {
            button.title = " \(DurationFormat.chronometer(controller.displayedElapsed))"
            if controller.phase == .pausedIdle {
                button.toolTip = "En pausa (inactividad)"
            } else {
                button.toolTip = controller.activeProject.map { "Enfocando: \($0.name)" } ?? "Enfocando"
            }
        } else {
            button.title = ""
            button.toolTip = "Momentum"
        }
    }

    private func rebuildMenu(into menu: NSMenu) {
        menu.removeAllItems()

        if controller.isFocusing {
            let projectName = controller.activeProject?.name ?? "Proyecto"
            let status = controller.phase == .pausedIdle ? "Pausado" : "En curso"
            let header = NSMenuItem(
                title: "\(status): \(projectName) · \(DurationFormat.chronometer(controller.displayedElapsed))",
                action: nil,
                keyEquivalent: ""
            )
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())

            let stop = NSMenuItem(title: "Detener sesión", action: #selector(stopSession), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
            menu.addItem(.separator())
        } else {
            let today = DurationFormat.summary(controller.todaySecondsTotal())
            let header = NSMenuItem(title: "Hoy · \(today)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())

            if let last = controller.mostRecentlyUsedProject() {
                let resume = NSMenuItem(
                    title: "Continuar \(last.name)",
                    action: #selector(continueLast),
                    keyEquivalent: ""
                )
                resume.target = self
                menu.addItem(resume)
                menu.addItem(.separator())
            }
        }

        let projects = controller.allProjects()
        if projects.isEmpty {
            let create = NSMenuItem(title: "Crear proyecto…", action: #selector(createProject), keyEquivalent: "")
            create.target = self
            menu.addItem(create)
        } else if !controller.isFocusing {
            let submenu = NSMenu()
            for project in projects.prefix(12) {
                let item = NSMenuItem(
                    title: project.name,
                    action: #selector(startProject(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = project.persistentModelID
                submenu.addItem(item)
            }
            let start = NSMenuItem(title: "Empezar en…", action: nil, keyEquivalent: "")
            start.submenu = submenu
            menu.addItem(start)

            let create = NSMenuItem(title: "Crear proyecto…", action: #selector(createProject), keyEquivalent: "")
            create.target = self
            menu.addItem(create)
        }

        menu.addItem(.separator())

        let open = NSMenuItem(title: "Abrir Momentum", action: #selector(openApp), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let settings = NSMenuItem(title: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Salir de Momentum", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        let hotkeyHint = NSMenuItem(title: "Atajo: ⌃⌥⌘M", action: nil, keyEquivalent: "")
        hotkeyHint.isEnabled = false
        menu.addItem(hotkeyHint)
    }

    @objc private func continueLast() {
        controller.toggleLastProject()
        updateButton()
    }

    @objc private func stopSession() {
        controller.stop(offerNotePrompt: true)
        updateButton()
        NotificationCenter.default.post(name: .momentumShowMainWindow, object: nil)
    }

    @objc private func startProject(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? PersistentIdentifier else { return }
        guard let project = controller.allProjects().first(where: { $0.persistentModelID == id }) else { return }
        controller.start(project: project)
        updateButton()
    }

    @objc private func createProject() {
        NotificationCenter.default.post(name: .momentumShowNewProject, object: nil)
    }

    @objc private func openApp() {
        NotificationCenter.default.post(name: .momentumShowMainWindow, object: nil)
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .momentumShowSettings, object: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
#endif
