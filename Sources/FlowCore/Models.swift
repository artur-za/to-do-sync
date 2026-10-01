import Foundation

public enum Bucket: String, Codable, CaseIterable, Identifiable, Sendable {
    case later, week, today, done
    public var id: String { rawValue }
    public var title: String {
        switch self { case .later: "Later"; case .week: "This week"; case .today: "Today"; case .done: "Done" }
    }
    public static func scheduled(for date: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bucket {
        guard let date else { return .later }
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) ? .week : .later
    }
}

public struct TaskList: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var color: String
    public var icon: String?
    public var symbolName: String { icon ?? "square" }
    public init(id: UUID = UUID(), name: String, color: String = "#FF5B60", icon: String? = nil) {
        self.id = id; self.name = name; self.color = color; self.icon = icon
    }
}

public struct FlowTask: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var note: String
    public var noteData: Data?
    public var listID: UUID?
    public var bucket: Bucket
    public var previousBucket: Bucket?
    public var dueDate: Date?
    public var reminder: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var plannedAt: Date
    public var order: Double
    public init(id: UUID = UUID(), title: String, note: String = "", listID: UUID? = nil,
                bucket: Bucket = .later, dueDate: Date? = nil, reminder: Date? = nil,
                now: Date = Date(), order: Double = 0) {
        self.id = id; self.title = title; self.note = note; self.listID = listID
        self.bucket = bucket; self.dueDate = dueDate; self.reminder = reminder
        self.createdAt = now; self.updatedAt = now; self.plannedAt = now; self.order = order
    }
    public mutating func move(to destination: Bucket, now: Date = Date()) {
        if destination == .done {
            if bucket != .done { previousBucket = bucket }
            completedAt = now
        } else { completedAt = nil }
        bucket = destination; plannedAt = now; updatedAt = now
    }
    public mutating func reopen(now: Date = Date()) { move(to: previousBucket ?? .later, now: now) }
}

public struct Board: Codable, Equatable, Sendable {
    public var version = 1
    public var revision: Int = 0
    public var tasks: [FlowTask] = []
    public var lists: [TaskList] = []
    public var pinnedTaskID: UUID?
    public init() {}

    /// Columns are user-owned. Time and deadlines never move existing tasks.
    /// Keep only non-scheduling housekeeping for callers during refresh/sync.
    public mutating func reconcile(now: Date = Date(), calendar: Calendar = .current) {
        if let pinnedTaskID, !tasks.contains(where: { $0.id == pinnedTaskID && $0.bucket != .done }) {
            self.pinnedTaskID = nil
        }
    }

    public func visible(_ bucket: Bucket, listID: UUID? = nil) -> [FlowTask] {
        tasks.filter { $0.bucket == bucket && (listID == nil || $0.listID == listID) }
            .sorted { bucket == .done ? ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) : $0.order < $1.order }
    }
}

public enum FlowError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}
