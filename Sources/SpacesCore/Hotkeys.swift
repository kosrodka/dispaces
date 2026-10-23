import Foundation

/// A key code plus modifier flags, in the same bit layout as `CGEventFlags`.
public struct KeyCombo: Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: UInt64

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let shift: UInt64 = 0x0002_0000
    public static let control: UInt64 = 0x0004_0000
    public static let option: UInt64 = 0x0008_0000
    public static let command: UInt64 = 0x0010_0000
    public static let numericPad: UInt64 = 0x0020_0000
    public static let function: UInt64 = 0x0080_0000
    /// The only modifier bits we will ever post.
    public static let allowedModifiers: UInt64 = shift | control | option | command | numericPad | function

    /// Highest virtual key code we accept (US keyboard layout codes are all below 128).
    public static let maxKeyCode: UInt16 = 127
}

/// One Mission Control shortcut as configured by the user.
public struct HotkeySetting: Equatable, Sendable {
    /// nil when the shortcut has no key assigned.
    public let combo: KeyCombo?
    /// true/false when the user's settings say so; nil when the settings don't mention it.
    public let enabled: Bool?

    public init(combo: KeyCombo?, enabled: Bool?) {
        self.combo = combo
        self.enabled = enabled
    }
}

/// Ids of the Mission Control shortcuts in `com.apple.symbolichotkeys`.
/// These are the only shortcuts this app will ever press.
public enum HotkeyID {
    public static let moveLeftASpace = 79
    public static let moveRightASpace = 81
    /// "Switch to Desktop 1" … "Switch to Desktop 16".
    public static let desktopRange = 118...133

    public static func switchToDesktop(_ number: Int) -> Int? {
        let id = 117 + number
        return desktopRange.contains(id) ? id : nil
    }

    public static func isAllowed(_ id: Int) -> Bool {
        id == moveLeftASpace || id == moveRightASpace || desktopRange.contains(id)
    }
}

/// The user's Mission Control shortcuts, with Apple's defaults for the ones not mentioned.
public struct HotkeyTable: Equatable, Sendable {
    let settings: [Int: HotkeySetting]

    public init(settings: [Int: HotkeySetting]) {
        self.settings = settings.filter { HotkeyID.isAllowed($0.key) }
    }

    public func setting(for id: Int) -> HotkeySetting {
        if let s = settings[id] { return s }
        return HotkeyTable.appleDefault(for: id)
    }

    /// Apple's defaults: Control-1…9 for desktops 1–9 (off unless turned on, but the
    /// key is known), Control-Left/Right for moving one Space, on by default.
    static func appleDefault(for id: Int) -> HotkeySetting {
        let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // 1…9
        switch id {
        case HotkeyID.moveLeftASpace:
            return HotkeySetting(combo: KeyCombo(keyCode: 123, modifiers: KeyCombo.control | KeyCombo.function), enabled: true)
        case HotkeyID.moveRightASpace:
            return HotkeySetting(combo: KeyCombo(keyCode: 124, modifiers: KeyCombo.control | KeyCombo.function), enabled: true)
        case 118...126:
            return HotkeySetting(combo: KeyCombo(keyCode: digitKeyCodes[id - 118], modifiers: KeyCombo.control), enabled: nil)
        default:
            return HotkeySetting(combo: nil, enabled: nil)
        }
    }

    public static let defaults = HotkeyTable(settings: [:])

    /// Desktops 1…`count` (at most 16) whose "Switch to Desktop N" shortcut
    /// isn't confirmed on: turned off, not mentioned in the user's settings
    /// (off by default), or without a key.
    public func desktopsWithoutConfirmedShortcut(count: Int) -> [Int] {
        let last = min(count, HotkeyID.desktopRange.count)
        guard last >= 1 else { return [] }
        return (1...last).filter { number in
            guard let id = HotkeyID.switchToDesktop(number) else { return false }
            let setting = self.setting(for: id)
            return setting.enabled != true || setting.combo == nil
        }
    }
}

/// Reads the `AppleSymbolicHotKeys` dictionary from `com.apple.symbolichotkeys`.
///
/// Entry shape: `"118": { enabled = 1; value = { parameters = (65535, 18, 262144); type = standard; }; }`
/// where parameters are (character, key code, modifier flags). Key code 65535 means "no key".
public enum HotkeyParser {
    public static func parse(_ raw: Any?) -> HotkeyTable {
        guard let dict = raw as? [String: Any] else { return .defaults }
        var settings: [Int: HotkeySetting] = [:]
        for (key, value) in dict {
            guard let id = Int(key), HotkeyID.isAllowed(id), let entry = value as? [String: Any] else { continue }
            let enabled = bool(entry["enabled"])
            var combo: KeyCombo? = nil
            if let v = entry["value"] as? [String: Any],
               let params = v["parameters"] as? [Any], params.count >= 3,
               let code = SnapshotParser.int(params[1]),
               let mods = SnapshotParser.int(params[2]),
               code >= 0, code <= Int(KeyCombo.maxKeyCode), mods >= 0 {
                combo = KeyCombo(keyCode: UInt16(code), modifiers: UInt64(mods) & KeyCombo.allowedModifiers)
            }
            settings[id] = HotkeySetting(combo: combo, enabled: enabled)
        }
        return HotkeyTable(settings: settings)
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.intValue != 0
        case let i as Int: return i != 0
        default: return nil
        }
    }
}
