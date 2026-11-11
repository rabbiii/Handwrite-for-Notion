import Foundation
import XCTest
@testable import PencilNotesCore

final class StorageTests: XCTestCase {
    private var directory: URL!
    private var repository: NoteRepository!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PencilNotesStorageTests-\(UUID().uuidString)", isDirectory: true)
        repository = try NoteRepository(directory: directory)
    }

    override func tearDownWithError() throws {
        if let directory = directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testRoundTripPreservesAllPagesMetadataAndEditableBytes() throws {
        var note = Note(title: "Calculus — ∫ f(x) dx")
        note.pages = [
            NotePage(drawing: Data([0, 1, 2, 127, 128, 255])),
            NotePage(drawing: Data("second-page-stroke-bytes".utf8))
        ]
        note.destination = NotionPage(id: "notion-page", title: "Class notes")
        note.sync = SyncState(destinationID: "notion-page", blockID: "block-id", revision: note.revision, format: .pdf)
        try repository.save(note)

        let reopenedRepository = try NoteRepository(directory: directory)
        let loaded = reopenedRepository.loadAll()
        XCTAssertEqual(loaded.notes, [note])
        XCTAssertTrue(loaded.issues.isEmpty)
    }

    func testBlankNoteHasAnEditableEmptyPageAndRoundTrips() throws {
        let note = Note()
        XCTAssertEqual(note.pages.count, 1)
        XCTAssertTrue(note.pages[0].drawing.isEmpty)
        try repository.save(note)
        XCTAssertEqual(repository.loadAll().notes, [note])
    }

    func testPreviousVersionRecoversAfterCorruptPrimaryAndPreservesCorruptBytesOnSave() throws {
        var note = Note(title: "Original")
        note.pages[0].drawing = Data([4, 5, 6])
        try repository.save(note)
        let previous = note
        note.title = "Recent edits"
        note.pages[0].drawing = Data([7, 8, 9])
        try repository.save(note)

        let corruptBytes = Data("interrupted/corrupt write".utf8)
        try corruptBytes.write(to: primary(note.id))
        let loaded = repository.loadAll()
        XCTAssertEqual(loaded.notes, [previous])
        XCTAssertEqual(loaded.issues.count, 1)
        XCTAssertTrue(loaded.issues[0].contains("Recovered"))
        XCTAssertEqual(try Data(contentsOf: primary(note.id)), corruptBytes, "Loading must never overwrite corrupt evidence.")

        try repository.save(try XCTUnwrap(loaded.notes.first))
        XCTAssertEqual(repository.loadAll().notes, [previous])
        let quarantines = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".corrupt-") }
        XCTAssertEqual(quarantines.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(quarantines.first)), corruptBytes)
    }

    func testUnreadableNoteIsReportedAndNotDeleted() throws {
        let id = UUID()
        let bytes = Data("not-json".utf8)
        try bytes.write(to: primary(id))
        let loaded = repository.loadAll()
        XCTAssertTrue(loaded.notes.isEmpty)
        XCTAssertEqual(loaded.issues.count, 1)
        XCTAssertTrue(loaded.issues[0].contains("preserved"))
        XCTAssertEqual(try Data(contentsOf: primary(id)), bytes)
    }

    func testFutureVersionReportedEvenWhenNoteRepresentationChanged() throws {
        let id = UUID()
        let bytes = Data("{\"version\":42,\"futureRepresentation\":true}".utf8)
        try bytes.write(to: primary(id))
        let loaded = repository.loadAll()
        XCTAssertTrue(loaded.notes.isEmpty)
        XCTAssertTrue(try XCTUnwrap(loaded.issues.first).contains("version 42"))
        XCTAssertEqual(try Data(contentsOf: primary(id)), bytes)
    }

    func testMismatchedFileIdentityIsRejected() throws {
        let note = Note(title: "Different identifier")
        let bytes = try repository.backupData(note)
        try bytes.write(to: primary(UUID()))
        let loaded = repository.loadAll()
        XCTAssertTrue(loaded.notes.isEmpty)
        XCTAssertTrue(try XCTUnwrap(loaded.issues.first).contains("identifier"))
    }

    func testDeleteRemovesPrimaryPreviousAndQuarantine() throws {
        var note = Note(title: "First save")
        try repository.save(note)
        note.title = "Second save"
        try repository.save(note)
        try Data("bad".utf8).write(to: primary(note.id))
        try repository.save(note)
        XCTAssertGreaterThan(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)

        try repository.delete(note.id)
        XCTAssertTrue(repository.loadAll().notes.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testBackupImportCreatesIndependentIdentityAndClearsRemoteState() throws {
        var original = Note(title: "Physics")
        original.pages = [NotePage(drawing: Data([1, 2])), NotePage(drawing: Data([3, 4]))]
        original.destination = NotionPage(id: "target", title: "Notion destination")
        original.sync = SyncState(destinationID: "target", blockID: "existing", pendingMarker: "pending", revision: original.revision, format: .pdf)
        let imported = try repository.importBackup(repository.backupData(original))

        XCTAssertNotEqual(imported.id, original.id)
        XCTAssertNotEqual(imported.revision, original.revision)
        XCTAssertEqual(imported.title, original.title)
        XCTAssertEqual(imported.pages, original.pages)
        XCTAssertNil(imported.sync)
        XCTAssertNil(imported.destination)
        XCTAssertTrue(repository.loadAll().notes.isEmpty, "Import returns a value without silently persisting it.")
        try repository.save(imported)
        XCTAssertEqual(repository.loadAll().notes, [imported])
    }

    func testInvalidNoteCannotReplaceExistingValidData() throws {
        let note = Note(title: "Valid")
        try repository.save(note)
        let before = try Data(contentsOf: primary(note.id))
        var invalid = note
        invalid.pages = []
        XCTAssertThrowsError(try repository.save(invalid))
        XCTAssertEqual(try Data(contentsOf: primary(note.id)), before)
        invalid = note
        invalid.title = String(repeating: "x", count: NoteRepository.maximumTitleLength + 1)
        XCTAssertThrowsError(try repository.save(invalid))
        invalid = note
        invalid.title = "   \n"
        XCTAssertThrowsError(try repository.save(invalid))
        invalid = note
        invalid.pages.append(invalid.pages[0])
        XCTAssertThrowsError(try repository.save(invalid))
        XCTAssertEqual(repository.loadAll().notes, [note])
    }

    func testOrphanPreviousVersionCanBeRecovered() throws {
        let note = Note(title: "Recoverable")
        try repository.save(note)
        try repository.save(note)
        try FileManager.default.removeItem(at: primary(note.id))
        let loaded = repository.loadAll()
        XCTAssertEqual(loaded.notes, [note])
        XCTAssertEqual(loaded.issues.count, 1)
    }

    func testNewestNotesAreListedFirst() throws {
        var older = Note(title: "Older")
        var newer = Note(title: "Newer")
        older.updatedAt = Date(timeIntervalSince1970: 100)
        newer.updatedAt = Date(timeIntervalSince1970: 200)
        try repository.save(newer)
        try repository.save(older)
        XCTAssertEqual(repository.loadAll().notes.map(\.title), ["Newer", "Older"])
    }

    private func primary(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).pencilnote")
    }
}
