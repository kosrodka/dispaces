import AppKit
import SpacesCore

/// Keeps the Spaces in the menu bar in sync with the snapshot: one menu bar
/// item with a square tile per logical space (the Spaces with one name across
/// displays, unplugged displays' too), then the full-screen Spaces. When macOS isn't showing the item (no room
/// beside the notch, a hidden menu bar, switched off in System Settings), a
/// small floating bar with the same tiles stands in, unless the user turned
/// that off.
@MainActor
final class BarController {
    private let menuItem = MenuBarItem()
    private let fallback = FallbackBar()
    private let messagePanel = MessagePanel()
    private let appsPanel = AppsPanel()
    /// The tile whose apps are showing (or about to), and the pending show.
    private var hoveredTarget: TileTarget?
    private var hoverWork: DispatchWorkItem?
    private let prefs: Preferences
    private let switcher: SpaceSwitcher
    private let monitor: SpaceMonitor

    private var snapshot = Snapshot.empty
    private var content = TilesContent()
    /// The logical spaces the tiles show, worked out on every redraw.
    private(set) var logical = LogicalSpaces(snapshot: .empty, memory: DisplayMemory(), names: Names(),
                                             screenOrder: [], showsFirstSpace: { _ in true })
    /// The display you're working on (the one with the focus); tiles are coloured as seen from it.
    private(set) var focusedDisplay: String?
    private var failedTarget: TileTarget?
    private var failedClear: DispatchWorkItem?
    /// Option-Control drag: the tile a held window is resting on.
    private var arming = DragArming()
    private var dragTimer: Timer?
    /// Checks every few seconds whether the menu bar item is on screen.
    private var fallbackTimer: Timer?
    private var fallbackWork: DispatchWorkItem?
    /// The item must be gone this long before the fallback bar shows, so the
    /// menu bar sliding in and out doesn't make it flicker.
    static let fallbackDelay: TimeInterval = 1
    var needsAttention: () -> Bool = { false }
    var onWarningClick: (() -> Void)?
    /// Open the app's menu under a view; the tile that was right-clicked, if any.
    var onMenu: ((NSView) -> Void)?

    init(prefs: Preferences, monitor: SpaceMonitor, switcher: SpaceSwitcher) {
        self.prefs = prefs
        self.monitor = monitor
        self.switcher = switcher
        appsPanel.onExit = { [weak self] in self?.hideAppsSoon() }
        for view in [menuItem.view, fallback.tiles] {
            view.onClick = { [weak self] target, thisDisplayOnly in self?.click(target, thisDisplayOnly: thisDisplayOnly) }
            view.onWarning = { [weak self] in self?.onWarningClick?() }
            view.onMenu = { [weak self, weak view] _ in
                guard let self, let view else { return }
                self.hideApps()
                self.onMenu?(view)
            }
            view.onHover = { [weak self] tile, inside in self?.hover(tile, inside: inside) }
        }
        menuItem.onVisibilityChange = { [weak self] in self?.checkFallback() }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFallback() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }

    // MARK: Model

    func show(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        rebuild()
        onChange?()
    }

    func redraw() {
        rebuild()
        onChange?()
    }

    /// Called after the Spaces, names or remembered displays may have changed.
    var onChange: (() -> Void)?

    /// Display identifiers in macOS's display order (the menu-bar display first).
    private static func screenOrder() -> [String] {
        NSScreen.screens.compactMap(Screens.identifier(of:))
    }

    // MARK: Displays and Spaces window

    /// Every display with its Spaces: connected ones first, in macOS's display
    /// order (the menu-bar display first), then disconnected ones.
    func overview() -> DisplayOverview {
        DisplayOverview(snapshot: snapshot, memory: prefs.memory, names: prefs.names,
                        screenOrder: Self.screenOrder(),
                        showsFirstSpace: { self.showsFirstSpace($0) }) { [names = prefs.names] in
            Self.displayName($0, names: names)
        }
    }

