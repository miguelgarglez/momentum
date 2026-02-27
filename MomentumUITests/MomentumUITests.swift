import XCTest

@MainActor
final class MomentumUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCreateProjectFlow() throws {
        let app = launch(reset: true)
        createProject(named: "UI Test Project", domain: "momentum.run", in: app)
        XCTAssertTrue(app.staticTexts["UI Test Project"].waitForExistence(timeout: 6))
    }

    func testEditingDomainsUpdatesDetail() throws {
        let app = launch(reset: true)
        createProject(named: "Editar Proyecto", domain: "momentum.run", in: app)
        openProject(named: "Editar Proyecto", in: app)
        openContextMenuAndSelectEdit(named: "Editar Proyecto", in: app)

        let domainsField = app.textFields["project-domains-field"]
        XCTAssertTrue(domainsField.waitForExistence(timeout: 2))
        let formScrollView = app.scrollViews.firstMatch
        if formScrollView.exists {
            var attempts = 0
            while !domainsField.isHittable, attempts < 3 {
                formScrollView.swipeUp()
                attempts += 1
            }
        }
        domainsField.click()
        domainsField.typeKey("a", modifierFlags: .command)
        domainsField.typeText("momentum.run, docs.test")
        app.buttons["Guardar"].click()
        XCTAssertTrue(app.staticTexts["docs.test"].waitForExistence(timeout: 6))
    }

    func testDashboardDisplaysWelcomeMetrics() throws {
        let app = launch(reset: true)
        createProject(named: "Dashboard Focus", domain: nil, in: app)
        let outline = app.outlines.firstMatch
        XCTAssertTrue(outline.waitForExistence(timeout: 6), "Expected sidebar outline to exist")
        let projectRow = outline.cells.containing(.staticText, identifier: "Dashboard Focus").firstMatch
        XCTAssertTrue(projectRow.waitForExistence(timeout: 6), "Expected project row to appear")
        let expandedButton = app.buttons["Ocultar resumen"]
        let collapsedButton = app.buttons["Mostrar resumen"]
        let summaryButtonExists = expandedButton.waitForExistence(timeout: 6) || collapsedButton.waitForExistence(timeout: 6)
        XCTAssertTrue(summaryButtonExists, "Expected dashboard summary button to appear")
        if collapsedButton.exists {
            collapsedButton.click()
        }
        XCTAssertTrue(app.otherElements["dashboard-metrics"].waitForExistence(timeout: 6), "Expected dashboard metrics to appear")
    }

    func testConflictBannerOpensResolutionSheet() throws {
        let app = launch(reset: true, seedConflicts: true)
        let banner = app.otherElements["pending-conflict-banner"]
        let resolveButton = app.buttons["pending-conflict-resolve-button"]
        let bannerExists = banner.waitForExistence(timeout: 6)
        let resolveExists = resolveButton.waitForExistence(timeout: 6)
        XCTAssertTrue(bannerExists || resolveExists, "Expected pending conflict banner or resolve button to appear")
        XCTAssertTrue(resolveExists, "Expected resolve button in pending conflict banner")
        resolveButton.click()
        waitForConflictResolutionSheet(in: app)
    }

    func testConflictListShowsAppAndDomainRows() throws {
        let app = launch(reset: true, seedConflicts: true)
        openConflictResolutionSheet(in: app)
        XCTAssertTrue(app.staticTexts["Seed App"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["example.com"].waitForExistence(timeout: 6))
    }

    func testConflictResolutionAssignsProject() throws {
        let app = launch(reset: true, seedConflicts: true)
        openConflictResolutionSheet(in: app)
        let assignButton = app.buttons["Asignar"].firstMatch
        XCTAssertTrue(assignButton.waitForExistence(timeout: 6))
        XCTAssertTrue(assignButton.isEnabled)
        assignButton.click()

        let closeButton = app.buttons["Cerrar"]
        if closeButton.waitForExistence(timeout: 2) {
            closeButton.click()
        }

        let bannerText = app.staticTexts["Tienes 1 contexto(s) por resolver."]
        XCTAssertTrue(bannerText.waitForExistence(timeout: 6))
    }

    func testManualTrackingFlowFromMainWindow() throws {
        let app = launch(reset: true)
        createProject(named: "Manual UI", domain: nil, in: app)

        let manualButton = app.buttons["action-panel-manual"]
        XCTAssertTrue(manualButton.waitForExistence(timeout: 6))
        manualButton.click()

        XCTAssertTrue(app.staticTexts["Manual en vivo"].waitForExistence(timeout: 6))
        let picker = app.popUpButtons["manual-tracking-project-picker"]
        if picker.waitForExistence(timeout: 6) {
            picker.click()
            let menuItem = picker.menuItems["Manual UI"].firstMatch
            XCTAssertTrue(menuItem.waitForExistence(timeout: 6))
            menuItem.click()
        }

        let startButton = app.buttons["Iniciar"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 6))
        startButton.click()

        let stopButton = app.buttons["Detener manual en vivo"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 6))
        stopButton.click()

        XCTAssertTrue(app.buttons["action-panel-manual"].waitForExistence(timeout: 6))
    }

    func testManualTimeEntryCreateAndDeleteFlow() throws {
        let app = launch(reset: true)
        createProject(named: "Manual Entry UI", domain: nil, in: app)
        openProject(named: "Manual Entry UI", in: app)

        let actionsMenu = app.buttons["project-actions-menu"]
        XCTAssertTrue(actionsMenu.waitForExistence(timeout: 6))
        actionsMenu.click()
        let addManualTimeItem = app.menuItems["Añadir tiempo manual"]
        XCTAssertTrue(addManualTimeItem.waitForExistence(timeout: 6))
        addManualTimeItem.click()

        XCTAssertTrue(app.staticTexts["Añadir tiempo manual"].waitForExistence(timeout: 6))
        let saveButton = app.buttons["manual-time-save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 6))
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.click()

        let manualEntryLabel = app.staticTexts["Entrada manual"].firstMatch
        XCTAssertTrue(manualEntryLabel.waitForExistence(timeout: 6))

        let deleteButton = app.buttons["manual-entry-delete-button"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 6))
        deleteButton.click()

        let confirmDelete = app.buttons["Eliminar entrada"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 6))
        confirmDelete.click()

        XCTAssertTrue(app.staticTexts["Aún no hay entradas manuales en este proyecto."].waitForExistence(timeout: 6))
    }

    func testAssignmentRulesAppearInSettings() throws {
        let app = launch(reset: true, seedRules: true)
        app.typeKey(",", modifierFlags: .command)

        var settingsWindow = app.windows.matching(NSPredicate(format: "title == %@", "Configuración")).firstMatch
        if !settingsWindow.waitForExistence(timeout: 4) {
            settingsWindow = app.windows.firstMatch
        }

        let rulesLink = settingsWindow.buttons["assignment-rules-link"]
        XCTAssertTrue(rulesLink.waitForExistence(timeout: 6))
        rulesLink.click()

        _ = app.windows.matching(NSPredicate(format: "title == %@", "Reglas de asignacion")).firstMatch.waitForExistence(timeout: 2)
        let rulesList = app.outlines["assignment-rules-list"]
        let searchField = app.textFields["assignment-rules-search-field"]
        let backButton = app.buttons["Volver"]
        let title = app.staticTexts["Reglas de asignacion"]
        let rulesViewIsVisible = rulesList.waitForExistence(timeout: 6)
            || searchField.waitForExistence(timeout: 6)
            || backButton.waitForExistence(timeout: 6)
            || title.waitForExistence(timeout: 6)
        XCTAssertTrue(rulesViewIsVisible)
        XCTAssertTrue(app.staticTexts["com.momentum.seed.app"].waitForExistence(timeout: 6))
    }

    func testFeedbackSectionAppearsInSettings() throws {
        let app = launch(reset: true)
        app.typeKey(",", modifierFlags: .command)

        var settingsWindow = app.windows.matching(NSPredicate(format: "title == %@", "Configuración")).firstMatch
        if !settingsWindow.waitForExistence(timeout: 4) {
            settingsWindow = app.windows.firstMatch
        }

        let feedbackSectionLink = settingsWindow.buttons["settings-section-feedback"]
        XCTAssertTrue(feedbackSectionLink.waitForExistence(timeout: 6))
        feedbackSectionLink.click()

        let feedbackButton = settingsWindow.buttons["feedback-send-email-button"]
        XCTAssertTrue(feedbackButton.waitForExistence(timeout: 6))
        XCTAssertTrue(feedbackButton.isEnabled)
    }

    // MARK: - Helpers

    private func launch(
        reset: Bool,
        seedConflicts: Bool = false,
        seedRules: Bool = false,
        skipOnboarding: Bool = true,
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let storePath = suiteStorePath
        var arguments = [
            "--uitests",
            "--store-path",
            storePath,
            "-ApplePersistenceIgnoreState",
            "YES",
            "-ApplePersistenceIgnoreStateQuietly",
            "YES",
        ]
        if reset {
            arguments.append("--uitests-reset")
            clearTestStoreDirectory(at: storePath)
        }
        if seedConflicts {
            arguments.append("--seed-conflicts")
        }
        if seedRules {
            arguments.append("--seed-rules")
        }
        if skipOnboarding {
            arguments.append("--skip-onboarding")
        }
        app.launchEnvironment["MOMENTUM_STORE_PATH"] = storePath
        app.launchArguments = arguments
        app.launch()
        waitForMainWindow(in: app)
        return app
    }

    private func createProject(named name: String, domain: String?, in app: XCUIApplication) {
        let newProjectButton = app.buttons["action-panel-create-project"]
        XCTAssertTrue(newProjectButton.waitForExistence(timeout: 6))
        newProjectButton.click()

        let titleField = app.textFields["project-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 6))
        titleField.click()
        titleField.typeText(name)

        if let domain {
            let domainField = app.textFields["project-domains-field"]
            XCTAssertTrue(domainField.waitForExistence(timeout: 6))
            if !domainField.isHittable {
                let formScrollView = app.scrollViews.firstMatch
                if formScrollView.exists {
                    var attempts = 0
                    while !domainField.isHittable, attempts < 3 {
                        formScrollView.swipeUp()
                        attempts += 1
                    }
                }
            }
            domainField.click()
            domainField.typeText(domain)
        }

        let confirmButton = app.buttons["Crear"]
        XCTAssertTrue(confirmButton.isEnabled)
        confirmButton.click()
    }

    private func openProject(named name: String, in app: XCUIApplication) {
        let outline = app.outlines.firstMatch
        XCTAssertTrue(outline.waitForExistence(timeout: 6))
        let row = outline.cells.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        row.click()
    }

    private func openContextMenuAndSelectEdit(named name: String, in app: XCUIApplication) {
        let outline = app.outlines.firstMatch
        XCTAssertTrue(outline.waitForExistence(timeout: 6))
        let row = outline.cells.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        row.rightClick()
        let editMenuItem = app.menuItems["Editar"]
        XCTAssertTrue(editMenuItem.waitForExistence(timeout: 6))
        editMenuItem.click()
    }

    private func waitForMainWindow(in app: XCUIApplication, timeout: TimeInterval = 15) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout))
        app.activate()
        let createButton = app.buttons["action-panel-create-project"]
        if !createButton.waitForExistence(timeout: 3) {
            openMainWindowIfNeeded(in: app)
            dismissWelcomeIfNeeded(in: app)
        }
        XCTAssertTrue(createButton.waitForExistence(timeout: timeout))
    }

    private func openMainWindowIfNeeded(in app: XCUIApplication) {
        let fileMenu = app.menuBars.menuBarItems["File"]
        guard fileMenu.waitForExistence(timeout: 2) else { return }
        fileMenu.click()
        let newWindow = fileMenu.menuItems["New Window"]
        if newWindow.waitForExistence(timeout: 2) {
            newWindow.click()
            return
        }
        let newWindowSpanish = fileMenu.menuItems["Nueva ventana"]
        if newWindowSpanish.waitForExistence(timeout: 2) {
            newWindowSpanish.click()
        }
    }

    private func dismissWelcomeIfNeeded(in app: XCUIApplication) {
        let welcomeTitle = app.staticTexts["Bienvenido a Momentum"]
        guard welcomeTitle.waitForExistence(timeout: 2) else { return }
        let skipButton = app.buttons["Saltar"]
        if skipButton.waitForExistence(timeout: 2) {
            skipButton.click()
        }
    }

    private func openConflictResolutionSheet(in app: XCUIApplication) {
        let resolveButton = app.buttons["pending-conflict-resolve-button"]
        XCTAssertTrue(resolveButton.waitForExistence(timeout: 6), "Expected resolve button in pending conflict banner")
        if !resolveButton.isHittable {
            app.windows.firstMatch.click()
        }
        resolveButton.click()
        waitForConflictResolutionSheet(in: app)
    }

    private func waitForConflictResolutionSheet(in app: XCUIApplication, timeout: TimeInterval = 6) {
        let sheet = app.otherElements["pending-conflict-sheet"]
        let title = app.staticTexts["Resolver conflictos"]
        let sheetIsVisible = sheet.waitForExistence(timeout: timeout)
            || title.waitForExistence(timeout: timeout)
        XCTAssertTrue(sheetIsVisible, "Expected pending conflict resolution sheet to appear")
    }
}

private extension MomentumUITests {
    var suiteBaseDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/MomentumTestStores", isDirectory: true)
    }

    var suiteStorePath: String {
        let url = suiteBaseDirectory.appendingPathComponent("UITests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        return url.path
    }

    private func clearTestStoreDirectory(at path: String) {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
