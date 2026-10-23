import Foundation

/// Which edges of a bar are being dragged to resize it.
public struct ResizeEdges: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let left = ResizeEdges(rawValue: 1)
    public static let right = ResizeEdges(rawValue: 2)
    public static let top = ResizeEdges(rawValue: 4)
    public static let bottom = ResizeEdges(rawValue: 8)
}

/// The arithmetic behind placing, resizing and filling a bar. Coordinates are
/// AppKit's: origin at the bottom left, y grows upwards.
///
/// Uses plain `Double`s rather than the CoreGraphics types, which SpacesCore
/// (Foundation only) can't use the same way the AppKit layer does.
public enum BarGeometry {
    /// A rectangle with a positive size.
    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
    }

    /// Narrowest a bar gets, in points.
    public static let minBarWidth = 60.0

    /// Moves `frame` back inside `visible` if any part of it is outside.
    /// When it's wider than `visible`, its left edge stays on the left edge.
    public static func clamp(_ frame: Rect, to visible: Rect) -> Rect {
        var f = frame
        f.x = min(max(f.x, visible.x), max(visible.x, visible.maxX - f.width))
        f.y = min(max(f.y, visible.y), visible.maxY - f.height)
        return f
    }

    /// Edges of a `width` × `height` view within `zone` points of the point
    /// (`x`, `y`) in its own coordinates; empty when the point is outside.
    public static func edges(x: Double, y: Double, width: Double, height: Double, zone: Double) -> ResizeEdges {
        guard x >= 0, x < width, y >= 0, y < height else { return [] }
        var edges: ResizeEdges = []
        if x < zone { edges.insert(.left) }
        if x > width - zone { edges.insert(.right) }
        if y < zone { edges.insert(.bottom) }
        if y > height - zone { edges.insert(.top) }
        return edges
    }

    /// The size asked for by dragging `edges` of `frame` by (`dx`, `dy`).
    /// The width never goes below `minBarWidth`; the height isn't limited here.
    public static func resizedSize(of frame: Rect, edges: ResizeEdges, dx: Double, dy: Double)
        -> (width: Double, height: Double) {
        var width = frame.width
        var height = frame.height
        if edges.contains(.right) { width += dx }
        if edges.contains(.left) { width -= dx }
        if edges.contains(.top) { height += dy }
        if edges.contains(.bottom) { height -= dy }
        return (max(width, minBarWidth), height)
    }

    /// Where `start` goes when resized to `width` × `height`, so the edges not
    /// being dragged stay put.
    public static func resizedFrame(from start: Rect, width: Double, height: Double, edges: ResizeEdges) -> Rect {
        Rect(x: edges.contains(.left) ? start.maxX - width : start.x,
             y: edges.contains(.top) ? start.y : start.maxY - height,
             width: width, height: height)
    }

    /// Tile widths for a bar and whether tiles are compact.
    ///
    /// With a width the user picked (`target`), tiles stretch or shrink to fill
    /// it, never narrower than `minTile`; otherwise they get their natural
    /// width, switching to compact tiles when the bar would be wider than
    /// 90 % of the screen.
    /// - Parameters:
    ///   - natural: each tile's natural width.
    ///   - compact: each tile's compact width (asked for only when needed).
    ///   - start: where the first tile starts.
    ///   - reserved: room needed after the tiles (warning, insets, other labels).
    public static func tileWidths(natural: [Double], compact: () -> [Double], start: Double, reserved: Double,
                                  gap: Double, minTile: Double, target: Double?,
                                  screenWidth: Double) -> (widths: [Double], compact: Bool) {
        let gaps = Double(max(natural.count - 1, 0)) * gap
        let naturalSum = natural.reduce(0, +)
        if let target, naturalSum > 0 {
            let factor = max(target - start - reserved - gaps, 0) / naturalSum
            return (natural.map { max(floor($0 * factor), minTile) }, factor < 1)
        }
        if start + naturalSum + gaps + reserved > screenWidth * 0.9 {
            return (compact(), true)
        }
        return (natural, false)
    }
}
