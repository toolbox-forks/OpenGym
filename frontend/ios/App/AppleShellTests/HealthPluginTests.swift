import XCTest
import HealthKit
import Capacitor
import OpenGymKit
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
    private enum CallError: Error { case rejected(String) }
    private func invoke(_ plugin: HealthPlugin, method: String, options: [String: Any]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            guard let call = CAPPluginCall(callbackId: UUID().uuidString, methodName: method, options: JSTypes.coerceDictionaryToJSObject(options as NSDictionary) ?? [:],
                success: { result, _ in continuation.resume(returning: result?.data ?? [:]) },
                error: { error in continuation.resume(throwing: CallError.rejected(error?.code ?? "unknown")) }) else {
                continuation.resume(throwing: CallError.rejected("call")); return
            }
            if method == "write" { plugin.write(call) } else { plugin.read(call) }
        }
    }
    private var workoutOptions: [String: Any] {
        ["clientId": "opengym-w-old-id", "uuid": "bd0c1f64-9e48-4a29-a81e-4dcfcf79e218", "title": "Strength",
         "start": 1000.0, "end": 61000.0, "energyKcal": 120.0, "version": 1]
    }
    func testNativeBridgeWritesCompletedWorkoutOnceAndReadsMeasurements() async throws {
        let store = try MockHealthRecordStore(), plugin = HealthPlugin()
        plugin.testingStore = store
        let options: [String: Any] = ["workouts": [workoutOptions], "measurements": [
            ["clientId": "mass", "kind": "bodyMass", "value": 80.0, "time": 2000.0],
            ["clientId": "waist", "kind": "waist", "value": 0.85, "time": 2000.0]
        ]]
        _ = try await invoke(plugin, method: "write", options: options)
        _ = try await invoke(plugin, method: "write", options: options)
        let saved = await store.workouts()
        XCTAssertEqual(saved.count, 1)
        let workout = try XCTUnwrap(saved.first)
        XCTAssertEqual(workout.energyKcal, 120)
        XCTAssertEqual(workout.uuid, workoutOptions["uuid"] as? String)
        XCTAssertEqual(workout.end - workout.start, 60000)
        let read = try await invoke(plugin, method: "read", options: ["since": 0])
        XCTAssertEqual(read["mode"] as? String, "mock")
        let measurements = try XCTUnwrap(read["measurements"] as? [[String: Any]])
        XCTAssertEqual(measurements.count, 2)
        XCTAssertEqual(measurements.first(where: { $0["kind"] as? String == "waist" })?["value"] as? Double, 0.85)
    }
    func testNativeBridgeRejectsWholeMalformedBatchBeforeAnyWrite() async throws {
        let store = try MockHealthRecordStore(), plugin = HealthPlugin()
        plugin.testingStore = store
        let invalid: [[String: Any]] = [
            ["clientId": "bad", "uuid": "broken"],
            ["clientId": "bad", "uuid": "bd0c1f64-9e48-4a29-a81e-4dcfcf79e218", "title": "Bad", "start": 1000.0, "end": 61000.0, "energyKcal": Double.nan]
        ]
        for row in invalid {
            do {
                _ = try await invoke(plugin, method: "write", options: ["workouts": [workoutOptions, row]])
                XCTFail("Malformed batch accepted")
            } catch CallError.rejected(let code) { XCTAssertEqual(code, "mapping") }
        }
        let saved = await store.workouts(); XCTAssertTrue(saved.isEmpty)
    }
}
