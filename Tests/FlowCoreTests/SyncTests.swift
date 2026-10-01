import XCTest
@testable import FlowCore

final class SyncTests: XCTestCase {
    func initial() -> Board { var b = Board(); b.tasks = [FlowTask(title: "Original", note: "Note", now: Date(timeIntervalSince1970: 1790770000))]; return b }
    func state(_ board: Board) throws -> SyncState {
        var s = SyncState(); s.epoch = "server"; s.records = try BoardSync.records(board).mapValues { var r = $0; r.version = 1; return r }; return s
    }
    func snapshot(_ board: Board) throws -> SyncSnapshot {
        SyncSnapshot(epoch: "server", revision: 2, records: try BoardSync.records(board).values.map { var r = $0; r.version = 2; return r })
    }
    func testImagesSurviveStorageAndIndependentNoteEdits() throws {
        var original = initial()
        original.tasks[0].images = [TaskImage(dataURL: "data:image/png;base64,AAAA")]
        let record = try XCTUnwrap(BoardSync.records(original).values.first { $0.kind == "task" })
        if case .array(let images) = record.value?.object?["images"] {
            XCTAssertEqual(images.first?.object?["id"], .string(original.tasks[0].images![0].id.uuidString.lowercased()))
        } else { XCTFail("Missing encoded images") }
        let data = try Repository.encoder().encode(original)
        XCTAssertEqual(try Repository.decoder().decode(Board.self, from: data), original)
        var legacy = initial()
        XCTAssertNil(try Repository.decoder().decode(Board.self, from: Repository.encoder().encode(legacy)).tasks[0].images)
        var upgraded = original; upgraded.tasks[0].images = nil
        XCTAssertTrue(try BoardSync.merge(board: &upgraded, base: state(original), remote: snapshot(original)).isEmpty)
        XCTAssertEqual(upgraded.tasks[0].images, original.tasks[0].images)
        var local = original; local.tasks[0].images?.append(TaskImage(dataURL: "data:image/jpeg;base64,BBBB"))
        var remote = original; remote.tasks[0].note = "Edited on another device"
        XCTAssertTrue(try BoardSync.merge(board: &local, base: state(original), remote: snapshot(remote)).isEmpty)
        XCTAssertEqual(local.tasks[0].images?.count, 2)
        XCTAssertEqual(local.tasks[0].note, remote.tasks[0].note)
        legacy = local; legacy.tasks[0].images = []
        _ = try BoardSync.merge(board: &local, base: state(local), remote: snapshot(legacy))
        XCTAssertEqual(local.tasks[0].images, [])
    }
    func testIndependentEditsMergeAndGenerateRetry() throws {
        let original = initial(); let base = try state(original)
        var local = original; local.tasks[0].title = "Mac"
        var remote = original; remote.tasks[0].note = "Telegram"
        let incoming = try snapshot(remote)
        XCTAssertTrue(try BoardSync.merge(board: &local, base: base, remote: incoming).isEmpty)
        XCTAssertEqual(local.tasks[0].title, "Mac"); XCTAssertEqual(local.tasks[0].note, "Telegram")
        let ops = try BoardSync.operations(board: local, state: state(remote))
        XCTAssertEqual(ops.count, 1); XCTAssertEqual(ops[0].baseVersion, 1)
    }
    func testSameFieldConflictRetainsBothVersions() throws {
        let original = initial(); var local = original; var remote = original
        local.tasks[0].title = "Mac"; remote.tasks[0].title = "Telegram"
        let conflicts = try BoardSync.merge(board: &local, base: state(original), remote: snapshot(remote))
        XCTAssertEqual(conflicts.count, 1); XCTAssertEqual(conflicts[0].fields, ["title"])
        XCTAssertEqual(conflicts[0].remote?.object?["title"], .string("Telegram"))
        XCTAssertEqual(local.tasks[0].title, "Mac")
    }
    func testDeletionWinsConcurrentEditAndIsArchived() throws {
        let original = initial(); var local = original; local.tasks[0].note = "Offline edit"
        let tombstone = SyncRecord(kind: "task", id: original.tasks[0].id.uuidString, version: 2, deleted: true, value: nil)
        let conflicts = try BoardSync.merge(board: &local, base: state(original), remote: SyncSnapshot(epoch: "server", revision: 2, records: [tombstone]))
        XCTAssertTrue(local.tasks.isEmpty); XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts[0].local?.object?["note"], .string("Offline edit"))
    }
    func testRemoteNewTaskAndRetryAreIdempotent() throws {
        var local = Board(); let remote = initial(); let incoming = try snapshot(remote)
        _ = try BoardSync.merge(board: &local, base: SyncState(), remote: incoming)
        XCTAssertEqual(local.tasks, remote.tasks)
        XCTAssertTrue(try BoardSync.operations(board: local, state: state(remote)).isEmpty)
        _ = try BoardSync.merge(board: &local, base: state(remote), remote: incoming)
        XCTAssertEqual(local.tasks.count, 1)
    }
    func testRemotePlainTextInvalidatesRichNote() throws {
        var original = initial(); original.tasks[0].noteData = Data("rich".utf8)
        var local = original; local.tasks[0].title = "Mac"
        var remote = original; remote.tasks[0].note = "Plain"; remote.tasks[0].noteData = nil
        _ = try BoardSync.merge(board: &local, base: state(original), remote: snapshot(remote))
        XCTAssertNil(local.tasks[0].noteData); XCTAssertEqual(local.tasks[0].note, "Plain")
    }
    func testEpochMismatchDoesNotMutateBoard() throws {
        var local = initial(); let before = local
        XCTAssertThrowsError(try BoardSync.merge(board: &local, base: state(local), remote: SyncSnapshot(epoch: "replaced", revision: 0, records: [])))
        XCTAssertEqual(local, before)
    }
    func testFirstConnectionAdoptsRemotePin() throws {
        var remote = initial(); remote.pinnedTaskID = remote.tasks[0].id
        var local = Board()
        XCTAssertTrue(try BoardSync.merge(board: &local, base: SyncState(), remote: snapshot(remote)).isEmpty)
        XCTAssertEqual(local.pinnedTaskID, remote.pinnedTaskID)
    }
    func testLocalDeletionProducesVersionedTombstone() throws {
        let original = initial(); let ops = try BoardSync.operations(board: Board(), state: state(original))
        XCTAssertEqual(ops.count, 1); XCTAssertTrue(ops[0].deleted); XCTAssertNil(ops[0].value)
        XCTAssertEqual(ops[0].baseVersion, 1)
    }
}
