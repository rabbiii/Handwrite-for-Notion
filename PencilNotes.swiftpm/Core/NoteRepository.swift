import Foundation

struct NoteLoadResult {
    var notes: [Note]
    var issues: [String]
}

enum NoteStorageError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidNote(String)
    case oversizedFile
    case wrongIdentity

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This note uses file version \(version), which this version of PencilNotes cannot open. Keep the file and update the app."
        case .invalidNote(let reason):
            return "The note could not be saved or opened: \(reason)"
        case .oversizedFile:
            return "This note exceeds the 100 MB local file limit. Split it into smaller notes."
        case .wrongIdentity:
            return "The note's identifier does not match its filename. The original file has been preserved."
        }
    }
}

/// Call from one serial executor (the app uses MainActor). Each note is one
/// atomically replaced envelope, so metadata and all stroke pages stay together.
/// A previous valid version is retained before replacement. Corrupt originals
/// are quarantined instead of being discarded by a subsequent save.
final class NoteRepository {
    static let maximumFileBytes = 100 * 1024 * 1024
    static let maximumDrawingBytes = 20 * 1024 * 1024
    static let maximumPages = 200
    static let maximumTitleLength = 200

    private struct Envelope: Codable {
        var version: Int
        var note: Note
    }

    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL) throws {
        self.directory = directory
        self.fileManager = .default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func loadAll() -> NoteLoadResult {
        var notes: [Note] = []
        var issues: [String] = []
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )
        } catch {
            return NoteLoadResult(notes: [], issues: ["Unable to read the notes folder: \(error.localizedDescription)"])
        }

        // Include backup-only notes, for example after an interrupted deletion.
        var identifiers = Set<UUID>()
        for url in files {
            let name = url.lastPathComponent
            let rawID: String
            if name.hasSuffix(".pencilnote.previous") {
                rawID = String(name.dropLast(".pencilnote.previous".count))
            } else if name.hasSuffix(".pencilnote") {
                rawID = String(name.dropLast(".pencilnote".count))
            } else {
                continue
            }
            if let id = UUID(uuidString: rawID) {
                identifiers.insert(id)
            } else {
                issues.append("Skipped unrecognized note filename \(name). Import this file with Restore Backup to read it safely.")
            }
        }

        for id in identifiers.sorted(by: { $0.uuidString < $1.uuidString }) {
            let primary = noteURL(id)
            do {
                let note = try decodeFile(primary, expectedID: id)
                notes.append(note)
            } catch {
                let primaryError = error
                do {
                    let recovered = try decodeFile(previousURL(id), expectedID: id)
                    notes.append(recovered)
                    issues.append("Recovered “\(recovered.title)” from its previous saved version. The latest file could not be read (\(primaryError.localizedDescription)). Some recent edits may be missing; its original file is preserved.")
                } catch {
                    issues.append("Could not open note \(id.uuidString): \(primaryError.localizedDescription) No readable previous version is available. The files have been preserved.")
                }
            }
        }
        notes.sort { $0.updatedAt > $1.updatedAt }
        return NoteLoadResult(notes: notes, issues: issues)
    }

    func save(_ note: Note) throws {
        let encoded = try backupData(note)
        let primary = noteURL(note.id)

        if fileManager.fileExists(atPath: primary.path) {
            // Read failure must stop the save; do not replace an unreadable file.
            let previousBytes = try readBounded(primary)
            let isValid: Bool
            do {
                _ = try decode(previousBytes, expectedID: note.id)
                isValid = true
            } catch {
                isValid = false
            }
            if isValid {
                try previousBytes.write(to: previousURL(note.id), options: .atomic)
            } else {
                // Preserve the original before any replacement and surface
                // failed quarantine writes without replacing the primary.
                let quarantine = directory.appendingPathComponent(
                    "\(note.id.uuidString).pencilnote.corrupt-\(UUID().uuidString)"
                )
                try previousBytes.write(to: quarantine, options: .atomic)
            }
        }

        try encoded.write(to: primary, options: .atomic)
    }

    func delete(_ id: UUID) throws {
        // Remove prior/quarantined copies first. If removal fails, the primary
        // remains visible and the app can display an actionable storage error.
        let prefix = "\(id.uuidString).pencilnote"
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files where file.lastPathComponent == prefix + ".previous"
            || file.lastPathComponent.hasPrefix(prefix + ".corrupt-") {
            try fileManager.removeItem(at: file)
        }
        let primary = noteURL(id)
        if fileManager.fileExists(atPath: primary.path) {
            try fileManager.removeItem(at: primary)
        }
    }

    func backupData(_ note: Note) throws -> Data {
        try validate(note)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(Envelope(version: 1, note: note))
        guard bytes.count <= Self.maximumFileBytes else { throw NoteStorageError.oversizedFile }
        return bytes
    }

    /// Import returns a separate note; the caller explicitly saves it. Remote
    /// sync state is cleared so restoring a backup cannot overwrite Notion ink.
    func importBackup(_ data: Data) throws -> Note {
        var note = try decode(data, expectedID: nil)
        if note.iconName == nil {
            let legacyIcons = ["book.closed", "pencil", "paintbrush", "lightbulb", "leaf", "star", "moon", "sun.max", "bolt", "sparkles", "heart", "paperplane"]
            note.iconName = legacyIcons[Int(note.id.uuid.0) % legacyIcons.count]
        }
        note.id = UUID()
        note.revision = UUID()
        note.createdAt = Date()
        note.updatedAt = note.createdAt
        note.deletedAt = nil
        note.destination = nil
        note.sync = nil
        return note
    }

    private func noteURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).pencilnote")
    }

    private func previousURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).pencilnote.previous")
    }

    private func readBounded(_ url: URL) throws -> Data {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber,
           size.intValue > Self.maximumFileBytes {
            throw NoteStorageError.oversizedFile
        }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumFileBytes else { throw NoteStorageError.oversizedFile }
        return data
    }

    private func decodeFile(_ url: URL, expectedID: UUID) throws -> Note {
        try decode(readBounded(url), expectedID: expectedID)
    }

    private func decode(_ data: Data, expectedID: UUID?) throws -> Note {
        guard data.count <= Self.maximumFileBytes else { throw NoteStorageError.oversizedFile }
        // Decode only the version first so a future schema gets an accurate
        // message even if its note representation has changed entirely.
        struct Version: Decodable { var version: Int }
        let decoder = JSONDecoder()
        let version = try decoder.decode(Version.self, from: data).version
        guard version == 1 else { throw NoteStorageError.unsupportedVersion(version) }
        let note = try decoder.decode(Envelope.self, from: data).note
        if let expectedID = expectedID, expectedID != note.id { throw NoteStorageError.wrongIdentity }
        try validate(note)
        return note
    }

    private func validate(_ note: Note) throws {
        guard !note.pages.isEmpty else { throw NoteStorageError.invalidNote("a note needs at least one page.") }
        guard note.pages.count <= Self.maximumPages else {
            throw NoteStorageError.invalidNote("a note can have at most \(Self.maximumPages) pages.")
        }
        guard !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              note.title.count <= Self.maximumTitleLength else {
            throw NoteStorageError.invalidNote("the title must contain 1–\(Self.maximumTitleLength) characters.")
        }
        guard Set(note.pages.map(\.id)).count == note.pages.count else {
            throw NoteStorageError.invalidNote("page identifiers must be unique.")
        }
        guard note.pages.allSatisfy({ $0.drawing.count <= Self.maximumDrawingBytes }) else {
            throw NoteStorageError.invalidNote("a drawing exceeds the 20 MB page limit.")
        }
        guard note.createdAt.timeIntervalSinceReferenceDate.isFinite,
              note.updatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw NoteStorageError.invalidNote("timestamps must be valid dates.")
        }
    }
}
