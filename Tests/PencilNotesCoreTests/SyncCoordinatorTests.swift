import Foundation
import XCTest
@testable import PencilNotesCore

final class SyncCoordinatorTests: XCTestCase {
    @MainActor
    func testFirstSyncPersistsIntentBeforeAppendAndThenRemoteIdentity() async throws {
        let note = makeNote()
        let service = MockSyncService()
        let bytes = Data("exported-pdf".utf8)

        let synced = try await SyncCoordinator.sync(
            note: note, data: bytes, format: .pdf, maxBytes: 4096,
            client: service, save: service.save, progress: { _ in }
        )

        let expectedMarker = SyncCoordinator.marker(noteID: note.id, format: .pdf)
        XCTAssertEqual(service.searches.count, 1)
        XCTAssertEqual(service.searches.first?.pageID, "destination-page")
        XCTAssertEqual(service.searches.first?.marker, expectedMarker)
        XCTAssertEqual(service.uploads.count, 1)
        XCTAssertEqual(service.uploads.first?.data, bytes)
        XCTAssertEqual(service.uploads.first?.contentType, "application/pdf")
        XCTAssertEqual(service.uploads.first?.maxBytes, 4096)
        XCTAssertEqual(service.uploads.first?.filename, "PencilNotes-\(note.id.uuidString).pdf")
        XCTAssertEqual(service.appends.count, 1)
        XCTAssertEqual(service.appends.first?.uploadID, "upload-id")
        XCTAssertEqual(service.appends.first?.caption, "Physics")
        let captionLink = try XCTUnwrap(service.appends.first?.captionLink)
        let link = try XCTUnwrap(URLComponents(url: captionLink, resolvingAgainstBaseURL: false))
        XCTAssertEqual(link.path, "/destination-page")
        XCTAssertEqual(link.queryItems?.first(where: { $0.name == "pencilnotes" })?.value, expectedMarker)
        XCTAssertEqual(service.pendingMarkerObservedAtAppend, expectedMarker,
                       "A crash after sending the append must leave durable reconciliation information.")
        XCTAssertEqual(service.calls, ["find", "upload", "save", "append", "save"])
        XCTAssertEqual(service.savedNotes.count, 2)
        XCTAssertNil(service.savedNotes.first?.sync?.blockID)
        XCTAssertEqual(service.savedNotes.first?.sync?.pendingMarker, expectedMarker)
        XCTAssertEqual(synced.sync?.blockID, "created-block")
        XCTAssertEqual(synced.sync?.revision, note.revision)
        XCTAssertEqual(synced.sync?.format, .pdf)
        XCTAssertEqual(synced.sync?.captionVersion, SyncCoordinator.captionVersion)
        XCTAssertNil(synced.sync?.pendingMarker)
        XCTAssertEqual(service.savedNotes.last, synced)
    }

    @MainActor
    func testUnchangedRevisionDoesNotSendRequestsOrSaveAgain() async throws {
        var note = makeNote()
        note.sync = SyncState(destinationID: "destination-page", blockID: "known-block",
                              revision: note.revision, format: .pdf, captionVersion: SyncCoordinator.captionVersion)
        let service = MockSyncService()
        var progressMessages: [String] = []

        let result = try await SyncCoordinator.sync(
            note: note, data: Data(), format: .pdf, maxBytes: 4096,
            client: service, save: service.save, progress: { progressMessages.append($0) }
        )

        XCTAssertEqual(result, note)
        XCTAssertTrue(service.calls.isEmpty)
        XCTAssertTrue(progressMessages.contains { $0.contains("Already synced") })
    }

    @MainActor
    func testLegacyCaptionIsReplacedEvenWhenNoteHasNotChanged() async throws {
        var note = makeNote()
        note.sync = SyncState(destinationID: "destination-page", blockID: "known-block",
                              revision: note.revision, format: .png)
        let service = MockSyncService()

        let result = try await SyncCoordinator.sync(
            note: note, data: Data([1]), format: .png, maxBytes: 4096,
            client: service, save: service.save, progress: { _ in }
        )

        XCTAssertTrue(service.searches.isEmpty)
        XCTAssertTrue(service.appends.isEmpty)
        XCTAssertEqual(service.updates.first?.blockID, "known-block")
        XCTAssertEqual(service.updates.first?.caption, note.title)
        XCTAssertNotNil(service.updates.first?.captionLink)
        XCTAssertEqual(result.sync?.captionVersion, SyncCoordinator.captionVersion)
        let calls = service.calls
        _ = try await SyncCoordinator.sync(
            note: result, data: Data([1]), format: .png, maxBytes: 4096,
            client: service, save: service.save, progress: { _ in }
        )
        XCTAssertEqual(service.calls, calls)
    }

