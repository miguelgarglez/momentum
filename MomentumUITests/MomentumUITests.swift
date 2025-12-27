import XCTest

final class MomentumUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCreateProjectFlow() throws {
        let app = launch(reset: true)
        createProject(named: "UI Test Project", domain: "momentum.run", in: app)
        XCTAssertTrue(app.staticTexts["UI Test Project"].waitForExistence(timeout: 3))
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
            while !domainsField.isHittable && attempts < 3 {
                formScrollView.swipeUp()
                attempts += 1
            }
        }
        domainsField.click()
        domainsField.typeKey("a", modifierFlags: .command)
        domainsField.typeText("momentum.run, docs.test")
        app.buttons["Guardar"].click()
        XCTAssertTrue(app.staticTexts["docs.test"].waitForExistence(timeout: 3))
    }

    func testDashboardDisplaysWelcomeMetrics() throws {
        let app = launch(reset: true)
        createProject(named: "Dashboard Focus", domain: nil, in: app)
        XCTAssertTrue(app.staticTexts["Mide tu progreso, no tu productividad."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Tus proyectos"].exists)
    }

    func testConflictBannerOpensResolutionSheet() throws {
        let app = launch(reset: true, seedConflicts: true)
        let conflictsText = app.staticTexts["Tienes 2 contexto(s) por resolver."]
        XCTAssertTrue(conflictsText.waitForExistence(timeout: 3))

        let resolveButton = app.buttons["Resolver"]
        XCTAssertTrue(resolveButton.waitForExistence(timeout: 2))
        resolveButton.click()

        let sheetTitle = app.staticTexts["Resolver conflictos"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 3))
    }

    func testConflictListShowsAppAndDomainRows() throws {
        let app = launch(reset: true, seedConflicts: true)
        let resolveButton = app.buttons["Resolver"]
        XCTAssertTrue(resolveButton.waitForExistence(timeout: 3))
        resolveButton.click()

        let sheetTitle = app.staticTexts["Resolver conflictos"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Seed App"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["example.com"].waitForExistence(timeout: 2))
    }

    func testConflictResolutionAssignsProject() throws {
        let app = launch(reset: true, seedConflicts: true)
        let resolveButton = app.buttons["Resolver"]
        XCTAssertTrue(resolveButton.waitForExistence(timeout: 3))
        resolveButton.click()

        let sheetTitle = app.staticTexts["Resolver conflictos"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 3))
        let assignButton = app.buttons["Asignar"].firstMatch
        XCTAssertTrue(assignButton.waitForExistence(timeout: 3))
        XCTAssertTrue(assignButton.isEnabled)
        assignButton.click()

        let closeButton = app.buttons["Cerrar"]
        if closeButton.waitForExistence(timeout: 2) {
            closeButton.click()
        }

        let bannerText = app.staticTexts["Tienes 1 contexto(s) por resolver."]
        XCTAssertTrue(bannerText.waitForExistence(timeout: 3))
    }

    // MARK: - Helpers

    private func launch(reset: Bool, seedConflicts: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        let storePath = suiteStorePath
        var arguments = ["--uitests", "--store-path", storePath]
        if reset {
            arguments.append("--uitests-reset")
            clearTestStoreDirectory(at: storePath)
        }
        if seedConflicts {
            arguments.append("--seed-conflicts")
        }
        app.launchEnvironment["MOMENTUM_STORE_PATH"] = storePath
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func createProject(named name: String, domain: String?, in app: XCUIApplication) {
        let newProjectButton = app.buttons["Nuevo proyecto"]
        XCTAssertTrue(newProjectButton.waitForExistence(timeout: 2))
        newProjectButton.click()

        let titleField = app.textFields["project-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.click()
        titleField.typeText(name)

        if let domain {
            let domainField = app.textFields["project-domains-field"]
            XCTAssertTrue(domainField.waitForExistence(timeout: 2))
            if !domainField.isHittable {
                let formScrollView = app.scrollViews.firstMatch
                if formScrollView.exists {
                    var attempts = 0
                    while !domainField.isHittable && attempts < 3 {
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
        XCTAssertTrue(outline.waitForExistence(timeout: 2))
        let row = outline.cells.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(row.exists)
        row.click()
    }

    private func openContextMenuAndSelectEdit(named name: String, in app: XCUIApplication) {
        let outline = app.outlines.firstMatch
        XCTAssertTrue(outline.waitForExistence(timeout: 2))
        let row = outline.cells.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(row.exists)
        row.rightClick()
        let editMenuItem = app.menuItems["Editar"]
        XCTAssertTrue(editMenuItem.waitForExistence(timeout: 2))
        editMenuItem.click()
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
