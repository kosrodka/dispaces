import AppKit
import SpacesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Preferences()
    private let monitor = SpaceMonitor()
    private lazy var switcher = SpaceSwitcher(monitor: monitor)
    private lazy var bar = BarController(prefs: prefs, monitor: monitor, switcher: switcher)
    private let menu = NSMenu()
    private lazy var manageWindow = ManageWindowController(bar: bar)
    private lazy var manualWindow = ManualWindowController()
    /// Connected displays, to notice one being plugged in or unplugged.
    private var displays: Set<String> = []
    private var resetWork: DispatchWorkItem?
    /// macOS moves Spaces between displays for a moment after a change.
    private static let resetDelay: TimeInterval = 1

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        bar.onMenu = { [weak self] view in self?.openMenu(under: view) }
        bar.needsAttention = { [weak self] in self?.setupIssues().isEmpty == false }
        bar.onWarningClick = { [weak self] in self?.showSetupCheck() }
        monitor.onRefresh = { [weak self] snapshot in self?.bar.show(snapshot) }
        bar.onChange = { [weak self] in self?.manageWindow.reload() }
        monitor.start()
        bar.setDragWatching(bar.dragsWindows)
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

    /// Opens the menu just under the menu bar (or the floating bar): right-click,
    /// Control-click, or a click between displays. It has no Rename: renaming
    /// is only in Manage displays and spaces.
    ///
    /// Placed under the bottom of the tiles' window, not of the tiles: beside
    /// the notch the menu bar is taller than the tiles, so just under the tiles
    /// is still inside the menu bar, and macOS then hides the menu's first item
    /// behind a scroll arrow.
    private func openMenu(under view: NSView) {
        let left = view.convert(view.bounds, to: nil).minX
        let point = view.convert(NSPoint(x: left, y: -4), from: nil)
        _ = menu.popUp(positioning: nil, at: point, in: view)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // First, on its own: the window for renaming and the on/off settings (Advanced).
        add(menu, "Manage displays and spaces", #selector(showManageWindow))
        menu.addItem(.separator())
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

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
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
    @objc private func quit() { NSApp.terminate(nil) }

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
