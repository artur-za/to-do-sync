import Foundation
import FlowCore

let repository = Repository()
let args = Array(CommandLine.arguments.dropFirst())
func emit<T: Encodable>(_ value: T) throws { print(String(decoding: try Repository.encoder().encode(value), as: UTF8.self)) }
func identifier(_ position: Int = 1) throws -> UUID {
    guard args.count > position, let id = UUID(uuidString: args[position]) else { throw FlowError.invalid("Provide a full task UUID.") }; return id
}
do {
    switch args.first ?? "help" {
    case "list":
        let board = try repository.transaction { $0.reconcile() }
        try emit(args.contains("--all") ? board.tasks : board.tasks.filter { $0.bucket != .done })
    case "export": try emit(repository.read())
    case "add":
        guard args.count > 1 else { throw FlowError.invalid("Usage: flowctl add 'Task title'") }
        let task = FlowTask(title: args.dropFirst().joined(separator: " "))
        try repository.transaction { board in var t = task; t.order = (board.tasks.map(\.order).max() ?? 0) + 1; board.tasks.append(t) }
        try emit(task)
    case "done": try repository.update(identifier()) { $0.move(to: .done) }
    case "reopen": try repository.update(identifier()) { $0.reopen() }
    case "move":
        guard args.count == 3, let bucket = Bucket(rawValue: args[2]) else { throw FlowError.invalid("Usage: flowctl move UUID later|week|today|done") }
        try repository.update(identifier()) { $0.move(to: bucket) }
    case "rename":
        guard args.count > 2 else { throw FlowError.invalid("Usage: flowctl rename UUID 'New title'") }
        try repository.update(identifier()) { $0.title = args.dropFirst(2).joined(separator: " ") }
    case "note":
        guard args.count > 2 else { throw FlowError.invalid("Usage: flowctl note UUID 'Notes'") }
        try repository.update(identifier()) { $0.note = args.dropFirst(2).joined(separator: " "); $0.noteData = nil }
    case "delete":
        let id = try identifier()
        try repository.transaction { board in
            guard board.tasks.contains(where: { $0.id == id }) else { throw FlowError.invalid("Task not found.") }
            board.tasks.removeAll { $0.id == id }; board.reconcile()
        }
    case "help", "--help":
        print("""
        flowctl — local Flodo Open interface. All output is JSON.
        list [--all] | export | add TITLE | done UUID | reopen UUID
        move UUID later|week|today|done | rename UUID TITLE | note UUID TEXT | delete UUID
        FLODO_OPEN_HOME sets an isolated data directory (use this for tests).
        """)
    default: throw FlowError.invalid("Unknown command. Run flowctl --help.")
    }
} catch { FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8)); exit(1) }