    @MainActor
    func testRevisedNoteUpdatesSameBlockWithoutAppending() async throws {
        var note = makeNote()
        note.sync = SyncState(destinationID: "destination-page", blockID: "known-block",
                              revision: UUID(), format: .pdf)
        let service = MockSyncService()

        let result = try await SyncCoordinator.sync(
            note: note, data: Data([1, 2, 3]), format: .pdf, maxBytes: 4096,
            client: service, save: service.save, progress: { _ in }
        )

        XCTAssertTrue(service.searches.isEmpty)
        XCTAssertTrue(service.appends.isEmpty)
        XCTAssertEqual(service.updates.count, 1)
        XCTAssertEqual(service.updates.first?.blockID, "known-block")
        XCTAssertEqual(service.updates.first?.uploadID, "upload-id")
        XCTAssertEqual(service.updates.first?.caption, note.title)
        XCTAssertNotNil(service.updates.first?.captionLink)
        XCTAssertEqual(result.sync?.blockID, "known-block")
        XCTAssertEqual(result.sync?.revision, note.revision)
        XCTAssertEqual(service.calls, ["upload", "update", "save"])
    }

    @MainActor
    func testLostAppendResponseRetainsIntentAndRetryFindsAndUpdatesRemoteBlock() async throws {
        let note = makeNote()
        let firstAttempt = MockSyncService()
        firstAttempt.appendError = NotionError.transport(message: "Connection lost", mutation: true)

        do {
            _ = try await SyncCoordinator.sync(
                note: note, data: Data([9]), format: .pdf, maxBytes: 4096,
                client: firstAttempt, save: firstAttempt.save, progress: { _ in }
            )
            XCTFail("An uncertain append must be surfaced to the caller.")
        } catch let error as NotionError {
            XCTAssertTrue(error.isAmbiguousMutation)
        }

        let persisted = try XCTUnwrap(firstAttempt.savedNotes.last)
        XCTAssertEqual(firstAttempt.appends.count, 1)
        XCTAssertEqual(firstAttempt.savedNotes.count, 1)
        XCTAssertNotNil(persisted.sync?.pendingMarker)
        XCTAssertNil(persisted.sync?.blockID)
        XCTAssertNil(persisted.sync?.revision)

        let retry = MockSyncService()
        retry.findResult = "block-created-by-first-attempt"
        let result = try await SyncCoordinator.sync(
            note: persisted, data: Data([9]), format: .pdf, maxBytes: 4096,
            client: retry, save: retry.save, progress: { _ in }
        )

        XCTAssertEqual(retry.searches.count, 1)
        XCTAssertTrue(retry.appends.isEmpty, "A recovered block must be updated, never appended twice.")
        XCTAssertEqual(retry.updates.first?.blockID, "block-created-by-first-attempt")
        XCTAssertEqual(result.sync?.blockID, "block-created-by-first-attempt")
        XCTAssertEqual(result.sync?.revision, note.revision)
        XCTAssertNil(result.sync?.pendingMarker)
    }

    @MainActor
    func testUnresolvedUncertainAppendNeverUploadsOrAppendsAgain() async throws {
        var note = makeNote()
        note.sync = SyncState(destinationID: "destination-page",
                              pendingMarker: SyncCoordinator.marker(noteID: note.id, format: .pdf),
                              format: .pdf)
        let service = MockSyncService()
        service.findResult = nil

        do {
            _ = try await SyncCoordinator.sync(
                note: note, data: Data([1]), format: .pdf, maxBytes: 4096,
                client: service, save: service.save, progress: { _ in }
            )
            XCTFail("A missing marker after an uncertain write cannot safely trigger another append.")
        } catch SyncError.uncertainAppend {
            // The destination may be eventually consistent; require manual resolution if still missing.
        }

        XCTAssertEqual(service.calls, ["find"])
        XCTAssertTrue(service.savedNotes.isEmpty)
        XCTAssertTrue(service.uploads.isEmpty)
        XCTAssertTrue(service.appends.isEmpty)
    }

