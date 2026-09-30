import AppKit
import Combine
import FlowCore

struct MenuBarState: Equatable {
    let todayCount: Int
    let pinnedTitle: String?
    init(board: Board) {
        todayCount = board.tasks.filter { $0.bucket == .today && $0.completedAt == nil }.count
        pinnedTitle = board.tasks.first { $0.id == board.pinnedTaskID && $0.bucket != .done }?.title
    }
    var title: String {
        let count = " \(todayCount)"
        guard let pinnedTitle else { return count }
        return count + " · " + String(pinnedTitle.prefix(18)) + (pinnedTitle.count > 18 ? "…" : "")
    }
    var tooltip: String {
        let summary = "Flodo Open — \(todayCount) unfinished tasks today"
        return pinnedTitle.map { summary + "\n" + $0 } ?? summary
    }
}

/// Retains the native status item independently of the board window's lifetime.
@MainActor final class MenuBarController {
    let item: NSStatusItem
    private var subscription: AnyCancellable?
    init(store: Store, menu: NSMenu) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "FlodoOpen.Today"
        item.behavior = []
        item.isVisible = true
        item.menu = menu
        if let button = item.button {
            let image = NSImage(systemSymbolName: "checkmark.square", accessibilityDescription: "Flodo Open")
            image?.size = NSSize(width: 16, height: 16)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            button.setAccessibilityIdentifier("FlodoOpen.TodayStatus")
        }
        subscription = store.$board.map(MenuBarState.init).removeDuplicates().sink { [weak self] state in
            self?.item.button?.title = state.title
            self?.item.button?.toolTip = state.tooltip
            self?.item.button?.setAccessibilityLabel(state.tooltip)
        }
    }
    func invalidate() {
        subscription?.cancel(); subscription = nil
        NSStatusBar.system.removeStatusItem(item)
    }
}
