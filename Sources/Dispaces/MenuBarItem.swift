import AppKit
import SpacesCore

/// What the Space tiles show: every display's tiles, left to right.
struct TilesContent: Equatable {
    struct Entry: Equatable {
        let tile: TileModel
        /// An unplugged display's Space that macOS moved onto a connected display.
        let dimmed: Bool
    }

    var entries: [Entry] = []
    /// How `entries` split into displays (and unplugged displays' groups).
    var runs: [MenuBarGeometry.Run] = []
    /// Show the amber "!" (setup needs attention, or the Space list can't be read).
    var warning = false
    /// Spoken by VoiceOver for the whole item.
    var summary = "Dispaces"
}

/// A tile the pointer is resting on, for the apps column.
struct HoverTile {
    let spaceID: UInt64
    let name: String
    /// The tile's frame on screen.
    let frame: NSRect
    let screen: NSScreen?
}

/// A row of small square Space tiles. Shown in the menu bar item and in the
/// fallback bar. Draws itself, so it follows the menu bar's light or dark look.
///
/// Click a tile: switch to it. Click the "!": Setup check. Right-click (or
/// Control-click) anywhere, or click between displays: the Dispaces menu.
@MainActor
final class SpaceTilesView: NSView {
    var onClick: ((UInt64) -> Void)?
    var onWarning: (() -> Void)?
    /// Open the menu; the Space under the pointer, if any, can be renamed from it.
    var onMenu: ((UInt64?, NSEvent) -> Void)?
    /// Pointer entered (true) or left (false) a tile.
    var onHover: ((HoverTile, Bool) -> Void)?

    private(set) var content = TilesContent()
    let metrics: MenuBarGeometry.Metrics
    private var layout: MenuBarGeometry.Layout
    private var hovered: Int?
    /// The tile the pointer is on now, placed where the pointer actually is.
    private var hoveredTile: HoverTile?
    private var tips: [ToolTipText] = []
    private var showsToolTips = true
    /// When the current press started, if it may still become a click.
    private var pressStart: (time: TimeInterval, point: NSPoint)?

