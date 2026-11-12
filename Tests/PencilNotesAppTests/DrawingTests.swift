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
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
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
        window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
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
    func testEditingDuringUploadKeepsNewInkAndSchedulesOneUpdatedImage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory); UploadProtocol.handler = nil }
        let appendStarted = expectation(description: "First image append started")
        let updateFinished = expectation(description: "Newer ink updates the same image")
        let uploadID = UUID().uuidString
        let blockID = UUID().uuidString
        let destinationID = UUID().uuidString
        let counts = RequestCounts()
        UploadProtocol.handler = { request in
            let path = request.url!.path
            let method = request.httpMethod!
            if path.hasSuffix("users/me") {
                return (0, ["name": "Test", "bot": ["workspace_limits": ["max_file_upload_size_in_bytes": 5242880]]])
            }
            if method == "GET" { return (0, ["results": [], "has_more": false]) }
            if path.hasSuffix("file_uploads") { return (0, ["id": uploadID]) }
            if path.hasSuffix("send") { return (0, ["id": uploadID, "status": "uploaded"]) }
            if path.hasSuffix("children") {
                counts.recordAppend()
                appendStarted.fulfill()
                return (0.8, ["results": [["id": blockID]]])
            }
            counts.recordUpdate()
            updateFinished.fulfill()
            return (0, ["id": blockID])
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UploadProtocol.self]
        let client = NotionClient(token: "test-only", session: URLSession(configuration: configuration), minimumRequestInterval: 0)
        let model = AppModel(directory: directory, loadCredential: false, notionClient: client)
        model.autoSyncEnabled = false
        model.newNote()
        let pageID = try XCTUnwrap(model.selectedPage?.id)
        model.drawingChanged(ink(y: 100).dataRepresentation(), pageID: pageID)
        model.chooseDestination(NotionPage(id: destinationID, title: "Test"))
        model.autoSyncEnabled = true
        await fulfillment(of: [appendStarted], timeout: 8)
        XCTAssertTrue(model.isSyncing)
        model.drawingChanged(ink(y: 4000, color: .green).dataRepresentation(), pageID: pageID)
        await fulfillment(of: [updateFinished], timeout: 8)
        try await Task.sleep(nanoseconds: 300_000_000)
        model.autoSyncEnabled = false
        let latest = try XCTUnwrap(model.selectedNote)
        XCTAssertGreaterThan(try NoteExporter.drawing(latest.pages[0].drawing).bounds.maxY, 3900)
        XCTAssertEqual(latest.revision, latest.sync?.revision)
        XCTAssertEqual(latest.sync?.blockID, blockID)
        XCTAssertEqual(counts.appends, 1)
        XCTAssertEqual(counts.updates, 1)
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
        window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
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
            let filename = style == .dark ? "editor-dark.png" : "editor-light.png"
            try XCTUnwrap(image.pngData()).write(to: FileManager.default.temporaryDirectory.appendingPathComponent(filename))
        }
        window.isHidden = true
    }
}

private final class RequestCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var a = 0
    private var u = 0
    var appends: Int { lock.lock(); defer { lock.unlock() }; return a }
    var updates: Int { lock.lock(); defer { lock.unlock() }; return u }
    func recordAppend() { lock.lock(); a += 1; lock.unlock() }
    func recordUpdate() { lock.lock(); u += 1; lock.unlock() }
}

private final class UploadProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (TimeInterval, [String: Any]))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { return }
        let (delay, json) = handler(request)
        let data = try! JSONSerialization.data(withJSONObject: json)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
