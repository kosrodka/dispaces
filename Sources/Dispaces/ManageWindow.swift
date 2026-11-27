import AppKit
import SpacesCore

/// "Manage displays and spaces": a normal window (close, minimise, resize).
///
/// Connected displays are a grid: one column per logical space (the Spaces
/// with one name across displays), one row per display, in macOS's display
/// order. A cell is that display's Space, or "Not assigned" when the display
/// has no Space with the column's name. Disconnected displays follow, each as
/// a bar of its remembered Spaces.
///
/// - A column heading has three rows: the logical space's number, its name, and
///   "Tile displayed", a field for up to 2 characters the menu bar shows
///   instead of the number (empty: the number).
/// - Click a column heading: every display switches. Click a Space: only its
///   display switches. Hovering shows the apps, as in the menu bar.
/// - Double-click (or right-click › Rename) a heading renames every Space in
///   the column; a Space's cell renames that Space, which moves it to the
///   column with that name. Dragging a Space onto "Not assigned" in its own row
///   gives it that column's name.
/// - A disconnected display's Space can be dragged onto the row of the
///   connected display it's on now, which takes it out of the disconnected
///   display's group; Forget drops a disconnected display. Both change only how
///   the app groups Spaces (its own preferences): macOS gives apps no way to
///   move a Space to another display, so no window or Space moves.
/// - Command-Z undoes renames, tile labels, moves and Forget; Shift-Command-Z redoes them.
/// - Advanced, at the bottom: the app's on/off settings (floating bar, apps on
///   hover, Option-Control drag, launch at login), as tick boxes.
///
/// An `AppWindow`: the app shows in the Dock while it's open.
@MainActor
final class ManageWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    /// What the window shows; redrawn only when this changes.
    private struct Shown: Equatable {
        let overview: DisplayOverview
        let logical: LogicalSpaces
        /// The display you're working on; the headings are coloured as seen from it.
        let focused: String?
    }

    /// An empty grid cell, a drop target for the Spaces of its row.
    private struct Placeholder {
        let view: NotAssignedView
        let display: String
        let columnKey: String
    }

    /// What a press on a tile turned into.
    private enum Press {
        /// The mouse never moved: a click.
        case click
        /// Dragged and let go over this drop target (nil: nowhere useful).
        case dropped(String?)
    }

    private let bar: BarController
    private var window: AppWindow?
    private let stack = NSStackView()
    private let hint = NSTextField(wrappingLabelWithString: "")
    private var shown: Shown?
    /// Every tile, for the hover column.
    private var tiles: [TileView] = []
    /// Connected displays' rows, by display identifier (drop targets for a disconnected display's Space).
    private var connectedBars: [String: ManageBarView] = [:]
    private var placeholders: [Placeholder] = []
    /// The "Tile displayed" fields, by logical key.
    private var labelFields: [String: LabelField] = [:]
    private var dragging = false
    /// A reload waits while a Space is dragged or a tile label is typed.
    private var reloadLater = false

    /// An on/off setting in the Advanced section.
    private struct Setting {
        let title: String
        let toolTip: String
        let isOn: () -> Bool
        let set: (Bool) -> Void
    }

    /// The Advanced section's tick boxes, in the order of `settings`.
    private var settingBoxes: [NSButton] = []

    /// The heading's rows, top to bottom.
    private static let rowTitles = ["Tile number", "Tile name", "Tile displayed"]
    private static let numberRowHeight: CGFloat = 16
    private static let fieldHeight: CGFloat = 22
    private static let headerGap: CGFloat = 4

    init(bar: BarController) {
        self.bar = bar
        super.init()
        bar.extraTile = { [weak self] point in self?.tileView(at: point)?.hoverTile }
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        reload(force: true)
        window.present()
        // Opening the window doesn't start typing in the first field.
        if isEditingLabel { window.makeFirstResponder(nil) }
    }

    /// True while a "Tile displayed" field is being typed in.
    private var isEditingLabel: Bool {
        labelFields.values.contains { $0.currentEditor() != nil }
    }

    /// Refreshes the grid if the window is open and something changed.
    func reload(force: Bool = false) {
        guard let window, force || window.isVisible || window.isMiniaturized else { return }
        // Rebuilding would drop a drag, or the field being typed in (and Tab to the next).
        if dragging || (!force && isEditingLabel) {
            reloadLater = true
            return
        }
        let now = Shown(overview: bar.overview(), logical: bar.logical, focused: bar.focusedDisplay)
        guard force || now != shown else { return }
        shown = now
        fill(now)
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)  // keeps a tile label being typed
        window?.undoManager?.removeAllActions()
        AppWindow.closing(window)
    }

    /// Launch at login can also be changed in System Settings meanwhile.
    func windowDidBecomeKey(_ notification: Notification) {
        updateSettingBoxes()
    }

    /// Leaving the window saves a tile label being typed.
    func windowDidResignKey(_ notification: Notification) {
        if isEditingLabel { window?.makeFirstResponder(nil) }
    }

    /// A reload that waited for typing runs once the focus has left the fields
    /// (Tab to the next field keeps it waiting).
    func controlTextDidEndEditing(_ notification: Notification) {
        guard reloadLater else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.reloadLater, !self.dragging, !self.isEditingLabel else { return }
                self.reloadLater = false
                self.reload()
            }
        }
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
        document.onClick = { [weak window] in window?.makeFirstResponder(nil) }
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
        hint.maximumNumberOfLines = 5
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

    private func fill(_ shown: Shown) {
        let overview = shown.overview
        let logical = shown.logical
        if isEditingLabel { window?.makeFirstResponder(nil) }  // keeps what was typed
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        tiles = []
        connectedBars = [:]
        placeholders = []
        labelFields = [:]
        settingBoxes = []

        // Every display-name cell has one width (wide enough for the heading's
        // row titles), and so does every Space cell.
        let titleWidth = Self.rowTitles.map { Self.rowTitle($0).fittingSize.width + 6 }.max() ?? 0
        let labelWidth = (overview.sections
            .map { DisplayLabelView(text: $0.name, scale: 1, ghost: !$0.connected).preferredWidth } + [ceil(titleWidth)])
            .max() ?? 0
        let cellWidths = overview.sections.flatMap(\.rows).map {
            TileView.width(for: tileModel($0), compact: false, scale: 1)
        }
        let headerWidths = logical.columns.map {
            TileView.width(for: headerModel($0), compact: false, scale: Metrics.headerScale)
        }
        let tileWidth = (cellWidths + headerWidths).max() ?? Metrics.normalTile.lowerBound

        let connected = overview.sections.filter(\.connected)
        let disconnected = overview.sections.filter { !$0.connected }
        let rows = Dictionary(overview.sections.flatMap(\.rows).compactMap { row in row.spaceID.map { ($0, row) } },
                              uniquingKeysWith: { first, _ in first })
        stack.addArrangedSubview(heading("Connected displays"))
        if !logical.columns.isEmpty {
            stack.addArrangedSubview(headerRow(logical, names: overview.sections, labelWidth: labelWidth, tileWidth: tileWidth))
        }
        for section in connected {
            let view = gridRow(section, logical: logical, rows: rows, labelWidth: labelWidth, tileWidth: tileWidth)
            connectedBars[section.identifier] = view
            stack.addArrangedSubview(view)
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
            stack.addArrangedSubview(horizontal([barView(section, labelWidth: labelWidth, tileWidth: tileWidth), forget]))
        }
        if let previous = stack.arrangedSubviews.last { stack.setCustomSpacing(18, after: previous) }
        stack.addArrangedSubview(heading("Advanced"))
        for (index, setting) in settings.enumerated() {
            let box = NSButton(checkboxWithTitle: setting.title, target: self, action: #selector(settingClicked(_:)))
            box.tag = index
            box.toolTip = setting.toolTip
            settingBoxes.append(box)
            stack.addArrangedSubview(box)
        }
        updateSettingBoxes()

        var text = "Click a column heading to switch every display; click a Space to switch only its display. "
            + "Double-click to rename. Drag a Space onto “Not assigned” in its row to give it that column's name. "
            + "Type a letter in Tile displayed to show it in the menu bar instead of the number."
        if let duplicate = logical.columns.first(where: { $0.duplicateOn != nil }) {
            text += " " + duplicateNote(duplicate, names: overview.sections)
        }
        if !disconnected.isEmpty {
            text += " Drag a disconnected display's Space onto the row of the display it's on now to move it there. "
                + "Only the app's grouping changes; windows stay where they are."
        }
        hint.stringValue = text
    }

    // MARK: Advanced

    private var settings: [Setting] {
        let bar = self.bar
        return [
            Setting(title: "Floating bar when the menu bar item is hidden",
                    toolTip: "Whenever macOS hides the menu bar item, a small bar with the same tiles appears at the top of the main display.",
                    isOn: { bar.showsFallback }, set: { bar.setShowsFallback($0) }),
            Setting(title: "Show apps on hover",
                    toolTip: "Rest the pointer on a tile to see its name and the apps with a window on its Space.",
                    isOn: { bar.showsAppsOnHover }, set: { bar.setShowsAppsOnHover($0) }),
            Setting(title: "Option-Control-drag windows to Spaces",
                    toolTip: "Grab a window, then hold Option and Control and drag the pointer onto a tile to take the window to that Space.",
                    isOn: { bar.dragsWindows }, set: { bar.setDragsWindows($0) }),
            Setting(title: "Launch at login",
                    toolTip: "Start Dispaces when you log in. Also in System Settings › General › Login Items.",
                    isOn: { LoginItem.isEnabled }, set: { LoginItem.set($0) }),
        ]
    }

    @objc private func settingClicked(_ sender: NSButton) {
        let settings = self.settings
        guard settings.indices.contains(sender.tag) else { return }
        settings[sender.tag].set(sender.state == .on)
        // Redrawn: the tiles' tooltips follow Show apps on hover, and the boxes
        // show what really happened (macOS may refuse Launch at login).
        reload(force: true)
    }

    private func updateSettingBoxes() {
        for (box, setting) in zip(settingBoxes, settings) {
            box.state = setting.isOn() ? .on : .off
        }
    }

    private func horizontal(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func tileModel(_ row: DisplayOverview.Row) -> TileModel {
        let kind = row.isFullScreen ? "Full-screen Space" : (row.spaceID == nil ? "Space" : "Desktop \(row.number)")
        return TileModel(target: .space(row.spaceID ?? 0), number: row.number, name: row.name,
                         state: state(of: row), isFullScreen: row.isFullScreen, failed: false,
                         accessibilityLabel: "\(kind), \(row.name)" + (row.note.map { ", " + $0 } ?? ""))
    }

    /// A Space's colour (a disconnected display's, or a full-screen one): strong
    /// when it's on screen, pale when another Space of its logical space is.
    private func state(of row: DisplayOverview.Row) -> TileModel.State {
        guard let id = row.spaceID,
              let column = shown?.logical.columns.first(where: { $0.cells.contains { $0.space.managedID == id } }),
              let cell = column.cells.first(where: { $0.space.managedID == id }) else {
            return row.isCurrent ? .strong : .normal
        }
        return TileModel.State(column.highlight(of: cell))
    }

    /// A column heading's name (its number is in the row above), coloured as
    /// seen from the display you're working on.
    private func headerModel(_ column: LogicalSpaces.Column) -> TileModel {
        let state = TileModel.State(column.highlight(seenFrom: shown?.focused))
        return TileModel(target: .logical(column.key), number: "", name: column.title,
                         state: state, isFullScreen: false, failed: false,
                         accessibilityLabel: "Logical space \(column.number), \(column.title). Switches every display.")
    }

    /// The sentence explaining a column started by a second Space with the same name.
    private func duplicateNote(_ column: LogicalSpaces.Column, names: [DisplayOverview.Section]) -> String {
        let display = names.first { $0.identifier == column.duplicateOn }?.name ?? "A display"
        return "\(display) has two Spaces named \(column.title); the second one has its own column."
    }

    /// The column headings, lined up with the cells under them: three rows
    /// (number, name, tile displayed), titled where the display names are.
    private func headerRow(_ logical: LogicalSpaces, names: [DisplayOverview.Section], labelWidth: CGFloat,
                           tileWidth: CGFloat) -> NSView {
        let view = NSView()
        let fieldY: CGFloat = 0
        let nameY = fieldY + Self.fieldHeight + Self.headerGap
        let numberY = nameY + Metrics.tileHeight + Self.headerGap
        let height = numberY + Self.numberRowHeight
        let titleX = Metrics.inset + Metrics.groupPadding
        for (title, row) in zip(Self.rowTitles, [(numberY, Self.numberRowHeight), (nameY, Metrics.tileHeight),
                                                 (fieldY, Self.fieldHeight)]) {
            let label = Self.rowTitle(title)
            let size = label.fittingSize
            label.frame = NSRect(x: titleX + 6, y: row.0 + (row.1 - size.height) / 2, width: labelWidth - 6, height: size.height)
            view.addSubview(label)
        }

        var x = titleX + labelWidth + Metrics.gap
        var fields: [LabelField] = []
        for column in logical.columns {
            let number = NSTextField(labelWithString: String(column.number))
            number.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            number.textColor = .secondaryLabelColor
            number.alignment = .center
            let numberHeight = number.fittingSize.height
            number.frame = NSRect(x: x, y: numberY + (Self.numberRowHeight - numberHeight) / 2,
                                  width: tileWidth, height: numberHeight)
            view.addSubview(number)

            let field = labelField(column)
            field.frame = NSRect(x: x, y: fieldY, width: tileWidth, height: Self.fieldHeight)
            view.addSubview(field)
            if field.isEnabled { fields.append(field) }

            let target = TileTarget.logical(column.key)
            let tile = TileView(model: headerModel(column), compact: false, scale: Metrics.headerScale)
            tile.frame = NSRect(x: x, y: nameY, width: tileWidth, height: Metrics.tileHeight)
            tile.renameTitle = "Rename on Every Display…"
            tile.toolTip = column.duplicateOn != nil ? duplicateNote(column, names: names)
                : (bar.showsAppsOnHover ? nil : "\(column.title): click to switch every display")
            tile.onClick = { [weak self] in self?.switchTo(target) }
            tile.onRename = { [weak self] in
                guard let self else { return }
                self.applyNames(self.bar.askNames(for: target), action: "Rename Logical Space")
            }
            tile.onHover = { [weak bar = self.bar, weak tile] inside in
                guard let tile = tile?.hoverTile else { return }
                bar?.hover(tile, inside: inside)
            }
            tiles.append(tile)
            view.addSubview(tile)
            x += tileWidth + Metrics.gap
        }
        // Tab goes from one field to the next, round to the first.
        for (field, next) in zip(fields, Array(fields.dropFirst()) + fields.prefix(1)) { field.nextKeyView = next }
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: x).isActive = true
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private static func rowTitle(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        field.textColor = .secondaryLabelColor
        return field
    }

    /// A column's "Tile displayed" field: empty shows the number, greyed.
    private func labelField(_ column: LogicalSpaces.Column) -> LabelField {
        let field = LabelField(columnKey: column.labelKey ?? "")
        field.alignment = .center
        field.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        field.placeholderString = String(column.number)
        field.bezelStyle = .roundedBezel
        field.cell?.isScrollable = true
        field.setAccessibilityLabel("Tile displayed for \(column.title)")
        guard let key = column.labelKey else {
            field.isEnabled = false
            field.toolTip = "Give this Space a name of its own to choose what its tile shows."
            return field
        }
        field.stringValue = bar.tileLabel(forLogicalKey: key) ?? ""
        field.toolTip = "Up to \(TileLabel.maxLength) characters the menu bar shows instead of \(column.number). "
            + "Leave empty to show the number."
        field.target = self
        field.action = #selector(labelEdited(_:))
        field.cell?.sendsActionOnEndEditing = true
        field.delegate = self
        labelFields[key] = field
        return field
    }

    /// Enter, Tab or leaving the field: stores the tile label (cleaned) if it changed.
    @objc private func labelEdited(_ sender: NSTextField) {
        guard let field = sender as? LabelField, !field.columnKey.isEmpty else { return }
        let typed = TileLabel.sanitize(field.stringValue)
        if field.stringValue != typed { field.stringValue = typed }
        guard typed != (bar.tileLabel(forLogicalKey: field.columnKey) ?? "") else { return }
        applyNames(NameChange(labels: [field.columnKey: typed]), action: "Change Tile Displayed")
    }

    /// Shows the stored tile labels in the fields, without rebuilding the grid.
    private func refreshLabelFields() {
        for (key, field) in labelFields {
            let stored = bar.tileLabel(forLogicalKey: key) ?? ""
            guard field.stringValue != stored else { continue }
            if field.currentEditor() != nil { field.abortEditing() }
            field.stringValue = stored
        }
    }

    /// A connected display's row: its name, its Space (or "Not assigned") in
    /// each column, then its full-screen Spaces.
    private func gridRow(_ section: DisplayOverview.Section, logical: LogicalSpaces, rows: [UInt64: DisplayOverview.Row],
                         labelWidth: CGFloat, tileWidth: CGFloat) -> ManageBarView {
        let tileY = (Metrics.barHeight - Metrics.tileHeight) / 2
        let view = ManageBarView(ghost: false)
        view.setAccessibilityLabel(section.name)
        var x = Metrics.inset + Metrics.groupPadding
        view.addSubview(displayLabel(section, frame: NSRect(x: x, y: tileY, width: labelWidth, height: Metrics.tileHeight)))
        x += labelWidth + Metrics.gap

        let display = section.identifier
        for column in logical.columns {
            let frame = NSRect(x: x, y: tileY, width: tileWidth, height: Metrics.tileHeight)
            x += tileWidth + Metrics.gap
            guard let cell = column.cell(on: display) else {
                let empty = NotAssignedView(text: "Not assigned – \(section.name)")
                empty.frame = frame
                empty.toolTip = "Name one of \(section.name)'s Spaces “\(column.title)”, or drag one here."
                placeholders.append(Placeholder(view: empty, display: display, columnKey: column.key))
                view.addSubview(empty)
                continue
            }
            let id = cell.space.managedID
            let name = rows[id]?.name ?? column.title
            let model = TileModel(target: .space(id), number: cell.space.numberLabel, name: name,
                                  // Strong only when this Space is the one on screen (its display may
                                  // be showing an unplugged display's Space of the same name instead).
                                  state: TileModel.State(column.highlight(of: cell)),
                                  isFullScreen: false, failed: false,
                                  accessibilityLabel: "Desktop \(cell.space.numberLabel), \(name), on \(section.name)"
                                      + (cell.isCurrent ? ", current" : ""))
            let tile = spaceTile(model, frame: frame, toolTip: name)
            // Mouse-downs go to onPress; these serve VoiceOver and the right-click menu.
            tile.onClick = { [weak self] in self?.switchTo(.space(id)) }
            tile.onRename = { [weak self] in
                guard let self else { return }
                self.applyNames(self.bar.askNames(for: .space(id)), action: "Rename Space")
            }
            tile.onPress = { [weak self, weak tile] event in
                guard let self, let tile else { return }
                self.pressCell(tile, spaceID: id, nameKey: cell.space.nameKey, display: display, event: event)
            }
            view.addSubview(tile)
        }

        let fullScreen = logical.fullScreen.filter { $0.display.caseInsensitiveCompare(display) == .orderedSame }
        if !fullScreen.isEmpty { x += Metrics.groupPadding }
        for cell in fullScreen {
            guard let row = rows[cell.space.managedID] else { continue }
            let tile = spaceTile(tileModel(row), frame: NSRect(x: x, y: tileY, width: tileWidth, height: Metrics.tileHeight),
                                 toolTip: row.name)
            let id = cell.space.managedID
            tile.onClick = { [weak self] in self?.switchTo(.space(id)) }
            tile.onRename = { [weak self] in
                guard let self else { return }
                self.applyNames(self.bar.askNames(for: .space(id)), action: "Rename Space")
            }
            view.addSubview(tile)
            x += tileWidth + Metrics.gap
        }
        x += Metrics.groupPadding - Metrics.gap + Metrics.inset

        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: x).isActive = true
        view.heightAnchor.constraint(equalToConstant: Metrics.barHeight).isActive = true
        return view
    }

    /// A Space's tile, hovering like in the menu bar; registered for the hover column.
    private func spaceTile(_ model: TileModel, frame: NSRect, toolTip: String) -> TileView {
        let tile = TileView(model: model, compact: false, scale: 1)
        tile.frame = frame
        tile.toolTip = bar.showsAppsOnHover ? nil : toolTip
        tile.onHover = { [weak bar = self.bar, weak tile] inside in
            guard let tile = tile?.hoverTile else { return }
            bar?.hover(tile, inside: inside)
        }
        tiles.append(tile)
        return tile
    }

    /// A display's name at the start of its row; a connected display's can be renamed.
    private func displayLabel(_ section: DisplayOverview.Section, frame: NSRect) -> DisplayLabelView {
        let label = DisplayLabelView(text: section.name, scale: 1, ghost: !section.connected)
        label.frame = frame
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
        return label
    }

    /// A disconnected display's bar: its name, then its remembered Spaces.
    private func barView(_ section: DisplayOverview.Section, labelWidth: CGFloat, tileWidth: CGFloat) -> ManageBarView {
        let tileY = (Metrics.barHeight - Metrics.tileHeight) / 2
        let view = ManageBarView(ghost: !section.connected)
        view.setAccessibilityLabel(section.name)
        var x = Metrics.inset + Metrics.groupPadding
        view.addSubview(displayLabel(section, frame: NSRect(x: x, y: tileY, width: labelWidth, height: Metrics.tileHeight)))
        x += labelWidth + Metrics.gap

        if section.rows.isEmpty {
            let empty = DisplayLabelView(text: "No Spaces", scale: 1, ghost: true)
            empty.toolTip = nil
            empty.frame = NSRect(x: x, y: tileY, width: empty.preferredWidth, height: Metrics.tileHeight)
            view.addSubview(empty)
            x += empty.preferredWidth + Metrics.gap
        }
        for row in section.rows {
            let tile = spaceTile(tileModel(row), frame: NSRect(x: x, y: tileY, width: tileWidth, height: Metrics.tileHeight),
                                 toolTip: [row.name, row.note].compactMap { $0 }.joined(separator: " – "))
            if let id = row.spaceID {
                // Mouse-downs go to onPress; these serve VoiceOver and the right-click menu.
                tile.onClick = { [weak self] in self?.switchTo(.space(id)) }
                tile.onRename = { [weak self] in
                    guard let self else { return }
                    self.applyNames(self.bar.askNames(for: .space(id)), action: "Rename Space")
                }
            } else {
                tile.alphaValue = 0.55
                tile.toolTip = [row.name, row.note].compactMap { $0 }.joined(separator: " – ")
            }
            if row.remembered != nil {
                // A disconnected display's Space can also be dragged.
                tile.onPress = { [weak self, weak tile] event in
                    guard let self, let tile else { return }
                    self.pressGhost(tile, display: section.identifier, row: row, event: event)
                }
            }
            view.addSubview(tile)
            x += tileWidth + Metrics.gap
        }
        x += Metrics.groupPadding - Metrics.gap + Metrics.inset

        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: x).isActive = true
        view.heightAnchor.constraint(equalToConstant: Metrics.barHeight).isActive = true
        return view
    }

    @objc private func forget(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue else { return }
        if let record = bar.forgetDisplay(identifier) { registerRestore(record) }
        reload(force: true)
    }

    /// Stores Space names and tile labels and registers the change for undo;
    /// undoing stores the previous ones the same way, which registers the redo.
    /// A change of tile labels alone updates the fields in place, so typing
    /// and Tab carry on; anything else redraws the grid.
    private func applyNames(_ change: NameChange?, action: String) {
        guard let change, !change.isEmpty else { return }
        let previous = bar.apply(change)
        if change.spaces.isEmpty {
            refreshLabelFields()
        } else {
            reload(force: true)
        }
        guard let undo = window?.undoManager else { return }
        undo.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.applyNames(previous, action: action) }
        }
        undo.setActionName(action)
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

    // MARK: Switching and dragging

    /// Switches like the menu bar (a heading: every display; a Space: its
    /// display), then brings this window to the front and focuses it: macOS
    /// hands focus to an app on the new Space, so take it back, once right away
    /// and once after macOS has finished switching.
    private func switchTo(_ target: TileTarget) {
        if isEditingLabel { window?.makeFirstResponder(nil) }  // saves a tile label being typed first
        bar.click(target, thisDisplayOnly: false) { [weak self] in
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

    /// Only a quick click switches; pressing and holding is for grabbing.
    private func isQuick(_ event: NSEvent) -> Bool {
        ProcessInfo.processInfo.systemUptime - event.timestamp <= TileView.maxClickHold
    }

    /// Mouse-down on a connected display's Space: a drag onto "Not assigned" in
    /// the same row gives it that column's name, a quick click switches only its
    /// display, Control-click or double-click renames it.
    private func pressCell(_ tile: TileView, spaceID: UInt64, nameKey: String, display: String, event: NSEvent) {
        if event.modifierFlags.contains(.control) || event.clickCount == 2 {
            applyNames(bar.askNames(for: .space(spaceID)), action: "Rename Space")
            return
        }
        let result = track(event, from: tile,
                           hint: "Drop on “Not assigned” in this row to give this Space that column's name.",
                           target: { [weak self] point in self?.placeholder(at: point, display: display) },
                           highlight: { [weak self] key in
                               self?.placeholders.forEach { $0.view.highlighted = $0.display == display && $0.columnKey == key }
                           })
        switch result {
        case .click:
            if isQuick(event) { switchTo(.space(spaceID)) }
        case .dropped(let key?):
            if let title = shown?.logical.column(key: key)?.title {
                applyNames(NameChange(spaces: [nameKey: title]), action: "Assign Space")
            }
        case .dropped(nil):
            break
        }
    }

    /// The "Not assigned" cell of `display`'s row under a window point.
    private func placeholder(at windowPoint: NSPoint, display: String) -> String? {
        placeholders.first { $0.display == display && $0.view.convert($0.view.bounds, to: nil).contains(windowPoint) }?
            .columnKey
    }

    /// Mouse-down on a disconnected display's Space: a drag moves it, a quick
    /// click switches to it (like the menu bar), Control-click or double-click renames it.
    private func pressGhost(_ tile: TileView, display: String, row: DisplayOverview.Row, event: NSEvent) {
        if event.modifierFlags.contains(.control) || event.clickCount == 2 {
            if let id = row.spaceID { applyNames(bar.askNames(for: .space(id)), action: "Rename Space") }
            return
        }
        let result = track(event, from: tile, hint: dragHint(row),
                           target: { [weak self] point in self?.dropTarget(at: point, for: row) },
                           highlight: { [weak self] target in self?.highlight(target) })
        switch result {
        case .click:
            if isQuick(event), let id = row.spaceID { switchTo(.space(id)) }
        case .dropped(_?):
            if let remembered = row.remembered, let index = bar.removeGhostSpace(remembered, from: display) {
                registerPutBack(remembered, at: index, into: display)
            }
        case .dropped(nil):
            break
        }
    }

    /// Follows the pointer; a copy of the tile moves along, and `target` names
    /// the drop target under it (lit up with `highlight`).
    private func track(_ event: NSEvent, from source: NSView, hint dragHint: String,
                       target: @escaping (NSPoint) -> String?, highlight: @escaping (String?) -> Void) -> Press {
        guard let window, let root = window.contentView else { return .click }
        let start = event.locationInWindow
        let hintBefore = hint.stringValue
        var preview: NSImageView?
        var grab = NSPoint.zero
        var over: String?
        dragging = true
        defer {
            dragging = false
            preview?.removeFromSuperview()
            highlight(nil)
            hint.stringValue = hintBefore
            if reloadLater {
                reloadLater = false
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
                self.hint.stringValue = dragHint
            }
            if let preview {
                let inRoot = root.convert(point, from: nil)
                preview.setFrameOrigin(NSPoint(x: inRoot.x - grab.x, y: inRoot.y - grab.y))
                over = target(point)
                highlight(over)
            }
            if event.type == .leftMouseUp { stop.pointee = true }
        }
        return preview == nil ? .click : .dropped(over)
    }

    private func dragHint(_ row: DisplayOverview.Row) -> String {
        guard let display = row.onDisplay,
              let name = shown?.overview.sections.first(where: { $0.identifier == display })?.name else {
            return "macOS no longer has this Space, so it can't be moved. Forget the display to drop it."
        }
        return "Drop on the \(name) row: macOS already moved this Space there, and it can't be moved to another display."
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
        return tiles.first { $0.window === window && $0.convert($0.bounds, to: nil).contains(point) }
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

/// A bar in the Manage window, one per display; a disconnected
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

/// Lays the list out from the top. A click on the background ends typing in a field.
private final class FlippedView: NSView {
    var onClick: (() -> Void)?
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// A column's "Tile displayed" field, knowing its logical key.
private final class LabelField: NSTextField {
    let columnKey: String

    init(columnKey: String) {
        self.columnKey = columnKey
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}
