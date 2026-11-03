import AppKit
import SpacesCore

/// A floating panel that never takes focus: clicking it doesn't activate the app,
/// doesn't create a Stage Manager stage, and doesn't steal your typing.
@MainActor
final class BarPanel: FloatingPanel {
    init() {
        super.init(size: NSSize(width: 200, height: Metrics.barHeight))
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
    }
}

/// One floating bar, shown on one display, holding that display's Spaces.
///
/// Left to right: control buttons (show/hide Spaces, lock, refresh), the
/// display's name, its Space tiles, and the amber "!" when setup needs attention.
/// Its edges can be dragged to resize it; tiles and text scale to fit.
@MainActor
final class DisplayBar {
    /// Display identifier, or `BarController.unreadableKey`.
    let key: String
    let panel = BarPanel()
    private let background = BarBackgroundView(frame: .zero)
    private(set) var model: BarModel?
    private var placed = false

    init(key: String) {
        self.key = key
        panel.contentView = background
    }

    var layoutKey: String { BarController.layoutKey(key) }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }

    /// Lays out the bar and places it. Returns false when nothing changed.
    @discardableResult
    func update(_ model: BarModel, screen: NSScreen?, controller: BarController, force: Bool = false) -> Bool {
        guard force || model != self.model else { return false }
        self.model = model
        background.glowing = model.glowing
        let size = layout(model, screen: screen, controller: controller)
        place(size: size, screen: screen, controller: controller)
        return true
    }

    /// Rebuilds the bar's contents for `model`. Returns the bar's size.
    private func layout(_ model: BarModel, screen: NSScreen?, controller: BarController) -> CGSize {
        background.subviews.forEach { $0.removeFromSuperview() }
        background.onDrag = dragHandler(controller)
        background.onResize = { [weak self, weak controller] event, edges in
            guard let self, let controller else { return }
            controller.resize(self, event, edges: edges)
        }
        background.onResetSize = { [weak self, weak controller] in
            guard let self, let controller else { return }
            controller.resetSize(self)
        }
        background.canResize = !model.locked && !model.collapsed && model.group != nil

        let heights = BarLayout.heights
        let height = model.size.map { min(max($0.height, CGFloat(heights.lowerBound)), CGFloat(heights.upperBound)) } ?? Metrics.barHeight
        let scale = height / Metrics.barHeight
        let tileHeight = height - (Metrics.barHeight - Metrics.tileHeight)
        let tileY = (height - tileHeight) / 2
        let controlY = (height - Metrics.controlSize) / 2
        let screenWidth = screen?.visibleFrame.width ?? 1440
        let showWarning = model.warning || model.group == nil
        let warningWidth = showWarning ? tileHeight + 4 : 0
        var x = Metrics.inset

        // Control section.
        let controls: [(String, String, () -> Void)] = [
            (model.collapsed ? "eye.slash" : "eye",
             model.collapsed ? "Show Spaces" : "Hide Spaces",
             { [weak controller, key] in controller?.toggleCollapsed(key) }),
            (model.locked ? "lock.fill" : "lock.open",
             model.locked ? "Unlock this bar" : "Lock this bar's position and size",
             { [weak controller, key] in controller?.toggleLock(key) }),
            ("arrow.clockwise", "Refresh now",
             { [weak controller] in controller?.refreshNow() }),
        ]
        for (symbol, label, action) in controls {
            let button = ControlButton(symbol: symbol, label: label)
            button.frame = NSRect(x: x, y: controlY, width: Metrics.controlSize, height: Metrics.controlSize)
            button.onClick = action
            background.addSubview(button)
            x += Metrics.controlSize + Metrics.controlGap
        }
        x += Metrics.groupPadding - Metrics.controlGap

        if !model.collapsed {
            background.addSubview(DividerView(frame: NSRect(x: x, y: 7, width: 1, height: height - 14)))
            x += 1 + Metrics.groupPadding

            if let group = model.group {
                let label = DisplayLabelView(text: group.label, scale: scale)
                label.frame = NSRect(x: x, y: tileY, width: label.preferredWidth, height: tileHeight)
                label.canReset = controller.hasCustomName(displayKey: group.displayKey)
                label.onRename = { [weak controller] in controller?.renameDisplay(key: group.displayKey) }
                label.onReset = { [weak controller] in controller?.resetDisplay(key: group.displayKey) }
                label.onDrag = dragHandler(controller)
                background.addSubview(label)
                x += label.preferredWidth + Metrics.gap

                // Disconnected displays' Spaces follow this display's own, each under its old name.
                let ghostLabels = group.ghosts.map { DisplayLabelView(text: $0.label, scale: scale, ghost: true) }
                let ghostSpace = ghostLabels.reduce(0) { $0 + $1.preferredWidth + Metrics.groupPadding + Metrics.gap }
                let allTiles = group.tiles + group.ghosts.flatMap(\.tiles)
                let (widths, compact) = tileWidths(allTiles, scale: scale, from: x,
                                                   reserved: warningWidth + Metrics.inset + ghostSpace,
                                                   target: model.size.map { min($0.width, screenWidth) },
                                                   screenWidth: screenWidth)
                // Index of the first tile of each ghost group, and its label.
                var ghostStarts: [Int: DisplayLabelView] = [:]
                var start = group.tiles.count
                for (ghost, label) in zip(group.ghosts, ghostLabels) {
                    ghostStarts[start] = label
                    start += ghost.tiles.count
                }
                for (index, (tile, width)) in zip(allTiles, widths).enumerated() {
                    if let label = ghostStarts[index] {
                        x += Metrics.groupPadding
                        label.frame = NSRect(x: x, y: tileY, width: label.preferredWidth, height: tileHeight)
                        label.onDrag = dragHandler(controller)
                        background.addSubview(label)
                        x += label.preferredWidth + Metrics.gap
                    }
                    let view = TileView(model: tile, compact: compact, scale: scale)
                    view.frame = NSRect(x: x, y: tileY, width: width, height: tileHeight)
                    view.onClick = { [weak controller] in controller?.click(tile.spaceID) }
                    view.onRename = { [weak controller] in controller?.renameSpace(id: tile.spaceID) }
                    view.onHover = { [weak controller, weak view] inside in
                        guard let view else { return }
                        controller?.hover(view, inside: inside)
                    }
                    // The hover column shows the full name instead.
                    view.toolTip = controller.showsAppsOnHover ? nil : tile.name
                    background.addSubview(view)
                    x += width + Metrics.gap
                }
                x -= Metrics.gap
            } else {
                let label = DisplayLabelView(text: "Can't read Spaces", scale: scale)
                label.frame = NSRect(x: x, y: tileY, width: label.preferredWidth, height: tileHeight)
                background.addSubview(label)
                x += label.preferredWidth
            }
        }

        if showWarning {
            let warning = WarningView(frame: NSRect(x: x + 4, y: tileY, width: tileHeight, height: tileHeight))
            warning.onClick = { [weak controller] in controller?.onWarningClick?() }
            background.addSubview(warning)
            x += warningWidth
        }
        x += Metrics.inset
        return CGSize(width: max(x, CGFloat(BarGeometry.minBarWidth)), height: height)
    }

    /// Tile widths and whether tiles are compact (see `BarGeometry.tileWidths`).
    private func tileWidths(_ tiles: [TileModel], scale: CGFloat, from start: CGFloat, reserved: CGFloat,
                            target: CGFloat?, screenWidth: CGFloat) -> ([CGFloat], Bool) {
        let result = BarGeometry.tileWidths(
            natural: tiles.map { Double(TileView.width(for: $0, compact: false, scale: scale)) },
            compact: { tiles.map { Double(TileView.width(for: $0, compact: true, scale: scale)) } },
            start: Double(start), reserved: Double(reserved), gap: Double(Metrics.gap),
            minTile: Double(Metrics.minTile * scale), target: target.map { Double($0) },
            screenWidth: Double(screenWidth))
        return (result.widths.map { CGFloat($0) }, result.compact)
    }

    /// Dragging a view with this handler moves the bar (unless it's locked).
    private func dragHandler(_ controller: BarController) -> (NSEvent) -> Void {
        { [weak self, weak controller] event in
            guard let self, let controller else { return }
            controller.drag(self, event)
        }
    }

    /// Sizes the panel and keeps it on its own display.
    private func place(size: CGSize, screen: NSScreen?, controller: BarController) {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var topLeft: NSPoint
        if placed {
            topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        } else if let offset = controller.savedOffset(for: layoutKey) {
            topLeft = NSPoint(x: visible.minX + offset.fromLeft, y: visible.maxY - offset.fromTop)
        } else {
            // Default: centred near the top of its display.
            topLeft = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - 8)
        }
        placed = true
        let frame = NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
        panel.setFrame(BarGeometry.clamp(.init(frame), to: .init(visible)).nsRect, display: true)
    }

    /// Follows the mouse while an edge is dragged, keeping the opposite edges
    /// still. Returns the final size, or nil if the bar can't be resized.
    func trackResize(_ event: NSEvent, edges: ResizeEdges, screen: NSScreen?, controller: BarController) -> CGSize? {
        guard let model, model.group != nil, !model.collapsed else { return nil }
        let start = NSEvent.mouseLocation
        let startFrame = panel.frame
        let visible = screen?.visibleFrame ?? startFrame
        var current = model
        background.activeResize = edges
        defer { background.activeResize = [] }
        panel.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration,
                          mode: .eventTracking) { event, stop in
            guard let event else {
                stop.pointee = true
                return
            }
            // Keep the resize cursor while dragging (see BarBackgroundView).
            BarBackgroundView.cursor(for: edges).set()
            let point = NSEvent.mouseLocation
            let wanted = BarGeometry.resizedSize(of: .init(startFrame), edges: edges,
                                                 dx: Double(point.x - start.x), dy: Double(point.y - start.y))
            current.size = CGSize(width: wanted.width, height: wanted.height)
            self.model = current
            let size = self.layout(current, screen: screen, controller: controller)
            // The edges not being dragged stay where they were.
            let frame = BarGeometry.resizedFrame(from: .init(startFrame), width: Double(size.width),
                                                 height: Double(size.height), edges: edges)
            self.panel.setFrame(BarGeometry.clamp(frame, to: .init(visible)).nsRect, display: true)
            if event.type == .leftMouseUp { stop.pointee = true }
        }
        return current.size.map { CGSize(width: panel.frame.width, height: $0.height) }
    }

    /// The tile view under a point in screen coordinates, if the bar is showing one there.
    func tileView(at screenPoint: NSPoint) -> TileView? {
        guard panel.isVisible, panel.frame.contains(screenPoint) else { return nil }
        let point = background.convert(panel.convertPoint(fromScreen: screenPoint), from: nil)
        return background.subviews.lazy.compactMap { $0 as? TileView }.first { $0.frame.contains(point) }
    }

    /// The tile under a point in screen coordinates, if the bar is showing one there.
    func tile(at screenPoint: NSPoint) -> TileModel? {
        tileView(at: screenPoint)?.model
    }

    /// After a drag or resize: snap back onto its own display and remember the spot.
    func finishDrag(screen: NSScreen?) -> BarLayout.Offset? {
        guard let visible = screen?.visibleFrame else { return nil }
        let frame = BarGeometry.clamp(.init(panel.frame), to: .init(visible)).nsRect
        if frame != panel.frame { panel.setFrame(frame, display: true) }
        return BarLayout.Offset(fromLeft: Double(frame.minX - visible.minX), fromTop: Double(visible.maxY - frame.maxY))
    }
}

