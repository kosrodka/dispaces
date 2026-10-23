import Foundation

/// What the "Manage displays and spaces" window shows: one bar per display,
/// connected displays first (in macOS's display order), then disconnected ones
/// (most recently seen first), each with its Spaces.
public struct DisplayOverview: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        /// Desktop number, "FS" for a full-screen Space, "–" when not found.
        public let number: String
        public let name: String
        /// E.g. "current", "now on Built-in Display", "not found".
        public let note: String?
        /// macOS's id for the live Space; nil when it wasn't found.
        public let spaceID: UInt64?
        /// Identifier of the connected display the live Space is on now.
        public let onDisplay: String?
        public let isCurrent: Bool
        public let isFullScreen: Bool
        /// Set on the rows of a disconnected display: what the app remembers.
        public let remembered: DisplayMemory.RememberedSpace?

        public init(number: String, name: String, note: String?, spaceID: UInt64? = nil, onDisplay: String? = nil,
                    isCurrent: Bool = false, isFullScreen: Bool = false,
                    remembered: DisplayMemory.RememberedSpace? = nil) {
            self.number = number
            self.name = name
            self.note = note
            self.spaceID = spaceID
            self.onDisplay = onDisplay
            self.isCurrent = isCurrent
            self.isFullScreen = isFullScreen
            self.remembered = remembered
        }
    }

    public struct Section: Equatable, Sendable {
        public let identifier: String
        public let name: String
        public let connected: Bool
        /// When a disconnected display was last connected, seconds since 1970.
        public let lastSeen: Double?
        public let rows: [Row]
    }

    public let sections: [Section]

    /// A Space's name: the user's name for it (under its current key, or the key
    /// it had on its own display), otherwise the default "Desktop N".
    public static func spaceName(_ space: Space, names: Names, remembered: DisplayMemory.RememberedSpace?,
                                 fallbackAppName: String? = nil) -> String {
        if let custom = names.spaces[space.nameKey] { return custom }
        if let key = remembered?.key, let custom = names.spaces[key] { return custom }
        return Names.defaultName(for: space, fallbackAppName: fallbackAppName)
    }

    /// The name of a disconnected display: the user's name for it, else the name it had.
    public static func displayName(_ record: DisplayMemory.Record, names: Names) -> String {
        names.displays[record.nameKey] ?? record.name
    }

    /// True when a disconnected display's Space (`ghost`) can be moved to the
    /// connected display `identifier`. Moving only changes the app's grouping,
    /// so the ghost's live Space must already be on that display: macOS gives
    /// apps no way to move a Space to another display.
    public static func canMove(_ ghost: Row, to identifier: String) -> Bool {
        ghost.remembered != nil && ghost.onDisplay == identifier
    }

    /// - Parameters:
    ///   - screenOrder: display identifiers in macOS's display order;
    ///     connected displays are listed in that order (unknown ones last).
    ///   - showsFirstSpace: false for a display whose first Space is hidden.
    public init(snapshot: Snapshot, memory: DisplayMemory, names: Names, screenOrder: [String] = [],
                showsFirstSpace: (String) -> Bool = { _ in true }, displayName: (Display) -> String) {
        let ghosts = memory.disconnected(in: snapshot)
        let shared = snapshot.displays.contains(where: \.spansAllDisplays)
        var sections: [Section] = []

        let order = screenOrder.map { $0.lowercased() }
        let rank = { (display: Display) in order.firstIndex(of: display.identifier.lowercased()) ?? order.count }
        let displays = snapshot.displays.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)

        for display in displays {
            let hidden = showsFirstSpace(display.identifier) ? nil : display.spaces.first?.managedID
            let rows = display.spaces
                .filter { $0.managedID != hidden }
                .filter { shared || memory.ghostOwner(of: $0, in: snapshot) == nil }
                .map { space in
                    let current = display.currentSpaceID == space.managedID
                    return Row(number: space.numberLabel, name: Self.spaceName(space, names: names, remembered: nil),
                               note: current ? "current" : nil, spaceID: space.managedID,
                               onDisplay: display.identifier, isCurrent: current,
                               isFullScreen: space.kind == .fullscreen)
                }
            sections.append(Section(identifier: display.identifier, name: displayName(display),
                                    connected: true, lastSeen: nil, rows: rows))
        }

        for record in shared ? [] : ghosts {
            let spaces = showsFirstSpace(record.identifier) ? record.spaces : Array(record.spaces.dropFirst())
            let rows = spaces.map { remembered -> Row in
                for display in snapshot.displays {
                    if let space = display.spaces.first(where: remembered.matches) {
                        return Row(number: space.numberLabel,
                                   name: Self.spaceName(space, names: names, remembered: remembered),
                                   note: "now on " + displayName(display), spaceID: space.managedID,
                                   onDisplay: display.identifier, isFullScreen: space.kind == .fullscreen,
                                   remembered: remembered)
                    }
                }
                return Row(number: "–", name: names.spaces[remembered.key] ?? remembered.name, note: "not found",
                           remembered: remembered)
            }
            sections.append(Section(identifier: record.identifier, name: Self.displayName(record, names: names),
                                    connected: false, lastSeen: record.lastSeen, rows: rows))
        }
        self.sections = sections
    }
}
