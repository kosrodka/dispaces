import XCTest
@testable import SpacesCore

final class SpaceAppsTests: XCTestCase {
    private func window(_ id: Int, pid: Int, layer: Int = 0, width: Double = 800, height: Double = 600,
                        alpha: Double = 1) -> [String: Any] {
        ["kCGWindowNumber": NSNumber(value: id), "kCGWindowOwnerPID": NSNumber(value: pid),
         "kCGWindowLayer": NSNumber(value: layer), "kCGWindowAlpha": NSNumber(value: alpha),
         "kCGWindowBounds": ["X": NSNumber(value: 0), "Y": NSNumber(value: 0),
                             "Width": NSNumber(value: width), "Height": NSNumber(value: height)]]
    }

    func testKeepsOnlyNormalAppWindows() {
        let raw: [Any] = [
            window(1, pid: 10),
            window(2, pid: 11, layer: 25),          // menu bar extra / floating
            window(3, pid: 12, width: 10),          // tiny helper
            window(4, pid: 13, alpha: 0),           // invisible
            window(5, pid: 99),                     // this app
            "garbage",
            ["kCGWindowNumber": "x"],
            window(6, pid: 14),
        ]
        XCTAssertEqual(SpaceApps.windows(from: raw, excludingPID: 99),
                       [WindowEntry(windowID: 1, ownerPID: 10), WindowEntry(windowID: 6, ownerPID: 14)])
    }

    func testMissingBoundsIsSkipped() {
        var info = window(1, pid: 10)
        info["kCGWindowBounds"] = nil
        XCTAssertEqual(SpaceApps.windows(from: [info], excludingPID: 0), [])
    }

    func testAppsOnSpaceAreUniqueAndInOrder() {
        let windows = [WindowEntry(windowID: 1, ownerPID: 10), WindowEntry(windowID: 2, ownerPID: 20),
                       WindowEntry(windowID: 3, ownerPID: 10), WindowEntry(windowID: 4, ownerPID: 30),
                       WindowEntry(windowID: 5, ownerPID: 40)]
        let spaces: [UInt32: [UInt64]] = [1: [7], 2: [8], 3: [7], 4: [7, 8], 5: []]
        XCTAssertEqual(SpaceApps.apps(on: 7, windows: windows) { spaces[$0] ?? [] }, [10, 30])
        XCTAssertEqual(SpaceApps.apps(on: 8, windows: windows) { spaces[$0] ?? [] }, [20, 30])
        XCTAssertEqual(SpaceApps.apps(on: 9, windows: windows) { spaces[$0] ?? [] }, [])
    }
}
