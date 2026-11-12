import SwiftUI

struct RecentlyDeletedView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: Note?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.deletedNotes) { note in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(note.title).font(.headline)
                            HStack {
                                Button("Restore", systemImage: "arrow.uturn.backward") { model.restoreDeleted(note.id) }
                                Spacer()
                                Button("Delete permanently", systemImage: "trash", role: .destructive) { deleting = note }
                            }.buttonStyle(.bordered)
                        }.padding(.vertical, 6)
                    }
                } footer: { Text("Notes remain here until you restore or permanently delete them. Notion images are unchanged.") }
            }.overlay { if model.deletedNotes.isEmpty { ContentUnavailableView("🌿 No deleted notes", systemImage: "trash") } }
                .navigationTitle("🗑️ Recently Deleted")
                .toolbar { Button("Done") { dismiss() } }
                .alert("Permanently delete this note?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("Delete permanently", role: .destructive) { if let note = deleting { model.permanentlyDelete(note.id) }; deleting = nil }
                    Button("Cancel", role: .cancel) { deleting = nil }
                } message: { Text("This removes the local note and its recovery copies. It cannot be undone.") }
        }
    }
}
