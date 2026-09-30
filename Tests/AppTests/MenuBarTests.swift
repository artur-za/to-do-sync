import XCTest
import AppKit
import FlowCore
@testable import FlodoOpen

final class MenuBarTests: XCTestCase {
    func testCountOnlyIncludesUnfinishedTodayAndKeepsZeroVisible() {
        var board = Board()
        XCTAssertEqual(MenuBarState(board: board).title, " 0")
        board.tasks = [FlowTask(title: "Today", bucket: .today), FlowTask(title: "Overdue but in Today", bucket: .today, dueDate: Date().addingTimeInterval(-86400)), FlowTask(title: "Later"), FlowTask(title: "Week", bucket: .week), FlowTask(title: "Done", bucket: .done)]
        XCTAssertEqual(MenuBarState(board: board).todayCount, 2)
        board.tasks[0].move(to: .done)
        XCTAssertEqual(MenuBarState(board: board).title, " 1")
    }
    func testPinDoesNotReplaceCountAndLongTitleIsBounded() {
        var board = Board()
        let pinned = FlowTask(title: String(repeating: "A", count: 80), bucket: .today)
        board.tasks = [pinned]; board.pinnedTaskID = pinned.id
        let state = MenuBarState(board: board)
        XCTAssertEqual(state.title, " 1 · " + String(repeating: "A", count: 18) + "…")
        XCTAssertTrue(state.tooltip.contains(pinned.title))
        board.tasks[0].move(to: .done)
        XCTAssertEqual(MenuBarState(board: board).title, " 0")
    }
    @MainActor func testNativeStatusUpdatesOnCompletionReopenAndIgnoresFilters() async throws {
        guard ProcessInfo.processInfo.environment["FLODO_TEST_UI"] == "1" else { throw XCTSkip("Requires desktop session") }
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FlodoStatusTests-\(UUID())")
        let store = Store(repository: Repository(directory: directory), enableSystemServices: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let today = FlowTask(title: "Today", bucket: .today)
        try store.repository.transaction { $0.tasks = [today, FlowTask(title: "Later")] }; store.refresh()
        let controller = MenuBarController(store: store, menu: NSMenu())
        defer { controller.invalidate() }
        XCTAssertTrue(controller.item.isVisible)
        XCTAssertEqual(controller.item.button?.title, " 1")
        XCTAssertTrue(controller.item.button?.image?.isTemplate == true)
        XCTAssertEqual(controller.item.button?.image?.size, NSSize(width: 16,height: 16))
        store.selectedList = UUID(); store.query = "no results"
        XCTAssertEqual(controller.item.button?.title, " 1")
        store.complete(today)
        XCTAssertEqual(controller.item.button?.title, " 0")
        let completed = try XCTUnwrap(store.board.tasks.first { $0.id == today.id })
        store.complete(completed)
        XCTAssertEqual(controller.item.button?.title, " 1")
        // Item survives closing the board; the controller has no window ownership.
        XCTAssertNotNil(controller.item.menu)
    }
}