    /// `height`: the height the tiles must fit in (the menu bar's thickness).
    init(height: CGFloat) {
        metrics = .forMenuBar(thickness: Double(height))
        layout = MenuBarGeometry.layout([], warning: false, metrics: metrics)
        super.init(frame: NSRect(x: 0, y: 0, width: CGFloat(layout.width), height: height))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(content.summary)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// The width the tiles need.
    var neededWidth: CGFloat { CGFloat(layout.width) }

    /// Shows `content`. Returns false when nothing changed.
    @discardableResult
    func update(_ content: TilesContent, showsToolTips: Bool) -> Bool {
        guard content != self.content || showsToolTips != self.showsToolTips else { return false }
        self.content = content
        self.showsToolTips = showsToolTips
        layout = MenuBarGeometry.layout(content.runs, warning: content.warning, metrics: metrics)
        setAccessibilityLabel(content.summary)
        if let hovered, hovered >= content.entries.count {
            self.hovered = nil
            hoveredTile = nil
        }
        resetToolTips()
        needsDisplay = true
        return true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resetToolTips()
    }

    // MARK: Geometry

    private func tileRect(_ index: Int) -> NSRect {
        let side = CGFloat(metrics.tile)
        return NSRect(x: CGFloat(layout.tileXs[index]), y: (bounds.height - side) / 2, width: side, height: side)
    }

    private func hit(_ event: NSEvent) -> MenuBarGeometry.Hit {
        let point = localPoint(event)
        guard point.y >= 0, point.y <= bounds.height else { return .gap }
        return MenuBarGeometry.hit(x: Double(point.x), in: layout, metrics: metrics)
    }

    /// Where the pointer is, in this view. Taken from the pointer's position on
    /// screen when it's over this view's window, since a menu bar event can come
    /// from a window other than the one holding the item.
    private func localPoint(_ event: NSEvent) -> NSPoint {
        if let window {
            let screenPoint = NSEvent.mouseLocation
            if window.frame.contains(screenPoint) {
                return convert(window.convertPoint(fromScreen: screenPoint), from: nil)
            }
        }
        return convert(event.locationInWindow, from: nil)
    }

    private func spaceID(at hit: MenuBarGeometry.Hit) -> UInt64? {
        guard case .tile(let index) = hit, index < content.entries.count else { return nil }
        return content.entries[index].tile.spaceID
    }

    /// The tile under a point in screen coordinates, if this view is on screen and shows one there.
    func hoverTile(atScreen point: NSPoint) -> HoverTile? {
        guard let window, window.isVisible, window.frame.contains(point) else { return nil }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        guard bounds.contains(local),
              case .tile(let index) = MenuBarGeometry.hit(x: Double(local.x), in: layout, metrics: metrics),
              index < content.entries.count else { return nil }
        return hoverTile(index)
    }

    private func hoverTile(_ index: Int) -> HoverTile? {
        guard let window, index < content.entries.count else { return nil }
        // The whole height, so the apps column opens just under the menu bar.
        let rect = NSRect(x: tileRect(index).minX, y: 0, width: CGFloat(metrics.tile), height: bounds.height)
        let tile = content.entries[index].tile
        return HoverTile(spaceID: tile.spaceID, name: tile.name,
                         frame: window.convertToScreen(convert(rect, to: nil)), screen: window.screen)
    }

    /// The whole row's frame on screen.
    var screenFrame: NSRect? {
        window.map { $0.convertToScreen(convert(bounds, to: nil)) }
    }

    // MARK: Tooltips

    private func resetToolTips() {
        removeAllToolTips()
        tips = []
        guard showsToolTips else { return }
        for (index, entry) in content.entries.enumerated() where index < layout.tileXs.count {
            let tip = ToolTipText(entry.tile.name)
            tips.append(tip)
            _ = addToolTip(tileRect(index).insetBy(dx: -CGFloat(metrics.gap) / 2, dy: 0), owner: tip, userData: nil)
        }
    }

    // MARK: Mouse

    /// In the menu bar the status item's button takes the clicks (macOS's own
    /// status item handling) and passes them on with `buttonClicked`; this view
    /// only draws and tracks hovering there.
    var clicksGoToButton = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        clicksGoToButton ? nil : super.hitTest(point)
    }

    /// A click on the status item's button (sent on mouse up): left click on a
    /// tile switches, on the "!" opens Setup check, between groups opens the
    /// menu; right-click or Control-click opens the menu.
    func buttonClicked(_ event: NSEvent) {
        setHovered(nil)
        pressStart = nil
        let hit = hit(event)
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            onMenu?(spaceID(at: hit), event)
            return
        }
        switch hit {
        case .tile:
            if let id = spaceID(at: hit) { onClick?(id) }
        case .warning:
            onWarning?()
        case .gap:
            let x = Double(localPoint(event).x)
            log.notice("Menu bar click between tiles at x \(x, privacy: .public) of \(Double(self.bounds.width), privacy: .public)")
            onMenu?(nil, event)
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        resetTrackingArea([.mouseMoved, .mouseEnteredAndExited])
    }

    override func mouseEntered(with event: NSEvent) { track(event) }
    override func mouseMoved(with event: NSEvent) { track(event) }
    override func mouseExited(with event: NSEvent) { setHovered(nil) }

    private func track(_ event: NSEvent) {
        if case .tile(let index) = hit(event) { setHovered(index, event: event) } else { setHovered(nil) }
    }

    private func setHovered(_ index: Int?, event: NSEvent? = nil) {
        guard index != hovered else { return }
        if let old = hoveredTile { onHover?(old, false) }
        hovered = index
        hoveredTile = index.flatMap { index in event.flatMap { hoverTile(index, pointerEvent: $0) } }
        if let tile = hoveredTile { onHover?(tile, true) }
    }

    /// The Space whose tile the pointer is on, as the last mouse event said.
    var hoveredSpaceID: UInt64? { hoveredTile?.spaceID }

