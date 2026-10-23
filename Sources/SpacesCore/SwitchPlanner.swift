import Foundation

public enum SwitchProblem: Equatable, Sendable {
    /// The Space is no longer in the list (deleted or display unplugged).
    case unknownSpace
    /// "Switch to Desktop N" is turned off in Keyboard Shortcuts.
    case shortcutOff(desktop: Int)
    /// "Switch to Desktop N" has no key assigned (desktops 10–16 by default).
    case noShortcut(desktop: Int)
    /// Full-screen Spaces (and desktops without a shortcut) can only be reached step by step,
    /// and macOS steps the display under the mouse pointer, which isn't the target display.
    case notOnPointerDisplay
    /// "Move left/right a Space" is turned off or unassigned.
    case stepShortcutOff
    /// Too many steps away to step safely.
    case tooFar
}

public enum SwitchPlan: Equatable, Sendable {
    case alreadyThere
    /// Press one "Switch to Desktop N" shortcut.
    case pressHotkey(id: Int, combo: KeyCombo, desktop: Int)
    /// Press "Move left/right a Space" `count` times.
    case step(id: Int, combo: KeyCombo, count: Int)
    case unavailable(SwitchProblem)
}

public enum SwitchPlanner {
    /// Upper bound on key presses for one switch.
    public static let maxSteps = 32

    /// Decides how to reach `spaceID`.
    /// - Parameter pointerDisplay: identifier of the display under the mouse pointer.
    public static func plan(to spaceID: UInt64, in snapshot: Snapshot,
                            hotkeys: HotkeyTable, pointerDisplay: String?) -> SwitchPlan {
        guard let found = snapshot.locate(spaceID: spaceID) else {
            return .unavailable(.unknownSpace)
        }
        let display = found.display
        let space = found.space
        if display.currentSpaceID == space.managedID { return .alreadyThere }

        var hotkeyProblem: SwitchProblem? = nil
        if space.kind == .desktop, let number = space.desktopNumber {
            if let id = HotkeyID.switchToDesktop(number) {
                let setting = hotkeys.setting(for: id)
                if let combo = setting.combo, setting.enabled != false {
                    return .pressHotkey(id: id, combo: combo, desktop: number)
                }
                hotkeyProblem = setting.combo == nil ? .noShortcut(desktop: number) : .shortcutOff(desktop: number)
            } else {
                hotkeyProblem = .noShortcut(desktop: number)
            }
        }

        // Step fallback: only on the display under the pointer (where macOS applies it).
        let stepPlan = planSteps(to: space, on: display, hotkeys: hotkeys, pointerDisplay: pointerDisplay)
        if case .step = stepPlan { return stepPlan }
        // Prefer telling the user about the desktop shortcut, which is the easy fix.
        if let problem = hotkeyProblem { return .unavailable(problem) }
        return stepPlan
    }

    static func planSteps(to space: Space, on display: Display, hotkeys: HotkeyTable,
                          pointerDisplay: String?) -> SwitchPlan {
        guard display.spansAllDisplays || pointerDisplay == display.identifier else {
            return .unavailable(.notOnPointerDisplay)
        }
        guard let currentID = display.currentSpaceID,
              let currentIndex = display.spaces.firstIndex(where: { $0.managedID == currentID }) else {
            return .unavailable(.unknownSpace)
        }
        let delta = space.indexOnDisplay - currentIndex
        if delta == 0 { return .alreadyThere }
        if abs(delta) > maxSteps { return .unavailable(.tooFar) }
        let id = delta > 0 ? HotkeyID.moveRightASpace : HotkeyID.moveLeftASpace
        let setting = hotkeys.setting(for: id)
        guard let combo = setting.combo, setting.enabled != false else {
            return .unavailable(.stepShortcutOff)
        }
        return .step(id: id, combo: combo, count: abs(delta))
    }

    /// Where the Space shortcuts are set.
    public static let shortcutSettings = "System Settings › Keyboard › Keyboard Shortcuts › Mission Control"

    /// A one-sentence explanation with the exact fix.
    public static func message(for problem: SwitchProblem) -> String {
        switch problem {
        case .unknownSpace:
            return "That Space no longer exists. The bar has been refreshed."
        case .shortcutOff(let n):
            return "Turn on \"Switch to Desktop \(n)\" in \(shortcutSettings)."
        case .noShortcut(let n):
            return "Give \"Switch to Desktop \(n)\" a key in \(shortcutSettings)."
        case .notOnPointerDisplay:
            return "This Space can only be reached from its own display. Move the bar to that display, or use Mission Control."
        case .stepShortcutOff:
            return "Turn on \"Move left a space\" and \"Move right a space\" in \(shortcutSettings)."
        case .tooFar:
            return "That Space is too far away to step to. Use Mission Control."
        }
    }

    /// The app may not press keys yet.
    public static let permissionMessage = "Dispaces needs Accessibility permission to switch Spaces. "
        + "Allow it in System Settings › Privacy & Security › Accessibility, then click again."

    /// "Switch to Desktop N" was pressed (twice) but the Space didn't change.
    public static func desktopShortcutFailedMessage(desktop: Int) -> String {
        "Didn't switch to Desktop \(desktop). Check that \"Switch to Desktop \(desktop)\" is turned on in \(shortcutSettings)."
    }

    /// Stepping with "Move left/right a space" didn't reach the Space.
    public static let stepFailedMessage = "Didn't reach that Space. Check that \"Move left a space\" and "
        + "\"Move right a space\" are on in \(shortcutSettings)."
}
