import Foundation

/// Remembers which Spaces belonged to which display, so a display that is
/// unplugged keeps its Spaces grouped under its name (a "disconnected" display).
///
/// macOS itself moves an unplugged display's Spaces onto a connected display;
/// the app can't stop that. It only remembers the grouping and shows it: in the
/// bar (as a separate group) and in the "Manage displays and spaces" window.
/// Stored in the app's own preferences; everything read back is validated.
public struct DisplayMemory: Equatable, Sendable {
    public struct RememberedSpace: Equatable, Sendable {
        /// The Space's name key when it was last seen on its display.
        public let key: String
        /// macOS's id for the Space; valid until the Mac restarts.
        public let managedID: UInt64
        /// The name the bar showed for it.
        public let name: String

        public init(key: String, managedID: UInt64, name: String) {
            self.key = key
            self.managedID = managedID
            self.name = name
        }

        /// True when `space` is this remembered Space. The id is used within a
        /// session; the key only when it's built from the Space's own UUID (a
        /// display's first desktop has none, so its key depends on the display).
        public func matches(_ space: Space) -> Bool {
            space.managedID == managedID || (!space.uuid.isEmpty && space.nameKey == key)
        }
    }

    public struct Record: Equatable, Sendable {
        /// Display identifier (UUID).
        public let identifier: String
        /// The display's name when it was last connected.
        public var name: String
        public var spaces: [RememberedSpace]
        /// When it was last connected, seconds since 1970.
        public var lastSeen: Double

        public init(identifier: String, name: String, spaces: [RememberedSpace], lastSeen: Double) {
            self.identifier = identifier
            self.name = name
            self.spaces = spaces
            self.lastSeen = lastSeen
        }

        public var nameKey: String { "display:" + identifier }
    }

    public static let maxDisplays = 16
    public static let maxSpaces = 64
    static let maxText = 256
    /// lastSeen of a connected display is refreshed at most this often, so
    /// preferences aren't rewritten on every refresh.
    static let touchInterval: Double = 3600

    public private(set) var records: [String: Record] = [:]

    public init() {}

    public init(stored raw: Any?) {
        guard let dict = raw as? [String: Any] else { return }
        for (id, value) in dict {
            if records.count >= Self.maxDisplays { break }
            guard !id.isEmpty, id.count <= Self.maxText, id != Display.combinedIdentifier,
                  let entry = value as? [String: Any],
                  let name = entry["name"] as? String, name.count <= Self.maxText,
                  let lastSeen = (entry["lastSeen"] as? NSNumber)?.doubleValue, lastSeen.isFinite,
                  let list = entry["spaces"] as? [Any] else { continue }
            let spaces = list.prefix(Self.maxSpaces).compactMap { item -> RememberedSpace? in
                guard let s = item as? [String: Any],
                      let key = s["key"] as? String, !key.isEmpty, key.count <= Self.maxText,
                      let spaceID = (s["id"] as? NSNumber)?.uint64Value,
                      let spaceName = s["name"] as? String, spaceName.count <= Self.maxText else { return nil }
                return RememberedSpace(key: key, managedID: spaceID, name: NameSanitizer.sanitize(spaceName))
            }
            records[id] = Record(identifier: id, name: NameSanitizer.sanitize(name), spaces: spaces, lastSeen: lastSeen)
        }
    }

    /// The form saved to preferences.
    public var stored: [String: Any] {
        records.mapValues { record in
            [
                "name": record.name,
                "lastSeen": record.lastSeen,
                "spaces": record.spaces.map { ["key": $0.key, "id": NSNumber(value: $0.managedID), "name": $0.name] as [String: Any] },
            ] as [String: Any]
        }
    }

    /// Remembered displays that aren't connected in `snapshot`, most recently seen first.
    public func disconnected(in snapshot: Snapshot) -> [Record] {
        let connected = Set(snapshot.displays.map(\.identifier))
        return records.values.filter { !connected.contains($0.identifier) }
            .sorted { ($0.lastSeen, $0.identifier) > ($1.lastSeen, $1.identifier) }
    }

