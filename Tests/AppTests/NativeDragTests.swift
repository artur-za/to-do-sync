import XCTest
import AppKit
import SwiftUI
import FlowCore
@testable import FlodoOpen

@MainActor private final class DragInfo: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .move
    var draggingLocation = NSPoint.zero
    var draggedImageLocation = NSPoint.zero
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any?
    var draggingSequenceNumber: Int = 1
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight = .none
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey : Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}

final class NativeDragTests: XCTestCase {
    @MainActor func testRealBoardHitTestingAndNativeDropRouting() async throws {
        // Opt in on a desktop session: this opens only an isolated test window.
        guard ProcessInfo.processInfo.environment["FLODO_TEST_UI"] == "1" else { throw XCTSkip("Run with FLODO_TEST_UI=1 in a macOS desktop session") }
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FlodoNativeDrag-\(UUID())")
        let store = Store(repository: Repository(directory: directory), enableSystemServices: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let task = FlowTask(title: "Drag this task", bucket: .today)
        try store.repository.transaction { $0.tasks = [task] }; store.refresh()
        let window = NSWindow(contentRect: NSRect(x: 100,y: 100,width: 1120,height: 700), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = BoardHostingView(rootView: BoardView().environmentObject(store), store: store)
        window.contentView = root; window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        root.layoutSubtreeIfNeeded()
        XCTAssertEqual(store.columnFrames.count, 3)
        let frame = try XCTUnwrap(store.rowFrames[task.id])
        func rootPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: root.isFlipped ? p.y : root.bounds.height - p.y) }
        let hit = root.hitTest(root.convert(rootPoint(CGPoint(x: frame.minX + 70, y: frame.midY)), to: root.superview))
        let source = try XCTUnwrap(hit as? TaskDragView, "Task text must receive native mouse events, got \(String(describing: hit))")
        XCTAssertEqual(source.task.id, task.id)
        XCTAssertFalse(root.hitTest(root.convert(rootPoint(CGPoint(x: frame.minX + 8,y: frame.midY)), to: root.superview)) is TaskDragView)
        XCTAssertFalse(window.isMovableByWindowBackground)
        // Blank-space selection changes must preserve an open editor and its draft.
        store.editor = task
        XCTAssertEqual(store.selectedTaskID, task.id)
        store.deselectIfOutsideTask(at: CGPoint(x: frame.midX, y: frame.midY))
        XCTAssertEqual(store.selectedTaskID, task.id)
        store.deselectIfOutsideTask(at: CGPoint(x: frame.midX, y: frame.maxY + 60))
        XCTAssertNil(store.selectedTaskID)
        XCTAssertEqual(store.editor?.id, task.id)
        store.editor = nil
        let info = DragInfo(); info.draggingDestinationWindow = window; info.draggingSource = source
        info.draggingPasteboard.setString(task.id.uuidString, forType: .flodoTask)
        defer { info.draggingPasteboard.releaseGlobally() }
        let target = try XCTUnwrap(store.columnFrames[.week])
        info.draggingLocation = root.convert(rootPoint(CGPoint(x: target.midX,y: target.minY + 120)), to: nil)
        let revision = store.board.revision
        store.beginDrag(task.id, height: frame.height)
        XCTAssertEqual(root.draggingEntered(info), .move)
        XCTAssertEqual(store.dragDestination?.bucket, .week)
        XCTAssertEqual(store.board.revision, revision)
        XCTAssertEqual(store.previewTasks(.week).map(\.id), [task.id])
        root.draggingExited(info); XCTAssertNil(store.dragDestination)
        XCTAssertEqual(root.draggingUpdated(info), .move)
        XCTAssertTrue(root.prepareForDragOperation(info))
        XCTAssertTrue(root.performDragOperation(info))
        XCTAssertEqual(store.board.tasks.first?.bucket, .week)
        XCTAssertEqual(store.board.revision, revision + 1)
        XCTAssertNil(store.draggedTaskID)
        // A foreign source carrying even a valid local UUID must be refused.
        store.beginDrag(task.id, height: frame.height); info.draggingSource = nil
        XCTAssertEqual(root.draggingEntered(info), [])
        XCTAssertFalse(root.performDragOperation(info)); store.endDrag()
    }
}
