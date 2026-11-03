import AppKit
import SpacesCore

/// "Manage displays and spaces": a normal window (close, minimise, resize)
/// showing a copy of every display's bar, connected displays first (in macOS's
/// display order), then disconnected ones.
///
/// Clicking a Space switches to it and hovering shows its apps, as on the bars.
/// "Show first Space" next to each display shows or hides its first Space here
/// and on its bar (shown by default).
/// A disconnected display's Space can be dragged onto the bar of the connected
/// display it's on now, which takes it out of the disconnected display's group;
/// Forget drops a disconnected display. Command-Z undoes either, Shift-Command-Z
/// redoes it. Both change only how the app groups
/// Spaces (its own preferences): macOS gives apps no way to move a Space to
/// another display, so no window or Space moves.
///
/// An `AppWindow`: the app shows in the Dock while it's open.
@MainActor
final class ManageWindowController: NSObject, NSWindowDelegate {
    private struct TileEntry {
        let view: TileView
        let display: String
        let row: DisplayOverview.Row
    }

    private let bar: BarController
    private var window: AppWindow?
    private let stack = NSStackView()
    private let hint = NSTextField(wrappingLabelWithString: "")
    private var shown: DisplayOverview?
    private var tiles: [TileEntry] = []
    /// Connected displays' bars, by display identifier (drop targets).
    private var connectedBars: [String: ManageBarView] = [:]
    private var dragging = false
    private var reloadAfterDrag = false

    init(bar: BarController) {
        self.bar = bar
        super.init()
        bar.extraTileView = { [weak self] point in self?.tileView(at: point) }
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        reload(force: true)
        window.present()
    }

    /// Refreshes the bars if the window is open and something changed.
    func reload(force: Bool = false) {
        guard let window, force || window.isVisible || window.isMiniaturized else { return }
        if dragging {
            reloadAfterDrag = true
            return
        }
        let overview = bar.overview()
        guard force || overview != shown else { return }
        shown = overview
        fill(overview)
    }

    func windowWillClose(_ notification: Notification) {
        window?.undoManager?.removeAllActions()
        AppWindow.closing(window)
    }

    // MARK: Building

