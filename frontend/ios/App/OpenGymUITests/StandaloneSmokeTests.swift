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
        let search = app.searchFields.firstMatch
        let searchExists = search.waitForExistence(timeout: 10) || app.textFields.firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(searchExists, app.debugDescription)
        app.buttons["Home"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Plan"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["Use on this device"].exists, "Local mode must persist through the native file mirror")
    }
    func testHealthPurposeAndSimulatorOptInPersistAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let local = app.buttons["Use on this device"]
        if local.waitForExistence(timeout: 15) { local.tap() }
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["Home"].tap()
        app.buttons["Settings"].tap()
        let data = app.buttons["Data & backup"]
        XCTAssertTrue(data.waitForExistence(timeout: 10), app.debugDescription)
        data.tap()
        let toggle = app.switches["Sync with Apple Health"]
        if !toggle.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Simulator Health store"].exists, app.debugDescription)
        // The mock authorization is handled by the registered native plugin, without real sensors.
        if (toggle.value as? String) != "1" { toggle.tap() }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed, app.debugDescription)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["Home"].tap()
        app.buttons["Settings"].tap()
        app.buttons["Data & backup"].tap()
        if !toggle.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "1", "Health opt-in must survive relaunch")
        XCTAssertFalse(app.staticTexts["Could not sync Apple Health"].exists, app.debugDescription)
    }
}
