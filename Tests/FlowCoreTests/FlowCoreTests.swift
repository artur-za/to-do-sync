import XCTest
@testable import FlowCore

final class FlowCoreTests: XCTestCase {
    var calendar: Calendar {
        var c = Calendar(identifier: .iso8601); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c
    }
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func repository() -> Repository { Repository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("FlowTests-\(UUID())")) }
    func testTodayRollsBackAtMidnightAndWeekRollsBackMonday() {
        var board = Board()
        board.tasks = [FlowTask(title: "Test", bucket: .today, now: date("2026-09-29T18:00:00Z"))]
        board.reconcile(now: date("2026-09-30T08:00:00Z"), calendar: calendar)
        XCTAssertEqual(board.tasks[0].bucket, .week)
        board.reconcile(now: date("2026-10-05T08:00:00Z"), calendar: calendar)
        XCTAssertEqual(board.tasks[0].bucket, .later)
    }
    func testTodayCrossingWeekBoundaryGoesStraightToLater() {
        var board = Board(); board.tasks = [FlowTask(title: "Test", bucket: .today, now: date("2026-10-04T20:00:00Z"))]
        board.reconcile(now: date("2026-10-05T08:00:00Z"), calendar: calendar)
        XCTAssertEqual(board.tasks[0].bucket, .later)
    }
    func testFutureDatePromotesOnceAndCompletionIsPreserved() {
        var board = Board()
        let due = date("2026-09-30T00:00:00Z")
        board.tasks = [FlowTask(title: "Due", dueDate: due, now: date("2026-09-29T08:00:00Z"))]
        board.reconcile(now: date("2026-09-30T08:00:00Z"), calendar: calendar)
        XCTAssertEqual(board.tasks[0].bucket, .today)
        board.reconcile(now: date("2026-10-01T08:00:00Z"), calendar: calendar)
        XCTAssertEqual(board.tasks[0].bucket, .week)
        board.tasks[0].move(to: .done)
        board.reconcile(now: date("2026-10-15T08:00:00Z"), calendar: calendar)
        XCTAssertEqual(board.tasks[0].bucket, .done)
    }
    func testUndoCompletionRestoresBucketAndClearsPinnedTask() {
        var board = Board(); board.tasks = [FlowTask(title: "Pinned", bucket: .today)]; board.pinnedTaskID = board.tasks[0].id
        board.tasks[0].move(to: .done); board.reconcile()
        XCTAssertNil(board.pinnedTaskID)
        board.tasks[0].reopen(); XCTAssertEqual(board.tasks[0].bucket, .today); XCTAssertNil(board.tasks[0].completedAt)
    }
    func testRoundTripAndTwoWritersPreserveBothTasks() throws {
        let a = repository(); defer { try? FileManager.default.removeItem(at: a.directory) }
        let b = Repository(directory: a.directory)
        try a.transaction { $0.tasks.append(FlowTask(title: "One")) }
        try b.transaction { $0.tasks.append(FlowTask(title: "Two")) }
        XCTAssertEqual(try a.read().tasks.map(\.title), ["One", "Two"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.directory.appendingPathComponent("board.previous.json").path))
    }
    func testConcurrentWritersDoNotLoseTasks() throws {
        let repo = repository(); defer { try? FileManager.default.removeItem(at: repo.directory) }
        let lock = NSLock(); var failures: [String] = []
        DispatchQueue.concurrentPerform(iterations: 24) { i in
            do { try Repository(directory: repo.directory).transaction { $0.tasks.append(FlowTask(title: "Task \(i)")) } }
            catch { lock.lock(); failures.append(error.localizedDescription); lock.unlock() }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "; "))
        XCTAssertEqual(try repo.read().tasks.count, 24)
    }
    func testCorruptionAndFutureVersionAreNeverOverwritten() throws {
        let repo = repository(); defer { try? FileManager.default.removeItem(at: repo.directory) }
        _ = try repo.read()
        let corrupted = Data("broken json".utf8); try corrupted.write(to: repo.fileURL)
        XCTAssertThrowsError(try repo.transaction { $0.tasks.append(FlowTask(title: "Should fail")) })
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), corrupted)
        var future = Board(); future.version = 999
        let bytes = try Repository.encoder().encode(future); try bytes.write(to: repo.fileURL)
        XCTAssertThrowsError(try repo.transaction { $0.tasks.append(FlowTask(title: "Should fail")) })
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), bytes)
    }
    func testInvalidTransactionDoesNotSave() throws {
        let repo = repository(); defer { try? FileManager.default.removeItem(at: repo.directory) }
        try repo.transaction { $0.tasks.append(FlowTask(title: "Keep")) }
        let before = try Data(contentsOf: repo.fileURL)
        XCTAssertThrowsError(try repo.transaction { $0.tasks.append(FlowTask(title: "   ")) })
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), before)
    }
    func testTitleParser() {
        let list = TaskList(name: "Work")
        let result = TitleParser.parse("Design review tomorrow 3pm #Work", lists: [list], now: date("2026-09-30T10:00:00Z"), calendar: calendar)
        XCTAssertEqual(result.title, "Design review"); XCTAssertEqual(result.listID, list.id)
        XCTAssertEqual(result.reminder, date("2026-10-01T15:00:00Z"))
        let invalid = TitleParser.parse("Meeting 29:99", lists: [], now: date("2026-09-30T10:00:00Z"), calendar: calendar)
        XCTAssertNil(invalid.reminder); XCTAssertEqual(invalid.title, "Meeting 29:99")
        let russian = TitleParser.parse("Позвонить завтра в 15:30", lists: [], now: date("2026-09-30T10:00:00Z"), calendar: calendar)
        XCTAssertEqual(russian.title, "Позвонить"); XCTAssertEqual(russian.reminder, date("2026-10-01T15:30:00Z"))
    }
}
