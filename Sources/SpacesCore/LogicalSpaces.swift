import Foundation

/// What a tile in the menu bar (or a heading in the Manage window) stands for.
public enum TileTarget: Hashable, Sendable {
    /// A logical space, by its `LogicalSpaces.Column.key`.
    case logical(String)
    /// One Space on one display (a full-screen app's Space, or an unplugged display's Space).
    case space(UInt64)
}

/// Spaces with the same name on different displays form one logical space.
///
/// Clicking a logical space switches every display that has a Space in it.
/// Nothing is stored: the grouping is worked out from the Space names each
/// time, so renaming a Space moves it to another logical space. A Space
/// nobody named ("Desktop N") is a logical space of its own.
public struct LogicalSpaces: Equatable, Sendable {
    /// One display's Space in a logical space.
    public struct Cell: Equatable, Sendable {
        /// Display identifier.
        public let display: String
        public let space: Space
        /// The display is showing this Space now.
        public let isCurrent: Bool

        public init(display: String, space: Space, isCurrent: Bool) {
            self.display = display
            self.space = space
            self.isCurrent = isCurrent
        }
    }

    public enum State: Equatable, Sendable {
        /// Every display with a Space in it shows that Space.
        case all
        /// Some displays show it, others show something else.
        case some
        case none
    }

    public struct Column: Equatable, Sendable {
        /// Stable while the names don't change: the folded name, plus a
        /// counter for a second Space with the same name on one display.
        public let key: String
        /// 1-based position, as the tile shows it.
        public let number: Int
        /// The name as the first Space in the column spells it.
        public let title: String
        /// At most one per display, in display order.
        public let cells: [Cell]
        public let state: State
        /// Set on a column started by a second Space with the same name on one
        /// display: that display's identifier.
        public let duplicateOn: String?

        public func cell(on display: String) -> Cell? {
            cells.first { $0.display.caseInsensitiveCompare(display) == .orderedSame }
        }

        /// The first name the user gave one of its Spaces, if any. Offered when
        /// renaming, so an unnamed logical space isn't stored as "Desktop N"
        /// (which would stop following the desktop's number).
        public func customName(in names: Names) -> String? {
            cells.lazy.compactMap { names.storedName(forSpaceKey: $0.space.nameKey) }.first
        }
    }

    public let columns: [Column]
    /// Full-screen Spaces, which belong to no logical space (macOS can only
    /// step to them on the display under the pointer). Display order.
    public let fullScreen: [Cell]

    /// - Parameters:
    ///   - screenOrder: display identifiers in macOS's display order (main display first).
    ///   - showsFirstSpace: false for a display whose first Space is hidden.
    public init(snapshot: Snapshot, memory: DisplayMemory, names: Names, screenOrder: [String],
                showsFirstSpace: (String) -> Bool) {
        struct Draft {
            let key: String
            let title: String
            var cells: [Cell]
            let duplicateOn: String?
        }
        var drafts: [Draft] = []
        var byGroupingKey: [String: [Int]] = [:]
        var fullScreen: [Cell] = []

        for display in Self.orderedDisplays(snapshot, screenOrder: screenOrder) {
            let hidden = showsFirstSpace(display.identifier) ? nil : display.spaces.first?.managedID
            var filled = Set<Int>()
            for space in display.spaces where space.managedID != hidden {
                if !display.spansAllDisplays, memory.ghostOwner(of: space, in: snapshot) != nil { continue }
                let cell = Cell(display: display.identifier, space: space,
                                isCurrent: display.currentSpaceID == space.managedID)
                guard space.kind == .desktop else {
                    fullScreen.append(cell)
                    continue
                }
                let title = DisplayOverview.spaceName(space, names: names, remembered: nil)
                let grouping = Self.groupingKey(title)
                let existing = byGroupingKey[grouping] ?? []
                if let index = existing.first(where: { !filled.contains($0) }) {
                    drafts[index].cells.append(cell)
                    filled.insert(index)
                } else {
                    // A second Space with this name on this display starts its own column.
                    let key = existing.isEmpty ? grouping : grouping + "\u{1F}" + String(existing.count + 1)
                    drafts.append(Draft(key: key, title: title, cells: [cell],
                                        duplicateOn: existing.isEmpty ? nil : display.identifier))
                    byGroupingKey[grouping, default: []].append(drafts.count - 1)
                    filled.insert(drafts.count - 1)
                }
            }
        }

        columns = drafts.enumerated().map { offset, draft in
            let shown = draft.cells.filter(\.isCurrent).count
            let state: State = shown == 0 ? .none : (shown == draft.cells.count ? .all : .some)
            return Column(key: draft.key, number: offset + 1, title: draft.title, cells: draft.cells,
                          state: state, duplicateOn: draft.duplicateOn)
        }
        self.fullScreen = fullScreen
    }

    public func column(key: String) -> Column? {
        columns.first { $0.key == key }
    }

    /// Names are compared ignoring case ("home" joins "Home").
    public static func groupingKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive], locale: nil)
    }

    /// Connected displays in macOS's display order (unknown ones last, in the
    /// order macOS lists them).
    public static func orderedDisplays(_ snapshot: Snapshot, screenOrder: [String]) -> [Display] {
        let order = screenOrder.map { $0.lowercased() }
        let rank = { (display: Display) in order.firstIndex(of: display.identifier.lowercased()) ?? order.count }
        return snapshot.displays.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }
}
