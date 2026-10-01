import SwiftUI
import FlowCore

struct TaskEditor: View {
    @EnvironmentObject var store: Store
    let initial: FlowTask
    @State private var draft: FlowTask
    @State private var original: FlowTask?
    @State private var datePopover = false
    @State private var reminderPopover = false
    @State private var listPopover = false
    @State private var manualDate = false
    @State private var manualList = false
    @State private var manualReminder = false
    @State private var parsedTitle: String?
    @State private var titleHover = false
    @State private var notesHover = false
    @State private var notesFocused = false
    @FocusState private var titleFocused: Bool
    init(initial: FlowTask) { self.initial = initial; _draft = State(initialValue: initial) }
    private var hasTitle: Bool { !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: Date())! }
    private func selected(_ date: Date) -> Bool { draft.dueDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("What’s next?", text: $draft.title, axis: .vertical)
                .font(.system(size: 15)).lineLimit(1...3).textFieldStyle(.plain).focused($titleFocused)
                .padding(.horizontal, 8).padding(.vertical, 7).frame(minHeight: 33)
                .background(Color.primary.opacity(titleFocused || titleHover ? 0.065 : 0), in: RoundedRectangle(cornerRadius: 9))
                .onHover { titleHover = $0 }
                .padding(.bottom, 4)
                .onSubmit(save).onChange(of: draft.title) { _, value in parse(value) }
            ZStack(alignment: .topLeading) {
                if draft.note.isEmpty { Text("Notes").foregroundStyle(.tertiary).padding(.leading, 8).padding(.top, 8).allowsHitTesting(false) }
                RichNoteEditor(text: $draft.note, richData: $draft.noteData, isFocused: $notesFocused, pasteImages: pasteImages).frame(height: 60).padding(.horizontal, 3).padding(.vertical, 4)
            }.background(Color.primary.opacity(notesFocused || notesHover ? 0.065 : 0), in: RoundedRectangle(cornerRadius: 9))
                .onHover { notesHover = $0 }.padding(.bottom, 10)
            if let images = draft.images, !images.isEmpty {
                TaskImageStrip(images: images, remove: { id in draft.images?.removeAll { $0.id == id } })
                    .padding(.bottom, 10)
            }
            dateRow
            separator
            reminderRow
            separator
            listRow
            HStack {
                Button { if original != nil { store.delete(initial) } else { store.editor = nil } } label: {
                    Image(systemName: "trash").foregroundStyle(.secondary).frame(width: 20, height: 28)
                }.buttonStyle(.plain).help(original == nil ? "Discard task" : "Delete task")
                Spacer()
                Button(original == nil ? "Create" : "Save", action: save)
                    .buttonStyle(CreateStyle()).disabled(!hasTitle).keyboardShortcut(.return, modifiers: .command)
            }.padding(.top, 12).padding(.bottom, 2)
        }
        .font(.system(size: 15)).padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
        .onAppear { original = store.board.tasks.first { $0.id == initial.id }; titleFocused = true }
        .background(ImagePasteCapture(action: pasteImages))
        .onExitCommand { store.editor = nil }
    }
    private func pasteImages() -> Bool {
        guard let images = NSImage.readableTypes(for: .general).first(where: { NSPasteboard.general.availableType(from: [$0]) != nil }), !images.rawValue.isEmpty else { return false }
        do {
            let additions = try ClipboardImages.read()
            guard !additions.isEmpty else { return false }
            let combined = (draft.images ?? []) + additions
            try ClipboardImages.validate(combined)
            draft.images = combined
        } catch { store.error = error.localizedDescription }
        return true
    }
    private var separator: some View { DottedLine().stroke(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [3, 7])).frame(height: 1).padding(.leading, 24) }
    private var dateRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "calendar").foregroundStyle(.secondary).frame(width: 16).padding(.trailing, 3)
            Text("Date"); Spacer(minLength: 2)
            Button("Today") { toggleDate(Date()) }.buttonStyle(PillStyle(selected: selected(Date())))
            Button("Tomorrow") { toggleDate(tomorrow) }.buttonStyle(PillStyle(selected: selected(tomorrow)))
            Button { datePopover.toggle() } label: {
                if let date = draft.dueDate, !selected(Date()), !selected(tomorrow) { Text(date.formatted(.dateTime.month(.abbreviated).day())).font(.system(size: 11)) }
                else { Image(systemName: "ellipsis") }
            }.buttonStyle(PillStyle(selected: draft.dueDate != nil && !selected(Date()) && !selected(tomorrow))).help("Another date")
                .popover(isPresented: $datePopover, arrowEdge: .top) {
                    VStack(spacing: 6) {
                        DatePicker("Date", selection: Binding(get: { draft.dueDate ?? Date() }, set: { setDate($0); datePopover = false }), displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
                        Button("No date") { draft.dueDate = nil; manualDate = true; datePopover = false }.buttonStyle(.plain).foregroundStyle(.secondary)
                    }.padding(12)
                }
        }.frame(height: 44)
    }
    private var reminderRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "alarm").foregroundStyle(.secondary).frame(width: 16)
            Text("Reminder"); Spacer()
            HStack(spacing: 5) {
                Button { reminderPopover.toggle() } label: { Text(draft.reminder?.formatted(date: .omitted, time: .shortened) ?? "None") }
                    .buttonStyle(.plain)
                    .popover(isPresented: $reminderPopover, arrowEdge: .top) { timePicker }
                if draft.reminder != nil {
                    Button { draft.reminder = nil; manualReminder = true } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }.buttonStyle(.plain).help("Clear reminder")
                }
            }.padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(draft.reminder == nil ? Color.primary : .white)
                .background(draft.reminder == nil ? Color.primary.opacity(0.055) : Color.blue, in: Capsule())
        }.frame(height: 44)
    }
    private var timePicker: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(0..<96, id: \.self) { slot in
                        let date = time(for: slot)
                        Button {
                            draft.reminder = date; manualReminder = true; reminderPopover = false
                        } label: { Text(date.formatted(date: .omitted, time: .shortened)).frame(maxWidth: .infinity).padding(.vertical, 6).contentShape(Rectangle()) }
                            .buttonStyle(.plain).id(slot)
                    }
                }.padding(5)
            }.frame(width: 116, height: 220).onAppear {
                let components = Calendar.current.dateComponents([.hour, .minute], from: draft.reminder ?? Date())
                proxy.scrollTo(min(95, (components.hour ?? 9) * 4 + (components.minute ?? 0) / 15), anchor: .center)
            }
        }
    }
    private func time(for slot: Int) -> Date { Calendar.current.date(bySettingHour: slot / 4, minute: (slot % 4) * 15, second: 0, of: draft.dueDate ?? Date())! }
    private var listRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "square").foregroundStyle(.secondary).frame(width: 16)
            Text("List"); Spacer()
            Button { listPopover.toggle() } label: {
                HStack(spacing: 5) {
                    if let list = store.board.lists.first(where: { $0.id == draft.listID }) { ListGlyph(list: list); Text(list.name).lineLimit(1) }
                    else { Image(systemName: "square").foregroundStyle(.secondary); Text("None") }
                    Image(systemName: "chevron.down").font(.system(size: 9))
                }
            }.buttonStyle(PillStyle()).popover(isPresented: $listPopover, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Button { draft.listID = nil; manualList = true; listPopover = false } label: {
                        Label("None", systemImage: "square").frame(maxWidth: .infinity, alignment: .leading).padding(7).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    ForEach(store.board.lists) { list in
                        Button { draft.listID = list.id; manualList = true; listPopover = false } label: {
                            HStack(spacing: 8) { ListGlyph(list: list); Text(list.name); Spacer(); if draft.listID == list.id { Image(systemName: "checkmark") } }.padding(7).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(5).frame(minWidth: 150)
            }
        }.frame(height: 44)
    }
    private func toggleDate(_ date: Date) { if selected(date) { draft.dueDate = nil; manualDate = true } else { setDate(date) } }
    private func setDate(_ date: Date) {
        draft.dueDate = Calendar.current.startOfDay(for: date); manualDate = true
        if let reminder = draft.reminder {
            let time = Calendar.current.dateComponents([.hour, .minute], from: reminder)
            draft.reminder = Calendar.current.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: date)
        }
    }
    private func parse(_ text: String) {
        guard original == nil else { return }
        let parsed = TitleParser.parse(text, lists: manualList ? [] : store.board.lists)
        if !manualDate { draft.dueDate = parsed.date }
        if !manualReminder { draft.reminder = parsed.reminder }
        if !manualList { draft.listID = parsed.listID ?? initial.listID }
        parsedTitle = (!manualDate && !manualList && !manualReminder) ? parsed.title : nil
    }
    private func save() {
        guard hasTitle else { return }
        var task = draft
        task.title = (parsedTitle ?? draft.title).trimmingCharacters(in: .whitespacesAndNewlines)
        task.updatedAt = Date()
        if store.save(task, original: original, scheduleChanged: manualDate), task.reminder != nil { store.scheduleReminders(requestPermission: true) }
    }
}

