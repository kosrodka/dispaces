import AppKit
import SpacesCore

/// Keeps the Spaces in the menu bar in sync with the snapshot: one menu bar
/// item with a square tile per Space, each display's Spaces as a group, the
/// displays in their left-to-right arrangement. When macOS isn't showing the
/// item (no room beside the notch, a hidden menu bar, switched off in System
/// Settings), a small floating bar with the same tiles stands in, unless the
/// user turned that off.
@MainActor
final class BarController {
    private let menuItem = MenuBarItem()
    private let fallback = FallbackBar()
    private let messagePanel = MessagePanel()
    private let appsPanel = AppsPanel()
    /// The tile whose apps are showing (or about to), and the pending show.
    private var hoveredSpaceID: UInt64?
    private var hoverWork: DispatchWorkItem?
    private let prefs: Preferences
    private let switcher: SpaceSwitcher
    private let monitor: SpaceMonitor

    private var snapshot = Snapshot.empty
    private var content = TilesContent()
    private var failedSpaceID: UInt64?
    private var failedClear: DispatchWorkItem?
    /// Option-drag: the tile a held window is resting on.
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
    /// Open the app's menu under a view; the Space that was right-clicked, if any.
    var onMenu: ((UInt64?, NSView) -> Void)?

    init(prefs: Preferences, monitor: SpaceMonitor, switcher: SpaceSwitcher) {
        self.prefs = prefs
        self.monitor = monitor
        self.switcher = switcher
        appsPanel.onExit = { [weak self] in self?.hideAppsSoon() }
        for view in [menuItem.view, fallback.tiles] {
            view.onClick = { [weak self] id in self?.click(id) }
            view.onWarning = { [weak self] in self?.onWarningClick?() }
            view.onMenu = { [weak self, weak view] id, _ in
                guard let self, let view else { return }
                self.hideApps()
                self.onMenu?(id, view)
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

    // MARK: Displays and Spaces window

    /// Every display with its Spaces: connected ones first, in macOS's display
    /// order (the menu-bar display first), then disconnected ones.
    func overview() -> DisplayOverview {
        DisplayOverview(snapshot: snapshot, memory: prefs.memory, names: prefs.names,
                        screenOrder: NSScreen.screens.compactMap(Screens.identifier(of:)),
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

    /// Whether a display's first Space is shown in the menu bar and in the Manage window.
    func showsFirstSpace(_ identifier: String) -> Bool {
        identifier == Display.combinedIdentifier
            || prefs.firstSpaces.isShown(identifier)
    }

    func setShowsFirstSpace(_ shown: Bool, for identifier: String) {
        prefs.updateFirstSpaces { $0.set(shown, for: identifier) }
        redraw()
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
                              spaceName: { names.name(for: $0) }, now: now)
            }
            let focusedDisplay = snapshot.focusedDisplay?.identifier ?? Screens.focusedIdentifier()
            for display in orderedDisplays() where !display.spaces.isEmpty {
                let onFocused = snapshot.displays.count == 1 || Screens.matches(focusedDisplay, display)
                let group = groupModel(for: display, names: names, onFocused: onFocused)
                content.runs.append(.init(count: group.tiles.count, spacing: .group))
                content.entries += group.tiles.map { .init(tile: $0, dimmed: false) }
                for ghost in group.ghosts {
                    content.runs.append(.init(count: ghost.tiles.count, spacing: .subgroup))
                    content.entries += ghost.tiles.map { .init(tile: $0, dimmed: true) }
                }
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
        if hoveredSpaceID != nil, !pointerOnApps() {
            hideApps()
        }
        checkFallback()
    }

    /// Displays left to right, as they're arranged in System Settings › Displays.
    private func orderedDisplays() -> [Display] {
        let far = CGFloat.greatestFiniteMagnitude
        return snapshot.displays.enumerated().sorted { a, b in
            let ax = Screens.screen(for: a.element)?.frame.minX ?? far
            let bx = Screens.screen(for: b.element)?.frame.minX ?? far
            return ax != bx ? ax < bx : a.offset < b.offset
        }.map(\.element)
    }

    private func groupModel(for display: Display, names: Names, onFocused: Bool) -> GroupModel {
        let memory = prefs.memory
        func tile(_ space: Space, remembered: DisplayMemory.RememberedSpace?) -> TileModel {
            let isCurrent = display.currentSpaceID == space.managedID
            let name = DisplayOverview.spaceName(space, names: names, remembered: remembered,
                                                 fallbackAppName: Self.fullScreenAppName(space))
            let kind = space.kind == .desktop ? "Desktop \(space.numberLabel)" : "Full-screen Space"
            return TileModel(
                spaceID: space.managedID, number: space.numberLabel, name: name,
                state: isCurrent ? (onFocused ? .focused : .current) : .normal,
                isFullScreen: space.kind == .fullscreen,
                failed: space.managedID == failedSpaceID,
                armed: space.managedID == arming.armedSpaceID,
                accessibilityLabel: "\(kind), \(name)" + (isCurrent ? ", current on this display" : ""))
        }
        // Spaces that belong to a disconnected display go into that display's group.
        var own: [TileModel] = []
        var ghosts: [(record: DisplayMemory.Record, tiles: [TileModel])] = []
        let hiddenFirst = showsFirstSpace(display.identifier) ? nil : display.spaces.first?.managedID
        for space in display.spaces where space.managedID != hiddenFirst {
            guard !display.spansAllDisplays, let record = memory.ghostOwner(of: space, in: snapshot) else {
                own.append(tile(space, remembered: nil))
                continue
            }
            let remembered = record.spaces.first { $0.matches(space) }
            // The disconnected display's own first Space follows its setting.
            if let first = record.spaces.first, first == remembered, !showsFirstSpace(record.identifier) { continue }
            if let index = ghosts.firstIndex(where: { $0.record.identifier == record.identifier }) {
                ghosts[index].tiles.append(tile(space, remembered: remembered))
            } else {
                ghosts.append((record, [tile(space, remembered: remembered)]))
            }
        }
        return GroupModel(displayKey: display.nameKey,
                          label: Self.displayName(display, names: names),
                          tiles: own,
                          ghosts: ghosts.map { .init(label: DisplayOverview.displayName($0.record, names: names), tiles: $0.tiles) })
    }

    /// A display's name: the user's, else the one macOS gives it.
    private static func displayName(_ display: Display, names: Names) -> String {
        names.name(for: display, defaultName: Screens.defaultName(for: display))
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

    /// The name shown for a Space (for the menu's Rename item).
    func spaceName(_ spaceID: UInt64) -> String? {
        content.entries.first { $0.tile.spaceID == spaceID }?.tile.name
    }

    // MARK: Fallback bar

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
                if let id = hoveredSpaceID, fallback.tiles.content.entries.contains(where: { $0.tile.spaceID == id }) {
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

    /// Shows the apps on a tile's Space after a short rest, so sweeping across the tiles stays quiet.
    /// The column stays while the pointer is on the tile or on the column.
    func hover(_ tile: HoverTile, inside: Bool) {
        let spaceID = tile.spaceID
        guard inside else {
            if hoveredSpaceID == spaceID { hideAppsSoon() }
            return
        }
        // Back on the tile from its own column: keep it.
        if hoveredSpaceID == spaceID && appsPanel.isVisible { return }
        hideApps()
        guard prefs.showAppsOnHover, NSEvent.pressedMouseButtons == 0 else { return }
        hoveredSpaceID = spaceID
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hoveredSpaceID == spaceID, NSEvent.pressedMouseButtons == 0,
                      let tile = self.hoverTile(at: NSEvent.mouseLocation), tile.spaceID == spaceID else { return }
                self.appsPanel.onPick = { [weak self] app in self?.bringToFront(app, on: spaceID) }
                self.appsPanel.show(title: tile.name, apps: SpaceAppsReader.apps(on: spaceID), tile: tile.frame,
                                    screen: tile.screen)
            }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// True while the pointer is on the hovered tile or on its apps column.
    private func pointerOnApps() -> Bool {
        let point = NSEvent.mouseLocation
        return appsPanel.contains(point) || (hoveredSpaceID != nil && hoverTile(at: point)?.spaceID == hoveredSpaceID)
    }

    /// Hides the column unless the pointer is on its way from the tile into it (or back).
    private func hideAppsSoon() {
        let spaceID = hoveredSpaceID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hoveredSpaceID == spaceID, !self.pointerOnApps() else { return }
                self.hideApps()
            }
        }
    }

    /// Clicked in the apps column: show that Space, then bring the app to the front,
    /// as clicking it in the Dock would. Only ever on the user's click.
    private func bringToFront(_ app: NSRunningApplication, on spaceID: UInt64) {
        hideApps()
        Task { @MainActor in
            await switchSpace(spaceID)
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
        failedSpaceID = nil
        arming = DragArming()
        fallback.orderOut(nil)
        fallbackWork?.cancel()
        fallbackWork = nil
        monitor.refresh()
    }

    func hideApps() {
        hoverWork?.cancel()
        hoverWork = nil
        hoveredSpaceID = nil
        appsPanel.orderOut(nil)
    }

    private func hoverTile(at point: NSPoint) -> HoverTile? {
        visibleRows.lazy.compactMap { $0.hoverTile(atScreen: point) }.first ?? extraTile?(point)
    }

    /// Switches to a Space; `switched` runs once macOS has made it current.
    func click(_ spaceID: UInt64, switched: (() -> Void)? = nil) {
        hideApps()
        Task { @MainActor in
            if await switchSpace(spaceID) == .switched { switched?() }
        }
    }

    /// Switches to a Space; if that fails, marks its tile and says why under the tiles.
    @discardableResult
    private func switchSpace(_ spaceID: UInt64) async -> SpaceSwitcher.Outcome {
        let outcome = await switcher.switchTo(spaceID: spaceID)
        if case .failed(let message) = outcome { flashFailure(spaceID: spaceID, message: message) }
        return outcome
    }

    // MARK: Option-drag

    /// Starts or stops watching for a window being Option-dragged onto a tile.
    ///
    /// Only reads the pointer position, mouse buttons and modifier keys through
    /// public `NSEvent` class properties: no event tap, no global monitor, no
    /// permission. The user physically holds the window; when the pointer rests
    /// on a desktop tile, the app presses that desktop's shortcut and macOS
    /// carries the held window along. The app never touches the window.
    func setDragWatching(_ on: Bool) {
        dragTimer?.invalidate()
        dragTimer = nil
        if arming.armedSpaceID != nil {
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
        let holding = NSEvent.pressedMouseButtons & 1 != 0 && NSEvent.modifierFlags.contains(.option)
        var space: UInt64?
        let point = NSEvent.mouseLocation
        if holding, let tile = visibleRows.lazy.compactMap({ $0.hoverTile(atScreen: point) }).first,
           content.entries.contains(where: { $0.tile.spaceID == tile.spaceID && !$0.tile.isFullScreen }) {
            space = tile.spaceID
        }
        let before = arming.armedSpaceID
        let fire = arming.update(holding: holding, spaceUnderPointer: space, now: ProcessInfo.processInfo.systemUptime)
        if before != arming.armedSpaceID { redraw() }
        if let fire { click(fire) }
    }

    private func flashFailure(spaceID: UInt64, message: String) {
        failedSpaceID = spaceID
        redraw()
        let anchor = fallback.isVisible ? fallback.frame : menuItem.view.screenFrame
        if let anchor { messagePanel.show(message, below: anchor) }
        failedClear?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.failedSpaceID = nil
                self?.redraw()
            }
        }
        failedClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    private func liveKeys() -> Set<String> {
        var keys = Set<String>()
        for display in snapshot.displays {
            keys.insert(display.nameKey)
            display.spaces.forEach { keys.insert($0.nameKey) }
        }
        return keys
    }

    func renameSpace(id: UInt64) {
        guard let found = snapshot.locate(spaceID: id) else { return }
        let space = found.space
        let defaultName = Names.defaultName(for: space, fallbackAppName: Self.fullScreenAppName(space))
        let current = prefs.names.spaces[space.nameKey] ?? ""
        guard let typed = NamePrompt.ask(title: "Rename Space", current: current, defaultName: defaultName) else { return }
        let keys = liveKeys()
        prefs.updateNames { $0.setName(typed, for: space, liveKeys: keys) }
        redraw()
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
    static func ask(title: String, current: String, defaultName: String) -> String? {
        let previous = NSWorkspace.shared.frontmostApplication
        defer {
            // Give keyboard focus back to the app you were using.
            if let previous, previous != NSRunningApplication.current { previous.activate() }
        }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Up to \(NameSanitizer.maxLength) characters. Leave empty to use “\(defaultName)”."
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

        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.borderWidth = 1
        box.layer?.borderColor = Palette.warning.cgColor
        box.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
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
