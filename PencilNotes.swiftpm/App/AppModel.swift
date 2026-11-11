import Foundation
import PencilKit
import SwiftUI

struct SharePayload: Identifiable {
    let id = UUID()
    let files: [URL]
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var selectedID: UUID?
    @Published var pageIndex = 0
    @Published var errorMessage: String?
    @Published var storageIssues: [String] = []
    @Published var saveStatus = "Saved on this iPad"
    @Published var connectionStatus = "Not connected"
    @Published private(set) var client: NotionClient?
    @Published var isBusy = false
    @Published var progress = ""
    @Published var sharePayload: SharePayload?
    @Published var syncFormat: ExportFormat = .pdf
    private(set) var maxUploadBytes = 5 * 1024 * 1024
    private var repository: NoteRepository?
    private var dirty = Set<UUID>()
    private var autosave: Task<Void, Never>?

    var selectedNote: Note? { notes.first { $0.id == selectedID } }
    var selectedPage: NotePage? {
        guard let note = selectedNote, note.pages.indices.contains(pageIndex) else { return nil }
        return note.pages[pageIndex]
    }

    init() {
        do {
            let base = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let repo = try NoteRepository(directory: base.appendingPathComponent("PencilNotes", isDirectory: true))
            repository = repo
            let result = repo.loadAll()
            notes = result.notes
            storageIssues = result.issues
            for note in notes {
                do { try NoteExporter.validate(note) }
                catch { storageIssues.append("“\(note.title)” contains unreadable PencilKit strokes. Its files are preserved; restore a backup to continue.") }
            }
            if let first = notes.first(where: { (try? NoteExporter.validate($0)) != nil }) { selectedID = first.id }
        } catch {
            errorMessage = "Local storage is unavailable: \(error.localizedDescription)"
        }
        do {
            if let token = try KeychainStore.read() {
                client = NotionClient(token: token)
                connectionStatus = "Saved connection · verify online in Settings"
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func newNote() {
        guard !isBusy, saveNow() else { return }
        let note = Note()
        do {
            try persist(note)
            notes.insert(note, at: 0)
            selectedID = note.id
            pageIndex = 0
        } catch { report(error) }
    }

    func select(_ id: UUID) {
        guard !isBusy, saveNow(), let note = notes.first(where: { $0.id == id }) else { return }
        do {
            try NoteExporter.validate(note)
            selectedID = id
            pageIndex = 0
        } catch {
            errorMessage = "This note has unreadable strokes. Its original files are preserved. Restore a .pencilnote backup; do not replace it with a blank drawing."
        }
    }

    func rename(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else {
            errorMessage = "Use a title between 1 and 200 characters."
            return
        }
        change { $0.title = trimmed }
        _ = saveNow()
    }

    func drawingChanged(_ data: Data, pageID: UUID) {
        guard !isBusy, let note = selectedNote,
              let index = note.pages.firstIndex(where: { $0.id == pageID }),
              note.pages[index].drawing != data else { return }
        change { $0.pages[index].drawing = data }
    }

    func addPage() {
        guard let note = selectedNote, note.pages.count < NoteRepository.maximumPages, saveNow() else {
            if selectedNote?.pages.count == NoteRepository.maximumPages { errorMessage = "This notebook has reached 200 pages. Start a new note." }
            return
        }
        change { $0.pages.append(NotePage()) }
        pageIndex = (selectedNote?.pages.count ?? 1) - 1
        _ = saveNow()
    }

    func removePage() {
        guard let note = selectedNote, note.pages.count > 1, note.pages.indices.contains(pageIndex) else { return }
        let removing = pageIndex
        change { $0.pages.remove(at: removing) }
        pageIndex = min(removing, (selectedNote?.pages.count ?? 1) - 1)
        _ = saveNow()
    }

    func movePage(_ offset: Int) {
        guard saveNow(), let note = selectedNote, note.pages.indices.contains(pageIndex + offset) else { return }
        pageIndex += offset
    }

    func deleteSelected() {
        guard !isBusy, let id = selectedID else { return }
        do {
            guard let repository else { throw storageUnavailable }
            try repository.delete(id)
            autosave?.cancel()
            dirty.remove(id)
            notes.removeAll { $0.id == id }
            selectedID = nil
            pageIndex = 0
            if let next = notes.first { select(next.id) }
        } catch { report(error) }
    }

    func chooseDestination(_ destination: NotionPage) {
        guard let index = selectedIndex else { return }
        if let state = notes[index].sync, state.pendingMarker != nil, state.destinationID != destination.id {
            errorMessage = "Resolve the uncertain sync on the original destination before choosing another page. Retry on that page, or inspect it before using Resolve uncertain sync."
            return
        }
        // Keep remote state until sync: changing selection itself never edits a Notion page.
        notes[index].destination = destination
        dirty.insert(notes[index].id)
        _ = saveNow()
    }

    func resolveUncertainSync() {
        guard let index = selectedIndex else { return }
        notes[index].sync?.pendingMarker = nil
        dirty.insert(notes[index].id)
        _ = saveNow()
    }

    func resetNotionLink() {
        guard let index = selectedIndex, notes[index].sync?.pendingMarker == nil else { return }
        notes[index].sync = nil
        dirty.insert(notes[index].id)
        _ = saveNow()
        progress = "Link reset. Next sync checks the page for this note before adding a block."
    }

    @discardableResult
    func saveNow() -> Bool {
        autosave?.cancel()
        for id in Array(dirty) {
            guard let note = notes.first(where: { $0.id == id }) else { continue }
            do {
                try persist(note)
                dirty.remove(id)
            } catch {
                saveStatus = "Not saved · tap Save to retry"
                report(error)
                return false
            }
        }
        saveStatus = "Saved on this iPad"
        return true
    }

    func connect(token: String) async -> Bool {
        guard !isBusy else { return false }
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains("\n") else {
            errorMessage = "Paste your Notion internal integration token into the secure field."
            return false
        }
        isBusy = true
        progress = "Connecting to Notion…"
        defer { isBusy = false }
        do {
            let candidate = NotionClient(token: clean)
            let connection = try await candidate.connection()
            try KeychainStore.write(clean)
            client = candidate
            maxUploadBytes = min(connection.maxUploadBytes, 20 * 1024 * 1024)
            connectionStatus = "Connected · \(connection.name)"
            return true
        } catch { report(error); return false }
    }

    func verifyConnection() async {
        guard let client, !isBusy else { return }
        isBusy = true
        progress = "Verifying Notion connection…"
        defer { isBusy = false }
        do {
            let info = try await client.connection()
            maxUploadBytes = min(info.maxUploadBytes, 20 * 1024 * 1024)
            connectionStatus = "Connected · \(info.name)"
        } catch { connectionStatus = "Connection needs attention"; report(error) }
    }

    func disconnect() {
        guard !isBusy else { return }
        do {
            try KeychainStore.delete()
            client = nil
            maxUploadBytes = 5 * 1024 * 1024
            connectionStatus = "Not connected"
        } catch { report(error) }
    }

    func sync() async {
        guard !isBusy, saveNow(), let note = selectedNote else { return }
        guard let client else { errorMessage = "Connect your Notion integration in Settings first."; return }
        guard note.destination != nil else { errorMessage = "Choose a destination page first."; return }
        isBusy = true
        progress = "Preparing your note…"
        defer { isBusy = false }
        do {
            // Refresh plan limits and credential status for each sync.
            let info = try await client.connection()
            maxUploadBytes = min(info.maxUploadBytes, 20 * 1024 * 1024)
            let data = try NoteExporter.syncData(note: note, format: syncFormat, maxBytes: maxUploadBytes)
            _ = try await SyncCoordinator.sync(note: note, data: data, format: syncFormat,
                maxBytes: maxUploadBytes, client: client, save: { [self] updated in
                    try persist(updated)
                    if let index = notes.firstIndex(where: { $0.id == updated.id }) { notes[index] = updated }
                    dirty.remove(updated.id)
                }, progress: { [weak self] message in
                    Task { @MainActor in self?.progress = message }
                })
        } catch { report(error) }
    }

    func export(_ format: ExportFormat) {
        guard !isBusy, saveNow(), let note = selectedNote else { return }
        do { sharePayload = SharePayload(files: try NoteExporter.shareFiles(note: note, format: format)) }
        catch { report(error) }
    }

    func exportBackup() {
        guard !isBusy, saveNow(), let note = selectedNote else { return }
        do {
            guard let repository else { throw storageUnavailable }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PencilNotes-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(NoteExporter.safeTitle(note.title)).pencilnote")
            try repository.backupData(note).write(to: url, options: .atomic)
            sharePayload = SharePayload(files: [url])
        } catch { report(error) }
    }

    func importBackup(url: URL) {
        guard !isBusy, saveNow() else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let repository else { throw storageUnavailable }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= NoteRepository.maximumFileBytes else { throw NoteStorageError.oversizedFile }
            let note = try repository.importBackup(Data(contentsOf: url))
            try NoteExporter.validate(note)
            try persist(note)
            notes.insert(note, at: 0)
            selectedID = note.id
            pageIndex = 0
        } catch { report(error) }
    }

    private var selectedIndex: Int? { notes.firstIndex { $0.id == selectedID } }
    private func change(_ edit: (inout Note) -> Void) {
        guard !isBusy, let index = selectedIndex else { return }
        edit(&notes[index])
        notes[index].revision = UUID()
        notes[index].updatedAt = Date()
        dirty.insert(notes[index].id)
        saveStatus = "Saving…"
        autosave?.cancel()
        autosave = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 450_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
    private func persist(_ note: Note) throws {
        guard let repository else { throw storageUnavailable }
        try repository.save(note)
    }
    private var storageUnavailable: NSError {
        NSError(domain: "PencilNotes.Storage", code: 1, userInfo: [NSLocalizedDescriptionKey: "The notes folder is unavailable. Free storage and reopen the app before writing new notes."])
    }
    private func report(_ error: Error) { errorMessage = error.localizedDescription }
}