struct PillStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15)).frame(minHeight: 18).padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(selected ? Color.white : .primary)
            .background(selected ? Color.blue : Color.primary.opacity(configuration.isPressed ? 0.12 : 0.055), in: Capsule())
    }
}
struct CreateStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(enabled ? 1 : 0.45))
            .padding(.horizontal, 17).padding(.vertical, 6).background(Color.blue.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.5), in: Capsule())
    }
}

struct ListEditor: View {
    @EnvironmentObject var store: Store
    @State private var draft: TaskList
    @State private var iconsExpanded = false
    @State private var colorsExpanded = false
    @FocusState private var focused: Bool
    init(initial: TaskList) { _draft = State(initialValue: initial) }
    private let palette = ["#FF5B60", "#FFD15B", "#58C85C", "#378DFF", "#9A5BD1", "#E884BB", "#67B7B0", "#969696"]
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { colorsExpanded.toggle() } label: { ListGlyph(list: draft, size: 12).frame(width: 18, height: 25) }.buttonStyle(.plain).help("List color")
                    .popover(isPresented: $colorsExpanded) {
                        HStack(spacing: 9) { ForEach(palette, id: \.self) { color in
                            Button { draft.color = color; colorsExpanded = false } label: { Circle().fill(Color(hex: color)).frame(width: 20, height: 20).overlay { if draft.color == color { Image(systemName: "checkmark").font(.system(size: 10)).foregroundStyle(.white) } } }.buttonStyle(.plain).accessibilityLabel(color)
                        } }.padding(12)
                    }
                TextField("", text: $draft.name).textFieldStyle(.plain).focused($focused).onSubmit(save).accessibilityLabel("List name")
            }.padding(.horizontal, 11).padding(.vertical, 4).background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            DisclosureGroup("Icon", isExpanded: $iconsExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Button { draft.icon = nil } label: { Label("Default square", systemImage: "square") }.buttonStyle(.plain).padding(.top, 6)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                        ForEach(ListSymbolChoice.all) { choice in
                            Button { draft.icon = choice.symbol } label: {
                                Image(systemName: choice.symbol).frame(width: 28, height: 28).foregroundStyle(Color(hex: draft.color))
                                    .background(draft.icon == choice.symbol ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            }.buttonStyle(.plain).help(choice.name).accessibilityLabel(choice.name)
                        }
                    }
                }
            }.font(.system(size: 12)).foregroundStyle(.secondary)
            Button(action: save) {
                Text(store.board.lists.contains(where: { $0.id == draft.id }) ? "Save list" : "Create list")
                    .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(13).frame(width: 238).onAppear { focused = true }.onExitCommand { store.listEditor = nil }
    }
    private func save() { draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines); guard !draft.name.isEmpty else { return }; store.saveList(draft) }
}
