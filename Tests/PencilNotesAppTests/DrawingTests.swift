import XCTest
import PencilKit
import SwiftUI
@testable import PencilNotes

@MainActor
final class DrawingTests: XCTestCase {
    private func ink(y: CGFloat, color: UIColor = .red) -> PKDrawing {
        let points = [CGPoint(x: 100, y: y), CGPoint(x: 300, y: y)].enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: TimeInterval(index) * 0.1,
                          size: CGSize(width: 8, height: 8), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
    }
    func testContinuousMigrationPreservesOrderedEditableStrokes() throws {
        var legacy = Note(title: "Legacy")
        legacy.canvasVersion = nil
        legacy.pages = [NotePage(drawing: ink(y: 100).dataRepresentation()), NotePage(drawing: ink(y: 200).dataRepresentation())]
        let migrated = try NoteExporter.continuous(legacy)
        let strokes = try NoteExporter.drawing(migrated.pages[0].drawing)
        XCTAssertEqual(migrated.pages.count, 1)
        XCTAssertEqual(migrated.canvasVersion, 2)
        XCTAssertEqual(strokes.strokes.count, 2)
        XCTAssertGreaterThan(strokes.bounds.maxY, 1200)
        XCTAssertEqual(try NoteExporter.continuous(migrated), migrated)
    }
    func testPNGIsOneTallDarkImageWithUnchangedRedInk() throws {
        var note = Note()
        note.pages[0].drawing = ink(y: 2200).dataRepresentation()
        let data = try NoteExporter.png(note: note, preferredScale: 1)
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.width, 768)
        XCTAssertGreaterThan(image.height, 2200)
        XCTAssertLessThan(image.height, 2300)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        XCTAssertEqual(Array(pixels[0..<3]), [25, 25, 25])
        let redPixels = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 180 && pixels[$0 + 1] < 80 && pixels[$0 + 2] < 80 }
        XCTAssertFalse(redPixels.isEmpty, "Original red ink must not be recolored for the dark export.")
    }
    func testBackupImportAndAppReopenKeepOneEditableCanvas() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(directory: directory, loadCredential: false)
        model.newNote()
        let page = try XCTUnwrap(model.selectedPage)
        model.drawingChanged(ink(y: 4000).dataRepresentation(), pageID: page.id)
        XCTAssertTrue(model.saveNow())
        let reopened = AppModel(directory: directory, loadCredential: false)
        let note = try XCTUnwrap(reopened.selectedNote)
        XCTAssertGreaterThan(try NoteExporter.drawing(note.pages[0].drawing).bounds.maxY, 3900)
    }
    func testClearCanvasCanBeUndoneAndRedone() async throws {
        let actions = CanvasActions()
        let controller = InkController(data: ink(y: 200).dataRepresentation(), fingerDrawing: false, actions: actions, changed: { _ in }, interaction: { _ in })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 1366))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        try await Task.sleep(nanoseconds: 300_000_000)
        actions.clear()
        XCTAssertEqual(controller.canvas.drawing.strokes.count, 0)
        actions.undo()
        XCTAssertEqual(controller.canvas.drawing.strokes.count, 1)
        actions.redo()
        XCTAssertEqual(controller.canvas.drawing.strokes.count, 0)
        window.isHidden = true
    }
    func testEditorLightAndDarkAppearance() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(directory: directory, loadCredential: false)
        model.newNote()
        model.rename("A place to think")
        let page = try XCTUnwrap(model.selectedPage)
        model.drawingChanged(ink(y: 260).dataRepresentation(), pageID: page.id)
        model.saveNow()
        let controller = UIHostingController(rootView: NotebookView().environmentObject(model).tint(NotebookTheme.ink))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1366, height: 1024))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        for (name, style) in [("Editor light", UIUserInterfaceStyle.light), ("Editor dark", .dark)] {
            window.overrideUserInterfaceStyle = style
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 800_000_000)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        window.isHidden = true
    }
}
