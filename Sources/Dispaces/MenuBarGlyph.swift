import AppKit

/// The menu bar icon: three Space tiles, the middle (current) one filled. Drawn in code
/// (same shapes as `Assets/MenuBarGlyph.svg`) and marked as a template, so macOS tints it
/// for light and dark menu bars.
enum MenuBarGlyph {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            for x in [1.1, 12.9] {
                let side = NSBezierPath(roundedRect: NSRect(x: x, y: 5.1, width: 4, height: 7.8), xRadius: 1, yRadius: 1)
                side.lineWidth = 1.2
                side.stroke()
            }
            NSBezierPath(roundedRect: NSRect(x: 6.5, y: 2.8, width: 5, height: 12.4), xRadius: 1.2, yRadius: 1.2).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Dispaces"
        return image
    }
}
