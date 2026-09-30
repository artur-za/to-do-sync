import XCTest
import FlowCore
@testable import FlodoOpen

final class StoreTests: XCTestCase {
    @MainActor func makeStore() -> Store {
        let repo = Repository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("FlowStoreTests-\(UUID())"))
        let store = Store(repository: repo, enableSystemServices: false)
        store.undoManager.groupsByEvent = false
        return store
    }
    @MainActor func testImmediateEditAfterCreationUsesPersistedPrecision() throws {
        let store = makeStore(); defer { try? FileManager.default.removeItem(at: store.repository.directory) }
        let task = FlowTask(title: "Created")
        store.undoManager.beginUndoGrouping()
        XCTAssertTrue(store.save(task, original: nil))
        store.undoManager.endUndoGrouping()
        let saved = try XCTUnwrap(store.board.tasks.first)
        var edited = saved; edited.title = "Edited immediately"
        store.undoManager.beginUndoGrouping()
        XCTAssertTrue(store.save(edited, original: saved))
        store.undoManager.endUndoGrouping()
        XCTAssertEqual(try store.repository.read().tasks.first?.title, "Edited immediately")
    }
    @MainActor func testUndoKeepsExternalTasksAndRedoRestoresEdit() throws {
        let store = makeStore(); defer { try? FileManager.default.removeItem(at: store.repository.directory) }
        store.undoManager.beginUndoGrouping()
        _ = store.save(FlowTask(title: "A"), original: nil)
        store.undoManager.endUndoGrouping()
        try store.repository.transaction { $0.tasks.append(FlowTask(title: "External B")) }
        store.undoManager.undo()
        XCTAssertEqual(store.board.tasks.map(\.title), ["External B"])
        store.undoManager.redo()
        XCTAssertEqual(Set(store.board.tasks.map(\.title)), Set(["A", "External B"]))
    }
    @MainActor func testConflictDoesNotOverwriteExternalEdit() throws {
        let store = makeStore(); defer { try? FileManager.default.removeItem(at: store.repository.directory) }
        store.undoManager.beginUndoGrouping()
        _ = store.save(FlowTask(title: "A"), original: nil)
        store.undoManager.endUndoGrouping()
        let saved = try XCTUnwrap(store.board.tasks.first)
        try store.repository.update(saved.id) { $0.title = "Changed externally" }
        var edited = saved; edited.title = "Local stale edit"
        store.undoManager.beginUndoGrouping()
        XCTAssertFalse(store.save(edited, original: saved))
        store.undoManager.endUndoGrouping()
        XCTAssertNotNil(store.error)
        XCTAssertEqual(try store.repository.read().tasks.first?.title, "Changed externally")
    }
    @MainActor func testReorderAndDeleteListPreserveTasks() throws {
        let store = makeStore(); defer { try? FileManager.default.removeItem(at: store.repository.directory) }
        let list = TaskList(name: "Work")
        let a = FlowTask(title: "A", listID: list.id, bucket: .week, order: 0)
        let b = FlowTask(title: "B", bucket: .week, order: 1)
        try store.repository.transaction { $0.lists = [list]; $0.tasks = [a, b] }
        store.refresh()
        store.undoManager.beginUndoGrouping()
        store.move(b.id, to: .week, before: a.id)
        store.deleteList(list)
        store.undoManager.endUndoGrouping()
        XCTAssertEqual(store.tasks(.week).map(\.title), ["B", "A"])
        XCTAssertEqual(store.board.tasks.count, 2)
        XCTAssertTrue(store.board.tasks.allSatisfy { $0.listID == nil })
    }
}
