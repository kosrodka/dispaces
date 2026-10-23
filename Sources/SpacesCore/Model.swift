import Foundation

/// What kind of Space macOS reports.
public enum SpaceKind: Equatable, Sendable {
    /// A normal desktop ("Desktop N" in Mission Control). Space list type 0.
    case desktop
    /// A full-screen app or split-view Space. Space list type 4.
    case fullscreen
}

public struct Space: Equatable, Sendable {
    /// macOS's id for the Space. Changes after a reboot, so never stored.
    public let managedID: UInt64
    /// macOS's UUID for the Space. Empty for the first desktop of a display.
    public let uuid: String
    public let kind: SpaceKind
    /// Global "Switch to Desktop N" number (1-based, counted across displays). Desktops only.
    public let desktopNumber: Int?
    /// 0-based position among the Spaces of its display, in Mission Control order.
    public let indexOnDisplay: Int
    /// Name of the app filling a full-screen Space, when macOS reports it.
    public let appName: String?
    /// Process id of the app filling a full-screen Space, when macOS reports it.
    public let ownerPID: Int32?
    /// Stable key used to remember the user's name for this Space.
    public let nameKey: String

    public init(managedID: UInt64, uuid: String, kind: SpaceKind, desktopNumber: Int?,
                indexOnDisplay: Int, appName: String?, ownerPID: Int32?, nameKey: String) {
        self.managedID = managedID
        self.uuid = uuid
        self.kind = kind
        self.desktopNumber = desktopNumber
        self.indexOnDisplay = indexOnDisplay
        self.appName = appName
        self.ownerPID = ownerPID
        self.nameKey = nameKey
    }

    /// The number a tile shows: the desktop number, or "FS" for a full-screen Space.
    public var numberLabel: String { desktopNumber.map(String.init) ?? "FS" }
}

public struct Display: Equatable, Sendable {
    /// Display UUID, or "Main" when "Displays have separate Spaces" is off.
    public let identifier: String
    /// The Space currently shown on this display, if macOS reported one.
    public let currentSpaceID: UInt64?
    public let spaces: [Space]

    public init(identifier: String, currentSpaceID: UInt64?, spaces: [Space]) {
        self.identifier = identifier
        self.currentSpaceID = currentSpaceID
        self.spaces = spaces
    }

    /// True when the Space list covers all displays at once.
    public var spansAllDisplays: Bool { identifier == Display.combinedIdentifier }

    public static let combinedIdentifier = "Main"

    public var nameKey: String { "display:" + identifier }
}

/// Everything the bar shows, read in one go.
public struct Snapshot: Equatable, Sendable {
    public let displays: [Display]
    /// The Space that has focus, i.e. the current Space of the display you are using.
    public let activeSpaceID: UInt64?

    public init(displays: [Display], activeSpaceID: UInt64? = nil) {
        self.displays = displays
        self.activeSpaceID = activeSpaceID
    }

    /// The display you are using, when macOS told us which Space has focus.
    public var focusedDisplay: Display? {
        guard let active = activeSpaceID else { return nil }
        return displays.first { $0.currentSpaceID == active }
    }

    public static let empty = Snapshot(displays: [])

    public var isEmpty: Bool { displays.allSatisfy { $0.spaces.isEmpty } }

    /// Finds a Space and the display that owns it.
    public func locate(spaceID: UInt64) -> (display: Display, space: Space)? {
        for display in displays {
            if let space = display.spaces.first(where: { $0.managedID == spaceID }) {
                return (display, space)
            }
        }
        return nil
    }

    /// Number of desktops (not full-screen Spaces) across all displays.
    public var desktopCount: Int {
        displays.reduce(0) { $0 + $1.spaces.filter { $0.kind == .desktop }.count }
    }
}
