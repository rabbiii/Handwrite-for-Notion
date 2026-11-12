import Foundation
import PencilKit
import UIKit

enum NoteExporter {
    static func drawing(_ data: Data) throws -> PKDrawing {
        data.isEmpty ? PKDrawing() : try PKDrawing(data: data)
    }

    static func validate(_ note: Note) throws {
        for page in note.pages { _ = try drawing(page.drawing) }
    }

    /// Fold older multi-page notes into one drawing without flattening strokes.
    static func continuous(_ original: Note) throws -> Note {
        guard original.canvasVersion != 2 || original.pages.count != 1 else { return original }
        var note = original
        var ink = PKDrawing()
        var offset: CGFloat = 0
        for page in note.pages {
            let part = try drawing(page.drawing)
            ink = ink.appending(part.transformed(using: CGAffineTransform(translationX: 0, y: offset)))
            offset += max(CanvasGeometry.legacyPageHeight, part.bounds.isNull ? 0 : part.bounds.maxY + CanvasGeometry.bottomPadding)
        }
        note.pages = [NotePage(id: original.pages.first?.id ?? UUID(), drawing: ink.dataRepresentation())]
        note.canvasVersion = 2
        note.revision = UUID()
        return note
    }

    static var notionBackground: UIColor { UIColor(white: 25.0 / 255.0, alpha: 1) }

    static func png(note: Note, preferredScale: CGFloat = 2) throws -> Data {
        let normalized = try continuous(note)
        let ink = try drawing(normalized.pages[0].drawing)
        let region = CanvasGeometry.imageBounds(ink: ink.bounds)
        // Width is fixed; height follows the lowest stroke, not the scroll position.
        let fit = CanvasGeometry.width / region.width
        let size = CGSize(width: CanvasGeometry.width, height: ceil(region.height * fit))
        let scale = CanvasGeometry.renderScale(bounds: CGRect(origin: .zero, size: size), preferred: preferredScale)
        guard scale >= 0.125, size.height.isFinite else {
            throw NSError(domain: "PencilNotes.Export", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "This canvas is too long to render safely as one image. Keep an editable backup and move some content into another note."])
        }
        return try autoreleasepool {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = true
            format.preferredRange = .standard
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                notionBackground.setFill()
                context.cgContext.fill(CGRect(origin: .zero, size: size))
                // Render the original ink colors. No light/dark recoloring pass.
                ink.image(from: region, scale: scale * fit).draw(in: CGRect(origin: .zero, size: size))
            }
            guard let bytes = image.pngData() else { throw exportError }
            return bytes
        }
    }

    static func syncData(note: Note, maxBytes: Int) throws -> Data {
        var lastCount = 0
        for scale in [CGFloat(2), 1.5, 1, 0.75, 0.5] {
            let data = try png(note: note, preferredScale: scale)
            lastCount = data.count
            if data.count <= maxBytes { return data }
        }
        throw NSError(domain: "PencilNotes.Export", code: 2, userInfo: [NSLocalizedDescriptionKey:
            "The image is \(ByteCountFormatter.string(fromByteCount: Int64(lastCount), countStyle: .file)); Notion allows \(ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)). Export an editable backup and split this note before syncing."])
    }

    static func shareFiles(note: Note) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PencilNotes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(safeTitle(note.title)).png")
        try png(note: note).write(to: url, options: .atomic)
        return [url]
    }

    static func safeTitle(_ title: String) -> String {
        let value = title.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" ? String($0) : "_" }.joined()
        return String((value.isEmpty ? "Note" : value).prefix(70))
    }

    private static var exportError: NSError {
        NSError(domain: "PencilNotes.Export", code: 3, userInfo: [NSLocalizedDescriptionKey: "The image could not be rendered. Your original strokes remain saved."])
    }
}
