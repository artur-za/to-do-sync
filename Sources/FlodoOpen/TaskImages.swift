import SwiftUI
import FlowCore
import CoreImage

/// Bound both decoded dimensions and wire size before adding an attachment to a draft.
@MainActor enum ClipboardImages {
    static func validate(_ images: [TaskImage]) throws {
        guard images.count <= 8, images.reduce(0, { $0 + $1.dataURL.utf8.count }) <= 1_500_000 else {
            throw FlowError.invalid("Up to 8 images per task (1.5 MB in total).")
        }
    }
    static func read() throws -> [TaskImage] {
        let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage] ?? []
        return try images.map(encode)
    }
    static func encode(_ image: NSImage) throws -> TaskImage {
        guard image.size.width > 0, image.size.height > 0 else { throw FlowError.invalid("Couldn’t read this image.") }
        var longest: CGFloat = 1600
        for _ in 0..<6 {
            let ratio = min(1, longest / max(image.size.width, image.size.height))
            let size = NSSize(width: max(1, round(image.size.width * ratio)), height: max(1, round(image.size.height * ratio)))
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw FlowError.invalid("Couldn’t prepare this image.") }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
            image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            if let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]), data.count <= 300_000 {
                return TaskImage(dataURL: "data:image/jpeg;base64," + data.base64EncodedString())
            }
            longest *= 0.75
        }
        throw FlowError.invalid("This image is too large to attach.")
    }
    static func decode(_ attachment: TaskImage) -> NSImage? {
        guard attachment.dataURL.hasPrefix("data:image/jpeg;base64,") || attachment.dataURL.hasPrefix("data:image/png;base64,"),
              let raw = attachment.dataURL.split(separator: ",", maxSplits: 1).last,
              let data = Data(base64Encoded: String(raw)) else { return nil }
        return NSImage(data: data)
    }
}

struct ImagePasteCapture: NSViewRepresentable {
    let action: () -> Bool
    func makeNSView(context: Context) -> PasteCaptureView { let view = PasteCaptureView(); view.action = action; return view }
    func updateNSView(_ view: PasteCaptureView, context: Context) { view.action = action }
}
final class PasteCaptureView: NSView {
    var action: (() -> Bool)?
    private var monitor: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window != nil, event.window === self.window, event.keyCode == 9,
                  !event.modifierFlags.contains(.option), event.modifierFlags.intersection([.command, .control]).isEmpty == false else { return event }
            return self.action?() == true ? nil : event
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

struct TaskImageStrip: View {
    let images: [TaskImage]
    var remove: ((UUID) -> Void)?
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(images) { item in
                    if let image = ClipboardImages.decode(item) {
                        ImageThumbnailView(image: image)
                            .frame(width: min(144, max(36, 36 * image.size.width / image.size.height)), height: 36)
                            .contextMenu { if let remove { Button("Remove image", role: .destructive) { remove(item.id) } } }
                    }
                }
            }
        }.scrollIndicators(.hidden).frame(height: 36)
    }
}
struct ImageThumbnailView: NSViewRepresentable {
    let image: NSImage
    func makeNSView(context: Context) -> ImageThumbnail { let view = ImageThumbnail(); view.image = image; return view }
    func updateNSView(_ view: ImageThumbnail, context: Context) { view.image = image }
}
final class ImageThumbnail: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    private var hovered = false
    private var tracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!); super.updateTrackingAreas()
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel("View image")
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true; NSCursor.pointingHand.push() }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true; NSCursor.pop() }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).addClip()
        if let image {
            let ratio = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
            let rect = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
            if hovered, let data = image.tiffRepresentation, let ci = CIImage(data: data) {
                let blurred = ci.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(2, ci.extent.height / 18)]).cropped(to: ci.extent)
                let result = NSImage(size: image.size); result.addRepresentation(NSCIImageRep(ciImage: blurred)); result.draw(in: rect)
            } else { image.draw(in: rect) }
        }
        if hovered {
            NSColor.black.withAlphaComponent(0.15).setFill(); bounds.fill()
            let symbol = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium).applying(.init(paletteColors: [.white]))
            symbol.withSymbolConfiguration(config)?.draw(in: NSRect(x: bounds.midX-9, y: bounds.midY-9, width: 18, height: 18))
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { show() } }
    override func keyDown(with event: NSEvent) { if event.keyCode == 36 || event.keyCode == 49 { show() } else { super.keyDown(with: event) } }
    override func accessibilityPerformPress() -> Bool { show(); return true }
    private func show() { guard let image, let root = window?.contentView else { return }; ImageLightbox.show(image: image, source: self, root: root) }
    static func containsThumbnail(in view: NSView, windowPoint: NSPoint) -> Bool {
        if let thumb = view as? ImageThumbnail, !thumb.isHidden, thumb.bounds.contains(thumb.convert(windowPoint, from: nil)) { return true }
        return view.subviews.contains { containsThumbnail(in: $0, windowPoint: windowPoint) }
    }
}

