import XCTest

final class StandaloneSmokeTests: XCTestCase {
    func testLocalModeSurvivesRelaunchAndExistingScreensOpen() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let local = app.buttons["Use on this device"]
        if local.waitForExistence(timeout: 15) { local.tap() }
        XCTAssertTrue(app.buttons["Plan"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["Plan"].tap()
        app.buttons["Stats"].tap()
        app.buttons["Exercises"].tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Home"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Plan"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["Use on this device"].exists, "Local mode must persist through the native file mirror")
    }
}
