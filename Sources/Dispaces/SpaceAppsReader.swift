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
        guard let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [Any] else {
            return []
        }
        let windows = SpaceApps.windows(from: raw, excludingPID: ProcessInfo.processInfo.processIdentifier)
        let connection = CGSMainConnectionID()
        let pids = SpaceApps.apps(on: spaceID, windows: windows) { windowID in
            guard let spaces: CFArray = CGSCopySpacesForWindows(connection, allSpaces, [NSNumber(value: windowID)] as CFArray) else {
                return []
            }
            return (spaces as NSArray).compactMap { ($0 as? NSNumber)?.uint64Value }
        }
        return pids.compactMap { NSRunningApplication(processIdentifier: $0) }
            .filter { $0.activationPolicy == .regular }
    }
}
