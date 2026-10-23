import Foundation

/// Turns the raw result of `CGSCopyManagedDisplaySpaces` into a `Snapshot`.
///
/// The input comes from a private API whose shape Apple may change, so every
/// value is type-checked and anything unexpected is skipped. This never traps.
public enum SnapshotParser {
    /// Hard limits so a corrupt or hostile input can't make us do unbounded work.
    public static let maxDisplays = 32
    public static let maxSpacesPerDisplay = 64
    public static let maxIdentifierLength = 128

    public static func parse(_ raw: Any?, activeSpaceID: UInt64? = nil) -> Snapshot {
        guard let list = raw as? [Any] else { return .empty }

        var displays: [Display] = []
        var nextDesktopNumber = 1

        for item in list.prefix(maxDisplays) {
            guard let dict = item as? [String: Any],
                  let identifier = cleanIdentifier(dict["Display Identifier"]) else { continue }

            let current = (dict["Current Space"] as? [String: Any]).flatMap { uint64($0["ManagedSpaceID"]) }

            var spaces: [Space] = []
            for rawSpace in (dict["Spaces"] as? [Any] ?? []).prefix(maxSpacesPerDisplay) {
                guard let s = rawSpace as? [String: Any],
                      let managedID = uint64(s["ManagedSpaceID"]) ?? uint64(s["id64"]),
                      let type = int(s["type"]) else { continue }

                let kind: SpaceKind
                switch type {
                case 0: kind = .desktop
                case 4: kind = .fullscreen
                default: continue // unknown Space types are not shown
                }

                let uuid = cleanIdentifier(s["uuid"]) ?? ""
                let index = spaces.count
                var number: Int? = nil
                if kind == .desktop {
                    number = nextDesktopNumber
                    nextDesktopNumber += 1
                }
                let key = uuid.isEmpty ? "space:\(identifier)#\(index + 1)" : "space:\(uuid)"
                let (appName, pid) = fullscreenOwner(s)

                spaces.append(Space(managedID: managedID, uuid: uuid, kind: kind, desktopNumber: number,
                                    indexOnDisplay: index, appName: kind == .fullscreen ? appName : nil,
                                    ownerPID: kind == .fullscreen ? pid : nil, nameKey: key))
            }

            // Ignore duplicate display entries rather than showing them twice.
            if displays.contains(where: { $0.identifier == identifier }) { continue }
            displays.append(Display(identifier: identifier, currentSpaceID: current, spaces: spaces))
        }
        return Snapshot(displays: displays, activeSpaceID: activeSpaceID == 0 ? nil : activeSpaceID)
    }

    // MARK: - Helpers

    static func uint64(_ value: Any?) -> UInt64? {
        switch value {
        case let v as UInt64: return v
        case let v as Int: return v >= 0 ? UInt64(v) : nil
        case let v as Int64: return v >= 0 ? UInt64(v) : nil
        case let v as NSNumber:
            let i = v.int64Value
            return i >= 0 ? UInt64(i) : nil
        default: return nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let v as Int: return v
        case let v as NSNumber: return v.intValue
        default: return nil
        }
    }

    /// Accepts short, printable identifiers only.
    static func cleanIdentifier(_ value: Any?) -> String? {
        guard let s = value as? String, s.count <= maxIdentifierLength else { return nil }
        if s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return nil }
        return s
    }

    /// Full-screen Spaces sometimes carry the owning app's name or pid. Both are optional.
    static func fullscreenOwner(_ space: [String: Any]) -> (String?, Int32?) {
        var name: String? = nil
        var pid: Int32? = nil
        if let manager = space["TileLayoutManager"] as? [String: Any],
           let tiles = manager["TileSpaces"] as? [Any],
           let first = tiles.first as? [String: Any] {
            name = first["appName"] as? String
            if let p = int(first["pid"]) { pid = Int32(clamping: p) }
        }
        if pid == nil, let p = int(space["pid"]) { pid = Int32(clamping: p) }
        if let n = name { name = NameSanitizer.sanitize(n) }
        if name?.isEmpty == true { name = nil }
        if let p = pid, p <= 0 { pid = nil }
        return (name, pid)
    }
}
