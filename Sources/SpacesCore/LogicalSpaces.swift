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
///
/// An unplugged display's Spaces, which macOS moved onto a connected display,
/// stay in their logical spaces as that display's cells (after the connected
/// displays, so the numbers don't change).
public struct LogicalSpaces: Equatable, Sendable {
    /// One display's Space in a logical space.
    public struct Cell: Equatable, Sendable {
        /// The display it belongs to (an unplugged display's, for its Spaces).
        public let display: String
        public let space: Space
        /// The display macOS has it on now, which is showing it when `isCurrent`.
        /// The same as `display`, unless that display is unplugged.
        public let onDisplay: String
        /// Its display (`onDisplay`) is showing this Space now.
        public let isCurrent: Bool

        public init(display: String, space: Space, isCurrent: Bool, onDisplay: String? = nil) {
            self.display = display
            self.space = space
            self.isCurrent = isCurrent
            self.onDisplay = onDisplay ?? display
        }

        /// It belongs to an unplugged display (macOS moved it to `onDisplay`).
        public var isDisconnected: Bool {
            display.caseInsensitiveCompare(onDisplay) != .orderedSame
        }
    }

    /// How a tile is coloured, seen from one display (the one you're working on).
    public enum Highlight: Equatable, Sendable {
        /// That display shows it: strong.
        case here
        /// Only other displays show it: pale. Flags that the displays differ.
        case elsewhere
        case none
    }

    /// A single Space's highlight: shown on `display`, seen from `seenFrom`
    /// (nil when it isn't known which display has the focus: showing counts as here).
    public static func highlight(isCurrent: Bool, on display: String, seenFrom: String?) -> Highlight {
        guard isCurrent else { return .none }
        guard let seenFrom else { return .here }
        return display.caseInsensitiveCompare(seenFrom) == .orderedSame ? .here : .elsewhere
    }

    public enum State: Equatable, Sendable {
        /// Every display with a Space in it shows one of its Spaces.
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

        /// The display's cell (an unplugged display's too).
        public func cell(on display: String) -> Cell? {
            cells.first { $0.display.caseInsensitiveCompare(display) == .orderedSame }
        }

        /// It has an unplugged display's Space: the apps column then offers a
        /// tile per display, to go to that display's Space of it.
        public var includesUnplugged: Bool {
            cells.contains(where: \.isDisconnected)
        }

        /// The Spaces a click switches: each connected display's own Space in
        /// it. An unplugged display's Space stays where it is (the display
        /// macOS moved it to shows its own), unless no connected display has
        /// one: then those are shown where they are, one per display.
        public var switchCells: [Cell] {
            let connected = cells.filter { !$0.isDisconnected }
            guard connected.isEmpty else { return connected }
            var seen = Set<String>()
            return cells.filter { seen.insert($0.onDisplay.lowercased()).inserted }
        }

        /// The Space a click switches on `display` (the display it's on now).
        public func switchCell(on display: String) -> Cell? {
            switchCells.first { $0.onDisplay.caseInsensitiveCompare(display) == .orderedSame }
        }

        /// Seen from `display`: `.here` when that display shows a Space of this
        /// logical space (an unplugged display's Space counts where it is now),
        /// `.elsewhere` when only other displays do.
        public func highlight(seenFrom display: String?) -> Highlight {
            let shown = cells.map { LogicalSpaces.highlight(isCurrent: $0.isCurrent, on: $0.onDisplay, seenFrom: display) }
            if shown.contains(.here) { return .here }
            return shown.contains(.elsewhere) ? .elsewhere : .none
        }

        /// Where its tile label is stored: its key. Nil for a column started by a
        /// second Space with the same name on one display (rename it to give it one).
        public var labelKey: String? {
            duplicateOn == nil ? key : nil
        }

        /// What its tile shows: the user's tile label ("Tile displayed"), or its number.
        public func displayed(in names: Names) -> String {
            labelKey.flatMap(names.label(forLogicalKey:)) ?? String(number)
        }