    /// A tile's frame on screen, measured from the pointer. On Spaces other
    /// than the first, macOS can show the menu bar item through a window other
    /// than the one holding this view, so its frame isn't where the tile is.
    private func hoverTile(_ index: Int, pointerEvent event: NSEvent) -> HoverTile? {
        guard index < content.entries.count, index < layout.tileXs.count else { return nil }
        let local = localPoint(event)
        let pointer = NSEvent.mouseLocation
        let frame = NSRect(x: pointer.x - (local.x - CGFloat(layout.tileXs[index])), y: pointer.y - local.y,
                           width: CGFloat(metrics.tile), height: bounds.height)
        let tile = content.entries[index].tile
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? window?.screen
        return HoverTile(spaceID: tile.spaceID, name: tile.name, frame: frame, screen: screen)
    }

    override func mouseDown(with event: NSEvent) {
        setHovered(nil)
        let hit = hit(event)
        if event.modifierFlags.contains(.control) || hit == .gap {
            pressStart = nil
            onMenu?(spaceID(at: hit), event)
        } else {
            pressStart = (event.timestamp, event.locationInWindow)
        }
    }

    /// The click happens on release: quick, and on the same tile it started on.
    override func mouseUp(with event: NSEvent) {
        guard let start = pressStart else { return }
        pressStart = nil
        let point = event.locationInWindow
        guard event.timestamp - start.time <= TileView.maxClickHold,
              hypot(point.x - start.point.x, point.y - start.point.y) <= 3 else { return }
        switch hit(event) {
        case .tile:
            if let id = spaceID(at: hit(event)) { onClick?(id) }
        case .warning:
            onWarning?()
        case .gap:
            break
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        setHovered(nil)
        pressStart = nil
        onMenu?(spaceID(at: hit(event)), event)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        for (index, entry) in content.entries.enumerated() where index < layout.tileXs.count {
            drawTile(entry, in: tileRect(index))
        }
        if let warningX = layout.warningX {
            let side = CGFloat(metrics.tile)
            drawWarning(in: NSRect(x: CGFloat(warningX), y: (bounds.height - side) / 2, width: side, height: side))
        }
    }

    /// The same looks as the old floating bar: the current Space of the display
    /// you're using is filled blue, the current Space of another display has a
    /// blue ring, a full-screen Space has a dashed border.
    private func drawTile(_ entry: TilesContent.Entry, in rect: NSRect) {
        let tile = entry.tile
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 3.5, yRadius: 3.5)
        path.lineWidth = 1.2
        var numberColor: NSColor
        switch tile.state {
        case .focused:
            Palette.focusFill.setFill()
            path.fill()
            Palette.focusFill.setStroke()
            numberColor = .white
        case .current:
            NSColor.quaternaryLabelColor.setFill()
            path.fill()
            Palette.ring.setStroke()
            path.lineWidth = 1.6
            numberColor = .labelColor
        case .normal:
            NSColor.labelColor.withAlphaComponent(0.45).setStroke()
            numberColor = .labelColor
        }
        if tile.armed {
            NSColor.systemYellow.setFill()
            path.fill()
            NSColor.systemYellow.setStroke()
            numberColor = .black
        }
        if tile.failed {
            Palette.warning.setStroke()
            path.lineWidth = 1.6
        }
        if tile.isFullScreen { path.setLineDash([2, 1.5], count: 2, phase: 0) }

        NSGraphicsContext.saveGraphicsState()
        if entry.dimmed && tile.state == .normal && !tile.armed {
            NSGraphicsContext.current?.cgContext.setAlpha(0.55)
        }
        path.stroke()
        let size = (tile.number.count > 1 ? 0.5 : 0.6) * rect.height
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: tile.state == .normal ? .medium : .bold),
            .foregroundColor: numberColor,
        ]
        let text = tile.number as NSString
        let textSize = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawWarning(in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 3.5, yRadius: 3.5)
        path.lineWidth = 1.2
        Palette.warning.setStroke()
        path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 0.65 * rect.height, weight: .bold),
                                                    .foregroundColor: Palette.warning]
        let size = ("!" as NSString).size(withAttributes: attrs)
        ("!" as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }
}

