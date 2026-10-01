import SwiftUI
import UniformTypeIdentifiers
import FlowCore

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x57A66A
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
}

struct WindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .underWindowBackground; view.blendingMode = .behindWindow; view.state = .active
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView); window.isOpaque = false
            window.backgroundColor = .clear; window.isMovableByWindowBackground = false
            window.setFrameAutosaveName("FlowBoard")
        }
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct DottedLine: Shape {
    func path(in rect: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: 0, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)); return p }
}

struct BoardView: View {
    @EnvironmentObject var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            WindowMaterial().ignoresSafeArea()
            VStack(spacing: 0) {
                windowHeader
                if store.searching {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search tasks", text: $store.query).textFieldStyle(.plain)
                        Button { store.searching = false; store.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                    }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 18).padding(.bottom, 8)
                }
                if store.showingDone { completedView }
                else {
                    HStack(spacing: 0) {
                        column(.later)
                        Divider().opacity(0.4).padding(.top, 28)
                        column(.week)
                        Divider().opacity(0.4).padding(.top, 28)
                        column(.today)
                    }
                }
            }
            if store.editor == nil && !store.showingDone {
                Button { store.create() } label: { Image(systemName: "plus").font(.system(size: 19, weight: .light)).frame(width: 40, height: 40).background(.regularMaterial, in: Circle()).overlay(Circle().strokeBorder(Color.primary.opacity(0.08))) }
                    .buttonStyle(.plain).padding(18).help("Create task").accessibilityLabel("Create task")
            }
            if let draft = store.editor {
                TaskEditor(initial: draft).id(draft.id).environmentObject(store)
                    .frame(width: 380).padding(16)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)))
                    .zIndex(10)
            }
        }
        .coordinateSpace(name: "board")
        .onPreferenceChange(RowFramesKey.self) { store.rowFrames = $0 }
        .onPreferenceChange(ColumnFramesKey.self) { store.columnFrames = $0 }
        .font(.system(size: 14))
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 820, minHeight: 500)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.9), value: store.editor?.id)
        .preferredColorScheme(store.appearance == "light" ? .light : store.appearance == "dark" ? .dark : nil)
        .alert("Couldn’t save the change", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .alert("Delete “\(store.listToDelete?.name ?? "")”?", isPresented: Binding(get: { store.listToDelete != nil }, set: { if !$0 { store.listToDelete = nil } })) {
            Button("Cancel", role: .cancel) { store.listToDelete = nil }
            Button("Delete", role: .destructive) { if let list = store.listToDelete { store.deleteList(list) }; store.listToDelete = nil }
        } message: { Text("Tasks will be kept without a list assignment.") }
    }
    private var windowHeader: some View {
        HStack(spacing: 15) {
            Spacer()
            if store.showingDone { Text("Done").fontWeight(.medium); Spacer() }
            Button { store.compact.toggle() } label: { Image(systemName: store.compact ? "list.bullet" : "text.alignleft") }
                .help(store.compact ? "Show descriptions" : "Hide descriptions")
            Button { store.showingDone.toggle() } label: { Image(systemName: store.showingDone ? "tray.full.fill" : "tray.full") }
                .help(store.showingDone ? "Back to board" : "Completed tasks")
        }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 20).frame(height: 28).padding(.top, 8)
    }
    private func column(_ bucket: Bucket) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 5) {
                Text(bucket.title).fontWeight(.semibold)
                if !store.tasks(bucket).isEmpty { Text("\(store.tasks(bucket).count)").foregroundStyle(.secondary).contentTransition(.numericText()) }
                Spacer(minLength: 4)
                if bucket == .later { listFilters }
            }.frame(height: 28).padding(.horizontal, 18)
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.previewTasks(bucket)) { task in
                            TaskRow(task: task, isFirst: store.previewTasks(bucket).first?.id == task.id).environmentObject(store)
                                .opacity(store.draggedTaskID == task.id ? 0.22 : 1)
                        }
                        if store.previewTasks(bucket).isEmpty {
                            Image(systemName: "tray").font(.system(size: 26, weight: .ultraLight)).foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity).frame(height: max(100, geometry.size.height - 70))
                        }
                        Color.clear.frame(height: 90).contentShape(Rectangle()).onTapGesture(count: 2) { store.create(in: bucket) }
                    }.padding(.horizontal, 18)
                        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.88), value: store.dragDestination)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.tasks(bucket).map(\.id))
                }.scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GeometryReader { column in Color.clear.preference(key: ColumnFramesKey.self, value: [bucket: column.frame(in: .named("board"))]) })
        .contentShape(Rectangle())
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named("board")).onEnded { store.deselectIfOutsideTask(at: $0.location) })
        .contextMenu { Button("New task") { store.create(in: bucket) } }
    }
    private var listFilters: some View {
        HStack(spacing: 7) {
            Button { store.selectedList = nil } label: {
                HStack(spacing: 4) { Image(systemName: "square.grid.2x2"); if store.selectedList == nil { Text("All") } }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(store.selectedList == nil ? Color.primary.opacity(0.07) : .clear, in: Capsule())
            }.fixedSize().help("All lists")
            ForEach(store.board.lists.prefix(4)) { list in
                Button { store.selectedList = store.selectedList == list.id ? nil : list.id } label: {
                    HStack(spacing: 5) {
                        ListGlyph(list: list, selected: store.selectedList == list.id)
                        if store.selectedList == list.id { Text(list.name).fontWeight(.semibold).lineLimit(1) }
                    }.padding(.horizontal, store.selectedList == list.id ? 10 : 4).padding(.vertical, 5)
                        .background(store.selectedList == list.id ? Color.primary.opacity(0.09) : .clear, in: Capsule())
                }.help(list.name).accessibilityLabel(list.name)
                    .contextMenu {
                        Button("Edit") { store.listEditor = list }
                        Button("Delete", role: .destructive) { store.listToDelete = list }
                    }
            }
            if store.board.lists.count > 4 {
                Menu { ForEach(store.board.lists.dropFirst(4)) { list in Button(list.name) { store.selectedList = list.id } } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
            }
            Button { store.listEditor = TaskList(name: "") } label: { Image(systemName: "plus").foregroundStyle(.secondary) }.help("Create list")
                .popover(isPresented: Binding(get: { store.listEditor != nil }, set: { if !$0 { store.listEditor = nil } }), arrowEdge: .bottom) {
                    if let list = store.listEditor { ListEditor(initial: list).id(list.id).environmentObject(store) }
                }
        }.buttonStyle(.plain).font(.system(size: 12))
    }
    private var completedView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if store.tasks(.done).isEmpty {
                    ContentUnavailableView("No completed tasks yet", systemImage: "checkmark.circle", description: Text("Completed tasks will appear here."))
                }
                ForEach(store.tasks(.done)) { task in TaskRow(task: task, isFirst: store.tasks(.done).first?.id == task.id).environmentObject(store) }
            }.padding(.horizontal, 24).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named("board")).onEnded { store.deselectIfOutsideTask(at: $0.location) })
    }
}

