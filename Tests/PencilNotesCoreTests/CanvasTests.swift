import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import PencilNotesCore

final class CanvasTests: XCTestCase {
    func testImageHeightFollowsLowestStrokeRatherThanPageHeight() {
        let short = CanvasGeometry.imageBounds(ink: CGRect(x: 20, y: 30, width: 100, height: 400))
        let long = CanvasGeometry.imageBounds(ink: CGRect(x: 20, y: 30, width: 100, height: 9000))
        XCTAssertEqual(short.width, 768)
        XCTAssertEqual(short.height, 462)
        XCTAssertEqual(long.width, 768)
        XCTAssertEqual(long.height, 9062)
    }
    func testBlankImageAndNotionBackgroundAreStable() {
        XCTAssertEqual(CanvasGeometry.imageBounds(ink: .null).size, CGSize(width: 768, height: 256))
        XCTAssertEqual(CanvasGeometry.notionBackgroundRGB, 0x191919)
    }
    func testOffCanvasInkIsIncluded() {
        let ink = CGRect(x: -50, y: -20, width: 1000, height: 800)
        XCTAssertTrue(CanvasGeometry.imageBounds(ink: ink).contains(ink))
    }
    func testVeryLongImageHasBoundedRasterFootprint() {
        let rect = CGRect(x: 0, y: 0, width: 768, height: 60000)
        let scale = CanvasGeometry.renderScale(bounds: rect)
        XCTAssertLessThanOrEqual(rect.width * rect.height * scale * scale, 24_000_001)
        XCTAssertLessThanOrEqual(rect.height * scale, 16384)
    }
    func testCompletedUploadPreservesNewerInkAndContentRevision() {
        let snapshot = Note(title: "Before upload")
        var current = snapshot
        current.pages[0].drawing = Data([1, 2, 3])
        current.title = "Edited during upload"
        current.revision = UUID()
        let state = SyncState(destinationID: "destination", blockID: "block", revision: snapshot.revision, format: .png)
        let merged = current.withSyncState(state)
        XCTAssertEqual(merged.pages, current.pages)
        XCTAssertEqual(merged.title, current.title)
        XCTAssertEqual(merged.revision, current.revision)
        XCTAssertNotEqual(merged.revision, merged.sync?.revision)
        XCTAssertEqual(merged.sync?.blockID, "block")
    }
    @MainActor
    func testAutoSyncDebouncesHalfSecondAfterLastActivity() async throws {
        let debounce = AutoSyncDebouncer()
        var requests = 0
        debounce.schedule { requests += 1 }
        try await Task.sleep(nanoseconds: 300_000_000)
        debounce.schedule { requests += 1 }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(requests, 0)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(requests, 1)
    }
    @MainActor
    func testTurningOffAutoSyncCancelsPendingTimer() async throws {
        let debounce = AutoSyncDebouncer()
        var requests = 0
        debounce.schedule(delay: 0.05) { requests += 1 }
        debounce.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(requests, 0)
    }
}
