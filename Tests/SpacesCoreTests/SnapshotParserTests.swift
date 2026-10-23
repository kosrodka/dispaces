import XCTest
@testable import SpacesCore

final class SnapshotParserTests: XCTestCase {
    func testParsesDisplaysInOrder() {
        let snap = Fixtures.twoDisplaysSnapshot
        XCTAssertEqual(snap.displays.map(\.identifier), ["AAAA-1111", "BBBB-2222"])
        XCTAssertEqual(snap.displays[0].currentSpaceID, 3)
        XCTAssertEqual(snap.displays[1].currentSpaceID, 5)
    }

    func testDesktopNumbersAreGlobalAndSkipFullScreen() {
        let snap = Fixtures.twoDisplaysSnapshot
        XCTAssertEqual(snap.displays[0].spaces.map(\.desktopNumber), [1, 2, 3, nil])
        XCTAssertEqual(snap.displays[1].spaces.map(\.desktopNumber), [4, 5])
        XCTAssertEqual(snap.desktopCount, 5)
    }

    func testFullScreenSpace() {
        let fs = Fixtures.twoDisplaysSnapshot.displays[0].spaces[3]
        XCTAssertEqual(fs.kind, .fullscreen)
        XCTAssertEqual(fs.appName, "Safari")
        XCTAssertEqual(fs.ownerPID, 501)
        XCTAssertEqual(fs.indexOnDisplay, 3)
    }

    func testNameKeys() {
        let snap = Fixtures.twoDisplaysSnapshot
        // Empty uuid → display + position.
        XCTAssertEqual(snap.displays[0].spaces[0].nameKey, "space:AAAA-1111#1")
        XCTAssertEqual(snap.displays[0].spaces[1].nameKey, "space:U-2")
        XCTAssertEqual(snap.displays[1].spaces[0].nameKey, "space:BBBB-2222#1")
        XCTAssertEqual(snap.displays[1].nameKey, "display:BBBB-2222")
    }

    func testNumberLabel() {
        let spaces = Fixtures.twoDisplaysSnapshot.displays.flatMap(\.spaces)
        XCTAssertEqual(spaces.map(\.numberLabel), ["1", "2", "3", "FS", "4", "5"])
    }

    func testLocate() {
        let snap = Fixtures.twoDisplaysSnapshot
        XCTAssertEqual(snap.locate(spaceID: 4)?.display.identifier, "BBBB-2222")
        XCTAssertNil(snap.locate(spaceID: 999))
    }

    func testFocusedDisplayFromActiveSpace() {
        let snap = SnapshotParser.parse(Fixtures.twoDisplays, activeSpaceID: 5)
        XCTAssertEqual(snap.focusedDisplay?.identifier, "BBBB-2222")
        XCTAssertNil(SnapshotParser.parse(Fixtures.twoDisplays, activeSpaceID: 0).focusedDisplay)
        XCTAssertNil(Fixtures.twoDisplaysSnapshot.focusedDisplay)
    }

    func testCombinedDisplay() {
        let snap = SnapshotParser.parse([Fixtures.display("Main", current: 1, spaces: [Fixtures.space(1), Fixtures.space(2)])])
        XCTAssertTrue(snap.displays[0].spansAllDisplays)
    }

    func testRejectsGarbageWithoutCrashing() {
        let inputs: [Any?] = [
            nil, 42, "x", [1, 2, 3], [["Display Identifier": 5]],
            [["Display Identifier": "A", "Spaces": "nope"]],
            [["Display Identifier": "A", "Spaces": [["ManagedSpaceID": "1", "type": 0] as [String: Any]]] as [String: Any]],
            [["Display Identifier": "A", "Spaces": [["ManagedSpaceID": -1, "type": 0]]] as [String: Any]],
            [["Display Identifier": "A\u{0}B", "Spaces": [Any]()] as [String: Any]],
            [["Display Identifier": String(repeating: "x", count: 500), "Spaces": [Any]()] as [String: Any]],
        ]
        for input in inputs {
            let snap = SnapshotParser.parse(input)
            XCTAssertTrue(snap.isEmpty, "expected nothing usable from \(String(describing: input))")
        }
    }

    func testSkipsUnknownSpaceTypes() {
        let snap = SnapshotParser.parse([Fixtures.display("A", current: 1, spaces: [Fixtures.space(1), Fixtures.space(2, type: 2)])])
        XCTAssertEqual(snap.displays[0].spaces.count, 1)
    }

    func testIgnoresDuplicateDisplays() {
        let d = Fixtures.display("A", current: 1, spaces: [Fixtures.space(1)])
        XCTAssertEqual(SnapshotParser.parse([d, d]).displays.count, 1)
    }

    func testCapsSizes() {
        let many = (1...500).map { Fixtures.space($0) }
        let snap = SnapshotParser.parse([Fixtures.display("A", current: 1, spaces: many)])
        XCTAssertEqual(snap.displays[0].spaces.count, SnapshotParser.maxSpacesPerDisplay)
    }

    /// Randomised structure fuzzing: must never trap.
    func testFuzzNeverCrashes() {
        var rng = SystemRandomNumberGenerator()
        func randomValue(_ depth: Int) -> Any {
            switch Int.random(in: 0..<7, using: &rng) {
            case 0: return Int.random(in: -5...5, using: &rng)
            case 1: return ["", "uuid", "Main", "\u{202E}x"].randomElement(using: &rng)!
            case 2: return NSNumber(value: Double.random(in: -1...1, using: &rng))
            case 3 where depth > 0: return (0..<Int.random(in: 0...3, using: &rng)).map { _ in randomValue(depth - 1) }
            case 4 where depth > 0:
                let keys = ["Display Identifier", "Current Space", "Spaces", "ManagedSpaceID", "uuid", "type", "TileLayoutManager", "TileSpaces", "pid", "appName"]
                var d: [String: Any] = [:]
                for _ in 0..<Int.random(in: 0...5, using: &rng) { d[keys.randomElement(using: &rng)!] = randomValue(depth - 1) }
                return d
            default: return NSNull()
            }
        }
        for _ in 0..<2_000 {
            _ = SnapshotParser.parse(randomValue(4))
        }
    }
}