    @MainActor
    func testChangingFormatCannotDiscardAnUnresolvedAppend() async throws {
        var persisted = makeNote()
        persisted.sync = SyncState(destinationID: "destination-page",
                                   pendingMarker: SyncCoordinator.marker(noteID: persisted.id, format: .pdf),
                                   format: .pdf)
        let service = MockSyncService()
        service.savedNotes = [persisted]

        do {
            _ = try await SyncCoordinator.sync(
                note: persisted, data: Data([1]), format: .png, maxBytes: 4096,
                client: service, save: service.save, progress: { _ in }
            )
            XCTFail("Switching format must not forget a possibly successful PDF append.")
        } catch SyncError.uncertainAppend {
            // The previous PDF must be reconciled before a separate PNG sync starts.
        }

        XCTAssertTrue(service.calls.isEmpty, "The unresolved intent must be checked before any request or save.")
        XCTAssertTrue(service.uploads.isEmpty)
        XCTAssertTrue(service.appends.isEmpty)
        XCTAssertEqual(service.savedNotes, [persisted], "The original pending marker must remain durable.")
    }

    @MainActor
    func testChangingDestinationCannotDiscardAnUnresolvedAppend() async throws {
        var persisted = makeNote()
        persisted.sync = SyncState(destinationID: "destination-page",
                                   pendingMarker: SyncCoordinator.marker(noteID: persisted.id, format: .pdf),
                                   format: .pdf)
        var requested = persisted
        requested.destination = NotionPage(id: "different-page", title: "Another class")
        let service = MockSyncService()
        service.savedNotes = [persisted]

        do {
            _ = try await SyncCoordinator.sync(
                note: requested, data: Data([1]), format: .pdf, maxBytes: 4096,
                client: service, save: service.save, progress: { _ in }
            )
            XCTFail("Switching destinations must not erase the original page's uncertain append.")
        } catch SyncError.uncertainAppend {
            // The owner can return to the original page or explicitly resolve the uncertainty.
        }

        XCTAssertTrue(service.calls.isEmpty)
        XCTAssertTrue(service.uploads.isEmpty)
        XCTAssertTrue(service.appends.isEmpty)
        XCTAssertEqual(service.savedNotes, [persisted], "Do not replace the original pending destination or marker.")
    }

    @MainActor
    func testFailedIntentSavePreventsBlockAppend() async throws {
        let note = makeNote()
        let service = MockSyncService()
        service.failSaves = true

        do {
            _ = try await SyncCoordinator.sync(
                note: note, data: Data([1]), format: .pdf, maxBytes: 4096,
                client: service, save: service.save, progress: { _ in }
            )
            XCTFail("A storage failure must stop the remote append.")
        } catch MockSyncService.StorageFailure.diskFull {
            // Uploading an unattached file may already have occurred; no visible block may be appended.
        }

        XCTAssertEqual(service.calls, ["find", "upload", "save"])
        XCTAssertEqual(service.uploads.count, 1)
        XCTAssertTrue(service.appends.isEmpty)
        XCTAssertTrue(service.updates.isEmpty)
        XCTAssertTrue(service.savedNotes.isEmpty)
    }

    @MainActor
    func testChangingExportFormatUsesItsOwnMarkerAndDoesNotOverwriteOldBlockType() async throws {
        var note = makeNote()
        note.sync = SyncState(destinationID: "destination-page", blockID: "pdf-block",
                              revision: note.revision, format: .pdf)
        let service = MockSyncService()

        let result = try await SyncCoordinator.sync(
            note: note, data: Data([1, 2]), format: .png, maxBytes: 4096,
            client: service, save: service.save, progress: { _ in }
        )

        let pngMarker = SyncCoordinator.marker(noteID: note.id, format: .png)
        XCTAssertNotEqual(pngMarker, SyncCoordinator.marker(noteID: note.id, format: .pdf))
        XCTAssertEqual(service.searches.first?.marker, pngMarker)
        XCTAssertEqual(service.uploads.first?.contentType, "image/png")
        XCTAssertEqual(service.appends.first?.format, .png)
        XCTAssertTrue(service.updates.isEmpty)
        XCTAssertEqual(result.sync?.format, .png)
        XCTAssertEqual(result.sync?.blockID, "created-block")
    }

    @MainActor
    func testChangingDestinationReconcilesNewPageInsteadOfUpdatingOldPageBlock() async throws {
        var note = makeNote()
        note.sync = SyncState(destinationID: "old-page", blockID: "old-page-block",
                              revision: note.revision, format: .pdf)
        let service = MockSyncService()
        service.findResult = "existing-on-new-page"

        let result = try await SyncCoordinator.sync(
            note: note, data: Data([1]), format: .pdf, maxBytes: 4096,
            client: service, save: service.save, progress: { _ in }
        )

        XCTAssertEqual(service.searches.first?.pageID, "destination-page")
        XCTAssertEqual(service.updates.first?.blockID, "existing-on-new-page")
        XCTAssertTrue(service.appends.isEmpty)
        XCTAssertEqual(result.sync?.destinationID, "destination-page")
    }

