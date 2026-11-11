import Foundation
import PencilKit
import UIKit

enum NoteExporter {
    static let pageSize = CGSize(width: 768, height: 1024)
    static let pageRect = CGRect(origin: .zero, size: pageSize)

    static func drawing(_ data: Data) throws -> PKDrawing {
        data.isEmpty ? PKDrawing() : try PKDrawing(data: data)
    }

    static func validate(_ note: Note) throws {
        for page in note.pages { _ = try drawing(page.drawing) }
    }

    static func png(page: NotePage, scale: CGFloat = 2) throws -> Data {
        let ink = try drawing(page.drawing)
        let region = try exportRegion(ink)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: pageSize, format: format).image { context in
            UIColor.white.setFill()
            context.cgContext.fill(pageRect)
            render(ink, region: region, scale: scale)
        }
        guard let data = image.pngData() else { throw exportError }
        return data
    }

    static func pdf(note: Note) throws -> Data {
        let drawings = try note.pages.map { page -> (PKDrawing, CGRect) in
            let ink = try drawing(page.drawing)
            return (ink, try exportRegion(ink))
        }
        return UIGraphicsPDFRenderer(bounds: pageRect).pdfData { context in
            for (ink, region) in drawings {
                context.beginPage()
                UIColor.white.setFill()
                context.cgContext.fill(pageRect)
                render(ink, region: region, scale: 2)
            }
        }
    }

    static func syncData(note: Note, format: ExportFormat, maxBytes: Int) throws -> Data {
        if format == .pdf {
            let data = try pdf(note: note)
            guard data.count <= maxBytes else { throw tooLarge(data.count, maxBytes) }
            return data
        }
        guard note.pages.count == 1 else {
            throw NSError(domain: "PencilNotes.Export", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "Use PDF to sync a notebook with multiple pages. PNG export still shares every page as a separate image."])
        }
        // Retain a legible 768 x 1024 minimum; never silently drop pages or crop ink.
        for scale in [CGFloat(2), 1.5, 1] {
            let data = try png(page: note.pages[0], scale: scale)
            if data.count <= maxBytes { return data }
        }
        throw tooLarge(try png(page: note.pages[0], scale: 1).count, maxBytes)
    }

    static func shareFiles(note: Note, format: ExportFormat?) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PencilNotes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var files: [URL] = []
        if format == .png {
            for (index, page) in note.pages.enumerated() {
                let url = directory.appendingPathComponent("\(safeTitle(note.title))-page-\(index + 1).png")
                try png(page: page).write(to: url, options: .atomic)
                files.append(url)
            }
        } else if format == .pdf {
            let url = directory.appendingPathComponent("\(safeTitle(note.title)).pdf")
            try pdf(note: note).write(to: url, options: .atomic)
            files.append(url)
        }
        return files
    }

    static func safeTitle(_ title: String) -> String {
        let value = title.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" ? String($0) : "_" }.joined()
        return String((value.isEmpty ? "Note" : value).prefix(70))
    }

    private static func exportRegion(_ ink: PKDrawing) throws -> CGRect {
        guard !ink.bounds.isNull, !ink.bounds.isEmpty else { return pageRect }
        let region = pageRect.union(ink.bounds.insetBy(dx: -4, dy: -4))
        guard region.minX.isFinite, region.minY.isFinite, region.width.isFinite,
              region.height.isFinite, region.width > 0, region.height > 0 else { throw exportError }
        return region
    }

    private static func render(_ ink: PKDrawing, region: CGRect, scale: CGFloat) {
        // Lasso operations/imports may put ink beyond the paper. Fit the entire
        // region into the exported page, keeping aspect ratio and every stroke.
        let fit = min(pageSize.width / region.width, pageSize.height / region.height)
        let size = CGSize(width: region.width * fit, height: region.height * fit)
        let destination = CGRect(x: (pageSize.width - size.width) / 2,
                                 y: (pageSize.height - size.height) / 2,
                                 width: size.width, height: size.height)
        ink.image(from: region, scale: scale * fit).draw(in: destination)
    }

    private static var exportError: NSError {
        NSError(domain: "PencilNotes.Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "The note could not be rendered. Your original strokes are still saved."])
    }
    private static func tooLarge(_ actual: Int, _ limit: Int) -> NSError {
        NSError(domain: "PencilNotes.Export", code: 3, userInfo: [NSLocalizedDescriptionKey:
            "This export is \(ByteCountFormatter.string(fromByteCount: Int64(actual), countStyle: .file)); the upload limit is \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)). Export locally or split this note into smaller notebooks."])
    }
}
