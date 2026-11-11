import AppKit
import SpacesCore

/// What one tile shows.
struct TileModel: Equatable {
    enum State: Equatable {
        /// Current Space on the display you are using.
        case focused
        /// Current Space on another display.
        case current
        case normal
    }

    let spaceID: UInt64
    let number: String
    let name: String
    let state: State
    let isFullScreen: Bool
    let failed: Bool
    /// A window is being Option-dragged onto this tile (shown in yellow).
    var armed = false
    let accessibilityLabel: String
}

struct GroupModel: Equatable {
    /// Spaces of a disconnected display that macOS moved onto this one,
    /// shown after this display's own Spaces under the old display's name.
    struct Ghost: Equatable {
        let label: String
        let tiles: [TileModel]
    }

    let displayKey: String
    let label: String
    let tiles: [TileModel]
    var ghosts: [Ghost] = []
}

enum Palette {
    static let focusFill = NSColor(srgbRed: 0, green: 0x63 / 255.0, blue: 0xCE / 255.0, alpha: 1)
    static let warning = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 0xB3 / 255.0, blue: 0x40 / 255.0, alpha: 1)
            : NSColor(srgbRed: 0xA0 / 255.0, green: 0x5A / 255.0, blue: 0, alpha: 1)
    }
    static let ring = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x4D / 255.0, green: 0xA3 / 255.0, blue: 1, alpha: 1)
            : focusFill
    }
}

/// Sizes of the Manage window's bars.
enum Metrics {
    static let barHeight: CGFloat = 36
    static let inset: CGFloat = 5
    static let tileHeight: CGFloat = 26
    static let gap: CGFloat = 4
    static let groupPadding: CGFloat = 6
    static let normalTile: ClosedRange<CGFloat> = 64...150
    static let compactTile: ClosedRange<CGFloat> = 40...90

    // Fonts grow with the bar's height; `scale` is 1 at the default height.
    static func tileFont(_ scale: CGFloat, bold: Bool) -> NSFont {
        NSFont.systemFont(ofSize: 11 * scale, weight: bold ? .bold : .medium)
    }
    static func numberFont(_ scale: CGFloat) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 10 * scale, weight: .regular)
    }
    static func labelFont(_ scale: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: 10 * scale, weight: .semibold)
    }
}

/// Base of the app's floating panels (apps column, messages): borderless,
/// non-activating, above normal windows and on every Space. Never key or main,
/// so it never takes focus or your typing.
@MainActor
class FloatingPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

extension NSView {
    /// Replaces the view's tracking areas with one that follows its visible rect.
    /// Always active: the app is never the active app.
    func resetTrackingArea(_ options: NSTrackingArea.Options) {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: options.union([.activeAlways, .inVisibleRect]),
                                       owner: self, userInfo: nil))
    }
}

/// A clickable, rounded tile in the Manage window. Draws itself; no subviews.
@MainActor
final class TileView: NSView {
    let model: TileModel
    let compact: Bool
    let scale: CGFloat
    var onClick: (() -> Void)?
    var onRename: (() -> Void)?
    /// Pointer entered (true) or left (false) the tile.
    var onHover: ((Bool) -> Void)?
    /// A click switches only when the button is let go within this many
    /// seconds; pressing and holding is kept for grabbing.
    static let maxClickHold: TimeInterval = 0.5
    /// When the current press started, if it may still become a click.
    private var pressStart: (time: TimeInterval, point: NSPoint)?

    /// When set, gets every mouse-down instead of the click/rename handling
    /// (a disconnected display's Space in the Manage window can be dragged).
    var onPress: ((NSEvent) -> Void)?

