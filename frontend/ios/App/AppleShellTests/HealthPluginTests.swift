import XCTest
import HealthKit
@testable import App

final class HealthPluginTests: XCTestCase {
    func testActivityMappingIncludesCardioAndStrength() {
        XCTAssertEqual(AppleHealthStore.activity("strength_training"), .traditionalStrengthTraining)
        XCTAssertEqual(AppleHealthStore.activity("functional_strength"), .functionalStrengthTraining)
        XCTAssertEqual(AppleHealthStore.activity("hiit"), .highIntensityIntervalTraining)
        XCTAssertEqual(AppleHealthStore.activity("running"), .running)
        XCTAssertEqual(AppleHealthStore.activity("biking_stationary"), .cycling)
        XCTAssertEqual(AppleHealthStore.activity("unknown"), .traditionalStrengthTraining)
    }
    func testMeasurementTypesAndCanonicalUnits() {
        XCTAssertEqual(AppleHealthStore.type(.bodyMass).identifier, HKQuantityTypeIdentifier.bodyMass.rawValue)
        XCTAssertEqual(AppleHealthStore.type(.bodyFat).identifier, HKQuantityTypeIdentifier.bodyFatPercentage.rawValue)
        XCTAssertEqual(AppleHealthStore.type(.waist).identifier, HKQuantityTypeIdentifier.waistCircumference.rawValue)
        XCTAssertEqual(HKQuantity(unit: AppleHealthStore.unit(.bodyFat), doubleValue: 0.21).doubleValue(for: .percent()), 0.21)
        XCTAssertEqual(HKQuantity(unit: AppleHealthStore.unit(.waist), doubleValue: 0.85).doubleValue(for: .meter()), 0.85)
    }
    func testSimulatorNeverClaimsRealHealthKit() {
        #if targetEnvironment(simulator)
        XCTAssertEqual(HealthPlugin.mode, "mock")
        #endif
    }
    func testPreferencesAtomicReplacementAndRelaunch() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("health.json")
        XCTAssertTrue(try HealthPreferencesFile.read(file).isEmpty)
        try HealthPreferencesFile.write(["identities": ["old-id": "uuid-one"]], to: file)
        try HealthPreferencesFile.write(["identities": ["old-id": "uuid-two"]], to: file)
        let restored = try HealthPreferencesFile.read(file)
        XCTAssertEqual((restored["identities"] as? [String: String])?["old-id"], "uuid-two")
    }
    func testPreferencesCorruptionAndFailedWriteCannotRegenerateIdentity() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("health.json")
        try HealthPreferencesFile.write(["id": "stable"], to: file)
        XCTAssertThrowsError(try HealthPreferencesFile.write(["bad": Double.nan], to: file))
        XCTAssertEqual(try HealthPreferencesFile.read(file)["id"] as? String, "stable")
        try Data("{broken".utf8).write(to: file)
        XCTAssertThrowsError(try HealthPreferencesFile.read(file))
    }
}
