import Foundation

/// Whether a display's first Space is shown (in the menu bar, in the logical
/// spaces and in the Manage window). The built-in display shows it and external
/// displays don't, unless the user changed that in the preferences file:
///
///     defaults write io.github.kosrodka.SpacesBar firstSpaceBuiltIn -bool false
///     defaults write io.github.kosrodka.SpacesBar firstSpaceExternal -bool true
///
/// Nothing in the app writes these; everything read back is type-checked.
public struct FirstSpaceRule: Equatable, Sendable {
    /// The built-in display shows its first Space.
    public var builtIn: Bool
    /// External displays show their first Space.
    public var external: Bool

    public init(builtIn: Bool, external: Bool) {
        self.builtIn = builtIn
        self.external = external
    }

    public static let defaults = FirstSpaceRule(builtIn: true, external: false)

    /// Builds from untrusted stored values; anything but a Bool means the default.
    public init(storedBuiltIn: Any?, storedExternal: Any?) {
        self.init(builtIn: storedBuiltIn as? Bool ?? Self.defaults.builtIn,
                  external: storedExternal as? Bool ?? Self.defaults.external)
    }

    /// When Spaces span all displays there's one list, and its first Space is always shown.
    public func isShown(identifier: String, builtIn isBuiltIn: Bool) -> Bool {
        identifier == Display.combinedIdentifier || (isBuiltIn ? builtIn : external)
    }
}
