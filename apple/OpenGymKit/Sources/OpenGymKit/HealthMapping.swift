import Foundation

public enum HealthMappingError: Error, Equatable {
    case invalidIdentity, invalidDates, invalidQuantity, unsupportedMeasurement
}
public struct HealthWorkoutRecord: Codable, Equatable, Sendable {
    public let clientId: String
    public let uuid: String
    public let title: String
    public let start: Double
    public let end: Double
    public let activity: String
    public let energyKcal: Double?
    public let version: Int
    public init(clientId: String, uuid: String, title: String, start: Double, end: Double, activity: String = "strength_training", energyKcal: Double? = nil, version: Int = 1) throws {
        guard !clientId.isEmpty, let identity=UUID(uuidString:uuid),version>0 else {throw HealthMappingError.invalidIdentity}
        guard start.isFinite,end.isFinite,start>0,end>start else {throw HealthMappingError.invalidDates}
        if let energyKcal {guard energyKcal.isFinite,energyKcal>=0 else {throw HealthMappingError.invalidQuantity}}
        self.clientId=clientId;self.uuid=identity.uuidString.lowercased();self.title=title;self.start=start;self.end=end;self.activity=activity;self.energyKcal=energyKcal;self.version=version
    }
    private enum CodingKeys: String, CodingKey {case clientId,uuid,title,start,end,activity,energyKcal,version}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(clientId: c.decode(String.self,forKey:.clientId), uuid:c.decode(String.self,forKey:.uuid),
            title:c.decode(String.self,forKey:.title), start:c.decode(Double.self,forKey:.start),end:c.decode(Double.self,forKey:.end),
            activity:c.decodeIfPresent(String.self,forKey:.activity) ?? "strength_training",
            energyKcal:c.decodeIfPresent(Double.self,forKey:.energyKcal),version:c.decodeIfPresent(Int.self,forKey:.version) ?? 1)
    }

}
public struct HealthMeasurementRecord: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {case bodyMass,bodyFat,waist}
    public let clientId: String
    public let kind: Kind
    public let value: Double // kg, fraction 0...1, metres
    public let time: Double // milliseconds
    public let source: String
    public let sampleId: String?
    public let version: Int
    public init(clientId:String,kind:Kind,value:Double,time:Double,source:String="openGym",sampleId:String?=nil,version:Int=1) throws {
        guard !clientId.isEmpty,version>0 else {throw HealthMappingError.invalidIdentity}
        guard time.isFinite,time>0 else {throw HealthMappingError.invalidDates}
        guard value.isFinite,value>0,kind != .bodyFat || value<=1 else {throw HealthMappingError.invalidQuantity}
        self.clientId=clientId;self.kind=kind;self.value=value;self.time=time;self.source=source;self.sampleId=sampleId;self.version=version
    }
    private enum CodingKeys:String,CodingKey {case clientId,kind,value,time,source,sampleId,version}
    public init(from decoder:Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        try self.init(clientId:c.decode(String.self,forKey:.clientId),kind:c.decode(Kind.self,forKey:.kind),
            value:c.decode(Double.self,forKey:.value),time:c.decode(Double.self,forKey:.time),
            source:c.decodeIfPresent(String.self,forKey:.source) ?? "openGym",sampleId:c.decodeIfPresent(String.self,forKey:.sampleId),
            version:c.decodeIfPresent(Int.self,forKey:.version) ?? 1)
    }
    public static func fromApp(clientId:String,kind:Kind,value:Double,time:Double,unit:TrainingMath.Unit = .kg) throws -> Self {
        let canonical=kind == .bodyMass ? (unit == .lb ? value/TrainingMath.poundsPerKilogram : value) : kind == .bodyFat ? value/100 : value/100
        return try Self(clientId:clientId,kind:kind,value:canonical,time:time)
    }
    public var appValue:Double {kind == .bodyMass ? value : value*100}
    public var deduplicationKey:String {source+"|"+(sampleId ?? String(time))+"|"+kind.rawValue}
}
public protocol HealthRecordStore: Sendable {
    func upsert(workout:HealthWorkoutRecord) async throws
    func upsert(measurement:HealthMeasurementRecord) async throws
    func workouts() async throws -> [HealthWorkoutRecord]
    func measurements(since:Double) async throws -> [HealthMeasurementRecord]
}
/// Simulator test store persists to its own file, never pretends to be the real Health database.
public actor MockHealthRecordStore: HealthRecordStore {
    private struct State:Codable {
        var workouts:[String:HealthWorkoutRecord]=[:]
        var measurements:[String:HealthMeasurementRecord]=[:]
    }
    private var state:State
    private let file:URL?
    public init(file:URL?=nil) throws {
        self.file=file
        if let file,FileManager.default.fileExists(atPath:file.path) {state=try JSONDecoder().decode(State.self,from:Data(contentsOf:file))}
        else {state=State()}
    }
    private func commit(_ next:State) throws {
        if let file {
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(next).write(to:file,options:.atomic)
        }
        state=next // adopt only after the durable write succeeds
    }
    public func upsert(workout:HealthWorkoutRecord) throws {
        if let old=state.workouts[workout.clientId],old.version>=workout.version {return}
        var next=state;next.workouts[workout.clientId]=workout;try commit(next)
    }
    public func upsert(measurement:HealthMeasurementRecord) throws {
        if let old=state.measurements[measurement.clientId],old.version>=measurement.version {return}
        var next=state;next.measurements[measurement.clientId]=measurement;try commit(next)
    }
    public func workouts() -> [HealthWorkoutRecord] {state.workouts.values.sorted {$0.start<$1.start}}
    public func measurements(since:Double) -> [HealthMeasurementRecord] {state.measurements.values.filter {$0.time>since}.sorted {$0.time<$1.time}}
}
