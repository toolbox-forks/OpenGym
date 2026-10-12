import Foundation

public enum ContractError: Error, Equatable {
    case unsupportedSchema(Int), invalidTimestamp, invalidPayload, invalidIdentity
}
private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
public struct RecordIdentity: Codable, Equatable, Sendable {
    public let uuid: UUID
    public let updatedAt: Double
    public let deviceId: String
    public init(uuid: UUID = UUID(), updatedAt: Double, deviceId: String) throws {
        guard updatedAt.isFinite && updatedAt >= 0 else { throw ContractError.invalidTimestamp }
        guard !deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ContractError.invalidIdentity }
        self.uuid = uuid; self.updatedAt = updatedAt; self.deviceId = deviceId
    }
    private enum CodingKeys: String, CodingKey { case uuid, updatedAt, deviceId }
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowed = Set(["uuid", "updatedAt", "deviceId"])
        guard fields.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else { throw ContractError.invalidPayload }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(uuid: c.decode(UUID.self, forKey: .uuid), updatedAt: c.decode(Double.self, forKey: .updatedAt), deviceId: c.decode(String.self, forKey: .deviceId))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(uuid.uuidString.lowercased(), forKey: .uuid)
        try c.encode(updatedAt, forKey: .updatedAt); try c.encode(deviceId, forKey: .deviceId)
    }
}
public struct SyncEnvelope: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public enum Kind: String, Codable, Sendable { case snapshot, workoutCompleted, liveEvent, ack }
    public let schemaVersion: Int
    public let kind: Kind
    public let payload: JSONValue
    public let sentAt: Double
    public init(schemaVersion: Int = currentVersion, kind: Kind, payload: JSONValue, sentAt: Double) throws {
        guard schemaVersion == Self.currentVersion else { throw ContractError.unsupportedSchema(schemaVersion) }
        guard sentAt.isFinite && sentAt >= 0 else { throw ContractError.invalidTimestamp }
        guard case .object = payload else { throw ContractError.invalidPayload }
        self.schemaVersion = schemaVersion; self.kind = kind; self.payload = payload; self.sentAt = sentAt
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, kind, payload, sentAt }
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowed = Set(["schemaVersion", "kind", "payload", "sentAt"])
        guard fields.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else { throw ContractError.invalidPayload }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(schemaVersion: c.decode(Int.self, forKey: .schemaVersion), kind: c.decode(Kind.self, forKey: .kind), payload: c.decode(JSONValue.self, forKey: .payload), sentAt: c.decode(Double.self, forKey: .sentAt))
    }
    /// Version 0 is a reserved prototype snapshot contract; legacy application state stays unchanged.
    public static func migrate(_ data: Data) throws -> SyncEnvelope {
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        if case .number(0) = value["schemaVersion"] {
            guard value.text("kind") == "snapshot" else { throw ContractError.unsupportedSchema(0) }
            guard case .number(let timestamp) = value["sentAt"] else { throw ContractError.invalidTimestamp }
            return try SyncEnvelope(kind: .snapshot, payload: value["payload"], sentAt: timestamp)
        }
        return try JSONDecoder().decode(SyncEnvelope.self, from: data)
    }
}