/// A single image view travels between the thumbnail and the fitted preview in both directions.
final class ImageLightbox: NSView {
    private let picture = NSImageView()
    private let blur = NSVisualEffectView()
    private let copyButton = NSButton()
    private weak var source: ImageThumbnail?
    private weak var previousResponder: NSResponder?
    private var origin = NSRect.zero
    private var monitor: Any?
    private var closing = false
    override var acceptsFirstResponder: Bool { true }
    static func show(image: NSImage, source: ImageThumbnail, root: NSView) {
        guard !root.subviews.contains(where: { $0 is ImageLightbox }) else { return }
        let box = ImageLightbox(frame: root.bounds)
        box.autoresizingMask = [.width, .height]; box.source = source
        box.previousResponder = root.window?.firstResponder
        root.addSubview(box)
        box.origin = source.convert(source.bounds, to: box)
        box.blur.frame = box.bounds; box.blur.autoresizingMask = [.width, .height]
        box.blur.material = .fullScreenUI; box.blur.blendingMode = .withinWindow; box.blur.state = .active
        box.blur.alphaValue = 0; box.addSubview(box.blur)
        box.picture.image = image; box.picture.imageScaling = .scaleProportionallyUpOrDown
        box.picture.wantsLayer = true; box.picture.layer?.cornerRadius = 7; box.picture.layer?.masksToBounds = true
        box.picture.frame = box.origin; box.addSubview(box.picture)
        box.copyButton.bezelStyle = .circular; box.copyButton.isBordered = false
        box.copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy image")
        box.copyButton.toolTip = "Copy image"; box.copyButton.setAccessibilityLabel("Copy image")
        box.copyButton.wantsLayer = true; box.copyButton.layer?.cornerRadius = 18
        box.copyButton.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.75).cgColor
        box.copyButton.target = box; box.copyButton.action = #selector(box.copyImage)
        box.copyButton.alphaValue = 0; box.addSubview(box.copyButton)
        box.positionCopyButton()
        root.window?.makeFirstResponder(box)
        source.alphaValue = 0
        box.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak box] event in
            guard let box, event.window === box.window else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { box.dismiss(); return nil }
                if event.keyCode == 8 && event.modifierFlags.contains(.command) { box.copyImage(); return nil }
                // Do not let editor shortcuts modify the task behind the preview.
                return nil
            }
            let point = box.convert(event.locationInWindow, from: nil)
            if !box.picture.frame.contains(point) && !box.copyButton.frame.contains(point) { box.dismiss(); return nil }
            return event
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            box.picture.animator().frame = box.fittedRect()
            box.blur.animator().alphaValue = 1; box.copyButton.animator().alphaValue = 1
        }
    }
    private func positionCopyButton() { copyButton.frame = NSRect(x: bounds.midX - 18, y: 18, width: 36, height: 36) }
    private func fittedRect() -> NSRect {
        guard let image = picture.image else { return .zero }
        let area = NSRect(x: 32, y: 72, width: max(1, bounds.width-64), height: max(1, bounds.height-104))
        let ratio = min(area.width/image.size.width, area.height/image.size.height)
        let size = NSSize(width: image.size.width*ratio, height: image.size.height*ratio)
        return NSRect(x: area.midX-size.width/2, y: area.midY-size.height/2, width: size.width, height: size.height)
    }
    override func resizeSubviews(withOldSize oldSize: NSSize) { super.resizeSubviews(withOldSize: oldSize); positionCopyButton(); if !closing { picture.frame = fittedRect() } }
    @objc private func copyImage() {
        guard let image = picture.image else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image])
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        DispatchQueue.main.asyncAfter(deadline: .now()+1) { [weak self] in self?.copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy image") }
    }
    private func dismiss() {
        guard !closing else { return }; closing = true
        if let source, source.window != nil { origin = source.convert(source.bounds, to: self) }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            picture.animator().frame = origin; blur.animator().alphaValue = 0; copyButton.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.source?.alphaValue = 1
            if let monitor = self.monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            self.window?.makeFirstResponder(self.previousResponder)
            self.removeFromSuperview()
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
