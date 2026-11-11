import AppKit
import ServiceManagement
import SpacesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Preferences()
    private let monitor = SpaceMonitor()
    private lazy var switcher = SpaceSwitcher(monitor: monitor)
    private lazy var bar = BarController(prefs: prefs, monitor: monitor, switcher: switcher)
    private let menu = NSMenu()
    /// The Space that was right-clicked to open the menu, offered for renaming.
    private var menuSpaceID: UInt64?
    private lazy var manageWindow = ManageWindowController(bar: bar)
    private lazy var manualWindow = ManualWindowController()
    /// Connected displays, to notice one being plugged in or unplugged.
    private var displays: Set<String> = []
    private var resetWork: DispatchWorkItem?
    /// macOS moves Spaces between displays for a moment after a change.
    private static let resetDelay: TimeInterval = 1

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        bar.onMenu = { [weak self] spaceID, view in self?.openMenu(spaceID: spaceID, under: view) }
        bar.needsAttention = { [weak self] in self?.setupIssues().isEmpty == false }
        bar.onWarningClick = { [weak self] in self?.showSetupCheck() }
        monitor.onRefresh = { [weak self] snapshot in self?.bar.show(snapshot) }
        bar.onChange = { [weak self] in self?.manageWindow.reload() }
        monitor.start()
        bar.setDragWatching(prefs.dragWindows)
        displays = Self.connectedDisplays()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        log.notice("Started")
    }

    // MARK: Display connected or disconnected

    /// Redraws the Spaces from scratch shortly after a display is connected or
    /// disconnected (not on resolution or arrangement changes).
    @objc private func screensChanged() {
        let now = Self.connectedDisplays()
        guard now != displays else { return }
        displays = now
        log.notice("Display connected or disconnected")
        resetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.bar.reset() }
        }
        resetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resetDelay, execute: work)
    }

    private static func connectedDisplays() -> Set<String> {
        Set(NSScreen.screens.compactMap(Screens.identifier(of:)))
    }

    // MARK: Menu

    /// Opens the menu just under the tiles (right-click, Control-click, or a
    /// click between displays).
    private func openMenu(spaceID: UInt64?, under view: NSView) {
        menuSpaceID = spaceID
        _ = menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
        menuSpaceID = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let id = menuSpaceID, let name = bar.spaceName(id) {
            let item = NSMenuItem(title: "Rename “\(name)”…", action: #selector(renameSpace(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: id)
            menu.addItem(item)
            menu.addItem(.separator())
        }
        add(menu, "Floating bar when the menu bar item is hidden", #selector(toggleFallback), checked: bar.showsFallback)
        add(menu, "Show apps on hover", #selector(toggleAppsOnHover), checked: bar.showsAppsOnHover)
        add(menu, "Option-drag windows to Spaces", #selector(toggleDragWindows), checked: prefs.dragWindows)
        add(menu, "Launch at login", #selector(toggleLogin), checked: SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator())
        add(menu, "Manage displays and spaces", #selector(showManageWindow))
        let issues = setupIssues().count
        add(menu, issues == 0 ? "Setup check…" : "Setup check… (\(issues) to fix)", #selector(showSetupCheck))
        add(menu, "Refresh now", #selector(refreshNow))
        let help = NSMenu(title: "Help")
        add(help, "Current release", #selector(showRelease))
        add(help, "User manual", #selector(showManual))
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpItem.submenu = help
        menu.addItem(helpItem)
        menu.addItem(.separator())
        let info = NSMenuItem(title: "Dispaces \(version) · no network access", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        add(menu, "Quit Dispaces", #selector(quit), key: "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, checked: Bool = false, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.state = checked ? .on : .off
        menu.addItem(item)
    }

    @objc private func toggleFallback() { bar.setShowsFallback(!bar.showsFallback) }
    @objc private func renameSpace(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.uint64Value else { return }
        bar.renameSpace(id: id)
    }
    @objc private func refreshNow() { bar.refreshNow() }
    @objc private func showManageWindow() { manageWindow.show() }
    @objc private func showManual() { manualWindow.show() }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    @objc private func showRelease() {
        let alert = NSAlert()
        alert.messageText = "Dispaces \(version)"
        alert.informativeText = "In this release:\n\n"
            + ReleaseNotes.highlights.map { "•  " + $0 }.joined(separator: "\n")
            + "\n\nNo network access. Uses only the Accessibility permission, to press the Switch to Desktop shortcuts."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Open User Manual")
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn { manualWindow.show() }
    }
    @objc private func toggleAppsOnHover() { bar.setShowsAppsOnHover(!bar.showsAppsOnHover) }

    @objc private func toggleDragWindows() {
        prefs.dragWindows.toggle()
        bar.setDragWatching(prefs.dragWindows)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            log.error("Launch at login change failed")
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at login"
            alert.informativeText = "Move Dispaces to the Applications folder and try again. You can also manage it in System Settings › General › Login Items."
            NSApp.activate()
            alert.runModal()
        }
    }

    // MARK: Setup check

    struct Check {
        let ok: Bool
        let title: String
        let detail: String
    }

    private func checks() -> [Check] {
        let snapshot = monitor.snapshot
        let hotkeys = HotkeyReader.read()
        let desktops = min(snapshot.desktopCount, HotkeyID.desktopRange.count)
        let off = hotkeys.desktopsWithoutConfirmedShortcut(count: desktops)
        let permission = KeyPoster.hasPermission
        let readable = !snapshot.isEmpty
        let spans = snapshot.displays.first?.spansAllDisplays ?? false
        let ago = monitor.lastRead.map { Int(Date().timeIntervalSince($0)) } ?? -1

        return [
            Check(ok: permission, title: "Accessibility permission",
                  detail: permission ? "Granted. Used only to press the Switch to Desktop shortcuts."
                                     : "Not granted. Needed only to press the Switch to Desktop shortcuts. System Settings › Privacy & Security › Accessibility."),
            Check(ok: off.isEmpty, title: "Switch to Desktop shortcuts",
                  detail: off.isEmpty ? "On for all \(desktops) desktops."
                                      : "Not confirmed on for desktop \(off.map(String.init).joined(separator: ", ")). \(SwitchPlanner.shortcutSettings)."),
            Check(ok: true, title: "Displays have separate Spaces",
                  detail: spans ? "Off. One shared set of Spaces for all displays." : "On. Each display shows its own Spaces."),
            Check(ok: readable, title: "Reading the Space list",
                  detail: readable ? "Working. Last read \(max(ago, 0)) s ago." : "Not working. macOS returned no Spaces."),
        ]
    }

    private func setupIssues() -> [Check] { checks().filter { !$0.ok } }

    @objc private func showSetupCheck() {
        let list = checks()
        let alert = NSAlert()
        alert.messageText = "Setup check"
        alert.informativeText = list.map { "\($0.ok ? "✓" : "✕")  \($0.title)\n      \($0.detail)" }.joined(separator: "\n\n")
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Open Keyboard Settings")
        NSApp.activate()
        switch alert.runModal() {
        case .alertSecondButtonReturn:
            if !KeyPoster.hasPermission { KeyPoster.requestPermission() }
            SettingsLinks.open(SettingsLinks.accessibility)
        case .alertThirdButtonReturn:
            SettingsLinks.open(SettingsLinks.keyboard)
        default:
            break
        }
        bar.redraw()
    }
}