        /// Renaming the logical space: every Space in it gets `typed`, and its tile
        /// label moves to the new name, unless that name has a label already (it
        /// keeps its own). A cleared name leaves the label stored under the old one.
        public func renameChange(to typed: String, names: Names) -> NameChange {
            var change = NameChange(spaces: Dictionary(cells.map { ($0.space.nameKey, typed) },
                                                       uniquingKeysWith: { first, _ in first }))
            let newKey = LogicalSpaces.groupingKey(NameSanitizer.sanitize(typed))
            if let oldKey = labelKey, let label = names.label(forLogicalKey: oldKey),
               !newKey.isEmpty, newKey != oldKey, names.label(forLogicalKey: newKey) == nil {
                change.labels = [newKey: label, oldKey: ""]
            }
            return change
        }

        /// One of its Spaces' own colour (the Manage window shows Spaces): `.here`
        /// when that Space is on screen, `.elsewhere` when another Space of this
        /// logical space is (on any display, an unplugged display's too).
        public func highlight(of cell: Cell) -> Highlight {
            if cell.isCurrent { return .here }
            return cells.contains(where: \.isCurrent) ? .elsewhere : .none
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
    ///   - showsFirstSpace: false for a display whose first Space is hidden
    ///     (asked for unplugged displays too).
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

        /// Puts a cell in the first column with its name that its display hasn't
        /// filled yet (`filled`), or starts a column.
        func place(_ cell: Cell, title: String, filled: inout Set<Int>) {
            let grouping = Self.groupingKey(title)
            let existing = byGroupingKey[grouping] ?? []
            if let index = existing.first(where: { !filled.contains($0) }) {
                drafts[index].cells.append(cell)
                filled.insert(index)
            } else {
                // A second Space with this name on this display starts its own column.
                let key = existing.isEmpty ? grouping : grouping + "\u{1F}" + String(existing.count + 1)
                drafts.append(Draft(key: key, title: title, cells: [cell],
                                    duplicateOn: existing.isEmpty ? nil : cell.display))
                byGroupingKey[grouping, default: []].append(drafts.count - 1)
                filled.insert(drafts.count - 1)
            }
        }

        // Unplugged displays' Spaces, by display in the order they turn up.
        var moved: [(owner: DisplayMemory.Record, cell: Cell, title: String)] = []
        for display in Self.orderedDisplays(snapshot, screenOrder: screenOrder) {
            let hidden = showsFirstSpace(display.identifier) ? nil : display.spaces.first?.managedID
            var filled = Set<Int>()
            for space in display.spaces where space.managedID != hidden {
                let isCurrent = display.currentSpaceID == space.managedID
                guard space.kind == .desktop else {
                    fullScreen.append(Cell(display: display.identifier, space: space, isCurrent: isCurrent))
                    continue
                }
                if !display.spansAllDisplays, let owner = memory.ghostOwner(of: space, in: snapshot) {
                    let remembered = owner.spaces.first { $0.matches(space) }
                    // The unplugged display's own first Space follows the first-Space rule.
                    if let first = owner.spaces.first, first == remembered, !showsFirstSpace(owner.identifier) { continue }
                    moved.append((owner, Cell(display: owner.identifier, space: space, isCurrent: isCurrent,
                                              onDisplay: display.identifier),
                                  DisplayOverview.spaceName(space, names: names, remembered: remembered)))
                    continue
                }
                place(Cell(display: display.identifier, space: space, isCurrent: isCurrent),
                      title: DisplayOverview.spaceName(space, names: names, remembered: nil), filled: &filled)
            }
        }
        var owners: [String] = []
        for entry in moved where !owners.contains(entry.owner.identifier) { owners.append(entry.owner.identifier) }
        for owner in owners {
            var filled = Set<Int>()
            for entry in moved where entry.owner.identifier == owner {
                place(entry.cell, title: entry.title, filled: &filled)
            }
        }

        columns = drafts.enumerated().map { offset, draft in
            // Shown on a display when it shows one of its Spaces there.
            let displays = Set(draft.cells.map { $0.onDisplay.lowercased() })
            let showing = Set(draft.cells.filter(\.isCurrent).map { $0.onDisplay.lowercased() })
            let state: State = showing.isEmpty ? .none : (showing.count == displays.count ? .all : .some)
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
