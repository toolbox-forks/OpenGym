import Foundation
import HealthKit
import OpenGymKit

struct WatchVitals {
    var heartRate: Double?
    var energyKcal: Double?
    var mock = false
    var unavailable = false
}

@MainActor
final class WatchHealth: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private let health = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var timer: Timer?
    private var active: JSONValue?
    private(set) var vitals = WatchVitals()
    var onUpdate: ((WatchVitals) -> Void)?
    private let mockStore: MockHealthRecordStore
    init(folder: URL) throws {
        mockStore = try MockHealthRecordStore(file: folder.appendingPathComponent("mock-health.json"))
        super.init()
    }
    func authorize() async throws {
        #if targetEnvironment(simulator)
        vitals.mock = true
        #else
        let workout = HKObjectType.workoutType(), energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        let heart = HKObjectType.quantityType(forIdentifier: .heartRate)!
        try await health.requestAuthorization(toShare: [workout, energy], read: [workout, energy, heart])
        #endif
    }
    func start(_ workout: JSONValue, recovering: Bool = false) async throws {
        active = workout
        #if targetEnvironment(simulator)
        vitals = WatchVitals(heartRate: 123, energyKcal: workout.number("energyKcal"), mock: true)
        onUpdate?(vitals)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.vitals.energyKcal = (self.vitals.energyKcal ?? 0) + 0.1
                self.onUpdate?(self.vitals)
            }
        }
        #else
        if recovering {
            let recovered: HKWorkoutSession? = try await withCheckedThrowingContinuation { continuation in
                health.recoverActiveWorkoutSession { session, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: session) }
                }
            }
            if let recovered { attach(recovered); update(); return }
        }
        let config = HKWorkoutConfiguration()
        config.activityType = workout.rows("entries").allSatisfy { $0["target"].text("mode") == "cardio" } ? .other : .traditionalStrengthTraining
        let session = try HKWorkoutSession(healthStore: health, configuration: config)
        attach(session)
        builder?.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: config)
        let date = Date(timeIntervalSince1970: workout.number("start") / 1000)
        session.startActivity(with: date)
        try await builder?.beginCollection(at: date)
        try await builder?.addMetadata([HKMetadataKeyExternalUUID: workout.text("uuid"),
            HKMetadataKeySyncIdentifier: "opengym-workout-" + workout.text("uuid"), HKMetadataKeySyncVersion: 1,
            "openGymClientId": "opengym-w-" + workout.text("id"), "openGymTitle": workout.text("name")])
        #endif
    }
    private func attach(_ value: HKWorkoutSession) {
        session = value; builder = value.associatedWorkoutBuilder()
        session?.delegate = self; builder?.delegate = self
    }
    private func update() {
        let heart = HKObjectType.quantityType(forIdentifier: .heartRate)!, energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        if let value = builder?.statistics(for: heart)?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) { vitals.heartRate = value }
        if let value = builder?.statistics(for: energy)?.sumQuantity()?.doubleValue(for: .kilocalorie()) { vitals.energyKcal = value }
        onUpdate?(vitals)
    }
    func finish(_ workout: JSONValue, end: Double) async throws -> Bool {
        timer?.invalidate(); timer = nil
        #if targetEnvironment(simulator)
        let record = try HealthWorkoutRecord(clientId: "opengym-w-" + workout.text("id"), uuid: workout.text("uuid"),
            title: workout.text("name"), start: workout.number("start"), end: end, energyKcal: vitals.energyKcal)
        try await mockStore.upsert(workout: record)
        active = nil; return true
        #else
        guard let session, let builder else { return false }
        let date = Date(timeIntervalSince1970: end / 1000)
        session.end()
        try await builder.endCollection(at: date)
        _ = try await builder.finishWorkout()
        self.session = nil; self.builder = nil; active = nil
        return true
        #endif
    }
    func mockWorkouts() async -> [HealthWorkoutRecord] { await mockStore.workouts() }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.vitals.unavailable = true; if let self { self.onUpdate?(self.vitals) } }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor [weak self] in self?.update() }
    }
}