/// Keeps one bar per display, each on its own display, in sync with the snapshot.
@MainActor
final class BarController {
    /// Key of the single bar shown when the Space list can't be read.
    static let unreadableKey = "unreadable"

    /// Key of a bar's entries in `BarLayout`.
    static func layoutKey(_ key: String) -> String { "bar:" + key }

    private var bars: [String: DisplayBar] = [:]
    private let messagePanel = MessagePanel()
    private let appsPanel = AppsPanel()
    /// The tile whose apps are showing (or about to), and the pending show.
    private var hoveredSpaceID: UInt64?
    private var hoverWork: DispatchWorkItem?
    private let prefs: Preferences
    private let switcher: SpaceSwitcher
    private let monitor: SpaceMonitor

    private var snapshot = Snapshot.empty
    private var failedSpaceID: UInt64?
    private var failedClear: DispatchWorkItem?
    /// Option-drag: the tile a held window is resting on, and the bar it's over.
    private var arming = DragArming()
    private var glowingBar: String?
    private var dragTimer: Timer?
    var needsAttention: () -> Bool = { false }
    var onWarningClick: (() -> Void)?

    init(prefs: Preferences, monitor: SpaceMonitor, switcher: SpaceSwitcher) {
        self.prefs = prefs
        self.monitor = monitor
        self.switcher = switcher
        appsPanel.onExit = { [weak self] in self?.hideAppsSoon() }
    }