    /// Takes a Space out of a disconnected display's group; it joins the group of
    /// the display it's on. Only the app's own memory changes.
    /// Returns where the Space was in the group (for undo), or nil if nothing changed.
    @discardableResult
    func removeGhostSpace(_ space: DisplayMemory.RememberedSpace, from identifier: String) -> Int? {
        let index = prefs.memory.records[identifier]?.spaces.firstIndex(of: space)
        var removed = false
        prefs.updateMemory { memory in
            removed = memory.removeSpace(space, from: identifier, snapshot: snapshot)
            return removed
        }
        redraw()
        return removed ? index : nil
    }

    /// Undo of `removeGhostSpace`.
    func putBackGhostSpace(_ space: DisplayMemory.RememberedSpace, at index: Int, into identifier: String) {
        prefs.updateMemory { $0.insertSpace(space, at: index, into: identifier, snapshot: snapshot) }
        redraw()
    }

    /// Whether a display's first Space is shown (in the menu bar, the logical
    /// spaces and the Manage window): the built-in display's yes, external
    /// displays' no, unless changed in the preferences file.
    func showsFirstSpace(_ identifier: String) -> Bool {
        prefs.firstSpaceRule.isShown(identifier: identifier, builtIn: isBuiltIn(identifier))
    }

    /// A connected display asks macOS; an unplugged one goes by what was remembered.
    private func isBuiltIn(_ identifier: String) -> Bool {
        Screens.isBuiltIn(identifier) ?? prefs.memory.records[identifier]?.builtIn ?? false
    }

    /// Tiles shown outside the menu bar (the Manage window), for the hover column.
    var extraTile: ((NSPoint) -> HoverTile?)?

    /// Forgets a disconnected display; its Spaces join the display they're on.
    /// Returns what was forgotten (for undo), or nil if nothing changed.
    @discardableResult
    func forgetDisplay(_ identifier: String) -> DisplayMemory.Record? {
        let record = prefs.memory.records[identifier]
        var forgotten = false
        prefs.updateMemory { memory in
            forgotten = memory.forget(identifier, snapshot: snapshot)
            return forgotten
        }
        redraw()
        return forgotten ? record : nil
    }

    /// Undo of `forgetDisplay`.
    func restoreDisplay(_ record: DisplayMemory.Record) {
        prefs.updateMemory { $0.restore(record, snapshot: snapshot) }
        redraw()
    }

    private func rebuild() {
        var content = TilesContent()
        content.warning = needsAttention() || snapshot.isEmpty
        if snapshot.isEmpty {
            content.summary = "Dispaces: can't read the Space list"
        } else {
            let names = prefs.names
            let now = Date().timeIntervalSince1970
            prefs.updateMemory { memory in
                memory.update(with: snapshot,
                              displayName: { Self.displayName($0, names: names) },
                              spaceName: { names.name(for: $0) },
                              isBuiltIn: { Screens.isBuiltIn($0.identifier) ?? false }, now: now)
            }
            focusedDisplay = Self.focusedDisplay(in: snapshot)
            logical = LogicalSpaces(snapshot: snapshot, memory: prefs.memory, names: names,
                                    screenOrder: Self.screenOrder(), showsFirstSpace: { self.showsFirstSpace($0) })
            content.runs.append(.init(count: logical.columns.count, spacing: .group))
            content.entries += logical.columns.map { .init(tile: logicalTile($0, names: names)) }
            content.runs.append(.init(count: logical.fullScreen.count, spacing: .group))
            content.entries += logical.fullScreen.map {
                .init(tile: spaceTile($0.space, current: $0.isCurrent, on: $0.display, names: names))
            }
            let current = content.entries.filter { $0.tile.state != .normal }.map(\.tile.name)
            content.summary = "Dispaces Spaces" + (current.isEmpty ? "" : ", current: " + current.joined(separator: ", "))
        }
        self.content = content
        // With apps on hover, the column shows the Space's name instead of a tooltip.
        let tips = !prefs.showAppsOnHover
        menuItem.update(content, showsToolTips: tips)
        fallback.update(content, showsToolTips: tips)
        // Tiles were redrawn: drop the column if the pointer isn't on that tile any more.
        if hoveredTarget != nil, !pointerOnApps() {
            hideApps()
        }
        checkFallback()
    }

