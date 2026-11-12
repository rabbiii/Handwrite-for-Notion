import SwiftUI

enum NoteIcons {
    static let legacy = ["book.closed", "pencil", "paintbrush", "lightbulb", "leaf", "star", "moon", "sun.max", "bolt", "sparkles", "heart", "paperplane"]
    static let groups: [(String, [String])] = [
        ("Writing", ["book.closed", "pencil", "paintbrush", "pencil.tip", "highlighter", "eraser", "book", "bookmark", "text.book.closed", "doc.text"]),
        ("Study", ["lightbulb", "graduationcap", "brain", "atom", "function", "sum", "number", "ruler", "globe", "testtube.2"]),
        ("Work", ["briefcase", "calendar", "clock", "checklist", "chart.bar", "chart.pie", "folder", "tray", "desktopcomputer", "keyboard"]),
        ("Nature", ["leaf", "moon", "sun.max", "flame", "drop", "snowflake", "cloud", "wind", "tree", "mountain.2"]),
        ("Objects", ["paperplane", "camera", "music.note", "headphones", "gift", "cup.and.saucer", "bicycle", "airplane", "balloon", "umbrella"]),
        ("Shapes", ["star", "bolt", "sparkles", "heart", "circle", "square", "triangle", "diamond", "seal", "hexagon"])
    ]
    static var all: [String] { groups.flatMap { $0.1 } }
    static func name(for note: Note) -> String {
        if let name = note.iconName, all.contains(name) { return name }
        return legacy[Int(note.id.uuid.0) % legacy.count]
    }
}

struct AnimatedNoteIcon: View {
    let name: String
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || reduceMotion || scenePhase != .active)) { context in
            let index = Double(NoteIcons.all.firstIndex(of: name) ?? 0)
            let running = active && !reduceMotion && scenePhase == .active
            let phase = running ? sin(context.date.timeIntervalSinceReferenceDate * (1.4 + index * 0.017)) : 0
            let floating = ["paperplane", "airplane", "balloon", "cloud", "leaf", "music.note"].contains(name)
            let glowing = ["heart", "lightbulb", "sun.max", "star", "sparkles", "flame", "bolt"].contains(name)
            Image(systemName: name)
                .scaleEffect(glowing ? 1 + phase * 0.10 : 1)
                .opacity(glowing ? 0.85 + phase * 0.15 : 1)
                .rotationEffect(.degrees(glowing ? 0 : phase * (3 + index.truncatingRemainder(dividingBy: 5))))
                .offset(y: floating ? phase * 3 : 0)
        }
    }
}

struct NoteIconPicker: View {
    let selected: String
    let choose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private func select(_ name: String) { choose(name); dismiss() }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button("Surprise me", systemImage: "shuffle") {
                        select(NoteIcons.all.filter { $0 != selected }.randomElement() ?? selected)
                    }.buttonStyle(.bordered)
                    ForEach(NoteIcons.groups, id: \.0) { category, symbols in
                        let matches = symbols.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) || category.localizedCaseInsensitiveContains(search) }
                        if !matches.isEmpty {
                            Text(category).font(.headline)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))]) {
                                ForEach(matches, id: \.self) { name in
                                    Button { select(name) } label: {
                                        Image(systemName: name).font(.title2).frame(width: 48, height: 48)
                                            .background(selected == name ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                                    }.buttonStyle(.plain).accessibilityLabel(name.replacingOccurrences(of: ".", with: " "))
                                        .accessibilityAddTraits(selected == name ? .isSelected : [])
                                }
                            }
                        }
                    }
                }.padding()
            }.background(.regularMaterial).searchable(text: $search, prompt: "Find an icon")
                .navigationTitle("Note icon").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
        }.frame(idealWidth: 360, idealHeight: 480)
    }
}
