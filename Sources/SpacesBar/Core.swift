import AppKit
import SpacesCore

/// The app's own preferences. Everything read back is validated.
@MainActor
final class Preferences {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let spaceNames = "spaceNames"
        static let displayNames = "displayNames"
        static let barOffsets = "barOffsets"
        static let barSizes = "barSizes"
        static let collapsedBars = "collapsedBars"
        static let lockedBars = "lockedBars"
        static let barHidden = "barHidden"
        static let showAppsOnHover = "showAppsOnHover"
        static let dragWindows = "dragWindows"
        static let displayMemory = "displayMemory"
        static let firstSpaces = "firstSpaces"
    }

    private(set) var names: Names

    init() {
        names = Names(storedSpaces: defaults.object(forKey: Key.spaceNames),
                      storedDisplays: defaults.object(forKey: Key.displayNames))
        layout = BarLayout(storedOffsets: defaults.object(forKey: Key.barOffsets),
                           storedSizes: defaults.object(forKey: Key.barSizes),
                           storedCollapsed: defaults.object(forKey: Key.collapsedBars),
                           storedLocked: defaults.object(forKey: Key.lockedBars))
        memory = DisplayMemory(stored: defaults.object(forKey: Key.displayMemory))
        firstSpaces = FirstSpaces(stored: defaults.object(forKey: Key.firstSpaces))
        // v0.1 kept one position for a single bar; it no longer applies.
        defaults.removeObject(forKey: "barLeft")
        defaults.removeObject(forKey: "barTop")
        // Until per-bar locks, one lock applied to every bar. Carried over once
        // the bars are known (see `takeLegacyLock`).
        legacyLock = defaults.object(forKey: "locked") as? Bool ?? false
    }

    private var legacyLock = false

    /// True once if the old single "locked" setting was on; then forgets it.
    func takeLegacyLock() -> Bool {
        guard legacyLock else { return false }
        legacyLock = false
        defaults.removeObject(forKey: "locked")
        return true
    }

    func updateNames(_ change: (inout Names) -> Void) {
        change(&names)
        defaults.set(names.spaces, forKey: Key.spaceNames)
        defaults.set(names.displays, forKey: Key.displayNames)
    }

    /// Per-display bar positions, sizes, and collapsed and locked state.
    private(set) var layout: BarLayout

    func updateLayout(_ change: (inout BarLayout) -> Void) {
        change(&layout)
        defaults.set(layout.storedOffsets, forKey: Key.barOffsets)
        defaults.set(layout.storedSizes, forKey: Key.barSizes)
        defaults.set(layout.storedCollapsed, forKey: Key.collapsedBars)
        defaults.set(layout.storedLocked, forKey: Key.lockedBars)
    }

    /// Which Spaces belong to which display, including unplugged displays.
    private(set) var memory: DisplayMemory

    func updateMemory(_ change: (inout DisplayMemory) -> Bool) {
        if change(&memory) { defaults.set(memory.stored, forKey: Key.displayMemory) }
    }

    /// Whether each display's first Space is shown (shown by default).
    private(set) var firstSpaces: FirstSpaces

    func updateFirstSpaces(_ change: (inout FirstSpaces) -> Void) {
        change(&firstSpaces)
        defaults.set(firstSpaces.stored, forKey: Key.firstSpaces)
    }

    var barHidden: Bool {
        get { defaults.object(forKey: Key.barHidden) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.barHidden) }
    }

    /// "Show apps on hover"; on unless the user turns it off.
    var showAppsOnHover: Bool {
        get { defaults.object(forKey: Key.showAppsOnHover) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showAppsOnHover) }
    }

    /// "Option-drag windows to Spaces"; off until the user turns it on.
    var dragWindows: Bool {
        get { defaults.object(forKey: Key.dragWindows) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.dragWindows) }
    }
}

/// Keeps the Space list fresh: on every Space change, display change and wake,
/// plus every 60 seconds as a safety net.
@MainActor
final class SpaceMonitor {
    static let fallbackInterval: TimeInterval = 60
    /// Bursts of notifications are coalesced into one read.
    static let coalesceDelay: TimeInterval = 0.1

    private(set) var snapshot = Snapshot.empty
    private(set) var lastRead: Date?
    var onRefresh: ((Snapshot) -> Void)?