    private func logicalTile(_ column: LogicalSpaces.Column, names: Names) -> TileModel {
        let target = TileTarget.logical(column.key)
        var label = "\(column.title), logical space \(column.number)"
        switch column.state {
        case .all:
            label += Set(column.cells.map { $0.onDisplay.lowercased() }).count > 1 ? ", on all displays" : ", current"
        case .some:
            label += ", on " + column.cells.filter(\.isCurrent).map { displayName(of: $0.onDisplay, names: names) }
                .joined(separator: ", ")
        case .none:
            break
        }
        return TileModel(target: target, number: column.displayed(in: names), name: column.title,
                         state: TileModel.State(column.highlight(seenFrom: focusedDisplay)),
                         isFullScreen: false, failed: failedTarget == target, armed: arming.armed == target,
                         accessibilityLabel: label)
    }

    private func spaceTile(_ space: Space, current: Bool, on display: String, names: Names) -> TileModel {
        let target = TileTarget.space(space.managedID)
        let name = DisplayOverview.spaceName(space, names: names, remembered: nil,
                                             fallbackAppName: Self.fullScreenAppName(space))
        let kind = space.kind == .desktop ? "Desktop \(space.numberLabel)" : "Full-screen Space"
        let state = TileModel.State(LogicalSpaces.highlight(isCurrent: current, on: display, seenFrom: focusedDisplay))
        return TileModel(target: target, number: space.numberLabel, name: name, state: state,
                         isFullScreen: space.kind == .fullscreen, failed: failedTarget == target,
                         armed: arming.armed == target,
                         accessibilityLabel: "\(kind), \(name)" + (current ? ", current on its display" : ""))
    }

    /// The display you're working on: the one showing the Space that has the
    /// focus, else the screen macOS calls main, else the first display.
    private static func focusedDisplay(in snapshot: Snapshot) -> String? {
        if let display = snapshot.focusedDisplay { return display.identifier }
        let main = Screens.focusedIdentifier()
        return (snapshot.displays.first { Screens.matches(main, $0) }
            ?? LogicalSpaces.orderedDisplays(snapshot, screenOrder: screenOrder()).first)?.identifier
    }

    /// A display's name: the user's, else the one macOS gives it.
    private static func displayName(_ display: Display, names: Names) -> String {
        names.name(for: display, defaultName: Screens.defaultName(for: display))
    }

    /// A connected or unplugged display's name.
    private func displayName(of identifier: String, names: Names) -> String {
        if let display = snapshot.displays.first(where: { $0.identifier == identifier }) {
            return Self.displayName(display, names: names)
        }
        return prefs.memory.disconnected(in: snapshot).first { $0.identifier == identifier }
            .map { DisplayOverview.displayName($0, names: names) } ?? identifier
    }

    /// The app filling a full-screen Space, when macOS reports its process.
    private static func fullScreenAppName(_ space: Space) -> String? {
        space.ownerPID.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
    }

    func hasCustomName(displayKey: String) -> Bool {
        prefs.names.displays[displayKey] != nil
    }

    func refreshNow() {
        monitor.refresh()
    }

    // MARK: Fallback bar

    /// "Floating bar when the menu bar item is hidden" (Manage window › Advanced).
    var showsFallback: Bool { prefs.fallbackBar }

    func setShowsFallback(_ on: Bool) {
        prefs.fallbackBar = on
        checkFallback()
    }

