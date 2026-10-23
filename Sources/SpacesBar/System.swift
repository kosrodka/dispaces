import AppKit
import CGSPrivate
import os
import SpacesCore

let log = Logger(subsystem: "io.github.kosrodka.SpacesBar", category: "app")

/// Reads the Space list. Read-only; takes well under a millisecond.
enum SpaceReader {
    static func read() -> Snapshot {
        let connection = CGSMainConnectionID()
        guard let array: CFArray = CGSCopyManagedDisplaySpaces(connection) else {
            log.error("Space list unavailable")
            return .empty
        }
        return SnapshotParser.parse(array as NSArray as [AnyObject], activeSpaceID: CGSGetActiveSpace(connection))
    }
}

/// Reads the user's Mission Control shortcuts (read-only).
enum HotkeyReader {
    static func read() -> HotkeyTable {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let value = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain)
        return HotkeyParser.parse(value)
    }
}

/// Maps macOS display identifiers to screens and names.
@MainActor
enum Screens {
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func identifier(of screen: NSScreen) -> String? {
        guard let id = displayID(of: screen),
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) else { return nil }
        return string as String
    }

    static func screen(for display: Display) -> NSScreen? {
        if display.spansAllDisplays { return NSScreen.screens.first }
        return NSScreen.screens.first { identifier(of: $0)?.caseInsensitiveCompare(display.identifier) == .orderedSame }
    }

    static func defaultName(for display: Display) -> String {
        if display.spansAllDisplays { return "All displays" }
        return screen(for: display)?.localizedName ?? "Display"
    }

    /// The display you are using: the one with the key window / menu bar focus.
    static func focusedIdentifier() -> String? {
        NSScreen.main.flatMap(identifier(of:))
    }

    /// The display under the mouse pointer.
    static func pointerIdentifier() -> String? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }.flatMap(identifier(of:))
    }

    static func matches(_ identifier: String?, _ display: Display) -> Bool {
        if display.spansAllDisplays { return true }
        guard let identifier else { return false }
        return identifier.caseInsensitiveCompare(display.identifier) == .orderedSame
    }
}

/// Posts keyboard events. The only code in the app that sends input.
///
/// Security: it only accepts the Mission Control shortcut ids in `HotkeyID`
/// and only the modifier bits in `KeyCombo.allowedModifiers`.
enum KeyPoster {
    static var hasPermission: Bool { CGPreflightPostEventAccess() }

    static func requestPermission() {
        _ = CGRequestPostEventAccess()
    }

    private static let modifierKeys: [(bit: UInt64, keyCode: CGKeyCode)] = [
        (KeyCombo.control, 59), (KeyCombo.option, 58), (KeyCombo.shift, 56), (KeyCombo.command, 55),
    ]

    /// Presses and releases one shortcut, holding its modifier keys around it.
    static func press(_ combo: KeyCombo, hotkeyID: Int) async -> Bool {
        guard HotkeyID.isAllowed(hotkeyID), combo.keyCode <= KeyCombo.maxKeyCode else {
            log.fault("Refused to post a key that is not a Space shortcut")
            return false
        }
        let modifiers = combo.modifiers & KeyCombo.allowedModifiers
        let source = CGEventSource(stateID: .hidSystemState)
        let held = modifierKeys.filter { modifiers & $0.bit != 0 }

        var flags: UInt64 = 0
        var ok = true
        for key in held {
            flags |= key.bit
            ok = post(source, key.keyCode, down: true, flags: flags) && ok
            await pause()
        }
        ok = post(source, CGKeyCode(combo.keyCode), down: true, flags: modifiers) && ok
        await pause()
        ok = post(source, CGKeyCode(combo.keyCode), down: false, flags: modifiers) && ok
        for key in held.reversed() {
            await pause()
            flags &= ~key.bit
            ok = post(source, key.keyCode, down: false, flags: flags) && ok
        }
        return ok
    }

    private static func post(_ source: CGEventSource?, _ key: CGKeyCode, down: Bool, flags: UInt64) -> Bool {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return false }
        event.flags = CGEventFlags(rawValue: flags)
        event.post(tap: .cghidEventTap)
        return true
    }

    private static func pause() async {
        try? await Task.sleep(nanoseconds: 8_000_000)
    }
}

/// Brings another app to the front, as clicking it in the Dock would.
/// The only code that activates other apps; used only on the user's click
/// in the apps column. Never hides, quits or changes the app's windows.
@MainActor
enum AppActivator {
    static func bringToFront(_ app: NSRunningApplication) {
        guard !app.isTerminated else { return }
        // macOS lets an app hand activation only to another while it is itself
        // active; the bar never is, so take it for a moment (as the rename dialog does).
        NSApp.activate()
        NSApp.yieldActivation(to: app)
        if !app.activate(from: NSRunningApplication.current, options: []) {
            log.error("Couldn't bring an app to the front")
        }
    }
}

/// Small wrapper for the few System Settings panes the app links to.
enum SettingsLinks {
    static let accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    static let keyboard = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

    @MainActor
    static func open(_ string: String) {
        guard let url = URL(string: string), url.scheme == "x-apple.systempreferences" else { return }
        NSWorkspace.shared.open(url)
    }
}
