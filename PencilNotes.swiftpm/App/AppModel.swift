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
    @Published private(set) var isSyncing = false
    @Published private(set) var autoSyncPaused = false
    @Published var autoSyncEnabled = UserDefaults.standard.bool(forKey: "PencilNotes.autoSync") {
        didSet {
            UserDefaults.standard.set(autoSyncEnabled, forKey: "PencilNotes.autoSync")
            autoSyncPaused = false
            lastCanvasActivity = Date()
            if autoSyncEnabled, let id = selectedID { queueAutoSync(id) }
            else { syncDebouncer.cancel(); pendingAutoSync.removeAll() }
        }
    }
    private let syncDebouncer = AutoSyncDebouncer()
    private var pendingAutoSync = Set<UUID>()
    private var canvasInteracting = false
    private var lastCanvasActivity = Date.distantPast
    private(set) var maxUploadBytes = 5 * 1024 * 1024
    private var repository: NoteRepository?
    private var dirty = Set<UUID>()
    private var autosave: Task<Void, Never>?

    var selectedNote: Note? { notes.first { $0.id == selectedID } }
    var selectedPage: NotePage? {
        guard let note = selectedNote, note.pages.indices.contains(pageIndex) else { return nil }
        return note.pages[pageIndex]
    }

    init(directory: URL? = nil, loadCredential: Bool = true) {
        do {
            let noteDirectory: URL
            if let directory { noteDirectory = directory }
            else {
                let base = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                noteDirectory = base.appendingPathComponent("PencilNotes", isDirectory: true)
            }
            let repo = try NoteRepository(directory: noteDirectory)
            repository = repo
            let result = repo.loadAll()
            storageIssues = result.issues
            for original in result.notes {
                do {
                    try NoteExporter.validate(original)
                    let note = try NoteExporter.continuous(original)
                    if note != original { try repo.save(note) }
                    notes.append(note)
                } catch {
                    notes.append(original)
                    storageIssues.append("“\(original.title)” could not be opened or upgraded: \(error.localizedDescription) Its original files are preserved.")
                }
            }
            if let first = notes.first(where: { $0.canvasVersion == 2 && (try? NoteExporter.validate($0)) != nil }) { selectedID = first.id }
        } catch {
            errorMessage = "Local storage is unavailable: \(error.localizedDescription)"
        }
        do {
            if loadCredential, let token = try KeychainStore.read() {
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
            let continuous = try NoteExporter.continuous(note)
            if continuous != note {
                try persist(continuous)
                if let index = notes.firstIndex(where: { $0.id == id }) { notes[index] = continuous }
            }
            canvasInteracting = false
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

    func deleteSelected() {
        guard !isBusy, !isSyncing, let id = selectedID else { return }
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
        if autoSyncEnabled { queueAutoSync(notes[index].id) }
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
            if autoSyncEnabled, let id = selectedID { queueAutoSync(id) }
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

    func canvasInteraction(_ active: Bool) {
        canvasInteracting = active
        lastCanvasActivity = Date()
        syncDebouncer.cancel()
        if !active, let id = selectedID { queueAutoSync(id) }
    }

    func sync() async {
        guard let id = selectedID else { return }
        autoSyncPaused = false
        await performSync(id: id, automatic: false)
    }

    private func performSync(id: UUID, automatic: Bool) async {
        guard !isBusy, !isSyncing else {
            if automatic { pendingAutoSync.insert(id) }
            return
        }
        guard saveNow(), let note = notes.first(where: { $0.id == id }) else {
            if automatic { autoSyncPaused = true }
            return
        }
        guard let client, note.destination != nil else {
            if !automatic { errorMessage = "Connect Notion in Settings and choose a destination page first." }
            return
        }
        if automatic && (!autoSyncEnabled || autoSyncPaused || canvasInteracting) { return }
        pendingAutoSync.remove(id)
        if note.sync?.revision == note.revision, note.sync?.format == .png,
           note.sync?.destinationID == note.destination?.id, note.sync?.blockID != nil, note.sync?.pendingMarker == nil {
            if !automatic { progress = "Up to date" }
            schedulePendingSync()
            return
        }
        isSyncing = true
        progress = "Preparing your note…"
        defer {
            isSyncing = false
            if autoSyncEnabled, !autoSyncPaused {
                if let current = notes.first(where: { $0.id == id }), current.revision != note.revision {
                    pendingAutoSync.insert(id)
                }
                schedulePendingSync()
            }
        }
        do {
            let info = try await client.connection()
            maxUploadBytes = min(info.maxUploadBytes, 20 * 1024 * 1024)
            let data = try NoteExporter.syncData(note: note, maxBytes: maxUploadBytes)
            _ = try await SyncCoordinator.sync(note: note, data: data, format: .png,
                maxBytes: maxUploadBytes, client: client, save: { [self] updated in
                    guard let index = notes.firstIndex(where: { $0.id == updated.id }) else { return }
                    // Uploads use a snapshot. Preserve ink edited while the network
                    // was suspended; only merge the snapshot's remote metadata.
                    let latest = notes[index].withSyncState(updated.sync)
                    try persist(latest)
                    notes[index] = latest
                    dirty.remove(updated.id)
                }, progress: { [weak self] message in
                    Task { @MainActor in self?.progress = message }
                })
        } catch {
            if automatic {
                autoSyncPaused = true
                progress = "Auto sync paused · tap Sync to retry"
            }
            report(error)
        }
    }

    private func queueAutoSync(_ id: UUID) {
        guard autoSyncEnabled, !autoSyncPaused else { return }
        pendingAutoSync.insert(id)
        schedulePendingSync()
    }

    private func schedulePendingSync() {
        guard autoSyncEnabled, !autoSyncPaused, !canvasInteracting, !isSyncing, client != nil else { return }
        pendingAutoSync = pendingAutoSync.filter { id in
            guard let note = notes.first(where: { $0.id == id }), note.destination != nil else { return false }
            return note.sync?.revision != note.revision || note.sync?.format != .png || note.sync?.destinationID != note.destination?.id
        }
        guard !pendingAutoSync.isEmpty else { return }
        let delay = max(0, 0.5 - Date().timeIntervalSince(lastCanvasActivity))
        syncDebouncer.schedule(delay: delay) { [weak self] in
            guard let self, self.autoSyncEnabled, !self.autoSyncPaused, !self.canvasInteracting else { return }
            let candidates = self.pendingAutoSync.sorted { $0.uuidString < $1.uuidString }
            guard let id = candidates.first else { return }
            // The debounce task must not own an in-flight request: new Pencil
            // activity cancels only the timer, never an uncertain remote write.
            Task { @MainActor [weak self] in await self?.performSync(id: id, automatic: true) }
        }
    }

    func export() {
        guard !isBusy, saveNow(), let note = selectedNote else { return }
        do { sharePayload = SharePayload(files: try NoteExporter.shareFiles(note: note)) }
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
            let note = try NoteExporter.continuous(repository.importBackup(Data(contentsOf: url)))
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
        lastCanvasActivity = Date()
        queueAutoSync(notes[index].id)
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
