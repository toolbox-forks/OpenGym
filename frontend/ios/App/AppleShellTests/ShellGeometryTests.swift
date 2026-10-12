import XCTest
@testable import App

final class ShellGeometryTests: XCTestCase {
    private let phone = CGRect(x: 0, y: 0, width: 393, height: 852)
    func testDockedKeyboardOccludesOnlyOverlap() {
        XCTAssertEqual(ShellGeometry.keyboardOcclusion(bounds: phone,
            keyboard: CGRect(x: 0, y: 516, width: 393, height: 400)), 336)
    }
    func testHiddenKeyboardDoesNotLiftSheets() {
        XCTAssertEqual(ShellGeometry.keyboardOcclusion(bounds: phone,
            keyboard: CGRect(x: 0, y: 852, width: 393, height: 336)), 0)
    }
    func testFloatingKeyboardDoesNotMoveBottomControls() {
        XCTAssertEqual(ShellGeometry.keyboardOcclusion(bounds: phone,
            keyboard: CGRect(x: 40, y: 300, width: 300, height: 200)), 0)
    }
    func testNarrowBottomKeyboardDoesNotLiftWholeScreen() {
        XCTAssertEqual(ShellGeometry.keyboardOcclusion(bounds: phone,
            keyboard: CGRect(x: 180, y: 516, width: 200, height: 336)), 0)
    }
    func testLandscapeGeometryUsesViewCoordinates() {
        XCTAssertEqual(ShellGeometry.keyboardOcclusion(bounds: CGRect(x: 0, y: 0, width: 852, height: 393),
            keyboard: CGRect(x: 0, y: 193, width: 852, height: 200)), 200)
    }
}