    var isVisible: Bool { !prefs.barHidden }

    func setVisible(_ visible: Bool) {
        prefs.barHidden = !visible
        for bar in bars.values {
            if visible { bar.panel.orderFrontRegardless() } else { bar.panel.orderOut(nil) }
        }
        if !visible {
            messagePanel.orderOut(nil)
            hideApps()
        }
    }

    // MARK: Model

    func show(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        rebuild(force: false)
        onChange?()
    }

    func redraw() {
        rebuild(force: true)
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

    /// Takes a Space out of a disconnected display's group; it joins the bar of
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

    /// Whether a display's first Space is shown on its bar and in the Manage window.
    func showsFirstSpace(_ identifier: String) -> Bool {
        identifier == Display.combinedIdentifier
            || prefs.firstSpaces.isShown(identifier)
    }

    func setShowsFirstSpace(_ shown: Bool, for identifier: String) {
        prefs.updateFirstSpaces { $0.set(shown, for: identifier) }
        redraw()
    }

    /// Tiles shown outside the bars (the Manage window), for the hover column.
    var extraTileView: ((NSPoint) -> TileView?)?

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

    private func rebuild(force: Bool) {
        let warning = needsAttention()
        var wanted: [String: (BarModel, NSScreen?)] = [:]

        if snapshot.isEmpty {
            let key = Self.layoutKey(Self.unreadableKey)
            wanted[Self.unreadableKey] = (BarModel(group: nil, warning: true, collapsed: false,
                                                   locked: prefs.layout.isLocked(key)),
                                         NSScreen.main ?? NSScreen.screens.first)
        } else {
            if prefs.takeLegacyLock() {
                prefs.updateLayout { layout in
                    for display in snapshot.displays { layout.setLocked(true, for: Self.layoutKey(display.identifier)) }
                }
            }
            let names = prefs.names
            let now = Date().timeIntervalSince1970
            prefs.updateMemory { memory in
                memory.update(with: snapshot,
                              displayName: { Self.displayName($0, names: names) },
                              spaceName: { names.name(for: $0) }, now: now)
            }
            let focusedDisplay = snapshot.focusedDisplay?.identifier ?? Screens.focusedIdentifier()
            for display in snapshot.displays where !display.spaces.isEmpty {
                let onFocused = snapshot.displays.count == 1 || Screens.matches(focusedDisplay, display)
                let group = groupModel(for: display, names: names, onFocused: onFocused)
                let key = display.identifier
                let layoutKey = Self.layoutKey(key)
                let size = prefs.layout.sizes[layoutKey].map { CGSize(width: $0.width, height: $0.height) }
                let model = BarModel(group: group, warning: warning,
                                     collapsed: prefs.layout.isCollapsed(layoutKey),
                                     locked: prefs.layout.isLocked(layoutKey), size: size,
                                     glowing: glowingBar == key)
                wanted[key] = (model, Self.screen(for: display))
            }
        }

        // Remove bars for displays that are gone.
        for (key, bar) in bars where wanted[key] == nil {
            bar.close()
            bars[key] = nil
        }
        for (key, (model, screen)) in wanted {
            let bar = bars[key] ?? DisplayBar(key: key)
            bars[key] = bar
            bar.update(model, screen: screen, controller: self, force: force)
            if !prefs.barHidden && !bar.panel.isVisible { bar.panel.orderFrontRegardless() }
        }
        // Tiles were rebuilt: drop the column if the pointer isn't on that tile any more.
        if hoveredSpaceID != nil, !pointerOnApps() {
            hideApps()
        }
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

    /// The screen a display's bar goes on.
    private static func screen(for display: Display) -> NSScreen? {
        Screens.screen(for: display) ?? NSScreen.main
    }

    // MARK: Called by the bars

    func savedOffset(for layoutKey: String) -> BarLayout.Offset? {
        prefs.layout.offsets[layoutKey]
    }

    func hasCustomName(displayKey: String) -> Bool {
        prefs.names.displays[displayKey] != nil
    }

    func drag(_ bar: DisplayBar, _ event: NSEvent) {
        guard !prefs.layout.isLocked(bar.layoutKey) else { return }
        bar.panel.performDrag(with: event)
        let screen = screen(forBar: bar.key)
        if let offset = bar.finishDrag(screen: screen) {
            prefs.updateLayout { $0.setOffset(fromLeft: offset.fromLeft, fromTop: offset.fromTop, for: bar.layoutKey) }
        }
    }

    func resize(_ bar: DisplayBar, _ event: NSEvent, edges: ResizeEdges) {
        guard !prefs.layout.isLocked(bar.layoutKey) else { return }
        let screen = screen(forBar: bar.key)
        guard let size = bar.trackResize(event, edges: edges, screen: screen, controller: self) else { return }
        let offset = bar.finishDrag(screen: screen)
        prefs.updateLayout { layout in
            layout.setSize(BarLayout.Size(width: Double(size.width), height: Double(size.height)), for: bar.layoutKey)
            if let offset { layout.setOffset(fromLeft: offset.fromLeft, fromTop: offset.fromTop, for: bar.layoutKey) }
        }
        redraw()
    }

    /// Back to the size that just fits the bar's contents.
    func resetSize(_ bar: DisplayBar) {
        guard !prefs.layout.isLocked(bar.layoutKey) else { return }
        prefs.updateLayout { $0.setSize(nil, for: bar.layoutKey) }
        redraw()
    }

    private func screen(forBar key: String) -> NSScreen? {
        snapshot.displays.first { $0.identifier == key }.flatMap(Self.screen(for:)) ?? NSScreen.main
    }

    func toggleCollapsed(_ key: String) {
        let layoutKey = Self.layoutKey(key)
        let collapse = !prefs.layout.isCollapsed(layoutKey)
        prefs.updateLayout { $0.setCollapsed(collapse, for: layoutKey) }
        redraw()
    }

    /// Locks or unlocks one bar's position and size.
    func toggleLock(_ key: String) {
        let layoutKey = Self.layoutKey(key)
        let lock = !prefs.layout.isLocked(layoutKey)
        prefs.updateLayout { $0.setLocked(lock, for: layoutKey) }
        redraw()
    }

    /// True when every bar on screen is locked.
    var allLocked: Bool {
        !bars.isEmpty && bars.keys.allSatisfy { prefs.layout.isLocked(Self.layoutKey($0)) }
    }

    func setAllLocked(_ lock: Bool) {
        prefs.updateLayout { layout in
            for key in bars.keys { layout.setLocked(lock, for: Self.layoutKey(key)) }
        }
        redraw()
    }

    func refreshNow() {
        monitor.refresh()
    }

    // MARK: Apps on hover

    var showsAppsOnHover: Bool { prefs.showAppsOnHover }

    func setShowsAppsOnHover(_ on: Bool) {
        prefs.showAppsOnHover = on
        if !on { hideApps() }
        redraw()
    }

    /// Shows the apps on a tile's Space after a short rest, so sweeping across the bar stays quiet.
    /// The column stays while the pointer is on the tile or on the column.
    func hover(_ view: TileView, inside: Bool) {
        let spaceID = view.model.spaceID
        guard inside else {
            if hoveredSpaceID == spaceID { hideAppsSoon() }
            return
        }
        // Back on the tile from its own column: keep it.
        if hoveredSpaceID == spaceID && appsPanel.isVisible { return }
        hideApps()
        guard prefs.showAppsOnHover, NSEvent.pressedMouseButtons == 0 else { return }
        hoveredSpaceID = spaceID
        let title = view.model.name
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hoveredSpaceID == spaceID, NSEvent.pressedMouseButtons == 0,
                      let tile = self.tileView(at: NSEvent.mouseLocation), tile.model.spaceID == spaceID,
                      let frame = tile.screenFrame else { return }
                self.appsPanel.onPick = { [weak self] app in self?.bringToFront(app, on: spaceID) }
                self.appsPanel.show(title: title, apps: SpaceAppsReader.apps(on: spaceID), tile: frame,
                                    screen: tile.window?.screen)
            }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// True while the pointer is on the hovered tile or on its apps column.
    private func pointerOnApps() -> Bool {
        let point = NSEvent.mouseLocation
        return appsPanel.contains(point) || (hoveredSpaceID != nil && tileView(at: point)?.model.spaceID == hoveredSpaceID)
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

    /// Soft restart after a display is connected or disconnected: throws every
    /// bar and passing state away and builds the bars again from a fresh read,
    /// as relaunching the app would, without launching anything.
    func resetBars() {
        hideApps()
        messagePanel.orderOut(nil)
        failedClear?.cancel()
        failedClear = nil
        failedSpaceID = nil
        arming = DragArming()
        glowingBar = nil
        for bar in bars.values { bar.close() }
        bars.removeAll()
        monitor.refresh()
    }

    private func hideApps() {
        hoverWork?.cancel()
        hoverWork = nil
        hoveredSpaceID = nil
        appsPanel.orderOut(nil)
    }

    private func tileView(at point: NSPoint) -> TileView? {
        bars.values.lazy.compactMap { $0.tileView(at: point) }.first ?? extraTileView?(point)
    }

    /// Switches to a Space; `switched` runs once macOS has made it current.
    func click(_ spaceID: UInt64, switched: (() -> Void)? = nil) {
        hideApps()
        Task { @MainActor in
            if await switchSpace(spaceID) == .switched { switched?() }
        }
    }

    /// Switches to a Space; if that fails, marks its tile and says why under the bar.
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
    /// permission. The user physically holds the window; when it rests on a
    /// desktop tile, the app presses that desktop's shortcut and macOS carries
    /// the held window along. The app never touches the window.
    func setDragWatching(_ on: Bool) {
        dragTimer?.invalidate()
        dragTimer = nil
        if arming.armedSpaceID != nil || glowingBar != nil {
            arming = DragArming()
            glowingBar = nil
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
        let point = NSEvent.mouseLocation
        var barKey: String?
        var space: UInt64?
        if holding && !prefs.barHidden {
            for (key, bar) in bars where bar.panel.isVisible && bar.panel.frame.contains(point) {
                barKey = key
                if let tile = bar.tile(at: point), !tile.isFullScreen { space = tile.spaceID }
                break
            }
        }
        let before = (arming.armedSpaceID, glowingBar)
        let fire = arming.update(holding: holding, spaceUnderPointer: space, now: ProcessInfo.processInfo.systemUptime)
        glowingBar = barKey
        if before != (arming.armedSpaceID, glowingBar) { redraw() }
        if let fire { click(fire) }
    }

    private func flashFailure(spaceID: UInt64, message: String) {
        failedSpaceID = spaceID
        redraw()
        let owner = snapshot.locate(spaceID: spaceID)?.display.identifier
        let anchor = owner.flatMap { bars[$0] } ?? bars.values.first
        if let anchor { messagePanel.show(message, below: anchor.panel.frame) }
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

/// A short message under the bar, e.g. why a switch failed. Hides itself.
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
        let x = barFrame.midX - width / 2
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
