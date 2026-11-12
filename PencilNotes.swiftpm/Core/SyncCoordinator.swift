import Foundation

protocol NotionSyncService {
    func findBlock(pageID: String, marker: String) async throws -> String?
    func upload(data: Data, filename: String, contentType: String, maxBytes: Int, progress: @escaping (String) -> Void) async throws -> String
    func appendFile(pageID: String, uploadID: String, format: ExportFormat, caption: String, captionLink: URL?) async throws -> String
    func updateFile(blockID: String, uploadID: String, format: ExportFormat, caption: String, captionLink: URL?) async throws
}

extension NotionClient: NotionSyncService {}

enum SyncError: LocalizedError {
    case noDestination
    case uncertainAppend
    var errorDescription: String? {
        switch self {
        case .noDestination: return "Choose a Notion destination page first."
        case .uncertainAppend: return "A previous sync may have reached Notion and is not yet confirmed. Use its original destination and export format, then retry. If it still cannot be found, inspect the original destination page before using ‘Resolve uncertain sync’ in the note menu."
        }
    }
}

@MainActor
enum SyncCoordinator {
    static let captionVersion = 1

    static func marker(noteID: UUID, format: ExportFormat) -> String {
        "PencilNotes:\(noteID.uuidString):\(format.rawValue)"
    }

    static func sync(note original: Note, data: Data, format: ExportFormat,
                     maxBytes: Int, client: NotionSyncService,
                     save: (Note) throws -> Void, progress: @escaping (String) -> Void) async throws -> Note {
        guard let destination = original.destination else { throw SyncError.noDestination }
        var note = original
        let tag = marker(noteID: note.id, format: format)
        var state = note.sync ?? SyncState(destinationID: destination.id)
        // An unresolved append belongs to its original page and format. Changing
        // either must not erase the durable evidence needed to reconcile it.
        if state.pendingMarker != nil && (state.destinationID != destination.id || state.format != format) {
            throw SyncError.uncertainAppend
        }
        if state.destinationID != destination.id || (state.format != nil && state.format != format) {
            state = SyncState(destinationID: destination.id)
        }
        if state.blockID != nil && state.revision == note.revision && state.format == format
            && state.pendingMarker == nil && state.captionVersion == captionVersion {
            progress("Already synced — no changes to upload.")
            return note
        }
        if state.blockID == nil {
            progress("Checking the destination for a previous upload…")
            state.blockID = try await client.findBlock(pageID: destination.id, marker: tag)
            if state.blockID == nil && state.pendingMarker != nil { throw SyncError.uncertainAppend }
        }
        state.format = format
        let uploadID = try await client.upload(data: data, filename: "PencilNotes-\(note.id.uuidString).\(format.rawValue)",
                                               contentType: format == .png ? "image/png" : "application/pdf",
                                               maxBytes: maxBytes, progress: progress)
        // Keep recovery identity in the title's link, outside its visible text.
        var link = URLComponents()
        link.scheme = "https"
        link.host = "www.notion.so"
        link.path = "/\(destination.id)"
        link.queryItems = [URLQueryItem(name: "pencilnotes", value: tag)]
        guard let captionLink = link.url else { throw NotionError.invalidInput("The Notion caption link is invalid.") }
        let caption = note.title
        if let blockID = state.blockID {
            progress("Updating your Notion block…")
            // Updating a known block is retryable: it replaces that block, never appends another.
            try await client.updateFile(blockID: blockID, uploadID: uploadID, format: format, caption: caption, captionLink: captionLink)
        } else {
            state.pendingMarker = tag
            note.sync = state
            // Persist intent BEFORE the append. A crash or lost response must never trigger a blind append.
            try save(note)
            progress("Adding the file to your Notion page…")
            do {
                state.blockID = try await client.appendFile(pageID: destination.id, uploadID: uploadID, format: format, caption: caption, captionLink: captionLink)
            } catch {
                if let apiError = error as? NotionError, !apiError.isAmbiguousMutation {
                    state.pendingMarker = nil
                    note.sync = state
                    try save(note)
                }
                throw error
            }
        }
        state.pendingMarker = nil
        state.revision = note.revision
        state.captionVersion = captionVersion
        note.sync = state
        try save(note)
        progress("Synced to \(destination.title).")
        return note
    }
}
