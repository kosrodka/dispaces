import Foundation

/// Decides when an Option-drag over a Space tile should switch to that Space.
///
/// The user holds a window with the mouse while holding Option, and rests the pointer on
/// a tile. The tile is "armed" (shown in yellow) straight away and the switch
/// happens once it has stayed there for `dwell`, so sweeping across the bar
/// doesn't switch. macOS carries the window the user is holding to the new
/// Space; the app never touches the window itself. Fires once per tile visit.
public struct DragArming: Equatable, Sendable {
    /// How long the pointer must rest on a tile before switching, in seconds.
    public static let dwell: TimeInterval = 0.4

    /// The tile currently armed, if any.
    public private(set) var armedSpaceID: UInt64?
    private var since: TimeInterval = 0
    private var fired = false

    public init() {}

    /// Feeds one sample of the pointer state. Returns the Space to switch to now, if any.
    /// - Parameters:
    ///   - holding: the left mouse button and Option are both held.
    ///   - spaceUnderPointer: the desktop tile under the pointer, or nil.
    ///   - now: a monotonic time in seconds.
    public mutating func update(holding: Bool, spaceUnderPointer: UInt64?, now: TimeInterval) -> UInt64? {
        guard holding, let space = spaceUnderPointer else {
            self = DragArming()
            return nil
        }
        if space != armedSpaceID {
            armedSpaceID = space
            since = now
            fired = false
        }
        guard !fired, now - since >= DragArming.dwell else { return nil }
        fired = true
        return space
    }
}
