import SwiftUI
import UserNotifications
import FlowCore
import Combine

@main enum FlodoOpenMain {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--configure-sync"), CommandLine.arguments.count > index + 1 {
            do {
                let endpoint = CommandLine.arguments[index + 1]
                let token = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                try SyncCredential.save(token, endpoint: endpoint)
                try SyncConfiguration(endpoint: endpoint, enabled: true).save()
                print("Sync configured; credential saved to Keychain")
                return
            } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate, NSWindowDelegate {
    var store: Store?
    private var syncController: SyncController?
    private var boardWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var menuBar: MenuBarController?
    private var boardSubscription: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = Store(enableSystemServices: !CommandLine.arguments.contains("--snapshot"))
        self.store = store
        if !CommandLine.arguments.contains("--snapshot") { syncController = SyncController(store: store) }
        configureMenu()
        createWindow(store)
        let statusMenu = NSMenu(); statusMenu.delegate = self
        menuBar = MenuBarController(store: store, menu: statusMenu)
        boardSubscription = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusTitle() }
        }
        updateStatusTitle()
        openBoard()
        let center = UNUserNotificationCenter.current(); center.delegate = self
        let complete = UNNotificationAction(identifier: "complete", title: "Complete", options: [])
        let ten = UNNotificationAction(identifier: "snooze10", title: "Remind in 10 minutes", options: [])
        let hour = UNNotificationAction(identifier: "snooze60", title: "Remind in 1 hour", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "TASK_REMINDER", actions: [complete, ten, hour], intentIdentifiers: [])])
        if CommandLine.arguments.contains("--snapshot") { FileHandle.standardError.write(Data("preview: notifications configured\n".utf8)) }
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--snapshot") { FileHandle.standardError.write(Data("preview: activated\n".utf8)) }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index + 1 {
            let destination = CommandLine.arguments[index + 1]
            if CommandLine.arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
            else { NSApp.appearance = NSAppearance(named: .aqua) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if CommandLine.arguments.contains("--compact") { self.store?.compact = true }
                if CommandLine.arguments.contains("--done") { self.store?.showingDone = true }
                if CommandLine.arguments.contains("--selected"), let task = self.store?.tasks(.today).dropFirst().first { self.store?.selectedTaskID = task.id }
                if CommandLine.arguments.contains("--editor") { self.store?.editor = FlowTask(title: CommandLine.arguments.contains("--empty") ? "" : "flow your todo.") }
                if CommandLine.arguments.contains("--list-editor") { self.store?.listEditor = TaskList(name: "") }
                if CommandLine.arguments.contains("--filter"), let list = self.store?.board.lists.first { self.store?.selectedList = list.id }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard let window = NSApp.windows.first(where: { $0.title == "Flodo Open" }), let content = window.contentView else { exit(2) }
                    content.layoutSubtreeIfNeeded()
                    guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { exit(3) }
                    content.cacheDisplay(in: content.bounds, to: bitmap)
                    guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(4) }
                    do {
                        try png.write(to: URL(fileURLWithPath: destination))
                        if let item = self.menuBar?.item {
                            self.menuWillOpen(item.menu!)
                            let report: [String: Any] = ["visible": item.isVisible, "title": item.button?.title ?? "", "hasImage": item.button?.image != nil, "quitWired": item.menu?.items.contains { $0.title == "Quit Flodo Open" && $0.target === self && $0.action == #selector(self.quit) } ?? false, "dockWhileWindowOpen": NSApp.activationPolicy() == .regular]
                            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: destination + ".status.json"))
                        }
                        FileHandle.standardError.write(Data("preview main frame: \(window.frame)\n".utf8))
                        for (index, panel) in NSApp.windows.filter({ $0 !== window && $0.isVisible && $0.contentView != nil }).enumerated() {
                            FileHandle.standardError.write(Data("preview panel frame: \(panel.frame)\n".utf8))
                            if let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                                view.cacheDisplay(in: view.bounds, to: rep)
                                try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: destination + ".panel-\(index).png"))
                            }
                        }
                        NSApp.terminate(nil)
                    }
                    catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8)); exit(5) }
                }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openBoard(); return true }
    private func createWindow(_ store: Store) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Flodo Open"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear; window.isOpaque = false; window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 820, height: 500)
        window.contentView = BoardHostingView(rootView: BoardView().environmentObject(store), store: store)
        if !window.setFrameUsingName("FlowBoard") { window.center() }
        window.setFrameAutosaveName("FlowBoard")
        boardWindow = window
    }
    @objc func openBoard() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        boardWindow?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hasWindow = self.boardWindow?.isVisible == true || self.settingsWindow?.isVisible == true
            NSApp.setActivationPolicy(hasWindow ? .regular : .accessory)
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func newTask() { openBoard(); store?.create() }
    @objc private func newList() { openBoard(); store?.listEditor = TaskList(name: "") }
    @objc private func findTasks() { openBoard(); store?.searching.toggle() }
    @objc private func toggleCompact() { store?.compact.toggle() }
    @objc private func showCompleted() { openBoard(); store?.showingDone.toggle() }
    @objc private func exportJSON() { store?.exportJSON() }
    @objc private func importJSON() { store?.importJSON() }
    @objc private func importFlodo() {
        openBoard()
        let alert = NSAlert(); alert.messageText = "Import tasks from Flodo?"
        alert.informativeText = "Adds a local copy of your Flodo tasks and lists. The original database stays unchanged. Repeated imports skip existing task IDs. Check the column placement and note formatting after import."
        alert.addButton(withTitle: "Import"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { store?.importFlodo() }
    }
    @objc private func showSettings() {
        guard let store else { return }
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 410), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Settings"; window.isReleasedWhenClosed = false; window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(sync: syncController).environmentObject(store))
            window.center(); settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    private var activeUndoManager: UndoManager? {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager ?? store?.undoManager
    }
    @objc private func undo() { activeUndoManager?.undo() }
    @objc private func redo() { activeUndoManager?.redo() }
    @objc private func completePinned() {
        guard let store, let task = store.board.tasks.first(where: { $0.id == store.board.pinnedTaskID }) else { return }
        store.complete(task)
    }
    @objc private func unpin() { store?.mutate("Unpin Task") { $0.pinnedTaskID = nil } }
    private func updateStatusTitle() {
        if !CommandLine.arguments.contains("--snapshot") {
            NSApp.appearance = store?.appearance == "light" ? NSAppearance(named: .aqua) : store?.appearance == "dark" ? NSAppearance(named: .darkAqua) : nil
        }
    }
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === menuBar?.item.menu else { return }
        menu.removeAllItems()
        if let store, let task = store.board.tasks.first(where: { $0.id == store.board.pinnedTaskID }) {
            menu.addItem(withTitle: task.title, action: nil, keyEquivalent: "")
            add("Mark Complete", #selector(completePinned), to: menu)
            add("Unpin", #selector(unpin), to: menu); menu.addItem(.separator())
        }
        add("Open Flodo Open", #selector(openBoard), to: menu)
        add("New Task", #selector(newTask), to: menu)
        menu.addItem(.separator())
        add("Settings…", #selector(showSettings), to: menu)
        menu.addItem(.separator())
        add("Quit Flodo Open", #selector(quit), key: "q", to: menu)
    }
    private func add(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command, to menu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self; item.keyEquivalentModifierMask = modifiers
    }
    private func configureMenu() {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = main.addItem(withTitle: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title); item.submenu = menu; return menu
        }
        let app = submenu("Flodo Open")
        app.addItem(withTitle: "About Flodo Open", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        add("Settings…", #selector(showSettings), key: ",", to: app)
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Flodo Open", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"); hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator()); add("Quit Flodo Open", #selector(quit), key: "q", to: app)
        let file = submenu("File")
        add("New Task", #selector(newTask), key: "n", to: file)
        add("New List", #selector(newList), key: "n", modifiers: [.command, .shift], to: file)
        file.addItem(.separator()); add("Import Flodo Tasks…", #selector(importFlodo), to: file)
        add("Import JSON…", #selector(importJSON), to: file)
        add("Export JSON…", #selector(exportJSON), key: "e", modifiers: [.command, .shift], to: file)
        file.addItem(.separator()); file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = submenu("Edit")
        add("Undo", #selector(undo), key: "z", to: edit)
        add("Redo", #selector(redo), key: "z", modifiers: [.command, .shift], to: edit)
        edit.addItem(.separator())
        for (name, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: name, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        if let fontMenu = NSFontManager.shared.fontMenu(true) { let fonts = edit.addItem(withTitle: "Font", action: nil, keyEquivalent: ""); fonts.submenu = fontMenu }
        let view = submenu("View")
        add("Find Tasks", #selector(findTasks), key: "f", to: view)
        add("Toggle Compact View", #selector(toggleCompact), key: "l", modifiers: [.command, .shift], to: view)
        add("Show / Hide Completed Tasks", #selector(showCompleted), key: "d", modifiers: [.command, .shift], to: view)
        let window = submenu("Window"); NSApp.windowsMenu = window
        add("Open Board", #selector(openBoard), to: window)
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.mainMenu = main
    }
    func applicationWillTerminate(_ notification: Notification) {
        menuBar?.invalidate(); menuBar = nil
        if CommandLine.arguments.contains("--snapshot") { FileHandle.standardError.write(Data("preview: will terminate\n".utf8)) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            defer { completionHandler() }
            guard let raw = response.notification.request.content.userInfo["taskID"] as? String, let id = UUID(uuidString: raw), let store = self.store else { return }
            store.refresh()
            switch response.actionIdentifier {
            case "complete":
                store.mutate("Complete Task") { board in if let i = board.tasks.firstIndex(where: { $0.id == id }) { board.tasks[i].move(to: .done) } }
            case "snooze10", "snooze60":
                store.mutate("Snooze Reminder") { board in if let i = board.tasks.firstIndex(where: { $0.id == id }) { board.tasks[i].reminder = Date().addingTimeInterval(response.actionIdentifier == "snooze10" ? 600 : 3600); board.tasks[i].updatedAt = Date() } }
            default:
                store.editor = store.board.tasks.first { $0.id == id }
                self.openBoard()
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    var sync: SyncController? = nil
    var body: some View {
        TabView {
            if let sync { SyncSettingsView(sync: sync).tabItem { Label("Telegram", systemImage: "arrow.triangle.2.circlepath") } }
            Form {
                Picker("Appearance", selection: $store.appearance) {
                    Text("Follow system").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                Toggle("Compact rows", isOn: $store.compact)
                Toggle("Completion sound", isOn: $store.soundEnabled)
                Section("Reminders") {
                    Button("Enable notifications") { store.scheduleReminders(requestPermission: true) }
                    Text("For persistent reminders, choose Alerts in System Settings → Notifications.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Local data") {
                    Text("Local storage with optional Telegram sync.").foregroundStyle(.secondary)
                    HStack { Button("Export backup…") { store.exportJSON() }; Button("Import backup…") { store.importJSON() } }
                    Button("Show data folder") { NSWorkspace.shared.open(store.repository.directory) }
                }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }
            VStack(spacing: 14) {
                Image(systemName: "checkmark.square.fill").font(.system(size: 50)).foregroundStyle(.blue.gradient)
                Text("Flodo Open").font(.title2.bold())
                Text("0.3.0 • Native macOS • MIT License").foregroundStyle(.secondary)
                Text("An independent, locally stored implementation.\nSource included. No task limits or tracking.")
                    .multilineTextAlignment(.center).font(.callout)
                Text("Inspired by Flodo by Zayn Hao. Not affiliated with the original app.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).tabItem { Label("About", systemImage: "info.circle") }
        }.frame(width: 470, height: 410)
    }
}
