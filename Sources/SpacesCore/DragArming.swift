import Foundation

/// Decides when an Option-Control drag over a tile should switch to that tile's Space.
///
/// The user holds a window with the mouse while holding Option and Control, and rests the
/// pointer on a tile. The tile is "armed" (shown with a thick ring) straight away and the switch
/// happens once it has stayed there for `dwell`, so sweeping across the bar
/// doesn't switch. macOS carries the window the user is holding to the new
/// Space; the app never touches the window itself. Fires once per tile visit.
public struct DragArming: Equatable, Sendable {
    /// How long the pointer must rest on a tile before switching, in seconds.
    public static let dwell: TimeInterval = 0.4

    /// The tile currently armed, if any.
    public private(set) var armed: TileTarget?
    private var since: TimeInterval = 0
    private var fired = false

    public init() {}

    /// Feeds one sample of the pointer state. Returns the tile to switch to now, if any.
    /// - Parameters:
    ///   - holding: the left mouse button, Option and Control are all held.
    ///   - target: the tile under the pointer that may arm, or nil.
    ///   - now: a monotonic time in seconds.
    public mutating func update(holding: Bool, target: TileTarget?, now: TimeInterval) -> TileTarget? {
        guard holding, let space = target else {
            self = DragArming()
            return nil
        }
        if space != armed {
            armed = space
            since = now
            fired = false
        }
        guard !fired, now - since >= DragArming.dwell else { return nil }
        fired = true
        return space
    }
}
