import Foundation
import XCTest
@testable import OpenGymKit

final class ContractTests: XCTestCase {
    let decoder=JSONDecoder(), encoder=JSONEncoder()
    func data(_ text: String) -> Data { Data(text.utf8) }
    func testAllEnvelopeKindsRoundTrip() throws {
        let payload=try decoder.decode(JSONValue.self,from:data(#"{"id":"old-short-id","future":{"x":[1,true,null]}}"#))
        for kind in [SyncEnvelope.Kind.snapshot,.workoutCompleted,.liveEvent,.ack] {
            let original=try SyncEnvelope(kind:kind,payload:payload,sentAt:1000)
            XCTAssertEqual(try decoder.decode(SyncEnvelope.self,from:encoder.encode(original)),original)
        }
    }
    func testUnsupportedVersionsRejected() {
        for version in [0,2,99] {
            XCTAssertThrowsError(try SyncEnvelope(schemaVersion:version,kind:.ack,payload:.object([:]),sentAt:0))
        }
    }
    func testUnknownKindAndExtraFieldsRejected() {
        for value in [#"{"schemaVersion":1,"kind":"other","payload":{},"sentAt":0}"#, #"{"schemaVersion":1,"kind":"ack","payload":{},"sentAt":0,"extra":true}"#] {
            XCTAssertThrowsError(try decoder.decode(SyncEnvelope.self,from:data(value)))
        }
    }
    func testInvalidTimestampAndPayloadRejected() {
        XCTAssertThrowsError(try SyncEnvelope(kind:.ack,payload:.object([:]),sentAt:-1))
        XCTAssertThrowsError(try SyncEnvelope(kind:.ack,payload:.object([:]),sentAt:.infinity))
        XCTAssertThrowsError(try SyncEnvelope(kind:.ack,payload:.array([]),sentAt:0))
    }
    func testPrototypeMigrationPreservesPayload() throws {
        let migrated=try SyncEnvelope.migrate(data(#"{"schemaVersion":0,"kind":"snapshot","payload":{"workouts":[{"id":"legacy"}]},"sentAt":20}"#))
        XCTAssertEqual(migrated.schemaVersion,1)
        XCTAssertEqual(migrated.payload.rows("workouts").first?.text("id"),"legacy")
        XCTAssertThrowsError(try SyncEnvelope.migrate(data(#"{"schemaVersion":0,"kind":"ack","payload":{},"sentAt":20}"#)))
        XCTAssertThrowsError(try SyncEnvelope.migrate(data(#"{"schemaVersion":0,"kind":"snapshot","payload":{},"sentAt":"20"}"#)))
    }
    func testLegacyStateUnknownFieldsAndCatalogueIDsSurvive() throws {
        let original=try decoder.decode(JSONValue.self,from:data(#"{"unit":"kg","future":{"keep":true},"workouts":[{"id":"legacy-id","entries":[{"id":"0025","future":9,"sets":[{"w":60,"r":5,"done":true,"note":"keep"}]}]}]}"#))
        let state=try decoder.decode(GymState.self,from:encoder.encode(original))
        XCTAssertEqual(state.workouts.first?.entries.first?.exerciseID,"0025")
        XCTAssertEqual(state.workouts.first?.entries.first?.sets.first?.weight,60)
        XCTAssertEqual(try decoder.decode(JSONValue.self,from:encoder.encode(state)),original)
    }
    func testStateRecordRejectsNonObject() {
        XCTAssertThrowsError(try decoder.decode(Workout.self,from:data("[]")))
    }
    func testIdentityUsesCanonicalUUIDAndValidatesClockDevice() throws {
        let id=UUID(uuidString:"13BBF91D-172D-4F2C-8A86-B4858E9FCECF")!
        let stamp=try RecordIdentity(uuid:id,updatedAt:1000,deviceId:"watch-a")
        let value=try decoder.decode(JSONValue.self,from:encoder.encode(stamp))
        XCTAssertEqual(value.text("uuid"),id.uuidString.lowercased())
        XCTAssertEqual(try decoder.decode(RecordIdentity.self,from:encoder.encode(stamp)),stamp)
        XCTAssertThrowsError(try RecordIdentity(updatedAt:0,deviceId:"  "))
        XCTAssertThrowsError(try RecordIdentity(updatedAt:-1,deviceId:"a"))
    }
    func testNonFiniteJSONCannotEncode() {
        XCTAssertThrowsError(try encoder.encode(JSONValue.object(["w":.number(.nan)])))
    }
}