    /// The disconnected display a live Space belongs to, if any.
    public func ghostOwner(of space: Space, in snapshot: Snapshot) -> Record? {
        disconnected(in: snapshot).first { $0.spaces.contains { $0.matches(space) } }
    }

    /// Records what each connected display holds now. Spaces that belong to a
    /// disconnected display stay with it instead of joining the display macOS
    /// moved them to. Does nothing when macOS reports one shared Space list.
    /// - Returns: true when something changed and should be saved.
    @discardableResult
    public mutating func update(with snapshot: Snapshot, displayName: (Display) -> String,
                                spaceName: (Space) -> String, now: Double) -> Bool {
        guard !snapshot.isEmpty, !snapshot.displays.contains(where: \.spansAllDisplays) else { return false }
        let ghosts = disconnected(in: snapshot)
        var changed = false
        for display in snapshot.displays where !display.spaces.isEmpty {
            let own = display.spaces.filter { space in !ghosts.contains { $0.spaces.contains { $0.matches(space) } } }
            let spaces = own.prefix(Self.maxSpaces).map {
                RememberedSpace(key: $0.nameKey, managedID: $0.managedID, name: NameSanitizer.sanitize(spaceName($0)))
            }
            let name = NameSanitizer.sanitize(displayName(display))
            var record = records[display.identifier]
                ?? Record(identifier: display.identifier, name: name, spaces: [], lastSeen: 0)
            let stale = now - record.lastSeen >= Self.touchInterval
            if record.name != name || record.spaces != spaces || stale {
                record.name = name
                record.spaces = spaces
                record.lastSeen = now
                records[display.identifier] = record
                changed = true
            }
        }
        // Keep the most recently seen displays.
        if records.count > Self.maxDisplays {
            let keep = records.values.sorted { $0.lastSeen > $1.lastSeen }.prefix(Self.maxDisplays).map(\.identifier)
            records = records.filter { keep.contains($0.key) }
            changed = true
        }
        return changed
    }

    /// Takes one Space out of a disconnected display's group. From then on the
    /// app treats it as belonging to the display macOS moved it to.
    /// Returns false if the display is connected or unknown, or the Space isn't in its group.
    @discardableResult
    public mutating func removeSpace(_ space: RememberedSpace, from identifier: String, snapshot: Snapshot) -> Bool {
        guard var record = records[identifier], !snapshot.displays.contains(where: { $0.identifier == identifier }),
              let index = record.spaces.firstIndex(of: space) else { return false }
        record.spaces.remove(at: index)
        records[identifier] = record
        return true
    }

    /// Puts a Space back into a disconnected display's group at `index`
    /// (undoing `removeSpace`). Returns false if the display is connected or
    /// unknown, or the Space is already there.
    @discardableResult
    public mutating func insertSpace(_ space: RememberedSpace, at index: Int, into identifier: String,
                                     snapshot: Snapshot) -> Bool {
        guard var record = records[identifier], !snapshot.displays.contains(where: { $0.identifier == identifier }),
              !record.spaces.contains(space), record.spaces.count < Self.maxSpaces else { return false }
        record.spaces.insert(space, at: min(max(index, 0), record.spaces.count))
        records[identifier] = record
        return true
    }

    /// Brings back a forgotten display's record (undoing `forget`). Returns
    /// false if the display is connected or already remembered, or memory is full.
    @discardableResult
    public mutating func restore(_ record: Record, snapshot: Snapshot) -> Bool {
        guard records[record.identifier] == nil, records.count < Self.maxDisplays,
              !snapshot.displays.contains(where: { $0.identifier == record.identifier }) else { return false }
        records[record.identifier] = record
        return true
    }

    /// Forgets a display that isn't connected. Returns false if it's connected or unknown.
    @discardableResult
    public mutating func forget(_ identifier: String, snapshot: Snapshot) -> Bool {
        guard records[identifier] != nil, !snapshot.displays.contains(where: { $0.identifier == identifier }) else {
            return false
        }
        records[identifier] = nil
        return true
    }
}
