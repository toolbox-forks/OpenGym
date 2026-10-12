import Capacitor
import Foundation
import HealthKit
import OpenGymKit

/// Apple frameworks stay outside the shared package. Simulator storage is explicitly labelled.
actor AppleHealthStore: HealthRecordStore {
    let health = HKHealthStore()
    static let quantities: [HealthMeasurementRecord.Kind: HKQuantityTypeIdentifier] = [
        .bodyMass: .bodyMass, .bodyFat: .bodyFatPercentage, .waist: .waistCircumference
    ]
    static func type(_ kind: HealthMeasurementRecord.Kind) -> HKQuantityType {
        HKObjectType.quantityType(forIdentifier: quantities[kind]!)!
    }
    static func unit(_ kind: HealthMeasurementRecord.Kind) -> HKUnit {
        switch kind { case .bodyMass: return .gramUnit(with: .kilo); case .bodyFat: return .percent(); case .waist: return .meter() }
    }
    static func activity(_ name: String) -> HKWorkoutActivityType {
        switch name {
        case "functional_strength": return .functionalStrengthTraining
        case "hiit": return .highIntensityIntervalTraining
        case "walking": return .walking
        case "running": return .running
        case "biking_stationary": return .cycling
        case "elliptical": return .elliptical
        case "stair_climbing_machine": return .stairClimbing
        case "other_workout": return .other
        default: return .traditionalStrengthTraining
        }
    }
    func authorize() async throws {
        let writes: Set<HKSampleType> = [HKObjectType.workoutType(), HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            Self.type(.bodyMass), Self.type(.bodyFat), Self.type(.waist)]
        var reads: Set<HKObjectType> = Set(writes)
        for id: HKQuantityTypeIdentifier in [.heartRate, .restingHeartRate, .heartRateVariabilitySDNN] {
            reads.insert(HKObjectType.quantityType(forIdentifier: id)!)
        }
        reads.insert(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        try await health.requestAuthorization(toShare: writes, read: reads)
        // HealthKit deliberately does not reveal read authorization. Never infer it from empty results.
    }
    func query(_ type: HKSampleType, predicate: NSPredicate?, limit: Int = HKObjectQueryNoLimit) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            health.execute(query)
        }
    }
    func upsert(workout: HealthWorkoutRecord) async throws {
        let identifier = "opengym-workout-" + workout.uuid
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [identifier])
        let previous = try await query(HKObjectType.workoutType(), predicate: predicate)
        if previous.contains(where: { ($0.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue ?? 0 >= workout.version }) { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activity(workout.activity)
        let builder = HKWorkoutBuilder(healthStore: health, configuration: configuration, device: .local())
        let start = Date(timeIntervalSince1970: workout.start / 1000), end = Date(timeIntervalSince1970: workout.end / 1000)
        try await builder.beginCollection(at: start)
        try await builder.addMetadata([HKMetadataKeySyncIdentifier: identifier, HKMetadataKeySyncVersion: workout.version,
            HKMetadataKeyExternalUUID: workout.uuid, "openGymClientId": workout.clientId, "openGymTitle": workout.title])
        if let energy = workout.energyKcal {
            let sample = HKQuantitySample(type: HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energy), start: start, end: end)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                builder.add([sample]) { success, error in
                    if let error { continuation.resume(throwing: error) }
                    else if success { continuation.resume() }
                    else { continuation.resume(throwing: NSError(domain: "openGymHealth", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Health did not accept the energy sample"])) }
                }
            }
        }
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }
    func upsert(measurement: HealthMeasurementRecord) async throws {
        let identifier = "opengym-measurement-" + measurement.clientId
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [identifier])
        let previous = try await query(Self.type(measurement.kind), predicate: predicate)
        if previous.contains(where: { ($0.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue ?? 0 >= measurement.version }) { return }
        let date = Date(timeIntervalSince1970: measurement.time / 1000)
        let sample = HKQuantitySample(type: Self.type(measurement.kind), quantity: HKQuantity(unit: Self.unit(measurement.kind), doubleValue: measurement.value),
            start: date, end: date, metadata: [HKMetadataKeySyncIdentifier: identifier, HKMetadataKeySyncVersion: measurement.version,
                "openGymClientId": measurement.clientId])
        try await health.save(sample)
    }
    func workouts() async throws -> [HealthWorkoutRecord] {
        let rows = try await query(HKObjectType.workoutType(), predicate: HKQuery.predicateForObjects(withMetadataKey: "openGymClientId"))
        return rows.compactMap { sample in
            guard let w = sample as? HKWorkout, let id = w.metadata?["openGymClientId"] as? String,
                let uuid = w.metadata?[HKMetadataKeyExternalUUID] as? String else { return nil }
            return try? HealthWorkoutRecord(clientId: id, uuid: uuid, title: w.metadata?["openGymTitle"] as? String ?? "", start: w.startDate.timeIntervalSince1970 * 1000,
                end: w.endDate.timeIntervalSince1970 * 1000, energyKcal: w.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                version: (w.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue ?? 1)
        }
    }
    func measurements(since: Double) async throws -> [HealthMeasurementRecord] {
        var result: [HealthMeasurementRecord] = []
        let predicate = HKQuery.predicateForSamples(withStart: Date(timeIntervalSince1970: since / 1000), end: nil, options: .strictStartDate)
        for kind in [HealthMeasurementRecord.Kind.bodyMass, .bodyFat, .waist] {
            let rows = try await query(Self.type(kind), predicate: predicate)
            for sample in rows {
                guard let q = sample as? HKQuantitySample else { continue }
                let own = q.metadata?["openGymClientId"] as? String
                if let record = try? HealthMeasurementRecord(clientId: own ?? q.uuid.uuidString.lowercased(), kind: kind,
                    value: q.quantity.doubleValue(for: Self.unit(kind)), time: q.startDate.timeIntervalSince1970 * 1000,
                    source: q.sourceRevision.source.bundleIdentifier, sampleId: q.uuid.uuidString.lowercased(),
                    version: (q.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue ?? 1) { result.append(record) }
            }
        }
        return result.sorted { $0.time < $1.time }
    }
}

/// Atomic replacement retains the previous identity map if the app dies during a write.
enum HealthPreferencesFile {
    static func read(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let result = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw HealthMappingError.invalidIdentity
        }
        return result
    }
    static func write(_ object: [String: Any], to url: URL) throws {
        guard JSONSerialization.isValidJSONObject(object) else { throw HealthMappingError.invalidIdentity }
        let data = try JSONSerialization.data(withJSONObject: object)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

@objc(HealthPlugin)
final class HealthPlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "HealthPlugin"
    let jsName = "AppleHealth"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "preferences", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "savePreferences", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "status", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "authorize", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "write", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "read", returnType: CAPPluginReturnPromise)
    ]
    private let real = AppleHealthStore()
    #if DEBUG
    var testingStore: MockHealthRecordStore?
    #endif
    private var store: any HealthRecordStore { get throws {
        #if DEBUG
        if let testingStore { return testingStore }
        #endif
        #if targetEnvironment(simulator)
        if let mock { return mock }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let value = try MockHealthRecordStore(file: folder.appendingPathComponent("openGym-mock-health.json"))
        mock = value
        return value
        #else
        return real
        #endif
    } }
    private var mock: MockHealthRecordStore?
    static var mode: String {
        #if targetEnvironment(simulator)
        return "mock"
        #else
        return HKHealthStore.isHealthDataAvailable() ? "healthkit" : "unsupported"
        #endif
    }
    private var preferencesURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("opengym-apple-health.json")
    }
    @objc func preferences(_ call: CAPPluginCall) {
        do { call.resolve(try HealthPreferencesFile.read(preferencesURL)) }
        catch { call.reject(error.localizedDescription, "storage", error) }
    }
    @objc func savePreferences(_ call: CAPPluginCall) {
        guard let object = call.getObject("preferences") else { call.reject("Missing preferences", "mapping"); return }
        do { try HealthPreferencesFile.write(object, to: preferencesURL); call.resolve() }
        catch { call.reject(error.localizedDescription, "storage", error) }
    }
    @objc func status(_ call: CAPPluginCall) { call.resolve(["mode": Self.mode]) }
    @objc func authorize(_ call: CAPPluginCall) {
        Task {
            do {
                if Self.mode == "unsupported" { call.reject("HealthKit unavailable", "unavailable"); return }
                #if !targetEnvironment(simulator)
                try await real.authorize()
                #endif
                call.resolve(["mode": Self.mode])
            } catch { call.reject(error.localizedDescription, "permission", error) }
        }
    }
    @objc func write(_ call: CAPPluginCall) {
        // Decode the complete batch before writing any samples, so malformed JS cannot partly import.
        do {
            let decoder = JSONDecoder()
            let workoutObjects = call.getArray("workouts") ?? [], measurementObjects = call.getArray("measurements") ?? []
            guard JSONSerialization.isValidJSONObject(workoutObjects), JSONSerialization.isValidJSONObject(measurementObjects) else {
                call.reject("Invalid Health records", "mapping"); return
            }
            let workouts = try decoder.decode([HealthWorkoutRecord].self, from: JSONSerialization.data(withJSONObject: workoutObjects))
            let measurements = try decoder.decode([HealthMeasurementRecord].self, from: JSONSerialization.data(withJSONObject: measurementObjects))
            let target = try store
            Task {
                do {
                    for workout in workouts { try await target.upsert(workout: workout) }
                    for measurement in measurements { try await target.upsert(measurement: measurement) }
                    call.resolve(["mode": Self.mode])
                } catch { call.reject(error.localizedDescription, "write", error) }
            }
        } catch { call.reject(error.localizedDescription, "mapping", error) }
    }
    @objc func read(_ call: CAPPluginCall) {
        do {
            let target = try store, since = call.getDouble("since") ?? 0
            guard since.isFinite, since >= 0 else { call.reject("Invalid timestamp", "mapping"); return }
            Task {
                do {
                    let rows = try await target.measurements(since: since)
                    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rows))
                    call.resolve(["mode": Self.mode, "measurements": object])
                } catch { call.reject(error.localizedDescription, "read", error) }
            }
        } catch { call.reject(error.localizedDescription, "store", error) }
    }
}
