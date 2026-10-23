import Foundation

/// Cleans user-typed names before they are stored or shown.
public enum NameSanitizer {
    public static let maxLength = 24

    /// Unicode bidirectional overrides and isolates, which can make text display
    /// differently from what it is (U+202A–U+202E, U+2066–U+2069), plus the
    /// zero-width and BOM characters that hide text.
    static let invisible: Set<Unicode.Scalar> = {
        var set = Set<Unicode.Scalar>()
        for v in 0x202A...0x202E { set.insert(Unicode.Scalar(v)!) }
        for v in 0x2066...0x2069 { set.insert(Unicode.Scalar(v)!) }
        for v in [0x200B, 0x200E, 0x200F, 0x061C, 0xFEFF] { set.insert(Unicode.Scalar(v)!) }
        return set
    }()

    /// Removes control and direction-override characters, collapses whitespace,
    /// trims, and cuts to `maxLength` characters (user-perceived characters, so
    /// emoji and accents are never split).
    public static func sanitize(_ input: String) -> String {
        var scalars = String.UnicodeScalarView()
        var lastWasSpace = false
        for scalar in input.unicodeScalars.prefix(1_000) {
            if invisible.contains(scalar) { continue }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !lastWasSpace { scalars.append(" ") }
                lastWasSpace = true
                continue
            }
            if CharacterSet.controlCharacters.contains(scalar) { continue }
            scalars.append(scalar)
            lastWasSpace = false
        }
        let trimmed = String(scalars).trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }
}

/// The user's names for Spaces and displays.
///
/// Stored as two plain `[String: String]` dictionaries in the app's own
/// preferences. Everything read back is re-validated, because the file can be
/// edited by anything running as the user.
public struct Names: Equatable, Sendable {
    public static let maxEntries = 256
    public static let maxKeyLength = 200

    public private(set) var spaces: [String: String]
    public private(set) var displays: [String: String]

    public init() {
        spaces = [:]
        displays = [:]
    }

    /// Builds from untrusted stored values. Anything malformed is dropped.
    public init(storedSpaces: Any?, storedDisplays: Any?) {
        spaces = Names.validate(storedSpaces)
        displays = Names.validate(storedDisplays)
    }

    static func validate(_ raw: Any?) -> [String: String] {
        guard let dict = raw as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in dict {
            if result.count >= maxEntries { break }
            guard key.count <= maxKeyLength, !key.isEmpty, let name = value as? String else { continue }
            let clean = NameSanitizer.sanitize(name)
            if !clean.isEmpty { result[key] = clean }
        }
        return result
    }

    // MARK: Reading

    public func name(for space: Space, fallbackAppName: String? = nil) -> String {
        if let custom = spaces[space.nameKey] { return custom }
        return Names.defaultName(for: space, fallbackAppName: fallbackAppName)
    }

    public static func defaultName(for space: Space, fallbackAppName: String? = nil) -> String {
        switch space.kind {
        case .desktop:
            return "Desktop \(space.desktopNumber ?? space.indexOnDisplay + 1)"
        case .fullscreen:
            return space.appName ?? fallbackAppName.map(NameSanitizer.sanitize) ?? "Full screen"
        }
    }

    public func name(for display: Display, defaultName: String) -> String {
        displays[display.nameKey] ?? defaultName
    }

    // MARK: Writing

    /// Sets or clears (empty string) a Space name. `liveKeys` are the keys in use
    /// right now; they are kept when old entries must be dropped to stay under the cap.
    public mutating func setName(_ name: String, for space: Space, liveKeys: Set<String>) {
        Names.set(&spaces, key: space.nameKey, name: name, liveKeys: liveKeys)
    }

    public mutating func setName(_ name: String, for display: Display, liveKeys: Set<String>) {
        Names.set(&displays, key: display.nameKey, name: name, liveKeys: liveKeys)
    }

    static func set(_ dict: inout [String: String], key: String, name: String, liveKeys: Set<String>) {
        guard key.count <= maxKeyLength else { return }
        let clean = NameSanitizer.sanitize(name)
        if clean.isEmpty {
            dict[key] = nil
            return
        }
        if dict[key] == nil && dict.count >= maxEntries {
            // Drop names of Spaces/displays that no longer exist.
            for k in dict.keys where !liveKeys.contains(k) {
                dict[k] = nil
                if dict.count < maxEntries { break }
            }
            if dict.count >= maxEntries { return }
        }
        dict[key] = clean
    }
}
