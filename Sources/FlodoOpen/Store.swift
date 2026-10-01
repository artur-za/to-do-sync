import SwiftUI
import FlowCore
import UserNotifications

@MainActor final class Store: ObservableObject {
    @Published var board = Board()
    @Published var error: String?
    @Published var selectedList: UUID?
    @Published var editor: FlowTask? { didSet { if let editor { selectedTaskID = editor.id } } }
    @Published var selectedTaskID: UUID?
    @Published var showingDone = false
    @Published var searching = false
    @Published var query = ""
    @Published var listEditor: TaskList?
    @Published var listToDelete: TaskList?
    @Published var draggedTaskID: UUID?
    @Published var dragDestination: DragDestination?
    var rowFrames: [UUID: CGRect] = [:]
    var columnFrames: [Bucket: CGRect] = [:]
    var dragBaseline: [UUID: CGRect] = [:]
    var dragStartBucket: Bucket?
    var dragPreviewHeight: CGFloat = 0
    var activeDragSource: TaskDragView?
    @Published var compact = false { didSet { if enableSystemServices { UserDefaults.standard.set(compact, forKey: "compactRows") } } }
    @Published var appearance = "system" { didSet { if enableSystemServices { UserDefaults.standard.set(appearance, forKey: "appearance") } } }
    @Published var soundEnabled = false { didSet { if enableSystemServices { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") } } }
    let repository: Repository
    let undoManager = UndoManager()
    private var timer: Timer?
    private var notificationSignature = ""
    private var notificationTask: Task<Void, Never>?
    private let enableSystemServices: Bool
    init(repository: Repository = Repository(), enableSystemServices: Bool = true) {
        self.repository = repository
        self.enableSystemServices = enableSystemServices
        if enableSystemServices {
            compact = UserDefaults.standard.bool(forKey: "compactRows")
            appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
            soundEnabled = UserDefaults.standard.bool(forKey: "soundEnabled")
        }
        refresh()
        if enableSystemServices { timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } } }
    }
    func refresh() {
        do {
            let fresh = try repository.transaction { $0.reconcile() }
            if fresh != board { board = fresh }
            scheduleReminders()
        } catch { self.error = error.localizedDescription }
    }
    func mutate(_ name: String, undoable: Bool = true, _ edit: (inout Board) throws -> Void) {
        error = nil
        do {
            var before = Board()
            let after = try repository.transaction { board in before = board; try edit(&board); board.reconcile() }
            board = after
            if undoable && before != after {
                undoManager.registerUndo(withTarget: self) { target in target.restoreChanges(from: after, to: before, name: name) }
                undoManager.setActionName(name)
            }
            scheduleReminders()
        } catch { self.error = error.localizedDescription }
    }
    private func restoreChanges(from expected: Board, to desired: Board, name: String) {
        // Undo only touched records, preserving unrelated changes made by the CLI.
        mutate(name) { current in
            let ids = Set(expected.tasks.map(\.id) + desired.tasks.map(\.id)).filter { id in expected.tasks.first { $0.id == id } != desired.tasks.first { $0.id == id } }
            for id in ids {
                guard current.tasks.first(where: { $0.id == id }) == expected.tasks.first(where: { $0.id == id }) else {
                    throw FlowError.invalid("This task changed elsewhere. Undo was cancelled to preserve the newer edit.")
                }
                current.tasks.removeAll { $0.id == id }
                if let task = desired.tasks.first(where: { $0.id == id }) { current.tasks.append(task) }
            }
            if expected.lists != desired.lists {
                guard current.lists == expected.lists else { throw FlowError.invalid("Lists changed elsewhere. Undo was cancelled.") }
                current.lists = desired.lists
            }
            if expected.pinnedTaskID != desired.pinnedTaskID { current.pinnedTaskID = desired.pinnedTaskID }
        }
    }
    func deselectIfOutsideTask(at point: CGPoint) {
        guard draggedTaskID == nil else { return }
        // Include the full-width highlight, beyond the text's horizontal inset.
        guard !rowFrames.values.contains(where: { $0.insetBy(dx: -18, dy: 0).contains(point) }) else { return }
        selectedTaskID = nil
    }
    func create(in bucket: Bucket = .later) {
        listEditor = nil; showingDone = false
        editor = FlowTask(title: "", listID: selectedList, bucket: .later, order: (board.tasks.map(\.order).min() ?? 0) - 1)
    }
    @discardableResult func save(_ task: FlowTask, original: FlowTask?, scheduleChanged: Bool = false) -> Bool {
        var task = task
        if task.bucket != .done && original == nil {
            task.move(to: Bucket.scheduled(for: task.dueDate))
        }
        var succeeded = false
        mutate(original == nil ? "Create Task" : "Edit Task") { board in
            if let index = board.tasks.firstIndex(where: { $0.id == task.id }) {
                guard board.tasks[index] == original else { throw FlowError.invalid("The task changed while you were editing. Close and reopen it to load the latest version.") }
                board.tasks[index] = task
            } else {
                guard original == nil else { throw FlowError.invalid("This task was deleted elsewhere.") }
                board.tasks.append(task)
            }
            succeeded = true
        }
        if succeeded && error == nil { editor = nil; return true }
        return false
    }
    func complete(_ task: FlowTask) {
        mutate(task.bucket == .done ? "Reopen Task" : "Complete Task") { board in
            guard let i = board.tasks.firstIndex(where: { $0.id == task.id }) else { return }
            if board.tasks[i].bucket == .done { board.tasks[i].reopen() } else { board.tasks[i].move(to: .done) }
        }
        if soundEnabled { NSSound(named: "Pop")?.play() }
    }
    func delete(_ task: FlowTask) { mutate("Delete Task") { $0.tasks.removeAll { $0.id == task.id } }; editor = nil }
    func move(_ id: UUID, to bucket: Bucket, before target: UUID? = nil) {
        mutate("Move Task") { board in
            guard let index = board.tasks.firstIndex(where: { $0.id == id }) else { return }
            guard id != target else { return }
            board.tasks[index].move(to: bucket)
            var ordered = board.visible(bucket).filter { $0.id != id }.map(\.id)
            let destination = target.flatMap { ordered.firstIndex(of: $0) } ?? ordered.count
            ordered.insert(id, at: destination)
            for (position, itemID) in ordered.enumerated() {
                if let i = board.tasks.firstIndex(where: { $0.id == itemID }) { board.tasks[i].order = Double(position) }
            }
        }
    }
    func pin(_ task: FlowTask) { mutate("Pin Task") { $0.pinnedTaskID = $0.pinnedTaskID == task.id ? nil : task.id } }
    func saveList(_ list: TaskList) {
        mutate("Edit List") { board in
            if let i = board.lists.firstIndex(where: { $0.id == list.id }) { board.lists[i] = list } else { board.lists.append(list) }
        }
        listEditor = nil
    }
    func deleteList(_ list: TaskList) {
        mutate("Delete List") { board in
            board.lists.removeAll { $0.id == list.id }
            for i in board.tasks.indices where board.tasks[i].listID == list.id { board.tasks[i].listID = nil }
        }
        if selectedList == list.id { selectedList = nil }
    }
    func tasks(_ bucket: Bucket) -> [FlowTask] {
        board.visible(bucket, listID: bucket == .later ? selectedList : nil).filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.note.localizedCaseInsensitiveContains(query)
        }
    }
    func assign(_ id: UUID, to listID: UUID?) {
        mutate("Change List") { board in
            guard let i = board.tasks.firstIndex(where: { $0.id == id }) else { return }
            board.tasks[i].listID = listID; board.tasks[i].updatedAt = Date()
        }
    }
    func previewTasks(_ bucket: Bucket) -> [FlowTask] {
        guard let id = draggedTaskID, let destination = dragDestination,
              let task = board.tasks.first(where: { $0.id == id }) else { return tasks(bucket) }
        var rows = tasks(bucket).filter { $0.id != id }
        if destination.bucket == bucket {
            let index = destination.before.flatMap { before in rows.firstIndex { $0.id == before } } ?? rows.count
            rows.insert(task, at: index)
        }
        return rows
    }
    func beginDrag(_ id: UUID, height: CGFloat) {
        guard let task = board.tasks.first(where: { $0.id == id }) else { return }
        editor = nil; listEditor = nil
        dragBaseline = rowFrames; dragStartBucket = task.bucket
        dragPreviewHeight = height; dragDestination = nil; draggedTaskID = id
    }
    func updateDrag(at point: CGPoint) {
        guard let id = draggedTaskID else { return }
        guard let bucket = [Bucket.later, .week, .today].first(where: { columnFrames[$0]?.contains(point) == true }) else {
            dragDestination = nil; return
        }
        let rows = tasks(bucket).filter { $0.id != id }
        // Stable pre-drag geometry prevents the animated insertion gap oscillating.
        let before = rows.first { task in
            guard let rect = dragBaseline[task.id] ?? rowFrames[task.id] else { return false }
            return point.y < rect.midY
        }?.id
        let destination = DragDestination(bucket: bucket, before: before)
        if destination != dragDestination { dragDestination = destination }
    }
    @discardableResult func commitDrag() -> Bool {
        guard let id = draggedTaskID, let destination = dragDestination,
              board.tasks.contains(where: { $0.id == id }) else { endDrag(); return false }
        move(id, to: destination.bucket, before: destination.before)
        if destination.bucket == .later, let selectedList,
           board.tasks.first(where: { $0.id == id })?.listID != selectedList { self.selectedList = nil }
        endDrag(); return error == nil
    }
    func endDrag() {
        draggedTaskID = nil; dragDestination = nil; dragBaseline = [:]; dragStartBucket = nil
    }
    func scheduleReminders(requestPermission: Bool = false) {
        guard enableSystemServices else { return }
        let tasks = board.tasks.filter { $0.bucket != .done && ($0.reminder ?? .distantPast) > Date() }
        let signature = tasks.map { "\($0.id):\($0.reminder!):\($0.title)" }.sorted().joined(separator: "|")
        guard signature != notificationSignature || requestPermission else { return }
        notificationSignature = signature
        notificationTask?.cancel()
        notificationTask = Task {
            let center = UNUserNotificationCenter.current()
            if requestPermission {
                do {
                    guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                        self.error = "Notifications are disabled. Enable Flodo Open in System Settings → Notifications to receive reminders."
                        return
                    }
                } catch { self.error = error.localizedDescription; return }
            }
            let settings = await center.notificationSettings()
            guard !Task.isCancelled else { return }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            center.removeAllPendingNotificationRequests()
            for task in tasks.sorted(by: { $0.reminder! < $1.reminder! }).prefix(60) {
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = task.title; content.body = task.note; content.sound = .default
                content.categoryIdentifier = "TASK_REMINDER"; content.userInfo = ["taskID": task.id.uuidString]
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: task.reminder!)
                do { try await center.add(UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))) }
                catch { self.error = error.localizedDescription }
            }
        }
    }
    func exportJSON() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "FlodoOpen-backup.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Repository.encoder().encode(repository.read()).write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    func importJSON() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try Repository.decoder().decode(Board.self, from: Data(contentsOf: url))
            guard imported.version == 1 else { throw FlowError.invalid("Unsupported backup version.") }
            merge(imported)
        } catch { self.error = error.localizedDescription }
    }
    func merge(_ imported: Board) {
        mutate("Import Tasks") { board in
            for list in imported.lists where !board.lists.contains(where: { $0.id == list.id }) { board.lists.append(list) }
            for task in imported.tasks where !board.tasks.contains(where: { $0.id == task.id }) { board.tasks.append(task) }
        }
    }
    func importFlodo() {
        do { merge(try FlodoImporter.read()) } catch { self.error = error.localizedDescription }
    }
}