    private func makeWindow() -> AppWindow {
        let window = AppWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 400),
                            styleMask: [.titled, .closable, .miniaturizable, .resizable],
                            backing: .buffered, defer: false)
        window.title = "Displays and Spaces"
        window.minSize = NSSize(width: 420, height: 240)
        window.isReleasedWhenClosed = false
        window.delegate = self

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false

        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 600
        hint.maximumNumberOfLines = 3
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let line = DividerView()
        line.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(scroll)
        root.addSubview(line)
        root.addSubview(hint)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            line.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
            hint.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20),
            hint.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),

            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.widthAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.widthAnchor),
        ])
        window.contentView = root
        window.center()
        window.setFrameAutosaveName("ManageDisplaysAndSpaces")
        return window
    }

    private func fill(_ overview: DisplayOverview) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        tiles = []
        connectedBars = [:]

        // Every display-name cell has one width, and so does every Space cell.
        let labelWidth = overview.sections
            .map { DisplayLabelView(text: $0.name, scale: 1, ghost: !$0.connected).preferredWidth }.max() ?? 0
        let tileWidth = overview.sections.flatMap(\.rows)
            .map { TileView.width(for: tileModel($0), compact: false, scale: 1) }.max() ?? Metrics.normalTile.lowerBound

        let connected = overview.sections.filter(\.connected)
        let disconnected = overview.sections.filter { !$0.connected }
        stack.addArrangedSubview(heading("Connected displays"))
        for section in connected {
            let view = barView(section, labelWidth: labelWidth, tileWidth: tileWidth)
            connectedBars[section.identifier] = view
            stack.addArrangedSubview(horizontal([view, firstSpaceBox(section.identifier)]))
        }
        if let previous = stack.arrangedSubviews.last { stack.setCustomSpacing(18, after: previous) }
        stack.addArrangedSubview(heading("Disconnected displays"))
        if disconnected.isEmpty {
            stack.addArrangedSubview(note("None. When you unplug a display, its Spaces stay grouped here under its name."))
        }
        for section in disconnected {
            let forget = NSButton(title: "Forget", target: self, action: #selector(forget(_:)))
            forget.bezelStyle = .push
            forget.controlSize = .small
            forget.identifier = NSUserInterfaceItemIdentifier(section.identifier)
            forget.toolTip = "Stop grouping this display's Spaces. Only the app's own memory changes."
            stack.addArrangedSubview(horizontal([barView(section, labelWidth: labelWidth, tileWidth: tileWidth),
                                          firstSpaceBox(section.identifier), forget]))
        }
        hint.stringValue = disconnected.isEmpty
            ? "Click a Space to switch to it. Hover to see its apps."
            : "Click a Space to switch to it. Hover to see its apps. Drag a disconnected display's Space onto the bar "
                + "of the display it's on now to move it there. Only the app's grouping changes; windows stay where they are."
    }

    private func horizontal(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    /// "Show first Space" for one display; applies to its bar too.
    private func firstSpaceBox(_ identifier: String) -> NSButton {
        let box = NSButton(checkboxWithTitle: "Show first Space", target: self, action: #selector(toggleFirstSpace(_:)))
        box.controlSize = .small
        box.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        box.state = bar.showsFirstSpace(identifier) ? .on : .off
        box.identifier = NSUserInterfaceItemIdentifier(identifier)
        box.toolTip = "Show this display's first Space here and on its bar"
        return box
    }

    @objc private func toggleFirstSpace(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue else { return }
        setFirstSpace(sender.state == .on, for: identifier)
    }

    /// Shows or hides a display's first Space; undoable.
    private func setFirstSpace(_ shown: Bool, for identifier: String) {
        let before = bar.showsFirstSpace(identifier)
        bar.setShowsFirstSpace(shown, for: identifier)
        reload(force: true)
        guard before != shown, let undo = window?.undoManager else { return }
        undo.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.setFirstSpace(before, for: identifier) }
        }
        undo.setActionName(shown ? "Show First Space" : "Hide First Space")
    }

    private func tileModel(_ row: DisplayOverview.Row) -> TileModel {
        let kind = row.isFullScreen ? "Full-screen Space" : (row.spaceID == nil ? "Space" : "Desktop \(row.number)")
        return TileModel(spaceID: row.spaceID ?? 0, number: row.number, name: row.name,
                         state: row.isCurrent ? .current : .normal, isFullScreen: row.isFullScreen, failed: false,
                         accessibilityLabel: "\(kind), \(row.name)" + (row.note.map { ", " + $0 } ?? ""))
    }

    /// One display's bar: its name, then its Spaces, all cells the same size.
    private func barView(_ section: DisplayOverview.Section, labelWidth: CGFloat, tileWidth: CGFloat) -> ManageBarView {
        let height = Metrics.barHeight
        let tileY = (height - Metrics.tileHeight) / 2
        let view = ManageBarView(ghost: !section.connected)
        view.setAccessibilityLabel(section.name)
        var x = Metrics.inset + Metrics.groupPadding

        let label = DisplayLabelView(text: section.name, scale: 1, ghost: !section.connected)
        label.frame = NSRect(x: x, y: tileY, width: labelWidth, height: Metrics.tileHeight)
        if let lastSeen = section.lastSeen {
            let date = DateFormatter.localizedString(from: Date(timeIntervalSince1970: lastSeen),
                                                     dateStyle: .medium, timeStyle: .short)
            label.toolTip = "Disconnected; last connected \(date)"
        } else {
            let key = "display:" + section.identifier
            label.toolTip = "Right-click or double-click to rename this display"
            label.canReset = bar.hasCustomName(displayKey: key)
            label.onRename = { [weak bar = self.bar] in bar?.renameDisplay(key: key) }
            label.onReset = { [weak bar = self.bar] in bar?.resetDisplay(key: key) }
        }
        view.addSubview(label)
        x += labelWidth + Metrics.gap

        if section.rows.isEmpty {
            let empty = DisplayLabelView(text: "No Spaces", scale: 1, ghost: true)
            empty.toolTip = nil
            empty.frame = NSRect(x: x, y: tileY, width: empty.preferredWidth, height: Metrics.tileHeight)
            view.addSubview(empty)
            x += empty.preferredWidth + Metrics.gap
        }
        for row in section.rows {
            let tile = TileView(model: tileModel(row), compact: false, scale: 1)
            tile.frame = NSRect(x: x, y: tileY, width: tileWidth, height: Metrics.tileHeight)
            tile.toolTip = bar.showsAppsOnHover && row.spaceID != nil
                ? nil : [row.name, row.note].compactMap { $0 }.joined(separator: " – ")
            if let id = row.spaceID {
                // Same as on the bars: click switches, hover shows the apps.
                tile.onClick = { [weak self] in self?.switchTo(id) }
                tile.onRename = { [weak bar = self.bar] in bar?.renameSpace(id: id) }
                tile.onHover = { [weak bar = self.bar, weak tile] inside in
                    guard let tile else { return }
                    bar?.hover(tile, inside: inside)
                }
            } else {
                tile.alphaValue = 0.55
            }
            if row.remembered != nil {
                // A disconnected display's Space can also be dragged.
                tile.onPress = { [weak self, weak tile] event in
                    guard let self, let tile else { return }
                    self.press(tile, display: section.identifier, row: row, event: event)
                }
            }
            tiles.append(TileEntry(view: tile, display: section.identifier, row: row))
            view.addSubview(tile)
            x += tileWidth + Metrics.gap
        }
        x += Metrics.groupPadding - Metrics.gap + Metrics.inset

        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: x).isActive = true
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    @objc private func forget(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue else { return }
        if let record = bar.forgetDisplay(identifier) { registerRestore(record) }
        reload(force: true)
    }

    // MARK: Undo and redo
    //
    // Each change registers its inverse; an inverse run by undo registers the
    // change again, which becomes the redo. Only the app's grouping changes.

    private func registerRestore(_ record: DisplayMemory.Record) {
        guard let undo = window?.undoManager else { return }
        undo.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.bar.restoreDisplay(record)
                target.registerForget(record.identifier)
                target.reload(force: true)
            }
        }
        undo.setActionName("Forget Display")
    }

    private func registerForget(_ identifier: String) {
        guard let undo = window?.undoManager else { return }
        undo.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                if let record = target.bar.forgetDisplay(identifier) { target.registerRestore(record) }
                target.reload(force: true)
            }
        }
        undo.setActionName("Forget Display")
    }

    private func registerPutBack(_ space: DisplayMemory.RememberedSpace, at index: Int, into display: String) {
        guard let undo = window?.undoManager else { return }
        undo.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.bar.putBackGhostSpace(space, at: index, into: display)
                target.registerMove(space, from: display)
                target.reload(force: true)
            }
        }
        undo.setActionName("Move Space")
    }

    private func registerMove(_ space: DisplayMemory.RememberedSpace, from display: String) {
        guard let undo = window?.undoManager else { return }
        undo.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                if let index = target.bar.removeGhostSpace(space, from: display) {
                    target.registerPutBack(space, at: index, into: display)
                }
                target.reload(force: true)
            }
        }
        undo.setActionName("Move Space")
    }

    // MARK: Dragging a disconnected display's Space

    /// Switches Space like the bars, then brings this window to the front and focuses it:
    /// macOS hands focus to an app on the new Space, so take it back, once right
    /// away and once after macOS has finished switching.
    private func switchTo(_ id: UInt64) {
        bar.click(id) { [weak self] in
            self?.refocus()
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: Self.refocusDelay)
                self?.refocus()
            }
        }
    }

    private static let refocusDelay: UInt64 = 300_000_000

    private func refocus() {
        guard let window, window.isVisible, !window.isMiniaturized else { return }
        window.bringToFront()
    }

    /// Mouse-down on a disconnected display's Space: a drag moves it, a quick
    /// click switches to it (like the bars), Control-click or double-click renames it.
    private func press(_ tile: TileView, display: String, row: DisplayOverview.Row, event: NSEvent) {
        if event.modifierFlags.contains(.control) || event.clickCount == 2 {
            if let id = row.spaceID { bar.renameSpace(id: id) }
            return
        }
        let dragged = track(event, from: tile, row: row, display: display)
        // Like the bars: only a quick click switches; pressing and holding is for grabbing.
        let held = ProcessInfo.processInfo.systemUptime - event.timestamp
        if !dragged, held <= TileView.maxClickHold, let id = row.spaceID { switchTo(id) }
    }

    /// Follows the pointer; a copy of the Space moves along. Dropping it on the
    /// bar of the display its live Space is on moves it there (grouping only);
    /// anywhere else does nothing. Returns false if the mouse never moved.
    private func track(_ event: NSEvent, from source: NSView, row: DisplayOverview.Row, display: String) -> Bool {
        guard let window, let root = window.contentView else { return false }
        let start = event.locationInWindow
        let hintBefore = hint.stringValue
        var preview: NSImageView?
        var grab = NSPoint.zero
        var target: String?
        dragging = true
        defer {
            dragging = false
            preview?.removeFromSuperview()
            highlight(nil)
            hint.stringValue = hintBefore
            if reloadAfterDrag {
                reloadAfterDrag = false
                reload()
            }
        }
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration,
                           mode: .eventTracking) { event, stop in
            guard let event else {
                stop.pointee = true
                return
            }
            let point = event.locationInWindow
            if preview == nil, hypot(point.x - start.x, point.y - start.y) > 3 {
                preview = self.preview(of: source, in: root)
                if let frame = preview?.frame {
                    let startInRoot = root.convert(start, from: nil)
                    grab = NSPoint(x: startInRoot.x - frame.minX, y: startInRoot.y - frame.minY)
                }
                self.hint.stringValue = self.dragHint(row)
            }
            if let preview {
                let inRoot = root.convert(point, from: nil)
                preview.setFrameOrigin(NSPoint(x: inRoot.x - grab.x, y: inRoot.y - grab.y))
                target = self.dropTarget(at: point, for: row)
                self.highlight(target)
            }
            if event.type == .leftMouseUp { stop.pointee = true }
        }
        guard preview != nil else { return false }
        if target != nil, let remembered = row.remembered,
           let index = bar.removeGhostSpace(remembered, from: display) {
            registerPutBack(remembered, at: index, into: display)
        }
        return true
    }

    private func dragHint(_ row: DisplayOverview.Row) -> String {
        guard let display = row.onDisplay,
              let name = shown?.sections.first(where: { $0.identifier == display })?.name else {
            return "macOS no longer has this Space, so it can't be moved. Forget the display to drop it."
        }
        return "Drop on the \(name) bar: macOS already moved this Space there, and it can't be moved to another display."
    }

    /// A translucent copy of `view`, placed over it.
    private func preview(of view: NSView, in root: NSView) -> NSImageView? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        let copy = NSImageView(frame: view.convert(view.bounds, to: root))
        copy.image = image
        copy.imageScaling = .scaleNone
        copy.alphaValue = 0.75
        root.addSubview(copy)
        return copy
    }

    /// The connected display under the pointer, if the Space may be dropped there.
    private func dropTarget(at windowPoint: NSPoint, for row: DisplayOverview.Row) -> String? {
        connectedBars.first { identifier, view in
            view.convert(view.bounds, to: nil).contains(windowPoint) && DisplayOverview.canMove(row, to: identifier)
        }?.key
    }

    private func highlight(_ target: String?) {
        for (identifier, view) in connectedBars { view.highlighted = identifier == target }
    }

    /// The tile under a point in screen coordinates (for the hover column).
    private func tileView(at screenPoint: NSPoint) -> TileView? {
        guard !dragging, let window, window.isVisible, !window.isMiniaturized,
              window.frame.contains(screenPoint) else { return nil }
        let point = window.convertPoint(fromScreen: screenPoint)
        return tiles.first { $0.view.convert($0.view.bounds, to: nil).contains(point) }?.view
    }

    private func heading(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text.uppercased())
        field.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        field.textColor = .secondaryLabelColor
        return field
    }

    private func note(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = NSFont.systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        return field
    }
}

/// A bar in the Manage window: looks like the floating bars; a disconnected
/// display's bar has a dashed border. Lights up while a Space may be dropped on it.
@MainActor
private final class ManageBarView: NSView {
    let ghost: Bool
    var highlighted = false {
        didSet { if highlighted != oldValue { needsDisplay = true } }
    }

    init(ghost: Bool) {
        self.ghost = ghost
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 11, yRadius: 11)
        let base = NSColor.controlBackgroundColor
        (highlighted ? (base.blended(withFraction: 0.25, of: .controlAccentColor) ?? base) : base).setFill()
        path.fill()
        if highlighted {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
        } else {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            if ghost { path.setLineDash([4, 3], count: 2, phase: 0) }
        }
        path.stroke()
    }
}

/// Lays the list out from the top.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
