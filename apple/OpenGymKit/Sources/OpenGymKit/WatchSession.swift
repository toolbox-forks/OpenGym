import Foundation

public enum WatchSessionError: Error, Equatable {
    case alreadyRunning, noSession, noRoutine, invalidExercise, invalidSet, invalidValue, noCompletedSets, corruptStore
}

/// Catalogue bytes stay in their immutable bundle/cache; only small training snapshots and journals mutate.
public struct WatchTrainingState: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var deviceId: String
    public var ownerId: String
    public var snapshot: JSONValue
    public var active: JSONValue?
    public var history: [JSONValue]
    public var outbox: [SyncEnvelope]
    public init(deviceId: String = UUID().uuidString.lowercased(), ownerId: String = "local", snapshot: JSONValue = .object([:]),
                active: JSONValue? = nil, history: [JSONValue] = [], outbox: [SyncEnvelope] = []) {
        self.deviceId=deviceId;self.ownerId=ownerId;self.snapshot=snapshot;self.active=active;self.history=history;self.outbox=outbox
    }
}

public struct WatchSessionMachine {
    public private(set) var state: WatchTrainingState
    public let catalogue: [String: JSONValue]
    public init(state: WatchTrainingState, catalogue: [String: JSONValue]) {self.state=state;self.catalogue=catalogue}
    public var entries: [JSONValue] {state.active?.rows("entries") ?? []}
    public var currentIndex: Int {max(0,Int(state.active?.number("cur") ?? 0))}
    public var currentEntry: JSONValue? {entries.indices.contains(currentIndex) ? entries[currentIndex] : nil}
    public var currentSetIndex: Int? {currentEntry?.rows("sets").firstIndex(where:{!$0.flag("done")})}
    public var currentSet: JSONValue? {
        guard let entry=currentEntry,let index=currentSetIndex else{return nil};return entry.rows("sets")[index]
    }
    public var completedSetCount: Int {entries.reduce(0){$0+$1.rows("sets").filter{$0.flag("done")}.count}}
    public var allDone: Bool {!entries.isEmpty && entries.allSatisfy{$0.flag("skipped") || $0.rows("sets").allSatisfy{$0.flag("done")}}}
    public var routines: [JSONValue] {state.snapshot.rows("routines")}
    public func restRemaining(now: Double) -> Double {max(0,((state.active?.number("restUntil") ?? 0)-now)/1000)}
    public func facts(for id: String) -> ExerciseFacts {
        guard let data=try? JSONEncoder().encode(catalogue[id]?["facts"] ?? .object([:])),
            let facts=try? JSONDecoder().decode(ExerciseFacts.self,from:data) else{return ExerciseFacts()};return facts
    }
    public func previous(for id:String) -> JSONValue? {
        (state.snapshot.rows("workouts")+state.history).reversed().compactMap{w in w.rows("entries").last(where:{$0.text("id")==id})}.first
    }
    private func identity(_ value:JSONValue,now:Double)->JSONValue {
        var x=value;x["uuid"] = .string(UUID().uuidString.lowercased());x["deviceId"] = .string(state.deviceId);x["updatedAt"] = .number(now);return x
    }
    private func day(_ now:Double)->String {
        var calendar=Calendar(identifier:.gregorian)
        calendar.timeZone=TimeZone(identifier:state.snapshot.text("tz")) ?? .current
        let c=calendar.dateComponents([.year,.month,.day],from:Date(timeIntervalSince1970:now/1000))
        return String(format:"%04d-%02d-%02d",c.year ?? 1970,c.month ?? 1,c.day ?? 1)
    }
    private func buildEntry(cfg:JSONValue,routine:JSONValue,now:Double) throws -> JSONValue {
        let id=cfg.text("id");guard !id.isEmpty,catalogue[id] != nil else{throw WatchSessionError.invalidExercise}
        let facts=facts(for:id),mode=cfg.text("mode",default:facts.cardio ? "cardio" : "reps")
        var training=state.snapshot;training["workouts"] = .array(state.snapshot.rows("workouts")+state.history)
        let plan=cfg.flag("noProg") || routine.flag("excludeFromProgression") ? JSONValue.object(["kind":.string("off")]) : Progression.next(state:training,cfg:cfg,routine:routine,facts:facts)
        var target=cfg
        for key in ["weight","reps","sets","sec","rowReps"] where plan[key] != .null {target[key]=plan[key]}
        target["mode"] = .string(mode)
        let previous=previous(for:id),lastRows=previous?.rows("sets").filter{!$0.flag("warmup") && $0.text("phase") != "warmup"} ?? []
        let rows=max(1,min(50,Int(target.number("sets",default:3))))
        var sets:[JSONValue]=[]
        for index in 0..<rows {
            let old=index<lastRows.count ? lastRows[index] : lastRows.last
            let weight=plan["weight"] != .null ? plan.number("weight") : old?.number("w") ?? target.number("weight")
            let rowReps=target.rows("rowReps")
            let reps=index<rowReps.count ? rowReps[index].doubleValue ?? 0 : target.number("reps",default:old?.number("r") ?? 5)
            var row=JSONValue.object(["w":.number(max(0,weight)),"r":.number(max(0,reps)),"done":.bool(false),"phase":.string("work"),"type":.string("straight")])
            if mode != "reps" {row["r"] = .number(0)}
            if mode=="time" {row["sec"] = .number(target.number("sec",default:old?.number("sec") ?? 30))}
            if mode=="cardio" {for key in ["min","speed","incline","distance"] {row[key]=target[key] != .null ? target[key] : old?[key] ?? .number(key=="min" ? 10 : 0)}}
            sets.append(identity(row,now:now))
        }
        var entry=identity(.object(["id":.string(id),"rid":routine["id"],"target":target,"planned":cfg,"plan":plan,"sets":.array(sets)]),now:now)
        entry["previous"] = previous ?? .null
        if routine.flag("excludeFromProgression") {entry["noProg"] = .bool(true)}
        return entry
    }
    public mutating func start(routineId:String?,now:Double) throws {
        guard state.active==nil else{throw WatchSessionError.alreadyRunning}
        guard now.isFinite,now>0 else{throw WatchSessionError.invalidValue}
        let routine=routineId.flatMap{id in routines.first(where:{$0.text("id")==id})}
        if routineId != nil && routine==nil {throw WatchSessionError.noRoutine}
        let entries=try (routine?.rows("ex") ?? []).map{try buildEntry(cfg:$0,routine:routine ?? .object([:]),now:now)}
        let id=UUID().uuidString.lowercased()
        state.active = .object(["id":.string(id),"uuid":.string(id),"deviceId":.string(state.deviceId),"updatedAt":.number(now),
            "name":.string(routine?.text("name",default:routine?.text("n") ?? "Workout") ?? "Freestyle workout"),
            "d":.string(day(now)),"start":.number(now),"unit":.string(state.snapshot.text("unit",default:"kg")),
            "routineId":routine?["id"] ?? .null,"routineIds":.array(routine.map{[$0["id"]]} ?? []),"entries":.array(entries),"cur":.number(0)])
    }
    private mutating func adoptEntries(_ rows:[JSONValue],now:Double) throws {
        guard var active=state.active else{throw WatchSessionError.noSession}
        active["entries"] = .array(rows);active["updatedAt"] = .number(now)
        let old=max(0,Int(active.number("cur")))
        if !rows.indices.contains(old) || rows[old].flag("skipped") || rows[old].rows("sets").allSatisfy({$0.flag("done")}) {
            active["cur"] = .number(Double(rows.firstIndex(where:{!$0.flag("skipped") && $0.rows("sets").contains(where:{!$0.flag("done")})}) ?? 0))
        }
        state.active=active
    }
    public mutating func adjust(field:String,value:Double,now:Double) throws {
        guard ["w","r","sec","min","speed","incline","distance","rir","rpe"].contains(field),value.isFinite,value>=0,
            field != "rpe" || value<=10,field != "rir" || value<=10 else{throw WatchSessionError.invalidValue}
        guard let setIndex=currentSetIndex,entries.indices.contains(currentIndex) else{throw WatchSessionError.invalidSet}
        var rows=entries,row=rows[currentIndex],sets=row.rows("sets")
        sets[setIndex][field] = .number(value);sets[setIndex]["updatedAt"] = .number(now);row["sets"] = .array(sets);row["updatedAt"] = .number(now);rows[currentIndex]=row
        try adoptEntries(rows,now:now)
    }
    /// Expected UUID comes from the rendered button; a stale/double callback cannot tick the next row.
    @discardableResult public mutating func confirm(expectedSetUUID:String,now:Double) throws -> Bool {
        guard let index=currentSetIndex,let current=currentSet else{throw WatchSessionError.invalidSet}
        guard current.text("uuid")==expectedSetUUID else{return false}
        var rows=entries,entry=rows[currentIndex],sets=entry.rows("sets"),set=sets[index]
        let mode=entry["target"].text("mode",default:"reps")
        guard set.number(mode=="time" ? "sec" : mode=="cardio" ? "min" : "r")>0 else{throw WatchSessionError.invalidValue}
        set["done"] = .bool(true);set["completedAt"] = .number(now);set["updatedAt"] = .number(now)
        sets[index]=set;entry["sets"] = .array(sets);entry["updatedAt"] = .number(now);rows[currentIndex]=entry
        let group=entry["target"].text("sg"),members=group.isEmpty ? [currentIndex] : rows.indices.filter{rows[$0]["target"].text("sg")==group && !rows[$0].flag("skipped")}
        let nextMember=members.first(where:{$0>currentIndex && rows[$0].rows("sets").contains(where:{!$0.flag("done")})})
        let wrapped=nextMember ?? members.first(where:{rows[$0].rows("sets").contains(where:{!$0.flag("done")})})
        var active=state.active!
        if let wrapped {active["cur"] = .number(Double(wrapped))}
        else {active["cur"] = .number(Double(rows.firstIndex(where:{!$0.flag("skipped") && $0.rows("sets").contains(where:{!$0.flag("done")})}) ?? currentIndex))}
        let rest=nextMember != nil && members.count>1 ? 0 : entry["target"].number("sgRest",default:entry["target"].number("rest",default:state.snapshot.number("restSec",default:90)))
        active["restUntil"] = .number(now+max(0,rest)*1000);state.active=active
        try adoptEntries(rows,now:now);return true
    }
    public mutating func rest(add seconds:Double?,now:Double) throws {
        guard var active=state.active else{throw WatchSessionError.noSession}
        active["restUntil"] = .number(seconds.map{max(now,active.number("restUntil"))+$0*1000} ?? now)
        active["updatedAt"] = .number(now);state.active=active
    }
    public mutating func addExercise(id:String,now:Double) throws {
        var rows=entries;rows.append(try buildEntry(cfg:.object(["id":.string(id),"sets":.number(3),"reps":.number(8),"weight":.number(0),"prog":.string("off")]),routine:.object([:]),now:now))
        try adoptEntries(rows,now:now)
    }
    public mutating func replaceExercise(at index:Int,id:String,now:Double) throws {
        guard entries.indices.contains(index) else{throw WatchSessionError.invalidExercise}
        // Completed rows stay in history; replacement adds a new entry and skips the old remainder.
        var rows=entries;rows[index]["skipped"] = .bool(true)
        let new=try buildEntry(cfg:.object(["id":.string(id),"sets":.number(3),"reps":.number(8),"prog":.string("off")]),routine:.object([:]),now:now)
        rows.insert(new,at:index+1);try adoptEntries(rows,now:now)
    }
    public mutating func moveExercise(from:Int,to:Int,now:Double) throws {
        guard entries.indices.contains(from),entries.indices.contains(to) else{throw WatchSessionError.invalidExercise}
        var rows=entries;let current=currentEntry?.text("uuid"),moved=rows.remove(at:from);rows.insert(moved,at:to)
        try adoptEntries(rows,now:now)
        if let index=rows.firstIndex(where:{$0.text("uuid")==current}) {state.active?["cur"] = .number(Double(index))}
    }
    public mutating func skipExercise(at index:Int,now:Double) throws {
        guard entries.indices.contains(index) else{throw WatchSessionError.invalidExercise}
        var rows=entries;rows[index]["skipped"] = .bool(true);try adoptEntries(rows,now:now)
    }
    public mutating func addSet(at index:Int,now:Double) throws {
        guard entries.indices.contains(index) else{throw WatchSessionError.invalidExercise}
        var rows=entries,sets=rows[index].rows("sets"),row=sets.last ?? .object(["w":.number(0),"r":.number(8)])
        row["done"] = .bool(false);row["completedAt"] = .null;row=identity(row,now:now)
        sets.append(row);rows[index]["sets"] = .array(sets);try adoptEntries(rows,now:now)
    }
    public mutating func deleteSet(entry index:Int,set:Int,now:Double) throws {
        guard entries.indices.contains(index),entries[index].rows("sets").indices.contains(set) else{throw WatchSessionError.invalidSet}
        var rows=entries,sets=rows[index].rows("sets");sets.remove(at:set);rows[index]["sets"] = .array(sets);try adoptEntries(rows,now:now)
    }
    public mutating func tag(_ tag:String,now:Double) throws {
        guard let index=currentSetIndex else{throw WatchSessionError.invalidSet}
        var rows=entries,sets=rows[currentIndex].rows("sets")
        sets[index]["phase"] = .string(tag=="warmup" ? "warmup" : "work")
        sets[index]["warmup"] = .bool(tag=="warmup");sets[index]["failure"] = .bool(tag=="failure")
        sets[index]["type"] = .string(tag=="dropset" ? "dropset" : "straight")
        rows[currentIndex]["sets"] = .array(sets);try adoptEntries(rows,now:now)
    }
    public mutating func summary(heartRate:Double?,energy:Double?,now:Double) throws {
        guard var active=state.active else{throw WatchSessionError.noSession}
        if let heartRate,heartRate.isFinite,heartRate>0 {active["currentHeartRate"] = .number(heartRate)}
        if let energy,energy.isFinite,energy>=0 {active["energyKcal"] = .number(energy)}
        active["updatedAt"] = .number(now);state.active=active
    }
    @discardableResult public mutating func finish(now:Double) throws -> JSONValue {
        guard var active=state.active else{throw WatchSessionError.noSession}
        guard completedSetCount>0 else{throw WatchSessionError.noCompletedSets}
        guard now.isFinite,now>active.number("start") else{throw WatchSessionError.invalidValue}
        active["end"] = .number(now);active["updatedAt"] = .number(now)
        var volume=0.0
        for entry in entries where entry["target"].text("mode",default:"reps")=="reps" {for row in entry.rows("sets") where row.flag("done") && !row.flag("warmup") && row.text("phase") != "warmup" {
            volume += row.number("w")*row.number("r")
            for drop in row.rows("drops") {volume += drop.number("w")*drop.number("r")}
        }}
        active["vol"] = .number(volume)
        state.history.append(active)
        state.outbox.append(try SyncEnvelope(kind:.workoutCompleted,payload:.object(["ownerId":.string(state.ownerId),"workout":active]),sentAt:now))
        state.active=nil;return active
    }
}