/// A tooltip's text (the owner `addToolTip` asks for the string).
final class ToolTipText: NSObject, NSViewToolTipOwner {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        text
    }
}

/// The Spaces in the macOS menu bar: one status item holding the tiles.
///
/// macOS decides whether a status item is on screen: it hides items that don't
/// fit (a crowded menu bar, the notch), hides the whole menu bar over
/// full-screen apps or when it's set to hide automatically, and lets the user
/// switch items off in System Settings › Menu Bar. `isShowing` reports whether
/// it's on screen right now, so the fallback bar can stand in.
@MainActor
final class MenuBarItem: NSObject {
    let view = SpaceTilesView(height: NSStatusBar.system.thickness)
    private let item: NSStatusItem
    /// The item may have appeared or disappeared.
    var onVisibilityChange: (() -> Void)?

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        // Remembers where the user Command-dragged it; can't be dragged out of the menu bar.
        item.autosaveName = "DispacesSpaces"
        item.behavior = []
        item.isVisible = true
        if let button = item.button {
            button.image = nil
            button.title = ""
            view.frame = button.bounds
            view.autoresizingMask = [.width, .height]
            view.clicksGoToButton = true
            button.addSubview(view)
            button.target = self
            button.action = #selector(buttonClicked(_:))
            _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        item.length = view.neededWidth
        NotificationCenter.default.addObserver(self, selector: #selector(windowChanged(_:)),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowChanged(_:)),
                                               name: NSWindow.didChangeScreenNotification, object: nil)
    }

    func update(_ content: TilesContent, showsToolTips: Bool) {
        guard view.update(content, showsToolTips: showsToolTips) else { return }
        item.length = view.neededWidth
    }

    /// True while the item is on a screen and macOS says some of it is visible.
    var isShowing: Bool {
        guard item.isVisible, let window = item.button?.window, window.isVisible,
              window.occlusionState.contains(.visible) else { return false }
        let middle = NSPoint(x: window.frame.midX, y: window.frame.midY)
        return NSScreen.screens.contains { $0.frame.contains(middle) }
    }

    @objc private func buttonClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        view.buttonClicked(event)
    }

    @objc private func windowChanged(_ note: Notification) {
        guard let window = note.object as? NSWindow, window === item.button?.window else { return }
        onVisibilityChange?()
    }
}

/// Stands in for the menu bar item while macOS isn't showing it: a small
/// floating bar with the same tiles, centred at the top of the display with
/// the menu bar. Never takes focus.
@MainActor
final class FallbackBar: FloatingPanel {
    static let height: CGFloat = 26
    let tiles = SpaceTilesView(height: FallbackBar.height)
    private let box = NSView()

    init() {
        super.init(size: NSSize(width: 100, height: Self.height))
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        box.wantsLayer = true
        box.layer?.cornerRadius = 7
        box.layer?.borderWidth = 1
        box.addSubview(tiles)
        contentView = box
        box.setAccessibilityElement(true)
        box.setAccessibilityRole(.group)
        box.setAccessibilityLabel("Dispaces")
    }

    func update(_ content: TilesContent, showsToolTips: Bool) {
        tiles.update(content, showsToolTips: showsToolTips)
        if isVisible { place() }
    }

    func showBar() {
        place()
        orderFrontRegardless()
    }

    /// Centred under the menu bar (or at the very top when the menu bar is hidden).
    private func place() {
        box.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        let pad: CGFloat = 2
        let size = NSSize(width: tiles.neededWidth + 2 * pad, height: Self.height)
        tiles.frame = NSRect(x: pad, y: 0, width: tiles.neededWidth, height: Self.height)
        guard let screen = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let width = min(size.width, visible.width)
        let frame = NSRect(x: visible.midX - width / 2, y: visible.maxY - size.height - 2,
                           width: width, height: size.height)
        if frame != self.frame { setFrame(frame, display: true) }
    }
}
