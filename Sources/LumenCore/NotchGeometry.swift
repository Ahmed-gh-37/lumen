import CoreGraphics
import Foundation

public enum NotchGeometry {
    public static func readingBodyHeight(fontSize: Double, lines: Int) -> CGFloat {
        CGFloat(min(64, max(24, fontSize)) * 1.55 * Double(min(8, max(2, lines))) + 112)
    }

    /// AppKit screen coordinates may have negative origins on secondary displays.
    public static func frame(
        screen: CGRect, cameraCenterX: CGFloat, cameraWidth: CGFloat,
        topInset: CGFloat, expanded: Bool, preferredWidth: CGFloat,
        bodyHeight: CGFloat
    ) -> CGRect {
        let width =
            expanded
            ? min(max(480, preferredWidth), max(1, screen.width - 24))
            : min(max(190, cameraWidth + 96), max(1, screen.width))
        let height = min(max(1, screen.height - 24), max(28, topInset) + (expanded ? max(1, bodyHeight) : 8))
        let x = min(max(screen.minX, cameraCenterX - width / 2), screen.maxX - width)
        return CGRect(x: x, y: screen.maxY - height, width: width, height: height)
    }
}
