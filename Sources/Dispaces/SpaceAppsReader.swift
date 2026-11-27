import AppKit
import CGSPrivate
import SpacesCore

/// Which apps have windows on a Space, for the hover icons. Read-only.
///
/// The only code that reads the window list (`source-check.sh` keeps it here).
/// It looks at each window's number and owning process only, never its title
/// or contents, so it needs no Screen Recording permission. Nothing it reads
/// is stored.
@MainActor
enum SpaceAppsReader {
    /// `CGSCopySpacesForWindows` mask for "any Space".
    private static let allSpaces: Int32 = 7

    static func apps(on spaceID: UInt64) -> [NSRunningApplication] {
        apps(on: [spaceID])[spaceID] ?? []
    }

    /// The apps on each of several Spaces (a logical space), reading the window
    /// list once and asking each window's Spaces once.
    static func apps(on spaceIDs: [UInt64]) -> [UInt64: [NSRunningApplication]] {
        guard !spaceIDs.isEmpty,
              let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [Any] else {
            return [:]
        }
        let windows = SpaceApps.windows(from: raw, excludingPID: ProcessInfo.processInfo.processIdentifier)
        let connection = CGSMainConnectionID()
        var known: [UInt32: [UInt64]] = [:]
        let spaces = { (windowID: UInt32) -> [UInt64] in
            if let cached = known[windowID] { return cached }
            var result: [UInt64] = []
            if let list: CFArray = CGSCopySpacesForWindows(connection, allSpaces, [NSNumber(value: windowID)] as CFArray) {
                result = (list as NSArray).compactMap { ($0 as? NSNumber)?.uint64Value }
            }
            known[windowID] = result
            return result
        }
        var result: [UInt64: [NSRunningApplication]] = [:]
        for spaceID in spaceIDs {
            result[spaceID] = SpaceApps.apps(on: spaceID, windows: windows, spaces: spaces)
                .compactMap { NSRunningApplication(processIdentifier: $0) }
                .filter { $0.activationPolicy == .regular }
        }
        return result
    }
}