struct TaskRow: View {
    @EnvironmentObject var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let task: FlowTask
    var isFirst = false
    @State private var hovering = false
    @State private var completing = false
    private var list: TaskList? { store.board.lists.first { $0.id == task.listID } }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                guard !completing else { return }
                if task.bucket == .done || reduceMotion { store.complete(task) }
                else {
                    withAnimation(.easeInOut(duration: 0.15)) { completing = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { store.complete(task); completing = false }
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(task.bucket == .done || completing ? Color.accentColor : Color.primary.opacity(hovering ? 0.12 : 0.06))
                    if task.bucket == .done || completing { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
                }.frame(width: 16, height: 16).scaleEffect(completing ? 0.86 : 1)
            }.buttonStyle(.plain).padding(.top, 2).help(task.bucket == .done ? "Mark as not completed" : "Complete task")
                .accessibilityLabel(task.bucket == .done ? "Reopen \(task.title)" : "Complete \(task.title)")
            VStack(alignment: .leading, spacing: store.compact ? 0 : 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(task.title).strikethrough(task.bucket == .done || completing).foregroundStyle(task.bucket == .done ? .secondary : .primary)
                    .lineLimit(store.compact ? 1 : nil).fixedSize(horizontal: false, vertical: true)
                if store.compact {
                    Spacer(minLength: 0)
                    if !task.note.isEmpty { Image(systemName: "text.alignleft").foregroundStyle(.tertiary).font(.system(size: 10)) }
                    if task.reminder != nil { Image(systemName: "alarm").foregroundStyle(.secondary).font(.system(size: 10)) }
                    else if task.dueDate != nil { Image(systemName: "calendar").foregroundStyle(.secondary).font(.system(size: 10)) }
                    if let list { ListGlyph(list: list, size: 8) }
                }
                }
                if !store.compact {
                    if !task.note.isEmpty { Text(task.note).foregroundStyle(.secondary).lineLimit(3) }
                    if let images = task.images, !images.isEmpty { TaskImageStrip(images: images) }
                    if list != nil || task.dueDate != nil || task.reminder != nil { metadata }
                }
                DottedLine().stroke(Color.primary.opacity(0.13), style: StrokeStyle(lineWidth: 1.5, dash: [3, 7])).frame(height: 1).padding(.top, store.compact ? 10 : 6)
            }
            if store.board.pinnedTaskID == task.id { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.tertiary) }
        }
        // The separator is the row boundary; inter-row spacing belongs above its content.
        .padding(.top, (store.compact ? 7.0 : 11.0) * (isFirst ? 1 : 2))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.compact)
        .contentShape(Rectangle())
        .overlay { TaskDragSource(task: task, store: store, isFirst: isFirst) }
        .onHover { hovering = $0 }
        .background {
            if store.selectedTaskID == task.id {
                Rectangle().fill(Color.accentColor.opacity(0.075)).padding(.horizontal, -18)
            }
        }
        .background(GeometryReader { row in Color.clear.preference(key: RowFramesKey.self, value: [task.id: row.frame(in: .named("board"))]) })
        .focusable().focusEffectDisabled()
        .onKeyPress(.return) { store.editor = task; return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Edit task") { store.editor = task }
        .contextMenu {
            Button("Edit") { store.editor = task }
            Button(task.bucket == .done ? "Mark as not completed" : "Complete") { store.complete(task) }
            Menu("Move to") { ForEach([Bucket.later, .week, .today]) { bucket in Button(bucket.title) { store.move(task.id, to: bucket) } } }
            Button(store.board.pinnedTaskID == task.id ? "Unpin from menubar" : "Pin to menubar") { store.pin(task) }.disabled(task.bucket == .done)
            Menu("List") {
                Button("None") { store.assign(task.id, to: nil) }
                ForEach(store.board.lists) { list in Button { store.assign(task.id, to: list.id) } label: { Label(list.name, systemImage: list.symbolName) } }
            }
            Divider()
            Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(task.title, forType: .string) }
            Button("Delete", role: .destructive) { store.delete(task) }
        }
    }
    private var metadata: some View {
        HStack(spacing: 5) {
            if let reminder = task.reminder {
                badge(reminder.formatted(date: Calendar.current.isDateInToday(reminder) ? .omitted : .abbreviated, time: .shortened), icon: "alarm", color: reminder < Date() ? .red : .orange)
            } else if let due = task.dueDate {
                badge(due.formatted(.dateTime.month(.abbreviated).day()), icon: "calendar", color: due < Calendar.current.startOfDay(for: Date()) ? .red : .secondary)
            }
            if let list {
                HStack(spacing: 4) {
                    ListGlyph(list: list, size: 8)
                    Text(list.name).foregroundStyle(.secondary).lineLimit(1)
                }.font(.system(size: 11)).padding(.horizontal, 6).padding(.vertical, 3).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }
    private func badge(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon).font(.system(size: 11)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 3).background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
    }
}

struct RowFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
struct ColumnFramesKey: PreferenceKey {
    static var defaultValue: [Bucket: CGRect] = [:]
    static func reduce(value: inout [Bucket: CGRect], nextValue: () -> [Bucket: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
