import Foundation

/// Where each display's bar sits, its size, and whether it is collapsed or locked.
///
/// Positions are stored per display as an offset from the top-left corner of
/// that display's usable area, so they survive rearranging displays in
/// System Settings. Read back from preferences, so everything is re-validated.
public struct BarLayout: Equatable, Sendable {
    public struct Offset: Equatable, Sendable {
        /// Points from the left edge of the display's usable area.
        public let fromLeft: Double
        /// Points down from the top edge of the display's usable area.
        public let fromTop: Double

        public init(fromLeft: Double, fromTop: Double) {
            self.fromLeft = fromLeft
            self.fromTop = fromTop
        }
    }

    /// A bar size the user picked by dragging its edges.
    public struct Size: Equatable, Sendable {
        public let width: Double
        public let height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    public static let maxEntries = 64
    public static let maxKeyLength = 200
    public static let maxOffset = 20_000.0
    /// Bar heights the user can pick; the default bar is 36 pt.
    public static let heights: ClosedRange<Double> = 28...72
    public static let maxWidth = 20_000.0

    public private(set) var offsets: [String: Offset]
    public private(set) var sizes: [String: Size]
    public private(set) var collapsed: Set<String>
    public private(set) var locked: Set<String>

    public init() {
        offsets = [:]
        sizes = [:]
        collapsed = []
        locked = []
    }

    /// Builds from untrusted stored values: `storedOffsets` is `[key: [left, top]]`,
    /// `storedSizes` is `[key: [width, height]]`, the others are `[key]`.
    /// Anything malformed is dropped.
    public init(storedOffsets: Any?, storedSizes: Any? = nil, storedCollapsed: Any?, storedLocked: Any? = nil) {
        offsets = BarLayout.pairs(storedOffsets).compactMapValues { BarLayout.offset($0.0, $0.1) }
        sizes = BarLayout.pairs(storedSizes).compactMapValues { BarLayout.size($0.0, $0.1) }
        collapsed = BarLayout.keys(storedCollapsed)
        locked = BarLayout.keys(storedLocked)
    }

    /// Values ready for `UserDefaults`.
    public var storedOffsets: [String: [Double]] {
        offsets.mapValues { [$0.fromLeft, $0.fromTop] }
    }

    public var storedSizes: [String: [Double]] {
        sizes.mapValues { [$0.width, $0.height] }
    }

    public var storedCollapsed: [String] { collapsed.sorted() }
    public var storedLocked: [String] { locked.sorted() }

    public mutating func setOffset(fromLeft: Double, fromTop: Double, for key: String) {
        guard BarLayout.isValidKey(key), let offset = BarLayout.offset(fromLeft, fromTop) else { return }
        if offsets[key] == nil && offsets.count >= BarLayout.maxEntries { return }
        offsets[key] = offset
    }

    /// Saves a size; the height is clamped to `heights`. nil forgets it (back to the natural size).
    public mutating func setSize(_ value: Size?, for key: String) {
        guard BarLayout.isValidKey(key) else { return }
        guard let value else {
            sizes[key] = nil
            return
        }
        guard let size = BarLayout.size(value.width, value.height) else { return }
        if sizes[key] == nil && sizes.count >= BarLayout.maxEntries { return }
        sizes[key] = size
    }

    public mutating func setCollapsed(_ value: Bool, for key: String) {
        BarLayout.set(&collapsed, value, key)
    }

    public mutating func setLocked(_ value: Bool, for key: String) {
        BarLayout.set(&locked, value, key)
    }

    public func isCollapsed(_ key: String) -> Bool { collapsed.contains(key) }
    public func isLocked(_ key: String) -> Bool { locked.contains(key) }

    // MARK: Helpers

    static func isValidKey(_ key: String) -> Bool {
        !key.isEmpty && key.count <= maxKeyLength
    }

    static func offset(_ left: Double, _ top: Double) -> Offset? {
        guard left.isFinite, top.isFinite, abs(left) <= maxOffset, abs(top) <= maxOffset else { return nil }
        return Offset(fromLeft: left, fromTop: top)
    }

    static func size(_ width: Double, _ height: Double) -> Size? {
        guard width.isFinite, height.isFinite, width > 0, width <= maxWidth, height > 0 else { return nil }
        return Size(width: width, height: min(max(height, heights.lowerBound), heights.upperBound))
    }

    private static func set(_ keys: inout Set<String>, _ value: Bool, _ key: String) {
        guard isValidKey(key) else { return }
        if value {
            if keys.count < maxEntries { keys.insert(key) }
        } else {
            keys.remove(key)
        }
    }

    /// `[key: [a, b]]` with valid keys and two numbers, at most `maxEntries`.
    private static func pairs(_ stored: Any?) -> [String: (Double, Double)] {
        guard let dict = stored as? [String: Any] else { return [:] }
        var result: [String: (Double, Double)] = [:]
        for key in dict.keys.sorted() where isValidKey(key) {
            if result.count >= maxEntries { break }
            guard let pair = dict[key] as? [Any], pair.count == 2,
                  let a = double(pair[0]), let b = double(pair[1]) else { continue }
            result[key] = (a, b)
        }
        return result
    }

    /// `[key]` with valid keys, at most `maxEntries`.
    private static func keys(_ stored: Any?) -> Set<String> {
        guard let list = stored as? [Any] else { return [] }
        var result = Set<String>()
        for case let key as String in list.prefix(maxEntries) where isValidKey(key) {
            result.insert(key)
        }
        return result
    }

    static func double(_ value: Any) -> Double? {
        switch value {
        case let d as Double: return d
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }
}
