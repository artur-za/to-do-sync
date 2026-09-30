import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
}
public struct SyncRecord: Codable, Equatable, Sendable {
    public var kind: String
    public var id: String
    public var version: Int
    public var deleted: Bool
    public var value: JSONValue?
    public var key: String { kind + "/" + id.lowercased() }
    public init(kind: String, id: String, version: Int = 0, deleted: Bool = false, value: JSONValue?) {
        self.kind = kind; self.id = id.lowercased(); self.version = version; self.deleted = deleted; self.value = value
    }
}
public struct SyncOperation: Codable, Sendable {
    public var kind: String
    public var id: String
    public var baseVersion: Int
    public var deleted: Bool
    public var value: JSONValue?
}
public struct SyncSnapshot: Codable, Sendable {
    public var epoch: String
    public var revision: Int
    public var records: [SyncRecord]
    public var unchanged: Bool?
    public init(epoch: String, revision: Int, records: [SyncRecord]) { self.epoch = epoch; self.revision = revision; self.records = records }
}
public struct SyncState: Codable, Sendable {
    public var epoch: String?
    public var records: [String: SyncRecord] = [:]
    public init() {}
}
public struct SyncConflict: Codable, Sendable {
    public let key: String
    public let base: JSONValue?
    public let local: JSONValue?
    public let remote: JSONValue?
    public let fields: [String]
}
public enum BoardSync {
    public static let settingsID = "00000000-0000-0000-0000-000000000001"
    private static func value<T: Encodable>(_ model: T) throws -> JSONValue {
        let v = try JSONDecoder().decode(JSONValue.self, from: Repository.encoder().encode(model))
        guard var object = v.object else { return v }
        for key in ["id", "listID", "pinnedTaskID"] {
            if case .string(let id) = object[key] { object[key] = .string(id.lowercased()) }
        }
        return .object(object)
    }
    public static func records(_ board: Board) throws -> [String: SyncRecord] {
        var result: [String: SyncRecord] = [:]
        for task in board.tasks { let r = SyncRecord(kind: "task", id: task.id.uuidString, value: try value(task)); result[r.key] = r }
        for list in board.lists { let r = SyncRecord(kind: "list", id: list.id.uuidString, value: try value(list)); result[r.key] = r }
        let pin = SyncRecord(kind: "settings", id: settingsID, value: .object(["pinnedTaskID": board.pinnedTaskID.map { .string($0.uuidString.lowercased()) } ?? .null]))
        result[pin.key] = pin; return result
    }
    public static func operations(board: Board, state: SyncState) throws -> [SyncOperation] {
        let local = try records(board)
        return Set(local.keys).union(state.records.keys).sorted().compactMap { key in
            let current = local[key]; let base = state.records[key]
            guard current?.value != base?.value else { return nil }
            guard current != nil || base?.deleted == false else { return nil }
            let record = current ?? base!
            return SyncOperation(kind: record.kind, id: record.id, baseVersion: base?.version ?? 0, deleted: current == nil, value: current?.value)
        }
    }
    /// Three-way merge: unrelated field edits combine. Concurrent edits to one field
    /// keep the local choice and archive BOTH versions before the transaction commits.
    public static func merge(board: inout Board, base: SyncState, remote: SyncSnapshot) throws -> [SyncConflict] {
        if let epoch = base.epoch, epoch != remote.epoch { throw FlowError.invalid("The sync server identity changed. Local tasks were kept. Reconnect after checking the server backup.") }
        let local = try records(board)
        let incoming = Dictionary(uniqueKeysWithValues: remote.records.map { ($0.key, $0) })
        var merged = local; var conflicts: [SyncConflict] = []
        for (key, r) in incoming {
            let b = base.records[key]?.value
            let l = local[key]?.value
            let other = r.deleted ? nil : r.value
            var chosen: JSONValue?
            if b == nil, r.kind == "settings", l?.object?["pinnedTaskID"] == .null { chosen = other }
            else if l == b { chosen = other }
            else if other == b || l == other { chosen = l }
            else if let lo = l?.object, let ro = other?.object {
                let bo = b?.object ?? [:]; var fields: [String] = []; var result: [String: JSONValue] = [:]
                for field in Set(lo.keys).union(ro.keys).union(bo.keys) {
                    let lv = lo[field]; let rv = ro[field]; let bv = bo[field]
                    if lv == bv { result[field] = rv }
                    else if rv == bv || lv == rv { result[field] = lv }
                    else {
                        result[field] = lv
                        if field != "updatedAt" { fields.append(field) }
                    }
                }
                // Plain text notes changed by Telegram must not keep stale rich text.
                if result["note"] != lo["note"] { result["noteData"] = ro["noteData"] }
                chosen = .object(result)
                if !fields.isEmpty { conflicts.append(SyncConflict(key: key, base: b, local: l, remote: other, fields: fields.sorted())) }
            } else {
                // Delete beats an edit, preventing zombie tasks on reconnect.
                // The edited version is retained in the conflict archive for recovery.
                chosen = nil
                conflicts.append(SyncConflict(key: key, base: b, local: l, remote: other, fields: ["deletion"]))
            }
            if let chosen { merged[key] = SyncRecord(kind: r.kind, id: r.id, version: r.version, value: chosen) }
            else { merged.removeValue(forKey: key) }
        }
        var tasks: [FlowTask] = []; var lists: [TaskList] = []; var pinned: UUID?
        for r in merged.values {
            guard let value = r.value else { continue }
            let data = try JSONEncoder().encode(value)
            if r.kind == "task" { tasks.append(try Repository.decoder().decode(FlowTask.self, from: data)) }
            else if r.kind == "list" { lists.append(try Repository.decoder().decode(TaskList.self, from: data)) }
            else if r.kind == "settings", case .string(let id) = value.object?["pinnedTaskID"] { pinned = UUID(uuidString: id) }
        }
        // Keep collection order stable; row ordering remains in each task's order field.
        let taskOrder = Dictionary(uniqueKeysWithValues: board.tasks.enumerated().map { ($0.element.id, $0.offset) })
        let listOrder = Dictionary(uniqueKeysWithValues: board.lists.enumerated().map { ($0.element.id, $0.offset) })
        board.tasks = tasks.sorted { (taskOrder[$0.id] ?? Int.max, $0.id.uuidString) < (taskOrder[$1.id] ?? Int.max, $1.id.uuidString) }
        board.lists = lists.sorted { (listOrder[$0.id] ?? Int.max, $0.id.uuidString) < (listOrder[$1.id] ?? Int.max, $1.id.uuidString) }
        board.pinnedTaskID = pinned
        return conflicts
    }
}