    init(model: TileModel, compact: Bool, scale: CGFloat) {
        self.model = model
        self.compact = compact
        self.scale = scale
        super.init(frame: .zero)
        toolTip = model.name
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(model.accessibilityLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    /// The tile's frame on screen.
    var screenFrame: NSRect? {
        window.map { $0.convertToScreen(convert(bounds, to: nil)) }
    }

    /// This tile, for the apps column.
    var hoverTile: HoverTile? {
        screenFrame.map { HoverTile(spaceID: model.spaceID, name: model.name, frame: $0, screen: window?.screen) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        resetTrackingArea([.mouseEnteredAndExited, .assumeInside])
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    static func width(for model: TileModel, compact: Bool, scale: CGFloat) -> CGFloat {
        let font = Metrics.tileFont(scale, bold: model.state != .normal)
        let text = (model.name as NSString).size(withAttributes: [.font: font]).width
        let number = (model.number as NSString).size(withAttributes: [.font: Metrics.numberFont(scale)]).width
        let range = compact ? Metrics.compactTile : Metrics.normalTile
        let padding: CGFloat = compact ? 12 : 18
        return min(max(ceil(text + number + 6 + padding), range.lowerBound * scale), range.upperBound * scale)
    }

    override func mouseDown(with event: NSEvent) {
        onHover?(false)
        if let onPress {
            onPress(event)
        } else if event.modifierFlags.contains(.control) {
            showMenu(event)
        } else if event.clickCount == 2 {
            pressStart = nil
            onRename?()
        } else if event.clickCount == 1 {
            pressStart = (event.timestamp, event.locationInWindow)
        }
    }

    /// The click happens on release: quick, without moving off the tile.
    override func mouseUp(with event: NSEvent) {
        guard let start = pressStart else { return }
        pressStart = nil
        let point = event.locationInWindow
        guard event.timestamp - start.time <= Self.maxClickHold,
              hypot(point.x - start.point.x, point.y - start.point.y) <= 3,
              bounds.contains(convert(point, from: nil)) else { return }
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onHover?(false)
        showMenu(event)
    }

    private func showMenu(_ event: NSEvent) {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Rename Space…", action: #selector(renameFromMenu), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func renameFromMenu() { onRename?() }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        path.lineWidth = 1.5

        var textColor: NSColor
        var numberColor: NSColor
        switch model.state {
        case .focused:
            Palette.focusFill.setFill()
            path.fill()
            Palette.focusFill.setStroke()
            textColor = .white
            numberColor = NSColor.white.withAlphaComponent(0.85)
        case .current:
            NSColor.quaternaryLabelColor.setFill()
            path.fill()
            Palette.ring.setStroke()
            textColor = .labelColor
            numberColor = .secondaryLabelColor
        case .normal:
            NSColor.separatorColor.setStroke()
            textColor = .labelColor
            numberColor = .secondaryLabelColor
        }
        if model.armed {
            NSColor.systemYellow.setFill()
            path.fill()
            NSColor.systemYellow.setStroke()
            textColor = .black
            numberColor = NSColor.black.withAlphaComponent(0.7)
        }
        if model.failed { Palette.warning.setStroke() }
        if model.isFullScreen { path.setLineDash([3, 2], count: 2, phase: 0) }
        path.stroke()

        let padding: CGFloat = compact ? 6 : 9
        let numberAttrs: [NSAttributedString.Key: Any] = [.font: Metrics.numberFont(scale), .foregroundColor: numberColor]
        let numberSize = (model.number as NSString).size(withAttributes: numberAttrs)
        let numberOrigin = NSPoint(x: padding, y: (bounds.height - numberSize.height) / 2)
        (model.number as NSString).draw(at: numberOrigin, withAttributes: numberAttrs)

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let font = Metrics.tileFont(scale, bold: model.state != .normal)
        let nameAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor, .paragraphStyle: style]
        let nameHeight = (model.name as NSString).size(withAttributes: nameAttrs).height
        let x = numberOrigin.x + numberSize.width + 6
        let nameRect = NSRect(x: x, y: (bounds.height - nameHeight) / 2, width: max(0, bounds.width - x - padding + 2), height: nameHeight)
        (model.name as NSString).draw(with: nameRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: nameAttrs)
    }
}

/// A display's name at the start of its area (Manage window).
@MainActor
final class DisplayLabelView: NSView {
    let text: String
    let scale: CGFloat
    var onRename: (() -> Void)?
    var onReset: (() -> Void)?
    var canReset = false
    var onDrag: ((NSEvent) -> Void)?
    /// Labels the Spaces of a disconnected display: dimmer, can't be renamed here.
    let ghost: Bool

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: Metrics.labelFont(scale),
         .foregroundColor: ghost ? NSColor.tertiaryLabelColor : NSColor.secondaryLabelColor, .kern: 0.8]
    }

    init(text: String, scale: CGFloat, ghost: Bool = false) {
        self.text = text.uppercased()
        self.scale = scale
        self.ghost = ghost
        super.init(frame: .zero)
        toolTip = ghost ? "Spaces of “\(text)”, which is disconnected. macOS moved them to this display."
                        : "Right-click or double-click to rename this display"
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel((ghost ? "Disconnected display " : "Display ") + text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var preferredWidth: CGFloat {
        min(ceil((text as NSString).size(withAttributes: attributes).width) + 12, 160 * scale)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
        } else if event.clickCount == 2 {
            onRename?()
        } else {
            onDrag?(event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !ghost else { return }
        let menu = NSMenu()
        let rename = NSMenuItem(title: "Rename display…", action: #selector(renameFromMenu), keyEquivalent: "")
        rename.target = self
        menu.addItem(rename)
        if canReset {
            let reset = NSMenuItem(title: "Reset to default name", action: #selector(resetFromMenu), keyEquivalent: "")
            reset.target = self
            menu.addItem(reset)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func renameFromMenu() { onRename?() }
    @objc private func resetFromMenu() { onReset?() }

    override func draw(_ dirtyRect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        var attrs = attributes
        attrs[.paragraphStyle] = style
        let height = (text as NSString).size(withAttributes: attrs).height
        let rect = NSRect(x: 6, y: (bounds.height - height) / 2, width: bounds.width - 12, height: height)
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }
}

/// A thin vertical line between display areas.
@MainActor
final class DividerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        bounds.fill()
    }
}

/// The column of app icons shown under a tile while it's hovered.
/// Each app is its own row: it glows under the pointer and a click picks it.
/// Never takes keyboard focus.
@MainActor
final class AppsPanel: FloatingPanel {
    /// Rows shown before "+N more".
    static let maxRows = 12
    private let stack = NSStackView()
    private let box = AppsBoxView()
    /// An app row was clicked.
    var onPick: ((NSRunningApplication) -> Void)?
    /// The pointer left the column.
    var onExit: (() -> Void)? {
        get { box.onExit }
        set { box.onExit = newValue }
    }

    init() {
        super.init(size: NSSize(width: 160, height: 40))
        animationBehavior = .none

        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.borderWidth = 1
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = true
        box.addSubview(stack)
        contentView = box
    }

    /// Shows `apps` in a column under (or, near the bottom of the screen, over) `tile`.
    func show(title: String, apps: [NSRunningApplication], tile: NSRect, screen: NSScreen?) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let heading = NSTextField(labelWithString: title)
        heading.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        heading.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(heading)
        if apps.isEmpty {
            stack.addArrangedSubview(Self.label("No windows", color: .tertiaryLabelColor))
        }
        for app in apps.prefix(Self.maxRows) {
            let row = AppRowView(app: app)
            row.onClick = { [weak self] in self?.onPick?(app) }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                       constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
        }
        if apps.count > Self.maxRows {
            stack.addArrangedSubview(Self.label("+\(apps.count - Self.maxRows) more", color: .secondaryLabelColor))
        }

        box.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        let fitting = stack.fittingSize
        let size = NSSize(width: min(max(fitting.width, 120), 260), height: fitting.height)
        stack.frame = NSRect(origin: .zero, size: size)
        stack.layoutSubtreeIfNeeded()
        let visible = screen?.visibleFrame ?? tile.insetBy(dx: -1000, dy: -1000)
        var origin = NSPoint(x: tile.minX, y: tile.minY - size.height - 4)
        if origin.y < visible.minY { origin.y = tile.maxY + 4 }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        setFrame(NSRect(origin: origin, size: size), display: true)
        orderFrontRegardless()
    }

    /// True when `point` (screen coordinates) is on the column.
    func contains(_ point: NSPoint) -> Bool {
        isVisible && frame.contains(point)
    }

    static func label(_ text: String, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 12)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}

/// The column's background; reports when the pointer leaves it.
@MainActor
final class AppsBoxView: NSView {
    var onExit: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        resetTrackingArea(.mouseEnteredAndExited)
    }

    override func mouseExited(with event: NSEvent) { onExit?() }
}

/// One app in the column: icon and name. Glows under the pointer; a click picks it.
@MainActor
final class AppRowView: NSView {
    var onClick: (() -> Void)?
    private var highlighted = false {
        didSet { if highlighted != oldValue { updateGlow() } }
    }

    init(app: NSRunningApplication) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        let icon = NSImageView(image: app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
        let name = AppsPanel.label(app.localizedName ?? "App", color: .labelColor)
        let row = NSStackView(views: [icon, name])
        row.orientation = .horizontal
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 2, left: 3, bottom: 2, right: 3)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Bring \(app.localizedName ?? "app") to the front")
        toolTip = "Click to bring to the front"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        resetTrackingArea(.mouseEnteredAndExited)
    }

    override func mouseEntered(with event: NSEvent) { highlighted = true }
    override func mouseExited(with event: NSEvent) { highlighted = false }
    override func mouseDown(with event: NSEvent) { onClick?() }

    /// A soft accent-coloured glow behind the row.
    private func updateGlow() {
        guard let layer else { return }
        let accent = NSColor.controlAccentColor
        layer.backgroundColor = highlighted ? accent.withAlphaComponent(0.22).cgColor : nil
        layer.shadowColor = accent.cgColor
        layer.shadowRadius = highlighted ? 6 : 0
        layer.shadowOpacity = highlighted ? 0.8 : 0
        layer.shadowOffset = .zero
        layer.masksToBounds = false
    }
}
