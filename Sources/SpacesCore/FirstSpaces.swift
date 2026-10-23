import Foundation

/// Whether each display's first Space is shown on its bar and in the Manage
/// window. Shown by default on every display; the user can untick it per display.
/// Only the user's changes are stored; everything read back is validated.
public struct FirstSpaces: Equatable, Sendable {
    public static let maxEntries = 64
    static let maxKeyLength = 256

    /// Display identifier → shown, for displays the user changed.
    public private(set) var overrides: [String: Bool] = [:]

    public init() {}

    public init(stored raw: Any?) {
        guard let dict = raw as? [String: Any] else { return }
        for (key, value) in dict where overrides.count < Self.maxEntries {
            guard !key.isEmpty, key.count <= Self.maxKeyLength, let shown = value as? Bool else { continue }
            overrides[key] = shown
        }
    }

    /// The form saved to preferences.
    public var stored: [String: Bool] { overrides }

    public static let defaultShown = true

    public func isShown(_ identifier: String) -> Bool {
        overrides[identifier] ?? Self.defaultShown
    }

    /// Records the user's choice; choosing the default removes the override.
    public mutating func set(_ shown: Bool, for identifier: String) {
        if shown == Self.defaultShown {
            overrides[identifier] = nil
        } else if overrides[identifier] != nil || overrides.count < Self.maxEntries, !identifier.isEmpty,
                  identifier.count <= Self.maxKeyLength {
            overrides[identifier] = shown
        }
    }
}
