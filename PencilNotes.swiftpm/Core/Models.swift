import Foundation

/// Editable PencilKit data is opaque to the persistence layer. An empty Data
/// value represents a new, blank PKDrawing. Old paged notes are migrated on iPad.
struct NotePage: Codable, Identifiable, Equatable {
    var id: UUID
    var drawing: Data

    init(id: UUID = UUID(), drawing: Data = Data()) {
        self.id = id
        self.drawing = drawing
    }
}

struct NotionPage: Codable, Identifiable, Equatable {
    var id: String
    var title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

enum ExportFormat: String, Codable, CaseIterable, Identifiable {
    case png
    case pdf

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var mimeType: String { self == .png ? "image/png" : "application/pdf" }
}

/// Only remote identifiers and content revisions are stored with a note.
/// Authentication credentials belong exclusively in Keychain.
struct SyncState: Codable, Equatable {
    var destinationID: String
    var blockID: String?
    var pendingMarker: String?
    var revision: UUID?
    var format: ExportFormat?
    var captionVersion: Int?

    init(
        destinationID: String,
        blockID: String? = nil,
        pendingMarker: String? = nil,
        revision: UUID? = nil,
        format: ExportFormat? = nil,
        captionVersion: Int? = nil
    ) {
        self.destinationID = destinationID
        self.blockID = blockID
        self.pendingMarker = pendingMarker
        self.revision = revision
        self.format = format
        self.captionVersion = captionVersion
    }
}

struct Note: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var revision: UUID
    var pages: [NotePage]
    var destination: NotionPage?
    var sync: SyncState?
    /// Absent in legacy paged files; version 2 is one continuous drawing.
    var canvasVersion: Int?

    init(title: String = "Untitled note") {
        let now = Date()
        self.id = UUID()
        self.title = title
        self.createdAt = now
        self.updatedAt = now
        self.revision = UUID()
        self.pages = [NotePage()]
        self.destination = nil
        self.sync = nil
        self.canvasVersion = 2
    }
}

extension Note {
    /// A completed upload must never replace newer local content with its snapshot.
    func withSyncState(_ state: SyncState?) -> Note {
        var copy = self
        copy.sync = state
        return copy
    }
}