    @MainActor
    func testExplicitAppendRejectionClearsUncertainIntentSoUserCanCorrectPermissions() async throws {
        let note = makeNote()
        let service = MockSyncService()
        service.appendError = NotionError.response(status: 403, code: "restricted_resource",
                                                   message: "No insert permission", retryAfter: nil, mutation: true)

        do {
            _ = try await SyncCoordinator.sync(
                note: note, data: Data([1]), format: .pdf, maxBytes: 4096,
                client: service, save: service.save, progress: { _ in }
            )
            XCTFail("Permission rejection must reach the caller.")
        } catch let error as NotionError {
            XCTAssertFalse(error.isAmbiguousMutation)
        }

        XCTAssertEqual(service.savedNotes.count, 2)
        XCTAssertNotNil(service.savedNotes.first?.sync?.pendingMarker)
        XCTAssertNil(service.savedNotes.last?.sync?.pendingMarker)
        XCTAssertNil(service.savedNotes.last?.sync?.blockID)
        XCTAssertNil(service.savedNotes.last?.sync?.revision)
    }

    @MainActor
    func testMissingDestinationDoesNotTouchNetworkOrStorage() async throws {
        let note = Note(title: "No destination")
        let service = MockSyncService()

        do {
            _ = try await SyncCoordinator.sync(
                note: note, data: Data([1]), format: .pdf, maxBytes: 4096,
                client: service, save: service.save, progress: { _ in }
            )
            XCTFail("Destination must be chosen before sync.")
        } catch SyncError.noDestination {
            // Expected validation error.
        }
        XCTAssertTrue(service.calls.isEmpty)
    }

    private func makeNote() -> Note {
        var note = Note(title: "Physics")
        note.destination = NotionPage(id: "destination-page", title: "Class notes")
        return note
    }
}

private final class MockSyncService: NotionSyncService {
    struct SearchCall {
        let pageID: String
        let marker: String
    }
    struct UploadCall {
        let data: Data
        let filename: String
        let contentType: String
        let maxBytes: Int
    }
    struct AppendCall {
        let pageID: String
        let uploadID: String
        let format: ExportFormat
        let caption: String
        let captionLink: URL?
    }
    struct UpdateCall {
        let blockID: String
        let uploadID: String
        let format: ExportFormat
        let caption: String
        let captionLink: URL?
    }
    enum StorageFailure: Error { case diskFull }

    var findResult: String?
    var appendError: Error?
    var failSaves = false
    var calls: [String] = []
    var searches: [SearchCall] = []
    var uploads: [UploadCall] = []
    var appends: [AppendCall] = []
    var updates: [UpdateCall] = []
    var savedNotes: [Note] = []
    var pendingMarkerObservedAtAppend: String?

    func save(_ note: Note) throws {
        calls.append("save")
        if failSaves { throw StorageFailure.diskFull }
        savedNotes.append(note)
    }

    func findBlock(pageID: String, marker: String) async throws -> String? {
        calls.append("find")
        searches.append(SearchCall(pageID: pageID, marker: marker))
        return findResult
    }

    func upload(data: Data, filename: String, contentType: String, maxBytes: Int,
                progress: @escaping (String) -> Void) async throws -> String {
        calls.append("upload")
        uploads.append(UploadCall(data: data, filename: filename, contentType: contentType, maxBytes: maxBytes))
        return "upload-id"
    }

    func appendFile(pageID: String, uploadID: String, format: ExportFormat, caption: String, captionLink: URL?) async throws -> String {
        calls.append("append")
        appends.append(AppendCall(pageID: pageID, uploadID: uploadID, format: format, caption: caption, captionLink: captionLink))
        pendingMarkerObservedAtAppend = savedNotes.last?.sync?.pendingMarker
        if let appendError { throw appendError }
        return "created-block"
    }

    func updateFile(blockID: String, uploadID: String, format: ExportFormat, caption: String, captionLink: URL?) async throws {
        calls.append("update")
        updates.append(UpdateCall(blockID: blockID, uploadID: uploadID, format: format, caption: caption, captionLink: captionLink))
    }
}