    /// Shows the fallback bar once the menu bar item has been off screen for
    /// `fallbackDelay`; hides it as soon as the item is back.
    private func checkFallback() {
        guard prefs.fallbackBar, !menuItem.isShowing else {
            fallbackWork?.cancel()
            fallbackWork = nil
            if fallback.isVisible {
                fallback.orderOut(nil)
                if let target = hoveredTarget, fallback.tiles.content.entries.contains(where: { $0.tile.target == target }) {
                    hideApps()
                }
            }
            return
        }
        guard !fallback.isVisible, fallbackWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.fallbackWork = nil
                if self.prefs.fallbackBar && !self.menuItem.isShowing { self.fallback.showBar() }
            }
        }
        fallbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fallbackDelay, execute: work)
    }

    /// The tile rows on screen now: the menu bar item's and, while shown, the fallback bar's.
    private var visibleRows: [SpaceTilesView] {
        var rows: [SpaceTilesView] = []
        if menuItem.isShowing { rows.append(menuItem.view) }
        if fallback.isVisible { rows.append(fallback.tiles) }
        return rows
    }

    // MARK: Apps on hover

    var showsAppsOnHover: Bool { prefs.showAppsOnHover }

    func setShowsAppsOnHover(_ on: Bool) {
        prefs.showAppsOnHover = on
        if !on { hideApps() }
        redraw()
    }

    /// Shows the apps on a tile's Space(s) after a short rest, so sweeping across the tiles stays quiet.
    /// The column stays while the pointer is on the tile or on the column.
    func hover(_ tile: HoverTile, inside: Bool) {
        let target = tile.target
        guard inside else {
            if hoveredTarget == target { hideAppsSoon() }
            return
        }
        // Back on the tile from its own column: keep it.
        if hoveredTarget == target && appsPanel.isVisible { return }
        hideApps()
        guard prefs.showAppsOnHover, NSEvent.pressedMouseButtons == 0 else { return }
        hoveredTarget = target
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hoveredTarget == target, NSEvent.pressedMouseButtons == 0,
                      self.pointerIsOn(target) else { return }
                self.appsPanel.onPick = { [weak self] app, section in self?.bringToFront(app, on: target, in: section) }
                self.appsPanel.onChoose = { [weak self] spaceID in self?.click(spaceID, flashing: target) }
                self.appsPanel.show(title: tile.name, choices: self.displayChoices(for: target),
                                    sections: self.appSections(for: target), tile: tile.frame, screen: tile.screen)
            }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// A tile per display for a logical space that has an unplugged display's
    /// Space (in the order of the sections below them); none otherwise.
    private func displayChoices(for target: TileTarget) -> [AppsPanel.Choice] {
        guard case .logical(let key) = target, let column = logical.column(key: key), column.includesUnplugged else {
            return []
        }
        let names = prefs.names
        return column.cells.map {
            .init(name: displayName(of: $0.display, names: names), faded: $0.isDisconnected, isCurrent: $0.isCurrent,
                  spaceID: $0.space.managedID)
        }
    }

    /// The apps on a tile's Space, or on each display's Space of a logical space
    /// (under the display's name when there are several; an unplugged
    /// display's name faded, and picking one of its apps goes to its Space).
    private func appSections(for target: TileTarget) -> [AppsPanel.Section] {
        switch target {
        case .space(let id):
            return [.init(heading: nil, apps: SpaceAppsReader.apps(on: id))]
        case .logical(let key):
            guard let column = logical.column(key: key) else { return [] }
            let apps = SpaceAppsReader.apps(on: column.cells.map(\.space.managedID))
            let names = prefs.names
            return column.cells.map { cell in
                .init(heading: column.cells.count > 1 ? displayName(of: cell.display, names: names) : nil,
                      apps: apps[cell.space.managedID] ?? [], faded: cell.isDisconnected,
                      spaceID: cell.isDisconnected ? cell.space.managedID : nil)
            }
        }
    }

    /// True while the pointer is on the hovered tile or on its apps column.
    private func pointerOnApps() -> Bool {
        let point = NSEvent.mouseLocation
        guard !appsPanel.contains(point) else { return true }
        return hoveredTarget.map(pointerIsOn) ?? false
    }

    /// True while the pointer is on this tile. The tile rows know it from
    /// their own mouse events, which also arrive when macOS shows the menu bar
    /// item through another window (on Spaces other than the first).
    private func pointerIsOn(_ target: TileTarget) -> Bool {
        [menuItem.view, fallback.tiles].contains { $0.hoveredTarget == target }
            || extraTile?(NSEvent.mouseLocation)?.target == target
    }

    /// Hides the column unless the pointer is on its way from the tile into it (or back).
    private func hideAppsSoon() {
        let target = hoveredTarget
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hoveredTarget == target, !self.pointerOnApps() else { return }
                self.hideApps()
            }
        }
    }

    /// Clicked in the apps column: show that Space (every display's, for a
    /// logical space; for an app in an unplugged display's section, that
    /// display's Space where it is now), then bring the app to the front, as
    /// clicking it in the Dock would. Only ever on the user's click.
    private func bringToFront(_ app: NSRunningApplication, on target: TileTarget, in section: AppsPanel.Section) {
        hideApps()
        Task { @MainActor in
            if let id = section.spaceID {
                await switchSpace(id, flashing: target)
            } else {
                switch target {
                case .space(let id):
                    await switchSpace(id, flashing: target)
                case .logical(let key):
                    if let column = logical.column(key: key) { _ = await switchLogical(column) }
                }
            }
            AppActivator.bringToFront(app)
        }
    }

    /// Soft restart after a display is connected or disconnected: throws all
    /// passing state away and draws the tiles again from a fresh read, as
    /// relaunching the app would, without launching anything.
    func reset() {
        hideApps()
        messagePanel.orderOut(nil)
        failedClear?.cancel()
        failedClear = nil
        failedTarget = nil
        arming = DragArming()
        fallback.orderOut(nil)
        fallbackWork?.cancel()
        fallbackWork = nil
        monitor.refresh()
    }

    func hideApps() {
        hoverWork?.cancel()
        hoverWork = nil
        hoveredTarget = nil
        appsPanel.orderOut(nil)
    }

    // MARK: Switching

    /// A tile was clicked. A logical space switches every display that has a
    /// Space in it, or with `thisDisplayOnly` (Option-click) only the display
    /// under the pointer; a single tile switches its own Space.
    /// `switched` runs once macOS has made the change.
    func click(_ target: TileTarget, thisDisplayOnly: Bool, switched: (() -> Void)? = nil) {
        switch target {
        case .space(let id):
            click(id, flashing: target, switched: switched)
        case .logical(let key):
            guard let column = logical.column(key: key) else { return }
            hideApps()
            if thisDisplayOnly, let display = pointerDisplay() {
                guard let cell = column.switchCell(on: display.identifier) else {
                    showMessage(SwitchPlanner.noSpaceMessage(display: Self.displayName(display, names: prefs.names),
                                                             title: column.title))
                    return
                }
                click(cell.space.managedID, flashing: target, switched: switched)
                return
            }
            Task { @MainActor in
                if await switchLogical(column) { switched?() }
            }
        }
    }

    /// Switches to one Space; `switched` runs once macOS has made it current.
    /// A failure marks the `flashing` tile.
    func click(_ spaceID: UInt64, flashing: TileTarget? = nil, switched: (() -> Void)? = nil) {
        hideApps()
        Task { @MainActor in
            if await switchSpace(spaceID, flashing: flashing ?? .space(spaceID)) == .switched { switched?() }
        }
    }

    /// The display under the pointer (the one whose menu bar was clicked), or
    /// the one Space list when Spaces span all displays.
    private func pointerDisplay() -> Display? {
        if let only = snapshot.displays.first, only.spansAllDisplays { return only }
        let pointer = Screens.pointerIdentifier()
        return snapshot.displays.first { Screens.matches(pointer, $0) }
    }

    /// Switches to a Space; if that fails, marks the tile and says why under the tiles.
    @discardableResult
    private func switchSpace(_ spaceID: UInt64, flashing target: TileTarget) async -> SpaceSwitcher.Outcome {
        let outcome = await switcher.switchTo(spaceID: spaceID)
        if case .failed(let message) = outcome { flashFailure(target, message: message) }
        return outcome
    }

    /// Switches every display with a Space in `column` to it, one after another,
    /// the display under the pointer last so it keeps the focus. Returns true
    /// when every display got there; otherwise marks the tile and names the
    /// first display that didn't switch, and why.
    private func switchLogical(_ column: LogicalSpaces.Column) async -> Bool {
        let pointer = pointerDisplay()
        let targets = SwitchPlanner.order(column.switchCells, pointerDisplay: pointer?.identifier)
        let focusOn = SwitchPlanner.focusTarget(column, pointerDisplay: pointer)
        guard let results = await switcher.switchAll(targets.map(\.space.managedID), focusOn: focusOn) else {
            return false
        }
        for result in results {
            guard case .failed(let message) = result.outcome else { continue }
            var text = message
            if snapshot.displays.count > 1, message != SwitchPlanner.permissionMessage,
               let display = snapshot.locate(spaceID: result.spaceID)?.display {
                text = Self.displayName(display, names: prefs.names) + ": " + message
            }
            flashFailure(.logical(column.key), message: text)
            return false
        }
        return true
    }

    // MARK: Option-Control drag

    /// Starts or stops watching for a window being Option-Control-dragged onto a tile.
    ///
    /// Only reads the pointer position, mouse buttons and modifier keys through
    /// public `NSEvent` class properties: no event tap, no global monitor, no
    /// permission. The user physically holds the window; when the pointer rests
    /// on a tile, the app presses the desktop shortcut of that tile's Space on
    /// the display under the pointer, and macOS carries the held window along.
    /// The app never touches the window.
    /// "Option-Control-drag windows to Spaces" (Manage window › Advanced).
    var dragsWindows: Bool { prefs.dragWindows }

    func setDragsWindows(_ on: Bool) {
        prefs.dragWindows = on
        setDragWatching(on)
    }

    func setDragWatching(_ on: Bool) {
        dragTimer?.invalidate()
        dragTimer = nil
        if arming.armed != nil {
            arming = DragArming()
            redraw()
        }
        guard on else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.dragTick() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        dragTimer = timer
    }

    private func dragTick() {
        let holding = NSEvent.pressedMouseButtons & 1 != 0 && NSEvent.modifierFlags.contains([.option, .control])
        var target: TileTarget?
        let point = NSEvent.mouseLocation
        if holding, let tile = visibleRows.lazy.compactMap({ $0.hoverTile(atScreen: point) }).first,
           content.entries.contains(where: { $0.tile.target == tile.target && !$0.tile.isFullScreen }),
           dragSpace(for: tile.target) != nil {
            target = tile.target
        }
        let before = arming.armed
        let fire = arming.update(holding: holding, target: target, now: ProcessInfo.processInfo.systemUptime)
        if before != arming.armed { redraw() }
        if let fire, let spaceID = dragSpace(for: fire) { click(spaceID, flashing: fire) }
    }

    /// The Space a drag onto this tile switches to: a single tile's own Space,
    /// or the pointer display's Space of a logical space (nil when it has none).
    private func dragSpace(for target: TileTarget) -> UInt64? {
        switch target {
        case .space(let id):
            return id
        case .logical(let key):
            guard let display = pointerDisplay() else { return nil }
            return logical.column(key: key)?.switchCell(on: display.identifier)?.space.managedID
        }
    }

    // MARK: Messages

    private func flashFailure(_ target: TileTarget, message: String) {
        failedTarget = target
        redraw()
        showMessage(message)
        failedClear?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.failedTarget = nil
                self?.redraw()
            }
        }
        failedClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    /// A short message under the tiles (or under the fallback bar while it's shown).
    private func showMessage(_ message: String) {
        let anchor = fallback.isVisible ? fallback.frame : menuItem.view.screenFrame
        if let anchor { messagePanel.show(message, below: anchor) }
    }

    // MARK: Names

    private func liveKeys() -> Set<String> {
        var keys = Set<String>()
        for display in snapshot.displays {
            keys.insert(display.nameKey)
            display.spaces.forEach { keys.insert($0.nameKey) }
        }
        return keys
    }

    /// The logical space keys in use now (labels of others may be dropped at the cap).
    private func liveLabelKeys() -> Set<String> {
        Set(logical.columns.compactMap(\.labelKey))
    }

    /// Asks for a new name: for one Space, or for a logical space, whose name
    /// every Space in it then gets (and its tile label moves along). Returns
    /// the change to store (an empty name: back to the default name), or nil
    /// when cancelled.
    func askNames(for target: TileTarget) -> NameChange? {
        switch target {
        case .space(let id):
            guard let space = snapshot.locate(spaceID: id)?.space else { return nil }
            let defaultName = Names.defaultName(for: space, fallbackAppName: Self.fullScreenAppName(space))
            let current = prefs.names.storedName(forSpaceKey: space.nameKey) ?? ""
            guard let typed = NamePrompt.ask(title: "Rename Space", current: current, defaultName: defaultName) else {
                return nil
            }
            return NameChange(spaces: [space.nameKey: typed])
        case .logical(let key):
            guard let column = logical.column(key: key) else { return nil }
            let count = column.cells.count
            let note = count > 1 ? "Renames this Space on all \(count) displays." : nil
            guard let typed = NamePrompt.ask(title: "Rename “\(column.title)”", current: column.customName(in: prefs.names) ?? "",
                                             defaultName: "Desktop N", note: note) else { return nil }
            return column.renameChange(to: typed, names: prefs.names)
        }
    }

    /// Stores Space names and tile labels (empty clears) and returns the
    /// change that undoes it.
    @discardableResult
    func apply(_ change: NameChange) -> NameChange {
        let spaceKeys = liveKeys()
        let labelKeys = liveLabelKeys()
        var inverse = NameChange()
        prefs.updateNames { inverse = $0.apply(change, liveSpaceKeys: spaceKeys, liveLabelKeys: labelKeys) }
        redraw()
        return inverse
    }

    /// The tile label stored for a logical space, if any.
    func tileLabel(forLogicalKey key: String) -> String? {
        prefs.names.label(forLogicalKey: key)
    }

    func renameDisplay(key: String) {
        guard let display = snapshot.displays.first(where: { $0.nameKey == key }) else { return }
        let defaultName = Screens.defaultName(for: display)
        let existing = prefs.names.displays[key] ?? ""
        guard let typed = NamePrompt.ask(title: "Rename display", current: existing, defaultName: defaultName) else { return }
        let keys = liveKeys()
        prefs.updateNames { $0.setName(typed, for: display, liveKeys: keys) }
        redraw()
    }

    func resetDisplay(key: String) {
        guard let display = snapshot.displays.first(where: { $0.nameKey == key }) else { return }
        let keys = liveKeys()
        prefs.updateNames { $0.setName("", for: display, liveKeys: keys) }
        redraw()
    }
}

