import SwiftUI
import FlowCore

extension NSPasteboard.PasteboardType {
    static let flodoTask = Self("local.flodo-open.task")
}

/// AppKit owns the drag session, including Escape cancellation and the floating image.
struct TaskDragSource: NSViewRepresentable {
    let task: FlowTask
    let store: Store
    var isFirst = false
    func makeNSView(context: Context) -> TaskDragView { TaskDragView(task: task, store: store, isFirst: isFirst) }
    func updateNSView(_ view: TaskDragView, context: Context) { view.task = task; view.isFirst = isFirst }
}

final class TaskDragView: NSView, NSDraggingSource {
    var task: FlowTask
    var isFirst: Bool
    weak var store: Store?
    private var down: NSEvent?
    private var sessionStarted = false
    init(task: FlowTask, store: Store, isFirst: Bool = false) { self.task = task; self.store = store; self.isFirst = isFirst; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local), local.x > 25 else { return nil }
        if let event = NSApp?.currentEvent, [.rightMouseDown, .rightMouseUp, .scrollWheel].contains(event.type) || event.modifierFlags.contains(.control) { return nil }
        return self
    }
    override func mouseDown(with event: NSEvent) { down = event; sessionStarted = false; store?.selectedTaskID = task.id }
    override func mouseUp(with event: NSEvent) {
        if down != nil && !sessionStarted { store?.editor = task }
        down = nil
    }
    override func mouseDragged(with event: NSEvent) {
        guard !sessionStarted, let down, let store else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard hypot(dx, dy) >= 4 else { return }
        let item = NSPasteboardItem(); item.setString(task.id.uuidString, forType: .flodoTask)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        let size = bounds.size
        // Render the same row at its exact source dimensions, including metadata.
        let root = TaskRow(task: task, isFirst: isFirst).environmentObject(store)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
        let host = NSHostingView(rootView: root); host.appearance = effectiveAppearance; host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        bitmap.size = size
        let image = NSImage(size: size); image.addRepresentation(bitmap); image.size = size
        dragging.setDraggingFrame(NSRect(x: 0, y: (bounds.height - size.height) / 2, width: size.width, height: size.height), contents: image)
        sessionStarted = true
        store.activeDragSource = self
        store.beginDrag(task.id, height: bounds.height)
        let session = beginDraggingSession(with: [dragging], event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? .move : [] }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { store?.endDrag(); store?.activeDragSource = nil; down = nil; sessionStarted = false }
}

final class BoardHostingView<Content: View>: NSHostingView<Content> {
    weak var store: Store?
    init(rootView: Content, store: Store) { self.store = store; super.init(rootView: rootView); registerForDraggedTypes([.flodoTask]) }
    @MainActor required init(rootView: Content) { super.init(rootView: rootView) }
    @MainActor required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        guard let source = sender.draggingSource as? TaskDragView, source.store === store,
              let raw = sender.draggingPasteboard.string(forType: .flodoTask), UUID(uuidString: raw) == store?.draggedTaskID,
              store?.showingDone == false else { return false }
        return true
    }
    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender) else { return [] }
        let local = convert(sender.draggingLocation, from: nil)
        let point = CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
        store?.updateDrag(at: point)
        if let hit = hitTest(convert(local, to: superview)), let scroll = hit.enclosingScrollView {
            let clip = scroll.contentView
            let p = clip.convert(sender.draggingLocation, from: nil)
            let edge: CGFloat = 30
            let delta: CGFloat = p.y < clip.bounds.minY + edge ? -7 : p.y > clip.bounds.maxY - edge ? 7 : 0
            if delta != 0, let document = scroll.documentView {
                let oldY = clip.bounds.minY
                let newY = min(max(0, oldY + delta), max(0, document.bounds.height - clip.bounds.height))
                clip.scroll(to: NSPoint(x: clip.bounds.minX, y: newY)); scroll.reflectScrolledClipView(clip)
                if let bucket = store?.dragDestination?.bucket, let store {
                    for task in store.tasks(bucket) { store.dragBaseline[task.id]?.origin.y -= newY - oldY }
                }
            }
        }
        return store?.dragDestination == nil ? [] : .move
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { store?.dragDestination = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard accepts(sender) else { return false }
        sender.animatesToDestination = true
        return true
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard accepts(sender) else { return false }
        _ = update(sender)
        if let id = store?.draggedTaskID, let frame = store?.rowFrames[id] {
            let target = isFlipped ? frame : CGRect(x: frame.minX, y: bounds.height - frame.maxY, width: frame.width, height: frame.height)
            sender.enumerateDraggingItems(options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in item.draggingFrame = target }
        }
        return store?.commitDrag() ?? false
    }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }
}
