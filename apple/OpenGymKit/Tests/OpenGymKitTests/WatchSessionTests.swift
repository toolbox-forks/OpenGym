import Foundation
import XCTest
@testable import OpenGymKit

final class WatchSessionTests:XCTestCase {
    let now=1_791_806_400_000.0
    var catalogue:[String:JSONValue] {[
        "row":.object(["id":.string("row"),"n":.string("Row"),"facts":.object(["loaded":.bool(true),"increment":.number(2.5)])]),
        "press":.object(["id":.string("press"),"n":.string("Press"),"facts":.object(["loaded":.bool(true),"increment":.number(2.5)])]),
        "run":.object(["id":.string("run"),"n":.string("Run"),"facts":.object(["loaded":.bool(false),"cardio":.bool(true)])])
    ]}
    func config(_ id:String="row",mode:String="reps",group:String="") -> JSONValue {
        .object(["id":.string(id),"mode":.string(mode),"sets":.number(3),"reps":.number(5),"weight":.number(60),"sec":.number(30),"min":.number(10),"inc":.number(2.5),"sg":.string(group),"rest":.number(30)])
    }
    func seed(ex:[JSONValue]?=nil,history:Bool=false) -> WatchTrainingState {
        let previous=JSONValue.object(["id":.string("old"),"d":.string("2026-10-01"),"routineId":.string("r"),"entries":.array([
            .object(["id":.string("row"),"rid":.string("r"),"target":config(),"sets":.array((0..<3).map{_ in .object(["w":.number(60),"r":.number(5),"done":.bool(true)])})])])])
        return WatchTrainingState(deviceId:"device-a",snapshot:.object(["unit":.string("kg"),"tz":.string("UTC"),"routines":.array([
            .object(["id":.string("r"),"name":.string("Routine"),"prog":.string("linear"),"ex":.array(ex ?? [config()])])
        ]),"workouts":.array(history ? [previous] : [])]))
    }
    func machine(ex:[JSONValue]?=nil,history:Bool=false) throws -> WatchSessionMachine {
        var m=WatchSessionMachine(state:seed(ex:ex,history:history),catalogue:catalogue);try m.start(routineId:"r",now:now);return m
    }
    func testRoutineAndEmptyStartDoNotNeedPhone() throws {
        let m=try machine();XCTAssertEqual(m.entries.count,1);XCTAssertEqual(m.currentEntry?.text("id"),"row")
        var empty=WatchSessionMachine(state:seed(),catalogue:catalogue);try empty.start(routineId:nil,now:now)
        XCTAssertEqual(empty.entries.count,0);try empty.addExercise(id:"press",now:now+1);XCTAssertEqual(empty.entries.count,1)
        XCTAssertThrowsError(try empty.start(routineId:nil,now:now+2))
    }
    func testPreviousPrefillAndExplainedProgression() throws {
        let m=try machine(history:true)
        XCTAssertEqual(m.currentSet?.number("w"),62.5);XCTAssertEqual(m.currentSet?.number("r"),5)
        XCTAssertEqual(m.currentEntry?["previous"].text("id"),"row")
        XCTAssertFalse(m.currentEntry?["plan"].rows("why").isEmpty ?? true)
    }
    func testIdentityDoesNotReplaceCatalogueIdAndStaleTapCannotTickNextSet() throws {
        var m=try machine();let set=try XCTUnwrap(m.currentSet)
        XCTAssertNotNil(UUID(uuidString:set.text("uuid")));XCTAssertEqual(m.currentEntry?.text("id"),"row")
        XCTAssertTrue(try m.confirm(expectedSetUUID:set.text("uuid"),now:now+1000))
        XCTAssertFalse(try m.confirm(expectedSetUUID:set.text("uuid"),now:now+1001));XCTAssertEqual(m.completedSetCount,1)
        XCTAssertEqual(m.currentSet?.number("r"),5)
    }
    func testAdjustmentsEffortAndInvalidValues() throws {
        var m=try machine();try m.adjust(field:"w",value:67.5,now:now+1);try m.adjust(field:"r",value:8,now:now+2);try m.adjust(field:"rir",value:2,now:now+3)
        XCTAssertEqual(m.currentSet?.number("w"),67.5);XCTAssertEqual(m.currentSet?.number("rir"),2)
        XCTAssertThrowsError(try m.adjust(field:"w",value:-1,now:now+4));XCTAssertThrowsError(try m.adjust(field:"rpe",value:11,now:now+4))
        XCTAssertThrowsError(try m.adjust(field:"r",value:.nan,now:now+4))
    }
    func testThreeSetsRestAddSkipAndFinish() throws {
        var m=try machine()
        for i in 1...3 {
            try m.confirm(expectedSetUUID:try XCTUnwrap(m.currentSet).text("uuid"),now:now+Double(i)*1000)
            XCTAssertEqual(m.restRemaining(now:now+Double(i)*1000),30)
        }
        try m.rest(add:15,now:now+3000);XCTAssertEqual(m.restRemaining(now:now+3000),45)
        try m.rest(add:nil,now:now+3001);XCTAssertEqual(m.restRemaining(now:now+3001),0)
        let finished=try m.finish(now:now+61000)
        XCTAssertEqual(finished.number("vol"),900);XCTAssertEqual(m.state.history.count,1);XCTAssertEqual(m.state.outbox.count,1);XCTAssertNil(m.state.active)
        XCTAssertThrowsError(try m.finish(now:now+62000))
    }
    func testSupersetAlternatesAndOnlyRestsAfterRound() throws {
        var m=try machine(ex:[config("row",group:"a"),config("press",group:"a")])
        try m.confirm(expectedSetUUID:try XCTUnwrap(m.currentSet).text("uuid"),now:now+1000)
        XCTAssertEqual(m.currentIndex,1);XCTAssertEqual(m.restRemaining(now:now+1000),0)
        try m.confirm(expectedSetUUID:try XCTUnwrap(m.currentSet).text("uuid"),now:now+2000)
        XCTAssertEqual(m.currentIndex,0);XCTAssertEqual(m.restRemaining(now:now+2000),30)
    }
    func testEditAddReplaceMoveSkipAndSetChangesPreserveCompletedWork() throws {
        var m=try machine();try m.confirm(expectedSetUUID:try XCTUnwrap(m.currentSet).text("uuid"),now:now+1)
        try m.replaceExercise(at:0,id:"press",now:now+2)
        XCTAssertEqual(m.entries[0].text("id"),"row");XCTAssertTrue(m.entries[0].flag("skipped"));XCTAssertEqual(m.completedSetCount,1)
        try m.addExercise(id:"run",now:now+3);try m.moveExercise(from:2,to:0,now:now+4)
        XCTAssertEqual(m.entries[0].text("id"),"run")
        try m.addSet(at:0,now:now+5);XCTAssertEqual(m.entries[0].rows("sets").count,4)
        try m.deleteSet(entry:0,set:3,now:now+6);XCTAssertEqual(m.entries[0].rows("sets").count,3)
        try m.skipExercise(at:0,now:now+7);XCTAssertTrue(m.entries[0].flag("skipped"))
    }
    func testTimedAndCardioEntriesUseTheirOwnQuantities() throws {
        var m=try machine(ex:[config("row",mode:"time"),config("run",mode:"cardio")])
        XCTAssertEqual(m.currentSet?.number("sec"),30);try m.adjust(field:"sec",value:40,now:now+1)
        for i in 0..<3 {try m.confirm(expectedSetUUID:try XCTUnwrap(m.currentSet).text("uuid"),now:now+Double(i+2))}
        XCTAssertEqual(m.currentEntry?.text("id"),"run");XCTAssertEqual(m.currentSet?.number("min"),10)
        try m.adjust(field:"speed",value:8,now:now+10);XCTAssertEqual(m.currentSet?.number("speed"),8)
        try m.confirm(expectedSetUUID:try XCTUnwrap(m.currentSet).text("uuid"),now:now+20)
        let done=try m.finish(now:now+1000);XCTAssertEqual(done.number("vol"),0)
    }
    func testWarmupFailureAndDropTagsKeepSchemaAndVolume() throws {
        var m=try machine();try m.tag("warmup",now:now+1);XCTAssertTrue(m.currentSet?.flag("warmup") ?? false)
        try m.confirm(expectedSetUUID:try XCTUnwrap(m.currentSet).text("uuid"),now:now+2)
        try m.tag("failure",now:now+3);XCTAssertTrue(m.currentSet?.flag("failure") ?? false)
        try m.confirm(expectedSetUUID:try XCTUnwrap(m.currentSet).text("uuid"),now:now+4)
        try m.tag("dropset",now:now+5);XCTAssertEqual(m.currentSet?.text("type"),"dropset")
        let done=try m.finish(now:now+1000);XCTAssertEqual(done.number("vol"),300)
    }
    func testHeartRateAndEnergySummariesSurviveInCompletedWorkout() throws {
        var m=try machine();try m.summary(heartRate:125,energy:42,now:now+1)
        try m.confirm(expectedSetUUID:try XCTUnwrap(m.currentSet).text("uuid"),now:now+2)
        let done=try m.finish(now:now+1000);XCTAssertEqual(done.number("energyKcal"),42);XCTAssertEqual(done.number("currentHeartRate"),125)
        XCTAssertEqual(m.state.outbox[0].payload["workout"].text("uuid"),done.text("uuid"))
    }
    func testEmptyFinishAndUnknownExerciseAreRejected() throws {
        var m=try machine();XCTAssertThrowsError(try m.finish(now:now+1000));XCTAssertThrowsError(try m.addExercise(id:"unknown",now:now+1))
        XCTAssertThrowsError(try m.deleteSet(entry:99,set:0,now:now+1))
    }
    func testActiveJournalRestAndExactSetsResumeAfterRelaunch() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let journal=try WatchJournal(folder:folder,seed:seed(),catalogue:catalogue)
        try journal.perform {try $0.start(routineId:"r",now:now)}
        let set=try XCTUnwrap(journal.machine.currentSet).text("uuid")
        try journal.perform {try $0.confirm(expectedSetUUID:set,now:now+1000)}
        let restored=try WatchJournal(folder:folder,seed:seed(),catalogue:catalogue)
        XCTAssertEqual(restored.machine.state,journal.machine.state);XCTAssertEqual(restored.machine.completedSetCount,1)
        XCTAssertEqual(restored.machine.restRemaining(now:now+1100),29.9,accuracy:0.001)
    }
    func testCompletedTransactionWinsOverLeftoverActiveJournal() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let repo=WatchRepository(folder:folder);var m=try machine()
        try m.confirm(expectedSetUUID:try XCTUnwrap(m.currentSet).text("uuid"),now:now+1);try repo.save(m.state)
        let oldActive=try Data(contentsOf:folder.appendingPathComponent("active.json"))
        try m.finish(now:now+1000);try repo.save(m.state,completed:true)
        try oldActive.write(to:folder.appendingPathComponent("active.json"),options:.atomic)
        let recovered=try repo.load(seed:seed());XCTAssertNil(recovered.active);XCTAssertEqual(recovered.history.count,1);XCTAssertEqual(recovered.outbox.count,1)
    }
    func testFailedJournalWriteDoesNotPublishSetConfirmation() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let journal=try WatchJournal(folder:folder,seed:seed(),catalogue:catalogue)
        try journal.perform {try $0.start(routineId:"r",now:now)}
        let before=journal.machine.state,set=try XCTUnwrap(journal.machine.currentSet).text("uuid")
        try FileManager.default.removeItem(at:folder);try Data("blocked".utf8).write(to:folder)
        XCTAssertThrowsError(try journal.perform {try $0.confirm(expectedSetUUID:set,now:now+1)})
        XCTAssertEqual(journal.machine.state,before)
    }
    func testCorruptJournalCannotSilentlyReplaceIdentity() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let repo=WatchRepository(folder:folder);try repo.save(seed())
        try Data("{broken".utf8).write(to:folder.appendingPathComponent("active.json"))
        XCTAssertThrowsError(try repo.load(seed:seed()))
    }
}
