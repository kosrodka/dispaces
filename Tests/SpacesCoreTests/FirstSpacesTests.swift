import XCTest
@testable import SpacesCore

final class FirstSpacesTests: XCTestCase {
    func testShownByDefaultOnEveryDisplay() {
        let first = FirstSpaces()
        XCTAssertTrue(first.isShown("EXT"))
        XCTAssertTrue(first.isShown("MAC"))
    }

    func testOverridesAndBackToDefault() {
        var first = FirstSpaces()
        first.set(false, for: "EXT")
        XCTAssertFalse(first.isShown("EXT"))
        XCTAssertTrue(first.isShown("MAC"))
        XCTAssertEqual(FirstSpaces(stored: first.stored), first)
        first.set(true, for: "EXT")
        XCTAssertNil(first.overrides["EXT"], "the default isn't stored")
    }

    func testBadStoredValues() {
        XCTAssertTrue(FirstSpaces(stored: "junk").overrides.isEmpty)
        let loaded = FirstSpaces(stored: ["A": true, "B": "yes", "": false, String(repeating: "x", count: 300): true])
        XCTAssertEqual(loaded.overrides, ["A": true])
        var many: [String: Any] = [:]
        for i in 0..<100 { many["D\(i)"] = true }
        XCTAssertEqual(FirstSpaces(stored: many).overrides.count, FirstSpaces.maxEntries)
    }

    func testOverviewHidesFirstSpaces() {
        var memory = DisplayMemory()
        memory.update(with: Fixtures.twoDisplaysSnapshot, displayName: { $0.identifier },
                      spaceName: { "Desk \($0.managedID)" }, now: 1000)
        let unplugged = SnapshotParser.parse([
            Fixtures.display("AAAA-1111", current: 3, spaces: [
                Fixtures.space(1), Fixtures.space(2, uuid: "U-2"), Fixtures.space(3, uuid: "U-3"),
                Fixtures.space(5, uuid: "U-5"),
            ]),
        ])
        let all = DisplayOverview(snapshot: unplugged, memory: memory, names: Names(), displayName: { $0.identifier })
        XCTAssertEqual(all.sections[0].rows.map(\.number), ["1", "2", "3"])
        XCTAssertEqual(all.sections[1].rows.map(\.note), ["not found", "now on AAAA-1111"])

        let hidden = DisplayOverview(snapshot: unplugged, memory: memory, names: Names(),
                                     showsFirstSpace: { $0 != "AAAA-1111" && $0 != "BBBB-2222" },
                                     displayName: { $0.identifier })
        XCTAssertEqual(hidden.sections[0].rows.map(\.number), ["2", "3"])
        XCTAssertEqual(hidden.sections[1].rows.map(\.note), ["now on AAAA-1111"], "B's lost first desktop is hidden")
    }
}
