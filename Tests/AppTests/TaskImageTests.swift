import XCTest
import AppKit
import SwiftUI
import FlowCore
@testable import FlodoOpen

final class TaskImageTests: XCTestCase {
    @MainActor func sample() -> NSImage {
        NSImage(size: NSSize(width: 640, height: 360), flipped: false) { rect in
            NSColor.systemTeal.setFill(); rect.fill()
            NSColor.systemYellow.setFill(); NSRect(x: 90, y: 80, width: 220, height: 160).fill()
            return true
        }
    }
    @MainActor func testRasterEncodingAndLimits() throws {
        let encoded = try ClipboardImages.encode(sample())
        XCTAssertTrue(encoded.dataURL.hasPrefix("data:image/jpeg;base64,"))
        XCTAssertNotNil(ClipboardImages.decode(encoded))
        XCTAssertLessThan(encoded.dataURL.count, 400_024)
        XCTAssertThrowsError(try ClipboardImages.validate(Array(repeating: encoded, count: 9)))
        XCTAssertThrowsError(try ClipboardImages.validate([TaskImage(dataURL: String(repeating: "a", count: 1_500_001))]))
        XCTAssertNil(ClipboardImages.decode(TaskImage(dataURL: "https://example.com/image.jpg")))
    }
    @MainActor func testEditorAcceptsControlAndCommandPaste() throws {
        guard ProcessInfo.processInfo.environment["FLODO_TEST_UI"] == "1" else { throw XCTSkip("Requires a macOS window session") }
        _ = NSApplication.shared
        let clipboard = NSPasteboard.general
        let saved = (clipboard.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
        defer {
            clipboard.clearContents()
            let items = saved.map { data in let item = NSPasteboardItem(); for (type, value) in data { item.setData(value, forType: type) }; return item }
            if !items.isEmpty { clipboard.writeObjects(items) }
        }
        clipboard.clearContents(); clipboard.writeObjects([sample()])
        let repository = Repository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("FlodoImageTest-\(UUID())"))
        defer { try? FileManager.default.removeItem(at: repository.directory) }
        let store = Store(repository: repository, enableSystemServices: false)
        let draft = FlowTask(title: "Image paste test")
        let host = NSHostingView(rootView: TaskEditor(initial: draft).environmentObject(store).frame(width: 380))
        let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 420, height: 450), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        func thumbnails(_ view: NSView) -> [ImageThumbnail] { (view as? ImageThumbnail).map { [$0] } ?? view.subviews.flatMap(thumbnails) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(try ClipboardImages.read().count, 1)
        func captures(_ view: NSView) -> [PasteCaptureView] { (view as? PasteCaptureView).map { [$0] } ?? view.subviews.flatMap(captures) }
        XCTAssertEqual(captures(host).count, 1)
        for (index, modifier) in [NSEvent.ModifierFlags.control, .command].enumerated() {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifier, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9))
            NSApp.sendEvent(event); RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            XCTAssertEqual(thumbnails(host).count, index+1)
        }
        XCTAssertTrue(thumbnails(host).allSatisfy { $0.frame.height == 36 })
    }
    @MainActor func testLightboxOpeningEscapeAndCopyControl() throws {
        guard ProcessInfo.processInfo.environment["FLODO_TEST_UI"] == "1" else { throw XCTSkip("Requires a macOS window session") }
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 150,y: 150,width: 800,height: 550), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = try XCTUnwrap(window.contentView)
        let thumb = ImageThumbnail(frame: NSRect(x: 60, y: 300, width: 64, height: 36)); thumb.image = sample(); root.addSubview(thumb)
        window.makeKeyAndOrderFront(nil); defer { window.close() }
        ImageLightbox.show(image: sample(), source: thumb, root: root)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let box = try XCTUnwrap(root.subviews.first { $0 is ImageLightbox })
        let image = try XCTUnwrap(box.subviews.first { $0 is NSImageView })
        XCTAssertGreaterThan(image.frame.width, 600); XCTAssertLessThan(image.frame.maxX, root.bounds.maxX)
        let copy = try XCTUnwrap(box.subviews.compactMap { $0 as? NSButton }.first)
        XCTAssertEqual(copy.frame.height, 36); XCTAssertEqual(copy.accessibilityLabel(), "Copy image")
        XCTAssertEqual(thumb.alphaValue, 0)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(event)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertFalse(root.subviews.contains { $0 is ImageLightbox }); XCTAssertEqual(thumb.alphaValue, 1)
    }
}
