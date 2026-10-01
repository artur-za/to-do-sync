import SwiftUI

/// AppKit retains system input methods, spelling, rich text, links, attachments,
/// selection, text undo, and the macOS contextual menu.
struct RichNoteEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var richData: Data?
    @Binding var isFocused: Bool
    var pasteImages: () -> Bool = { false }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let view = FocusNoteView(frame: .zero)
        view.pasteImages = { context.coordinator.parent.pasteImages() }
        view.focusChanged = { focused in context.coordinator.parent.isFocused = focused }
        view.isRichText = true; view.importsGraphics = true; view.allowsUndo = true
        view.isAutomaticLinkDetectionEnabled = true; view.isContinuousSpellCheckingEnabled = true
        view.isAutomaticSpellingCorrectionEnabled = true; view.usesAdaptiveColorMappingForDarkAppearance = true
        view.drawsBackground = false; view.font = .systemFont(ofSize: 14); view.textColor = .labelColor
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width: 0, height: 4)
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.delegate = context.coordinator; view.setAccessibilityLabel("Notes")
        scroll.documentView = view; context.coordinator.view = view; load(view)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { load(view) }
    }
    private func load(_ view: NSTextView) {
        if let richData, let attributed = try? NSAttributedString(data: richData, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil) {
            view.textStorage?.setAttributedString(attributed)
        } else { view.string = text; view.font = .systemFont(ofSize: 14); view.textColor = .labelColor }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichNoteEditor
        weak var view: NSTextView?
        init(_ parent: RichNoteEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view else { return }
            parent.text = view.string
            parent.richData = try? view.attributedString().data(from: NSRange(location: 0, length: view.attributedString().length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        }
    }
}

final class FocusNoteView: NSTextView {
    var pasteImages: (() -> Bool)?
    override func paste(_ sender: Any?) { if pasteImages?() != true { super.paste(sender) } }
    var focusChanged: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged?(true) }; return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusChanged?(false) }; return accepted
    }
}
