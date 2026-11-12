import Foundation

/// Logical drawing coordinates stay stable across iPad sizes and rotations.
enum CanvasGeometry {
    static let width: CGFloat = 768
    static let legacyPageHeight: CGFloat = 1024
    static let bottomPadding: CGFloat = 32
    static let minimumImageHeight: CGFloat = 256
    static let notionBackgroundRGB: UInt32 = 0x191919

    static func imageBounds(ink: CGRect) -> CGRect {
        guard !ink.isNull, !ink.isEmpty, ink.minX.isFinite, ink.maxX.isFinite,
              ink.minY.isFinite, ink.maxY.isFinite else {
            return CGRect(x: 0, y: 0, width: width, height: minimumImageHeight)
        }
        // Normally x is 0...768. Include imported/lasso-moved ink as well.
        let left = min(0, ink.minX - 4)
        let top = min(0, ink.minY - 4)
        return CGRect(x: left, y: top, width: max(width, ink.maxX + 4) - left,
                      height: max(minimumImageHeight, ink.maxY + bottomPadding) - top)
    }

    static func renderScale(bounds: CGRect, preferred: CGFloat = 2) -> CGFloat {
        // Bound raster memory while retaining every stroke on long canvases.
        min(preferred, sqrt(24_000_000 / max(1, bounds.width * bounds.height)),
            16_384 / max(bounds.width, bounds.height))
    }
}
