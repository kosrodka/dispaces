import Foundation

/// One window from the window server's list. Only what's needed to tell which
/// app owns a window: never its title or contents.
public struct WindowEntry: Equatable, Sendable {
    public let windowID: UInt32
    public let ownerPID: Int32

    public init(windowID: UInt32, ownerPID: Int32) {
        self.windowID = windowID
        self.ownerPID = ownerPID
    }
}

/// Works out which apps have windows on which Space, for the hover icons.
public enum SpaceApps {
    /// Windows smaller than this (in points, either side) are skipped: they are
    /// usually invisible helpers, not something the user thinks of as a window.
    public static let minimumSide: Double = 40

    /// Picks the normal app windows out of the raw window-server window list
    /// result, front to back. Checks every type; skips anything unexpected.
    public static func windows(from raw: [Any], excludingPID ownPID: Int32) -> [WindowEntry] {
        raw.compactMap { item -> WindowEntry? in
            guard let info = item as? [String: Any],
                  let number = (info["kCGWindowNumber"] as? NSNumber)?.uint32Value,
                  let pid = (info["kCGWindowOwnerPID"] as? NSNumber)?.int32Value,
                  pid != ownPID,
                  (info["kCGWindowLayer"] as? NSNumber)?.intValue == 0 else { return nil }
            if let alpha = (info["kCGWindowAlpha"] as? NSNumber)?.doubleValue, alpha <= 0 { return nil }
            guard let bounds = info["kCGWindowBounds"] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue,
                  width >= minimumSide, height >= minimumSide else { return nil }
            return WindowEntry(windowID: number, ownerPID: pid)
        }
    }

    /// The apps (process ids) with a window on `spaceID`, front-most first, each once.
    /// - Parameter spaces: the Spaces a window is on (empty when unknown).
    public static func apps(on spaceID: UInt64, windows: [WindowEntry],
                            spaces: (UInt32) -> [UInt64]) -> [Int32] {
        var seen = Set<Int32>()
        var result: [Int32] = []
        for window in windows where !seen.contains(window.ownerPID) && spaces(window.windowID).contains(spaceID) {
            seen.insert(window.ownerPID)
            result.append(window.ownerPID)
        }
        return result
    }
}