    private var timer: Timer?
    private var pending = false
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification, NSWorkspace.didActivateApplicationNotification] {
            observe(workspace, name)
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)

        timer = Timer.scheduledTimer(withTimeInterval: Self.fallbackInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.refresh() }
        }
        timer?.tolerance = 5
        refresh()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        tokens.append((center, token))
    }

    func scheduleRefresh() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalesceDelay) { [weak self] in
            MainActor.assumeIsolated {
                self?.pending = false
                self?.refresh()
            }
        }
    }

    /// Reads now and tells the UI. Returns the new snapshot.
    @discardableResult
    func refresh() -> Snapshot {
        snapshot = SpaceReader.read()
        lastRead = Date()
        onRefresh?(snapshot)
        return snapshot
    }

    /// Reads without notifying the UI (used while verifying a switch).
    func peek() -> Snapshot {
        SpaceReader.read()
    }
}

/// Switches Space by pressing the user's own Mission Control shortcuts,
/// then checks that it actually happened.
@MainActor
final class SpaceSwitcher {
    enum Outcome: Equatable {
        case switched
        case alreadyThere
        case ignoredBusy
        case failed(String)
    }

    static let verifyTimeout: TimeInterval = 1.0
    static let pollInterval: UInt64 = 50_000_000
    static let retryDelay: UInt64 = 300_000_000

    private let monitor: SpaceMonitor
    private(set) var busy = false

    init(monitor: SpaceMonitor) {
        self.monitor = monitor
    }

    func switchTo(spaceID: UInt64) async -> Outcome {
        guard !busy else { return .ignoredBusy }
        busy = true
        defer {
            busy = false
            monitor.refresh()
        }

        let snapshot = monitor.peek()
        let plan = SwitchPlanner.plan(to: spaceID, in: snapshot, hotkeys: HotkeyReader.read(),
                                      pointerDisplay: Screens.pointerIdentifier())
        switch plan {
        case .alreadyThere:
            return .alreadyThere
        case .unavailable(let problem):
            return .failed(SwitchPlanner.message(for: problem))
        case let .pressHotkey(id, combo, desktop):
            if let missing = permissionMissing() { return missing }
            return await press(id, combo, desktop: desktop, reaching: spaceID)
        case let .step(id, combo, count):
            if let missing = permissionMissing() { return missing }
            return await step(id, combo, count: count, reaching: spaceID)
        }
    }

    /// nil when the app may press keys; otherwise asks for Accessibility and says how to allow it.
    private func permissionMissing() -> Outcome? {
        guard !KeyPoster.hasPermission else { return nil }
        KeyPoster.requestPermission()
        return .failed(SwitchPlanner.permissionMessage)
    }

    /// Presses "Switch to Desktop N", once more if the first press didn't take.
    private func press(_ id: Int, _ combo: KeyCombo, desktop: Int, reaching spaceID: UInt64) async -> Outcome {
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: Self.retryDelay) }
            guard await KeyPoster.press(combo, hotkeyID: id) else { break }
            if await waitUntil({ self.isCurrent(spaceID, in: $0) }) { return .switched }
        }
        log.notice("Switch by desktop shortcut did not take effect")
        return .failed(SwitchPlanner.desktopShortcutFailedMessage(desktop: desktop))
    }

    /// Presses "Move left/right a space" `count` times, stopping when a press doesn't move.
    private func step(_ id: Int, _ combo: KeyCombo, count: Int, reaching spaceID: UInt64) async -> Outcome {
        for _ in 0..<count {
            let before = currentSpace(on: spaceID, in: monitor.peek())
            guard await KeyPoster.press(combo, hotkeyID: id) else { break }
            let moved = await waitUntil { self.currentSpace(on: spaceID, in: $0) != before }
            if !moved { break }
        }
        if isCurrent(spaceID, in: monitor.peek()) { return .switched }
        log.notice("Switch by stepping did not reach the target")
        return .failed(SwitchPlanner.stepFailedMessage)
    }

    private func isCurrent(_ spaceID: UInt64, in snapshot: Snapshot) -> Bool {
        snapshot.locate(spaceID: spaceID).map { $0.display.currentSpaceID == spaceID } ?? false
    }

    /// The current Space of the display that owns `spaceID`.
    private func currentSpace(on spaceID: UInt64, in snapshot: Snapshot) -> UInt64? {
        snapshot.locate(spaceID: spaceID)?.display.currentSpaceID
    }

    private func waitUntil(_ condition: (Snapshot) -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(Self.verifyTimeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: Self.pollInterval)
            if condition(monitor.peek()) { return true }
        }
        return false
    }
}
