import Foundation

/// Where the square Space tiles go in the menu bar item, and which tile a click
/// lands on. Pure geometry (points, x grows to the right) so it can be tested.
public enum MenuBarGeometry {
    public struct Metrics: Equatable, Sendable {
        /// Side of a square tile.
        public var tile: Double
        /// Between two tiles of one group.
        public var gap: Double
        /// Between two displays' groups.
        public var groupGap: Double
        /// Before the Spaces of an unplugged display that macOS moved onto this one.
        public var subgroupGap: Double
        /// Left and right padding inside the item.
        public var inset: Double

        public init(tile: Double, gap: Double, groupGap: Double, subgroupGap: Double, inset: Double) {
            self.tile = tile
            self.gap = gap
            self.groupGap = groupGap
            self.subgroupGap = subgroupGap
            self.inset = inset
        }

        /// Tiles fit the menu bar's height (22 pt, or 24 pt beside the notch)
        /// with a little room above and below.
        public static func forMenuBar(thickness: Double) -> Metrics {
            let tile = min(max((thickness - 6).rounded(), 12), 20)
            return Metrics(tile: tile, gap: 3, groupGap: 9, subgroupGap: 6, inset: 3)
        }
    }

    /// The space before a run of tiles (ignored for the first run).
    public enum Spacing: Equatable, Sendable {
        /// A new display.
        case group
        /// An unplugged display's Spaces, after the display they're on now.
        case subgroup
    }

    /// A run of tiles shown together.
    public struct Run: Equatable, Sendable {
        public let count: Int
        public let spacing: Spacing

        public init(count: Int, spacing: Spacing) {
            self.count = count
            self.spacing = spacing
        }
    }

    public struct Layout: Equatable, Sendable {
        /// Left edge of each tile, in order across all runs.
        public let tileXs: [Double]
        /// Left edge of the amber "!", when shown.
        public let warningX: Double?
        /// The whole item's width.
        public let width: Double
    }

    /// Lays the runs out left to right, then the "!" if `warning`.
    /// Empty runs take no room. The item is never narrower than one tile.
    public static func layout(_ runs: [Run], warning: Bool, metrics: Metrics) -> Layout {
        var xs: [Double] = []
        var x = metrics.inset
        // A display with no tiles still starts a new display for the runs after it.
        var newDisplay = false
        for run in runs {
            guard run.count > 0 else {
                if run.spacing == .group { newDisplay = true }
                continue
            }
            if !xs.isEmpty {
                let group = run.spacing == .group || newDisplay
                x += (group ? metrics.groupGap : metrics.subgroupGap) - metrics.gap
            }
            newDisplay = false
            for _ in 0..<run.count {
                xs.append(x)
                x += metrics.tile + metrics.gap
            }
        }
        var warningX: Double?
        if warning {
            if !xs.isEmpty { x += metrics.groupGap - metrics.gap }
            warningX = x
            x += metrics.tile + metrics.gap
        }
        if xs.isEmpty && !warning { x += metrics.tile + metrics.gap }
        let width = x - metrics.gap + metrics.inset
        return Layout(tileXs: xs, warningX: warningX, width: width)
    }

    /// What a click at `x` lands on.
    public enum Hit: Equatable, Sendable {
        case tile(Int)
        case warning
        /// Padding or the gap between displays.
        case gap
    }

    /// A tile counts half the small gap on each side as its own, so every
    /// click between two neighbouring tiles lands on one of them.
    public static func hit(x: Double, in layout: Layout, metrics: Metrics) -> Hit {
        let slack = metrics.gap / 2
        if let index = layout.tileXs.firstIndex(where: { x >= $0 - slack && x < $0 + metrics.tile + slack }) {
            return .tile(index)
        }
        if let warningX = layout.warningX, x >= warningX - slack, x < warningX + metrics.tile + slack {
            return .warning
        }
        return .gap
    }
}
