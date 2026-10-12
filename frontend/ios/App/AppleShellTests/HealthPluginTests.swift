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
}