/// The rename dialog.
@MainActor
enum NamePrompt {
    /// `note`, when given, comes first in the dialog's text (e.g. that every display's Space is renamed).
    static func ask(title: String, current: String, defaultName: String, note: String? = nil) -> String? {
        let previous = NSWorkspace.shared.frontmostApplication
        defer {
            // Give keyboard focus back to the app you were using.
            if let previous, previous != NSRunningApplication.current { previous.activate() }
        }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = (note.map { $0 + " " } ?? "")
            + "Up to \(NameSanitizer.maxLength) characters. Leave empty to use “\(defaultName)”."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = current
        field.placeholderString = defaultName
        field.cell?.isScrollable = true
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? field.stringValue : nil
    }
}

/// A short message under the tiles, e.g. why a switch failed. Hides itself.
@MainActor
final class MessagePanel: FloatingPanel {
    private let label = NSTextField(wrappingLabelWithString: "")
    private var hide: DispatchWorkItem?

    init() {
        super.init(size: NSSize(width: 420, height: 40))
        ignoresMouseEvents = true

        let box = PanelBoxView(cornerRadius: 8)
        box.border = Palette.warning
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.setAccessibilityRole(.staticText)
        box.addSubview(label)
        contentView = box
    }

    func show(_ message: String, below barFrame: NSRect) {
        label.stringValue = message
        let width: CGFloat = 420
        label.preferredMaxLayoutWidth = width - 24
        let height = ceil(label.intrinsicContentSize.height) + 18
        label.frame = NSRect(x: 12, y: 9, width: width - 24, height: height - 18)
        var x = barFrame.midX - width / 2
        let anchor = NSPoint(x: barFrame.midX, y: barFrame.midY)
        if let visible = NSScreen.screens.first(where: { $0.frame.contains(anchor) })?.visibleFrame {
            x = min(max(x, visible.minX + 6), visible.maxX - width - 6)
        }
        setFrame(NSRect(x: x, y: barFrame.minY - height - 6, width: width, height: height), display: true)
        orderFrontRegardless()
        NSAccessibility.post(element: label, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])

        hide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }
}
