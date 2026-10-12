import XCTest

final class WatchStandaloneTests: XCTestCase {
    func app(_ label: String, reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-seed", "--ui-case", label, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if reset { app.launchArguments.append("--ui-reset") }
        return app
    }
    func testStartLogThreeRestAndFinishWithoutPhone() {
        let app = app("three-sets", reset: true)
        app.launch()
        let today = app.buttons["start-today"]
        XCTAssertTrue(today.waitForExistence(timeout: 20), app.debugDescription)
        today.tap()
        let allow = app.buttons["allow-health"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10), app.debugDescription); allow.tap()
        let done = app.buttons["complete-set"]
        XCTAssertTrue(done.waitForExistence(timeout: 20), app.debugDescription)
        for index in 1...3 {
            done.tap()
            let count = app.staticTexts["completed-count"]
            let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", String(index)), object: count)
            XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed, app.debugDescription)
            let skip = app.buttons["rest-skip"]
            if skip.exists { skip.tap() }
        }
        app.swipeUp()
        let finish = app.buttons["finish-workout"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), app.debugDescription); finish.tap()
        XCTAssertTrue(app.staticTexts["workout-saved"].waitForExistence(timeout: 20), app.debugDescription)
    }
    func testJournalResumesExactSetAndRestAfterRelaunch() {
        let app = app("resume", reset: true)
        app.launch()
        XCTAssertTrue(app.buttons["start-today"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["start-today"].tap()
        XCTAssertTrue(app.buttons["allow-health"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["allow-health"].tap()
        XCTAssertTrue(app.buttons["complete-set"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["complete-set"].tap()
        XCTAssertTrue(app.staticTexts["completed-count"].waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
        let restored = self.app("resume", reset: false)
        restored.launch()
        XCTAssertTrue(restored.buttons["complete-set"].waitForExistence(timeout: 20), restored.debugDescription)
        XCTAssertTrue(restored.staticTexts["set-context"].label.contains("2"), restored.debugDescription)
        XCTAssertTrue(restored.staticTexts["completed-count"].label.contains("1"), restored.debugDescription)
    }
}
