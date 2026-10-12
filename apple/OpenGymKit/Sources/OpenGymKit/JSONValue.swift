import Foundation

/// Lossless JSON boundary: keep fields written by newer clients and old compact state keys.
public enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    public subscript(_ key: String) -> JSONValue {
        get { objectValue[key] ?? .null }
        set { var dict = objectValue; dict[key] = newValue; self = .object(dict) }
    }
    public var objectValue: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
    public var arrayValue: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    public var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    public var doubleValue: Double? {
        switch self { case .number(let v): return v; case .string(let v): return Double(v); default: return nil }
    }
    public var boolValue: Bool { if case .bool(let v) = self { return v }; return false }
    public func number(_ key: String, default fallback: Double = 0) -> Double { self[key].doubleValue ?? fallback }
    public func text(_ key: String, default fallback: String = "") -> String { self[key].stringValue ?? fallback }
    public func flag(_ key: String) -> Bool { self[key].boolValue }
    public func rows(_ key: String) -> [JSONValue] { self[key].arrayValue }
}

/// These adapters mirror state without replacing catalogue ids or dropping unknown fields.
public protocol StateRecord: Codable, Equatable, Sendable {
    var raw: JSONValue { get set }
    init(raw: JSONValue)
}
public extension StateRecord {
    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        guard case .object = value else { throw ContractError.invalidPayload }
        self.init(raw: value)
    }
    func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }
}
public struct SetRecord: StateRecord {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var weight: Double { raw.number("w") }
    public var reps: Double { raw.number("r") }
    public var seconds: Double { raw.number("sec") }
    public var minutes: Double { raw.number("min") }
    public var done: Bool { raw.flag("done") }
    public var isWarmup: Bool { raw.flag("warmup") || raw.text("phase") == "warmup" }
    public var uuid: String? { raw["uuid"].stringValue }
}
public struct ExerciseEntry: StateRecord {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var exerciseID: String { raw.text("id") }
    public var sets: [SetRecord] { raw.rows("sets").map(SetRecord.init) }
    public var target: JSONValue { raw["target"] }
}
public struct Workout: StateRecord {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { raw.text("id") }
    public var uuid: String? { raw["uuid"].stringValue }
    public var start: Double { raw.number("start") }
    public var end: Double { raw.number("end") }
    public var entries: [ExerciseEntry] { raw.rows("entries").map(ExerciseEntry.init) }
}
public struct Routine: StateRecord {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { raw.text("id") }
    public var name: String { raw.text("name") }
    public var exercises: [JSONValue] { raw.rows("ex") }
}
public struct GymState: StateRecord {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var workouts: [Workout] { raw.rows("workouts").map(Workout.init) }
    public var routines: [Routine] { raw.rows("routines").map(Routine.init) }
    public var bodyweight: [JSONValue] { raw.rows("bodyweight") }
    public var measurements: [JSONValue] { raw.rows("measurements") }
}