/// Active mutations are a small atomic file; completion history/outbox is a separate atomic transaction.
public final class WatchRepository {
    public let folder: URL
    public init(folder:URL) {self.folder=folder}
    private var durableURL:URL {folder.appendingPathComponent("completed.json")}
    private var activeURL:URL {folder.appendingPathComponent("active.json")}
    private struct ActiveJournal:Codable {var schemaVersion=1;var deviceId:String;var ownerId:String;var active:JSONValue?}
    private func write<T:Encodable>(_ value:T,to url:URL) throws {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try JSONEncoder().encode(value).write(to:url,options:.atomic)
    }
    public func load(seed:WatchTrainingState) throws -> WatchTrainingState {
        var state=seed
        if FileManager.default.fileExists(atPath:durableURL.path) {state=try JSONDecoder().decode(WatchTrainingState.self,from:Data(contentsOf:durableURL))}
        guard state.schemaVersion==1 else{throw WatchSessionError.corruptStore}
        if FileManager.default.fileExists(atPath:activeURL.path) {
            let journal=try JSONDecoder().decode(ActiveJournal.self,from:Data(contentsOf:activeURL))
            guard journal.schemaVersion==1,journal.deviceId==state.deviceId,journal.ownerId==state.ownerId else{throw WatchSessionError.corruptStore}
            if let active=journal.active,!state.history.contains(where:{$0.text("uuid")==active.text("uuid")}) {state.active=active}
        }
        return state
    }
    public func save(_ state:WatchTrainingState,completed:Bool=false) throws {
        if !FileManager.default.fileExists(atPath:durableURL.path) || completed {var durable=state;durable.active=nil;try write(durable,to:durableURL)}
        try write(ActiveJournal(deviceId:state.deviceId,ownerId:state.ownerId,active:state.active),to:activeURL)
    }
}

/// Single owner on the UI actor: publish a new machine only after its journal commits.
public final class WatchJournal {
    public private(set) var machine:WatchSessionMachine
    public let repository:WatchRepository
    public init(folder:URL,seed:WatchTrainingState,catalogue:[String:JSONValue]) throws {
        repository=WatchRepository(folder:folder)
        machine=WatchSessionMachine(state:try repository.load(seed:seed),catalogue:catalogue)
        try repository.save(machine.state)
    }
    public func perform(completed:Bool=false,_ action:(inout WatchSessionMachine)throws->Void) throws {
        var candidate=machine
        try action(&candidate)
        try repository.save(candidate.state,completed:completed)
        machine=candidate
    }
}
