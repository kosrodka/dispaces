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

/// What a logical space's tile shows instead of its number ("Tile displayed").
public enum TileLabel {
    /// The room a two-digit number takes on the square tile.
    public static let maxLength = 2

    /// Cleaned like a name, then cut to `maxLength` characters (user-perceived,
    /// so emoji are never split) and trimmed again.
    public static func sanitize(_ input: String) -> String {
        String(NameSanitizer.sanitize(input).prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }
}

/// Space names and tile labels to store together, as one undoable change.
/// An empty string clears the entry.
public struct NameChange: Equatable, Sendable {
    /// Space name key → name.
    public var spaces: [String: String]
    /// Logical space key (`LogicalSpaces.Column.labelKey`) → tile label.
    public var labels: [String: String]

    public init(spaces: [String: String] = [:], labels: [String: String] = [:]) {
        self.spaces = spaces
        self.labels = labels
    }

    public var isEmpty: Bool { spaces.isEmpty && labels.isEmpty }
}

/// The user's names for Spaces and displays, and the tile labels of logical spaces.
///
/// Stored as plain `[String: String]` dictionaries in the app's own
/// preferences. Everything read back is re-validated, because the file can be
/// edited by anything running as the user.
public struct Names: Equatable, Sendable {
    public static let maxEntries = 256
    public static let maxKeyLength = 200

    public private(set) var spaces: [String: String]
    public private(set) var displays: [String: String]
    /// Logical space key (its folded name) → what its tile shows instead of the number.
    public private(set) var labels: [String: String]

    public init() {
        spaces = [:]
        displays = [:]
        labels = [:]
    }

    /// Builds from untrusted stored values. Anything malformed is dropped.
    public init(storedSpaces: Any?, storedDisplays: Any?, storedLabels: Any? = nil) {
        spaces = Names.validate(storedSpaces, clean: NameSanitizer.sanitize)
        displays = Names.validate(storedDisplays, clean: NameSanitizer.sanitize)
        labels = Names.validate(storedLabels, clean: TileLabel.sanitize)
    }

    static func validate(_ raw: Any?, clean: (String) -> String) -> [String: String] {
        guard let dict = raw as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in dict {
            if result.count >= maxEntries { break }
            guard key.count <= maxKeyLength, !key.isEmpty, let name = value as? String else { continue }
            let cleaned = clean(name)
            if !cleaned.isEmpty { result[key] = cleaned }
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

    /// The tile label stored for a logical space, if any.
    public func label(forLogicalKey key: String) -> String? {
        labels[key]
    }

    // MARK: Writing

    /// Sets or clears (empty string) a Space name. `liveKeys` are the keys in use
    /// right now; they are kept when old entries must be dropped to stay under the cap.
    public mutating func setName(_ name: String, for space: Space, liveKeys: Set<String>) {
        setName(name, forSpaceKey: space.nameKey, liveKeys: liveKeys)
    }

    /// Sets or clears (empty string) the name stored under a Space's name key
    /// (used to undo renames, and to rename every Space of a logical space).
    public mutating func setName(_ name: String, forSpaceKey key: String, liveKeys: Set<String>) {
        Names.set(&spaces, key: key, name: name, liveKeys: liveKeys)
    }

    /// The user's name stored under a Space's name key, if any.
    public func storedName(forSpaceKey key: String) -> String? {
        spaces[key]
    }

    public mutating func setName(_ name: String, for display: Display, liveKeys: Set<String>) {
        Names.set(&displays, key: display.nameKey, name: name, liveKeys: liveKeys)
    }

    /// Sets or clears (empty string) a logical space's tile label. `liveKeys`
    /// are the logical keys in use right now.
    public mutating func setLabel(_ label: String, forLogicalKey key: String, liveKeys: Set<String>) {
        Names.set(&labels, key: key, name: label, liveKeys: liveKeys, clean: TileLabel.sanitize)
    }

    /// Stores a change and returns its inverse (what was stored before, empty
    /// where nothing was), which undoes it when applied.
    @discardableResult
    public mutating func apply(_ change: NameChange, liveSpaceKeys: Set<String>, liveLabelKeys: Set<String>)
        -> NameChange {
        var inverse = NameChange()
        for (key, name) in change.spaces {
            inverse.spaces[key] = spaces[key] ?? ""
            setName(name, forSpaceKey: key, liveKeys: liveSpaceKeys)
        }
        for (key, label) in change.labels {
            inverse.labels[key] = labels[key] ?? ""
            setLabel(label, forLogicalKey: key, liveKeys: liveLabelKeys)
        }
        return inverse
    }

    static func set(_ dict: inout [String: String], key: String, name: String, liveKeys: Set<String>,
                    clean sanitize: (String) -> String = NameSanitizer.sanitize) {
        guard key.count <= maxKeyLength, !key.isEmpty else { return }
        let clean = sanitize(name)
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
