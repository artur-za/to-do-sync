import XCTest
import AppKit
import FlowCore
@testable import FlodoOpen

final class InteractionTests: XCTestCase {
    @MainActor private func makeStore() -> Store {
        let store = Store(repository: Repository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("FlodoInteraction-\(UUID())")), enableSystemServices: false)
        store.undoManager.groupsByEvent = false
        return store
    }
    @MainActor func testNoDateCreationAndExplicitDateClearingGoToLater() throws {
        let store = makeStore(); defer { try? FileManager.default.removeItem(at: store.repository.directory) }
        store.undoManager.beginUndoGrouping(); defer { store.undoManager.endUndoGrouping() }
        store.create(in: .today)
        XCTAssertNil(store.editor?.dueDate)
        var task = FlowTask(title: "Undated", bucket: .today, reminder: Date().addingTimeInterval(3600))
        XCTAssertTrue(store.save(task, original: nil))
        XCTAssertEqual(store.board.tasks.first?.bucket, .later)
        task = try XCTUnwrap(store.board.tasks.first)
        let original = task; task.dueDate = Calendar.current.startOfDay(for: Date())
        XCTAssertTrue(store.save(task, original: original))
        XCTAssertEqual(store.board.tasks.first?.bucket, .today)
        task = try XCTUnwrap(store.board.tasks.first)
        let dated = task; task.dueDate = nil
        XCTAssertTrue(store.save(task, original: dated, scheduleChanged: true))
        XCTAssertEqual(store.board.tasks.first?.bucket, .later)
    }
    @MainActor func testEditingAnUndatedManuallyMovedTaskPreservesItsColumn() throws {
        let store = makeStore(); defer { try? FileManager.default.removeItem(at: store.repository.directory) }
        let task = FlowTask(title: "Moved manually", bucket: .today)
        try store.repository.transaction { $0.tasks = [task] }; store.refresh()
        let original = try XCTUnwrap(store.board.tasks.first)
        var edited = original; edited.note = "Note"
        store.undoManager.beginUndoGrouping()
        XCTAssertTrue(store.save(edited, original: original))
        store.undoManager.endUndoGrouping()
        XCTAssertEqual(store.board.tasks.first?.bucket, .today)
    }
    @MainActor func testFilterOnlyAffectsLaterAndCrossColumnPreviewNeverWrites() throws {
        let store = makeStore(); defer { try? FileManager.default.removeItem(at: store.repository.directory) }
        let list = TaskList(name: "Daily")
        let a = FlowTask(title: "A", bucket: .today, order: 0)
        let b = FlowTask(title: "B", listID: list.id, bucket: .later, order: 1)
        let c = FlowTask(title: "C", bucket: .week, order: 2)
        try store.repository.transaction { $0.tasks = [a,b,c]; $0.lists = [list] }; store.refresh(); store.selectedList = list.id
        XCTAssertEqual(store.tasks(.today).count, 1); XCTAssertEqual(store.tasks(.week).count, 1)
        store.columnFrames = [.later: CGRect(x: 0,y: 0,width: 100,height: 500), .week: CGRect(x: 100,y: 0,width: 100,height: 500), .today: CGRect(x: 200,y: 0,width: 100,height: 500)]
        store.rowFrames = [b.id: CGRect(x: 0,y: 50,width: 100,height: 50), a.id: CGRect(x: 200,y: 50,width: 100,height: 50)]
        let before = try store.repository.read()
        store.beginDrag(a.id, height: 50); store.updateDrag(at: CGPoint(x: 10,y: 20))
        XCTAssertEqual(store.previewTasks(.later).map(\.id), [a.id,b.id])
        XCTAssertTrue(store.previewTasks(.today).isEmpty)
        XCTAssertEqual(store.tasks(.today).count, 1)
        XCTAssertEqual(try store.repository.read(), before)
        store.endDrag()
        XCTAssertEqual(store.previewTasks(.today).map(\.id), [a.id]); XCTAssertEqual(try store.repository.read(), before)
        store.beginDrag(a.id, height: 50); store.updateDrag(at: CGPoint(x: 10,y: 20))
        store.undoManager.beginUndoGrouping(); XCTAssertTrue(store.commitDrag()); store.undoManager.endUndoGrouping()
        XCTAssertEqual(store.tasks(.later).map(\.id), [a.id,b.id]); XCTAssertNil(store.selectedList)
        XCTAssertEqual(store.board.revision, before.revision + 1)
        store.undoManager.undo(); XCTAssertEqual(store.board.tasks.first { $0.id == a.id }?.bucket, .today)
    }
    @MainActor func testReorderAndInvalidDrop() throws {
        let store = makeStore(); defer { try? FileManager.default.removeItem(at: store.repository.directory) }
        let a = FlowTask(title: "A", bucket: .week, dueDate: Date().addingTimeInterval(86400), order: 0)
        let b = FlowTask(title: "B", bucket: .week, order: 1)
        try store.repository.transaction { $0.tasks = [a,b] }; store.refresh()
        store.columnFrames = [.week: CGRect(x: 0,y: 0,width: 100,height: 300)]
        store.rowFrames = [a.id: CGRect(x: 0,y: 50,width: 100,height: 50),b.id: CGRect(x: 0,y: 100,width: 100,height: 50)]
        let savedDate = store.board.tasks.first { $0.id == a.id }?.dueDate
        store.beginDrag(a.id, height: 50); store.updateDrag(at: CGPoint(x: 10,y: 250))
        XCTAssertEqual(store.previewTasks(.week).map(\.id), [b.id,a.id])
        store.undoManager.beginUndoGrouping(); XCTAssertTrue(store.commitDrag()); store.undoManager.endUndoGrouping()
        XCTAssertEqual(store.tasks(.week).map(\.id), [b.id,a.id]); XCTAssertEqual(store.board.tasks.first { $0.id == a.id }?.dueDate, savedDate)
        let revision = store.board.revision
        store.beginDrag(a.id, height: 50); store.updateDrag(at: CGPoint(x: 500,y: 500)); XCTAssertFalse(store.commitDrag())
        XCTAssertEqual(store.board.revision, revision)
    }
    @MainActor func testListCompatibilityAndAllThirtySymbolsExist() throws {
        let oldJSON = Data("{\"id\":\"\(UUID())\",\"name\":\"Old list\",\"color\":\"#FF0000\"}".utf8)
        let old = try JSONDecoder().decode(TaskList.self, from: oldJSON)
        XCTAssertNil(old.icon); XCTAssertEqual(old.symbolName, "square")
        let custom = TaskList(name: "Code", icon: "chevron.left.forwardslash.chevron.right")
        XCTAssertEqual(try JSONDecoder().decode(TaskList.self, from: JSONEncoder().encode(custom)), custom)
        XCTAssertEqual(ListSymbolChoice.all.count, 30)
        XCTAssertEqual(Set(ListSymbolChoice.all.map(\.symbol)).count, 30)
        for choice in ListSymbolChoice.all { XCTAssertNotNil(NSImage(systemSymbolName: choice.symbol, accessibilityDescription: nil), choice.symbol) }
    }
    @MainActor func testNativeDragHitRegionLeavesCheckboxAvailable() {
        let store = makeStore(); defer { try? FileManager.default.removeItem(at: store.repository.directory) }
        let container = NSView(frame: CGRect(x: 0,y: 0,width: 300,height: 80))
        let view = TaskDragView(task: FlowTask(title: "A"), store: store)
        view.frame = container.bounds; container.addSubview(view)
        XCTAssertNil(view.hitTest(CGPoint(x: 10,y: 20)))
        XCTAssertTrue(view.hitTest(CGPoint(x: 90,y: 20)) === view)
        XCTAssertFalse(view.mouseDownCanMoveWindow)
    }
}
