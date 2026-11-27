import AppKit
import SpacesCore

/// What one tile shows.
struct TileModel: Equatable {
    /// Seen from the display you're working on (the one with the focus).
    enum State: Equatable {
        /// That display shows it. Strong orange.
        case strong
        /// Only other displays show it, so the displays differ. Pale orange.
        case pale
        case normal

        init(_ highlight: LogicalSpaces.Highlight) {
            switch highlight {
            case .here: self = .strong
            case .elsewhere: self = .pale
            case .none: self = .normal
            }
        }
    }

    let target: TileTarget
    let number: String
    let name: String
    let state: State
    let isFullScreen: Bool
    let failed: Bool
    /// A window is being Option-Control-dragged onto this tile (thick ring).
    var armed = false
    let accessibilityLabel: String
}

enum Palette {
    /// Fill of a tile the display you're working on shows (`TileModel.State.strong`), and the ring of a pale one.
    static let strong = NSColor.systemOrange
    /// Fill of a tile only other displays show (`TileModel.State.pale`).
    static let pale = NSColor.systemOrange.withAlphaComponent(0.35)
    /// Ring of a tile whose switch failed.
    static let failed = NSColor.systemRed
    /// The setup "!" and message borders.
    static let warning = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 0xB3 / 255.0, blue: 0x40 / 255.0, alpha: 1)
            : NSColor(srgbRed: 0xA0 / 255.0, green: 0x5A / 255.0, blue: 0, alpha: 1)
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
    /// Display names, a size above the Space names so the rows read at a glance.
    static func labelFont(_ scale: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: 12 * scale, weight: .semibold)
    }
    /// Column headings (logical spaces) are drawn this much larger than the
    /// Spaces under them (13 pt names instead of 11 pt); the Spaces keep their size.
    static let headerScale: CGFloat = 13.0 / 11.0
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

/// The rounded box of a floating panel (apps column, message, floating bar).
///
/// Its colours are set in `updateLayer()`, which AppKit runs with the box's
/// own light or dark appearance, and again whenever that changes. A colour set
/// once when the panel opens keeps the look macOS had then: after macOS
/// switched to Dark, the background stayed white behind the now white text.
@MainActor
class PanelBoxView: NSView {
    var fill: NSColor = .windowBackgroundColor {
        didSet { needsDisplay = true }
    }
    /// Applied when drawing: `withAlphaComponent` would fix the colour's look.
    var fillAlpha: CGFloat = 1 {
        didSet { needsDisplay = true }
    }
    var border: NSColor = .separatorColor {
        didSet { needsDisplay = true }
    }

    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = fill.cgColor.copy(alpha: fillAlpha) ?? fill.cgColor
        layer?.borderColor = border.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
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
    /// The rename item in the tile's right-click menu.
    var renameTitle = "Rename Space…"
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
        screenFrame.map { HoverTile(target: model.target, name: model.name, frame: $0, screen: window?.screen) }
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
        let number = model.number.isEmpty ? 0
            : (model.number as NSString).size(withAttributes: [.font: Metrics.numberFont(scale)]).width + 6
        let range = compact ? Metrics.compactTile : Metrics.normalTile
        let padding: CGFloat = compact ? 12 : 18
        return min(max(ceil(text + number + padding), range.lowerBound * scale), range.upperBound * scale)
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
        let item = NSMenuItem(title: renameTitle, action: #selector(renameFromMenu), keyEquivalent: "")
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
        case .strong:
            Palette.strong.setFill()
            path.fill()
            Palette.strong.setStroke()
            textColor = .black
            numberColor = NSColor.black.withAlphaComponent(0.7)
        case .pale:
            Palette.pale.setFill()
            path.fill()
            Palette.strong.setStroke()
            textColor = .labelColor
            numberColor = .secondaryLabelColor
        case .normal:
            NSColor.separatorColor.setStroke()
            textColor = .labelColor
            numberColor = .secondaryLabelColor
        }
        if model.armed {
            NSColor.labelColor.setStroke()
            path.lineWidth = 2.5
        }
        if model.failed {
            Palette.failed.setStroke()
            path.lineWidth = 2
        }
        if model.isFullScreen { path.setLineDash([3, 2], count: 2, phase: 0) }
        path.stroke()

