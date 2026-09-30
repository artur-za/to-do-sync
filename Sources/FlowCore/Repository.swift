import Foundation
import Darwin

/// One transaction boundary for the app and CLI. flock prevents lost updates between
/// processes; atomic replacement prevents a torn JSON document after interruption.
public final class Repository: @unchecked Sendable {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("board.json") }
    public init(directory: URL? = nil) {
        self.directory = directory ?? ProcessInfo.processInfo.environment["FLODO_OPEN_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FlodoOpen")
    }
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }
    public static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw FlowError.invalid("Cannot open the data lock (errno \(errno)).") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw FlowError.invalid("Cannot lock the data file.") }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }
    private func readUnlocked() throws -> Board {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Board() }
        let board = try Self.decoder().decode(Board.self, from: Data(contentsOf: fileURL))
        guard board.version == 1 else { throw FlowError.invalid("Unsupported data version \(board.version); the file was left unchanged.") }
        return board
    }
    public func read() throws -> Board { try locked { try readUnlocked() } }
    @discardableResult public func transaction(_ change: (inout Board) throws -> Void) throws -> Board {
        try locked {
            let previous = try readUnlocked()
            var board = previous
            try change(&board)
            guard board != previous else { return board }
            guard board.tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw FlowError.invalid("A task needs a title.")
            }
            guard Set(board.tasks.map(\.id)).count == board.tasks.count,
                  Set(board.lists.map(\.id)).count == board.lists.count else { throw FlowError.invalid("Duplicate IDs in data.") }
            board.revision = previous.revision + 1
            // Keep the preceding valid state for manual recovery.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try Self.encoder().encode(previous).write(to: directory.appendingPathComponent("board.previous.json"), options: .atomic)
            }
            let encoded = try Self.encoder().encode(board)
            try encoded.write(to: fileURL, options: .atomic)
            // Return the same timestamp precision as other processes will read.
            return try Self.decoder().decode(Board.self, from: encoded)
        }
    }
    @discardableResult public func update(_ id: UUID, _ change: (inout FlowTask) throws -> Void) throws -> Board {
        try transaction { board in
            guard let i = board.tasks.firstIndex(where: { $0.id == id }) else { throw FlowError.invalid("Task not found: \(id)") }
            try change(&board.tasks[i]); board.tasks[i].updatedAt = Date(); board.reconcile()
        }
    }
}
