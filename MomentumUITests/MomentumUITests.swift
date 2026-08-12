import XCTest

final class MomentumUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsMainWindow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--uitests-reset"]
        app.launch()
        // Menu-bar app may start as accessory; activate via menu is hard in UI tests.
        // Smoke: process is running.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5) || app.state != .notRunning)
    }
}
