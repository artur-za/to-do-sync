import Foundation
import SQLite3
import FlowCore
import AppKit

enum FlodoImporter {
    /// Reads through SQLite's transaction snapshot, including its WAL. Never opens the original for writing.
    static func read() throws -> Board {
        let path = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("default.store").path
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; throw FlowError.invalid("Could not open Flodo's local database.")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 3000)
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw FlowError.invalid("Could not read a consistent database snapshot.") }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        func rows(_ query: String, _ consume: (OpaquePointer) throws -> Void) throws {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement else { throw FlowError.invalid("Flodo's data format is not supported by this importer.") }
            defer { sqlite3_finalize(statement) }
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW { try consume(statement); status = sqlite3_step(statement) }
            guard status == SQLITE_DONE else { throw FlowError.invalid("Could not read Flodo data.") }
        }
        func text(_ s: OpaquePointer, _ c: Int32) -> String { sqlite3_column_text(s, c).map { String(cString: $0) } ?? "" }
        func date(_ s: OpaquePointer, _ c: Int32) -> Date? { sqlite3_column_type(s, c) == SQLITE_NULL ? nil : Date(timeIntervalSinceReferenceDate: sqlite3_column_double(s, c)) }
        func uuid(_ s: OpaquePointer, _ c: Int32) throws -> UUID {
            guard sqlite3_column_bytes(s, c) == 16, let bytes = sqlite3_column_blob(s, c)?.assumingMemoryBound(to: UInt8.self) else { throw FlowError.invalid("Unsupported Flodo identifier format.") }
            return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        }
        var result = Board(); var categories: [Int64: UUID] = [:]
        try rows("SELECT Z_PK,ZID,ZNAME,ZCOLORHEX FROM ZTASKCATEGORY ORDER BY ZSORTINDEX") { s in
            let id = try uuid(s, 1); categories[sqlite3_column_int64(s, 0)] = id
            result.lists.append(TaskList(id: id, name: text(s, 2), color: text(s, 3)))
        }
        try rows("SELECT ZID,ZTITLE,ZNOTE,ZCOMPLETED,ZDUEDATE,ZREMINDERAT,ZCREATEDAT,ZUPDATEDAT,ZCOMPLETEDAT,ZCATEGORY,ZSORTINDEX,ZWEEK,ZYEAR,ZNOTEDATA FROM ZTASKITEM") { s in
            let due = date(s, 4); let completed = sqlite3_column_int(s, 3) != 0
            let now = Date(); let calendar = Calendar.current
            let week = sqlite3_column_int(s, 11), year = sqlite3_column_int(s, 12)
            var bucket: Bucket = .later
            if week == calendar.component(.weekOfYear, from: now) && year == calendar.component(.yearForWeekOfYear, from: now) { bucket = .week }
            if let due, calendar.isDateInToday(due) { bucket = .today }
            if completed { bucket = .done }
            var task = FlowTask(id: try uuid(s, 0), title: text(s, 1), note: text(s, 2), listID: categories[sqlite3_column_int64(s, 9)], bucket: bucket, dueDate: due, reminder: date(s, 5), now: date(s, 6) ?? now, order: sqlite3_column_double(s, 10))
            task.updatedAt = date(s, 7) ?? now; task.completedAt = date(s, 8); task.plannedAt = now
            if let bytes = sqlite3_column_blob(s, 13), sqlite3_column_bytes(s, 13) > 0 {
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(s, 13)))
                if let rich = try? JSONDecoder().decode(AttributedString.self, from: data) {
                    let attributed = NSAttributedString(rich)
                    task.note = attributed.string
                    task.noteData = try? attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
                }
            }
            if !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.tasks.append(task) }
        }
        return result
    }
}
