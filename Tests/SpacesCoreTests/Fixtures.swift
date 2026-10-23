import Foundation
@testable import SpacesCore

/// Raw data shaped like `CGSCopyManagedDisplaySpaces` output.
enum Fixtures {
    static func space(_ id: Int, uuid: String = "", type: Int = 0) -> [String: Any] {
        ["ManagedSpaceID": NSNumber(value: id), "id64": NSNumber(value: id), "uuid": uuid, "type": NSNumber(value: type)]
    }

    static func display(_ identifier: String, current: Int, spaces: [[String: Any]]) -> [String: Any] {
        ["Display Identifier": identifier,
         "Current Space": ["ManagedSpaceID": NSNumber(value: current), "uuid": "", "type": NSNumber(value: 0)] as [String: Any],
         "Spaces": spaces]
    }

    /// Two displays: A has desktops 1–3 and a full-screen Space; B has desktops 4–5.
    static var twoDisplays: [Any] {
        [
            display("AAAA-1111", current: 3, spaces: [
                space(1), space(2, uuid: "U-2"), space(3, uuid: "U-3"),
                { () -> [String: Any] in
                    var fs = space(9, uuid: "U-9", type: 4)
                    fs["TileLayoutManager"] = ["TileSpaces": [["appName": "Safari", "pid": NSNumber(value: 501)] as [String: Any]]] as [String: Any]
                    return fs
                }(),
            ]),
            display("BBBB-2222", current: 5, spaces: [space(4), space(5, uuid: "U-5")]),
        ]
    }

    static var twoDisplaysSnapshot: Snapshot { SnapshotParser.parse(twoDisplays) }
}