        let padding: CGFloat = compact ? 6 : 9
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        var x = padding
        if model.number.isEmpty {
            // A name alone (a column heading in the Manage window) is centred.
            style.alignment = .center
        } else {
            let numberAttrs: [NSAttributedString.Key: Any] = [.font: Metrics.numberFont(scale), .foregroundColor: numberColor]
            let numberSize = (model.number as NSString).size(withAttributes: numberAttrs)
            let numberOrigin = NSPoint(x: padding, y: (bounds.height - numberSize.height) / 2)
            (model.number as NSString).draw(at: numberOrigin, withAttributes: numberAttrs)
            x = numberOrigin.x + numberSize.width + 6
        }

        let font = Metrics.tileFont(scale, bold: model.state != .normal)
        let nameAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor, .paragraphStyle: style]
        let nameHeight = (model.name as NSString).size(withAttributes: nameAttrs).height
        let nameRect = NSRect(x: x, y: (bounds.height - nameHeight) / 2, width: max(0, bounds.width - x - padding + 2), height: nameHeight)
        (model.name as NSString).draw(with: nameRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: nameAttrs)
    }
}

/// An empty cell in the Manage window grid: this display has no Space with
/// the column's name. Lights up while a Space from its row may be dropped on it.
@MainActor
final class NotAssignedView: NSView {
    let text: String
    var highlighted = false {
        didSet { if highlighted != oldValue { needsDisplay = true } }
    }

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        if highlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
        } else {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.setLineDash([3, 2], count: 2, phase: 0)
        }
        path.stroke()
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10),
                                                    .foregroundColor: NSColor.tertiaryLabelColor, .paragraphStyle: style]
        let height = (text as NSString).size(withAttributes: attrs).height
        let rect = NSRect(x: 8, y: (bounds.height - height) / 2, width: max(0, bounds.width - 16), height: height)
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
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
        min(ceil((text as NSString).size(withAttributes: attributes).width) + 12, 220 * scale)
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
    private let stack = NSStackView()
    /// Holds the stack, top first; scrolls when the column is taller than the screen allows.
    private let scroll = NSScrollView()
    private let document = FlippedStackHolder()
    private let box = AppsBoxView(cornerRadius: 8)
    /// An app row was clicked, in this section.
    var onPick: ((NSRunningApplication, Section) -> Void)?
    /// A display tile was clicked: go to this Space.
    var onChoose: ((UInt64) -> Void)?
    /// The pointer left the column.
    var onExit: (() -> Void)? {
        get { box.onExit }
        set { box.onExit = newValue }
    }

    init() {
        super.init(size: NSSize(width: 160, height: 40))
        animationBehavior = .none

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = true
        document.addSubview(stack)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        box.addSubview(scroll)
        contentView = box
    }

    /// One display's apps in the column; the heading names the display when a
    /// logical space spans several.
    struct Section {
        let heading: String?
        let apps: [NSRunningApplication]
        /// An unplugged display's section: its heading is faded.
        var faded = false
        /// Picking an app in it goes to this Space (an unplugged display's,
        /// where macOS moved it) instead of the tile's.
        var spaceID: UInt64?
    }

    /// A display's Space of the hovered logical space, offered as a tile under
    /// the title when one of them belongs to an unplugged display.
    struct Choice {
        let name: String
        /// An unplugged display's: its name is faded.
        let faded: Bool
        /// Shown on screen now: strong orange.
        let isCurrent: Bool
        let spaceID: UInt64
    }

    /// Shows the apps in a column under (or, near the bottom of the screen, over)
    /// `tile`: the title, then the display tiles (if any), one per line, then
    /// every app. Scrolls when taller than the room on screen.
    func show(title: String, choices: [Choice] = [], sections: [Section], tile: NSRect, screen: NSScreen?) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let heading = NSTextField(labelWithString: title)
        heading.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        heading.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(heading)
        for choice in choices {
            let view = DisplayChoiceView(choice)
            view.onClick = { [weak self] in self?.onChoose?(choice.spaceID) }
            addFullWidth(view)
        }
        if !choices.isEmpty, let last = stack.arrangedSubviews.last { stack.setCustomSpacing(8, after: last) }
        for section in sections {
            if let name = section.heading {
                let label = NSTextField(labelWithString: name.uppercased())
                label.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
                // An unplugged display's name is faded; that's the only difference.
                label.textColor = section.faded ? .tertiaryLabelColor : .secondaryLabelColor
                label.lineBreakMode = .byTruncatingTail
                stack.addArrangedSubview(label)
            }
            if section.apps.isEmpty {
                stack.addArrangedSubview(Self.label("No windows", color: .tertiaryLabelColor))
            }
            for app in section.apps {
                let row = AppRowView(app: app)
                row.onClick = { [weak self] in self?.onPick?(app, section) }
                addFullWidth(row)
            }
        }

        let fitting = stack.fittingSize
        let width = min(max(fitting.width, 120), 260)
        stack.frame = NSRect(x: 0, y: 0, width: width, height: fitting.height)
        stack.layoutSubtreeIfNeeded()
        document.frame = stack.frame
        let visible = screen?.visibleFrame ?? tile.insetBy(dx: -1000, dy: -1000)
        let place = MenuBarGeometry.appsColumn(height: Double(fitting.height), tileBottom: Double(tile.minY),
                                               tileTop: Double(tile.maxY), visibleBottom: Double(visible.minY),
                                               visibleTop: Double(visible.maxY), gap: 4)
        // A scroll bar that takes room ("Always" in System Settings) mustn't cover the rows.
        var panelWidth = width
        if CGFloat(place.height) < fitting.height, NSScroller.preferredScrollerStyle == .legacy {
            panelWidth += NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        }
        let size = NSSize(width: panelWidth, height: CGFloat(place.height))
        scroll.frame = NSRect(origin: .zero, size: size)
        scroll.contentView.scroll(to: .zero)  // top of the list
        scroll.reflectScrolledClipView(scroll.contentView)
        let x = min(max(tile.minX, visible.minX), visible.maxX - panelWidth)
        setFrame(NSRect(origin: NSPoint(x: x, y: CGFloat(place.y)), size: size), display: true)
        orderFrontRegardless()
    }

    /// Adds a row (a display tile or an app) as wide as the column.
    private func addFullWidth(_ row: NSView) {
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                   constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
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

/// A display's tile in the apps column: its name; a click goes to that
/// display's Space of the hovered logical space. Strong orange when that Space
/// is on screen; an unplugged display's name faded. Glows under the pointer.
@MainActor
final class DisplayChoiceView: NSView {
    var onClick: (() -> Void)?
    private let isCurrent: Bool
    private var highlighted = false {
        didSet { if highlighted != oldValue { needsDisplay = true } }
    }

    init(_ choice: AppsPanel.Choice) {
        isCurrent = choice.isCurrent
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: choice.name.uppercased())
        label.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        label.textColor = choice.isCurrent ? .black : (choice.faded ? .tertiaryLabelColor : .secondaryLabelColor)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Go to \(choice.name)'s Space" + (choice.isCurrent ? ", shown now" : ""))
        toolTip = "Go to this display's Space"
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

    /// Drawn (not layer colours), so it follows light and dark mode.
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: 5, yRadius: 5)
        path.lineWidth = 1.2
        if isCurrent {
            Palette.strong.setFill()
            path.fill()
        } else if highlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
            path.fill()
        }
        (isCurrent ? Palette.strong : (highlighted ? NSColor.controlAccentColor : NSColor.separatorColor)).setStroke()
        path.stroke()
    }
}

/// The apps column's scrolling content, laid out from the top.
private final class FlippedStackHolder: NSView {
    override var isFlipped: Bool { true }
}

/// The column's background; reports when the pointer leaves it.
@MainActor
final class AppsBoxView: PanelBoxView {
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
