import Foundation
import XCTest
@testable import OpenGymKit

final class HealthMappingTests:XCTestCase {
    let uuid="bd0c1f64-9e48-4a29-a81e-4dcfcf79e218"
    func workout(version:Int=1) throws -> HealthWorkoutRecord {try .init(clientId:"w-one",uuid:uuid,title:"Strength",start:1000,end:61000,energyKcal:120,version:version)}
    func testWorkoutDatesEnergyIdentityMapping() throws {
        let w=try workout();XCTAssertEqual(w.end-w.start,60000);XCTAssertEqual(w.energyKcal,120);XCTAssertEqual(w.uuid,uuid)
        XCTAssertThrowsError(try HealthWorkoutRecord(clientId:"a",uuid:uuid,title:"",start:1000,end:1000))
        XCTAssertThrowsError(try HealthWorkoutRecord(clientId:"a",uuid:"bad",title:"",start:1000,end:2000))
        XCTAssertThrowsError(try HealthWorkoutRecord(clientId:"a",uuid:uuid,title:"",start:1000,end:2000,energyKcal:-1))
    }
    func testMeasurementCanonicalUnits() throws {
        let lb=try HealthMeasurementRecord.fromApp(clientId:"mass",kind:.bodyMass,value:220.46226218,time:1000,unit:.lb)
        XCTAssertEqual(lb.value,100,accuracy:1e-8)
        let fat=try HealthMeasurementRecord.fromApp(clientId:"fat",kind:.bodyFat,value:21,time:1000)
        XCTAssertEqual(fat.value,0.21,accuracy:1e-9);XCTAssertEqual(fat.appValue,21)
        let waist=try HealthMeasurementRecord.fromApp(clientId:"waist",kind:.waist,value:85,time:1000)
        XCTAssertEqual(waist.value,0.85,accuracy:1e-9);XCTAssertEqual(waist.appValue,85)
        XCTAssertThrowsError(try HealthMeasurementRecord.fromApp(clientId:"a",kind:.bodyFat,value:110,time:1000))
    }
    func testSourceTimestampAndSampleIdentityDeduplication() throws {
        let a=try HealthMeasurementRecord(clientId:"a",kind:.bodyMass,value:80,time:1000,source:"Oura",sampleId:"sample")
        let b=try HealthMeasurementRecord(clientId:"b",kind:.bodyMass,value:80,time:2000,source:"Oura",sampleId:"sample")
        let other=try HealthMeasurementRecord(clientId:"c",kind:.bodyMass,value:80,time:1000,source:"Scale",sampleId:"sample")
        XCTAssertEqual(a.deduplicationKey,b.deduplicationKey);XCTAssertNotEqual(a.deduplicationKey,other.deduplicationKey)
    }
    func testRepeatedWorkoutWritesOnceAndNewVersionReplaces() async throws {
        let store=try MockHealthRecordStore();let w=try workout()
        try await store.upsert(workout:w);try await store.upsert(workout:w)
        var rows=await store.workouts();XCTAssertEqual(rows.count,1)
        try await store.upsert(workout:workout(version:2));rows=await store.workouts();XCTAssertEqual(rows.count,1);XCTAssertEqual(rows[0].version,2)
        try await store.upsert(workout:w);rows=await store.workouts();XCTAssertEqual(rows[0].version,2)
    }
    func testMockStoreSurvivesRelaunch() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("mock-health.json"),store=try MockHealthRecordStore(file:file)
        try await store.upsert(workout:workout())
        try await store.upsert(measurement:HealthMeasurementRecord.fromApp(clientId:"mass",kind:.bodyMass,value:80,time:2000))
        let restored=try MockHealthRecordStore(file:file)
        let workouts=await restored.workouts(),measurements=await restored.measurements(since:0)
        XCTAssertEqual(workouts.count,1);XCTAssertEqual(measurements.count,1)
        let empty=await restored.measurements(since:3000);XCTAssertTrue(empty.isEmpty)
    }
    func testDecodedRecordsCannotBypassValidation() throws {
        let decoder=JSONDecoder()
        let invalidWorkout=Data(#"{"clientId":"a","uuid":"bad","title":"","start":1000,"end":2000}"#.utf8)
        let invalidMeasurement=Data(#"{"clientId":"a","kind":"bodyFat","value":1.1,"time":1000}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(HealthWorkoutRecord.self,from:invalidWorkout))
        XCTAssertThrowsError(try decoder.decode(HealthMeasurementRecord.self,from:invalidMeasurement))
        let roundtrip=try decoder.decode(HealthWorkoutRecord.self,from:JSONEncoder().encode(workout()))
        XCTAssertEqual(roundtrip,try workout())
    }
    func testMeasurementRetryAndStaleVersionAreIdempotent() async throws {
        let store=try MockHealthRecordStore()
        let first=try HealthMeasurementRecord(clientId:"mass",kind:.bodyMass,value:80,time:1000)
        let edit=try HealthMeasurementRecord(clientId:"mass",kind:.bodyMass,value:81,time:1000,version:2)
        try await store.upsert(measurement:first);try await store.upsert(measurement:first)
        try await store.upsert(measurement:edit);try await store.upsert(measurement:first)
        let rows=await store.measurements(since:0)
        XCTAssertEqual(rows.count,1);XCTAssertEqual(rows[0].value,81)
    }
    func testWorkoutUUIDDeduplicatesLegacyIdAliases() async throws {
        let store=try MockHealthRecordStore()
        try await store.upsert(workout:workout())
        let alias=try HealthWorkoutRecord(clientId:"another-id",uuid:uuid,title:"Same",start:1000,end:61000)
        try await store.upsert(workout:alias)
        let rows=await store.workouts();XCTAssertEqual(rows.count,1)
    }
}
