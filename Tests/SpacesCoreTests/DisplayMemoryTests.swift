import XCTest
@testable import SpacesCore

final class DisplayMemoryTests: XCTestCase {
    private func remember(_ snapshot: Snapshot, into memory: inout DisplayMemory, now: Double = 1000) {
        memory.update(with: snapshot, displayName: { "Name " + $0.identifier.prefix(4) },
                      spaceName: { "Desk \($0.managedID)" }, now: now)
    }

    /// B unplugged: macOS moved its Spaces 4 and 5 onto A.
    private var afterUnplug: Snapshot {
        SnapshotParser.parse([
            Fixtures.display("AAAA-1111", current: 3, spaces: [
                Fixtures.space(1), Fixtures.space(2, uuid: "U-2"), Fixtures.space(3, uuid: "U-3"),
                Fixtures.space(4), Fixtures.space(5, uuid: "U-5"),
            ]),
        ])
    }

    func testRemembersEachDisplaysSpaces() {
        var memory = DisplayMemory()
        remember(Fixtures.twoDisplaysSnapshot, into: &memory)
        XCTAssertEqual(memory.records["AAAA-1111"]?.spaces.map(\.managedID), [1, 2, 3, 9])
        XCTAssertEqual(memory.records["BBBB-2222"]?.spaces.map(\.managedID), [4, 5])
        XCTAssertEqual(memory.records["BBBB-2222"]?.name, "Name BBBB")
    }

    func testUnpluggedDisplayKeepsItsSpaces() {
        var memory = DisplayMemory()
        remember(Fixtures.twoDisplaysSnapshot, into: &memory)
        remember(afterUnplug, into: &memory, now: 2000)

        XCTAssertEqual(memory.records["AAAA-1111"]?.spaces.map(\.managedID), [1, 2, 3], "A doesn't absorb B's Spaces")
        XCTAssertEqual(memory.disconnected(in: afterUnplug).map(\.identifier), ["BBBB-2222"])
        let moved = afterUnplug.displays[0].spaces.filter { $0.managedID >= 4 }
        for space in moved {
            XCTAssertEqual(memory.ghostOwner(of: space, in: afterUnplug)?.identifier, "BBBB-2222")
        }
        XCTAssertNil(memory.ghostOwner(of: afterUnplug.displays[0].spaces[0], in: afterUnplug))
    }

    func testReconnectingRefreshesTheRecord() {
        var memory = DisplayMemory()
        remember(Fixtures.twoDisplaysSnapshot, into: &memory)
        remember(afterUnplug, into: &memory, now: 2000)
        // lastSeen is refreshed at most once per touchInterval, so prefs aren't rewritten each refresh.
        let later = 1000 + DisplayMemory.touchInterval
        remember(Fixtures.twoDisplaysSnapshot, into: &memory, now: later)
        XCTAssertEqual(memory.disconnected(in: Fixtures.twoDisplaysSnapshot), [])
        XCTAssertEqual(memory.records["BBBB-2222"]?.lastSeen, later)
    }

    func testSharedSpaceListIsIgnored() {
        var memory = DisplayMemory()
        let shared = SnapshotParser.parse([Fixtures.display("Main", current: 1, spaces: [Fixtures.space(1)])])
        XCTAssertFalse(memory.update(with: shared, displayName: { _ in "x" }, spaceName: { _ in "y" }, now: 1))
        XCTAssertTrue(memory.records.isEmpty)
    }

    func testNoRewriteWhenNothingChanged() {
        var memory = DisplayMemory()
        remember(Fixtures.twoDisplaysSnapshot, into: &memory, now: 1000)
        XCTAssertFalse(memory.update(with: Fixtures.twoDisplaysSnapshot, displayName: { "Name " + $0.identifier.prefix(4) },
                                     spaceName: { "Desk \($0.managedID)" }, now: 1500))
    }

    func testRoundTripAndBadInput() {
        var memory = DisplayMemory()
        remember(Fixtures.twoDisplaysSnapshot, into: &memory)
        XCTAssertEqual(DisplayMemory(stored: memory.stored), memory)

        XCTAssertTrue(DisplayMemory(stored: "garbage").records.isEmpty)
        let bad: [String: Any] = [
            "X": ["name": 5, "lastSeen": 1, "spaces": []],
            "Y": ["name": "ok", "lastSeen": 1, "spaces": [["key": "", "id": 1, "name": "a"], "junk"]],
            "Main": ["name": "shared", "lastSeen": 1, "spaces": []],
        ]
        let loaded = DisplayMemory(stored: bad)
        XCTAssertEqual(Array(loaded.records.keys), ["Y"])
        XCTAssertEqual(loaded.records["Y"]?.spaces, [])
    }

    func testForgetOnlyDisconnected() {
        var memory = DisplayMemory()
        remember(Fixtures.twoDisplaysSnapshot, into: &memory)
        XCTAssertFalse(memory.forget("AAAA-1111", snapshot: afterUnplug))
        XCTAssertTrue(memory.forget("BBBB-2222", snapshot: afterUnplug))
        XCTAssertNil(memory.records["BBBB-2222"])
    }

    func testUndoRemoveAndForget() {
        var memory = DisplayMemory()
        remember(Fixtures.twoDisplaysSnapshot, into: &memory)
        guard let record = memory.records["BBBB-2222"], let first = record.spaces.first else {
            return XCTFail("not remembered")
        }
        XCTAssertTrue(memory.removeSpace(first, from: "BBBB-2222", snapshot: afterUnplug))
        XCTAssertTrue(memory.insertSpace(first, at: 0, into: "BBBB-2222", snapshot: afterUnplug))
        XCTAssertEqual(memory.records["BBBB-2222"], record, "back in its old place")
        XCTAssertFalse(memory.insertSpace(first, at: 0, into: "BBBB-2222", snapshot: afterUnplug), "no duplicates")
        XCTAssertFalse(memory.insertSpace(first, at: 0, into: "AAAA-1111", snapshot: afterUnplug), "connected")

        XCTAssertTrue(memory.forget("BBBB-2222", snapshot: afterUnplug))
        XCTAssertTrue(memory.restore(record, snapshot: afterUnplug))
        XCTAssertEqual(memory.records["BBBB-2222"], record)
        XCTAssertFalse(memory.restore(record, snapshot: afterUnplug), "already there")
        XCTAssertTrue(memory.forget("BBBB-2222", snapshot: afterUnplug))
        XCTAssertFalse(memory.restore(record, snapshot: Fixtures.twoDisplaysSnapshot), "connected again")
    }

    func testRemoveSpaceOnlyFromDisconnected() {
        var memory = DisplayMemory()
        remember(Fixtures.twoDisplaysSnapshot, into: &memory)
        guard let first = memory.records["BBBB-2222"]?.spaces.first,
              let own = memory.records["AAAA-1111"]?.spaces.first else { return XCTFail("not remembered") }
        XCTAssertFalse(memory.removeSpace(own, from: "AAAA-1111", snapshot: afterUnplug), "connected")
        XCTAssertTrue(memory.removeSpace(first, from: "BBBB-2222", snapshot: afterUnplug))
        XCTAssertFalse(memory.removeSpace(first, from: "BBBB-2222", snapshot: afterUnplug), "already gone")
        XCTAssertEqual(memory.records["BBBB-2222"]?.spaces.map(\.managedID), [5])

        // Next refresh: the released Space belongs to A, the other stays with B.
        remember(afterUnplug, into: &memory, now: 2000)
        XCTAssertEqual(memory.records["AAAA-1111"]?.spaces.map(\.managedID), [1, 2, 3, 4])
        XCTAssertNil(memory.ghostOwner(of: afterUnplug.displays[0].spaces[3], in: afterUnplug))
        XCTAssertEqual(memory.ghostOwner(of: afterUnplug.displays[0].spaces[4], in: afterUnplug)?.identifier, "BBBB-2222")
    }
}

final class DisplayOverviewTests: XCTestCase {
    func testConnectedFirstThenDisconnectedWithWhereaboutsOfItsSpaces() {
        var memory = DisplayMemory()
        memory.update(with: Fixtures.twoDisplaysSnapshot, displayName: { "Name " + $0.identifier.prefix(4) },
                      spaceName: { "Desk \($0.managedID)" }, now: 1000)
        let unplugged = SnapshotParser.parse([
            Fixtures.display("AAAA-1111", current: 3, spaces: [
                Fixtures.space(1), Fixtures.space(2, uuid: "U-2"), Fixtures.space(3, uuid: "U-3"), Fixtures.space(4),
            ]),
        ])
        var names = Names()
        names.setName("Music", for: Fixtures.twoDisplaysSnapshot.displays[1].spaces[1], liveKeys: [])

        let overview = DisplayOverview(snapshot: unplugged, memory: memory, names: names,
                                       displayName: { _ in "Built-in" })
        XCTAssertEqual(overview.sections.map(\.connected), [true, false])
        XCTAssertEqual(overview.sections[0].rows.map(\.number), ["1", "2", "3"], "B's Space isn't listed under A")
        XCTAssertEqual(overview.sections[0].rows[2].note, "current")
        XCTAssertEqual(overview.sections[1].name, "Name BBBB")
        XCTAssertEqual(overview.sections[1].lastSeen, 1000)
        XCTAssertEqual(overview.sections[1].rows.map(\.note), ["now on Built-in", "not found"])
        XCTAssertEqual(overview.sections[1].rows[1].name, "Music", "keeps the user's name")

        // A ghost Space can move only to the display its live Space is on.
        let ghostFound = overview.sections[1].rows[0]
        let ghostLost = overview.sections[1].rows[1]
        XCTAssertEqual(ghostFound.onDisplay, "AAAA-1111")
        XCTAssertTrue(DisplayOverview.canMove(ghostFound, to: "AAAA-1111"))
        XCTAssertFalse(DisplayOverview.canMove(ghostFound, to: "BBBB-2222"), "macOS put it elsewhere")
        XCTAssertFalse(DisplayOverview.canMove(ghostLost, to: "AAAA-1111"), "not found")
        XCTAssertFalse(DisplayOverview.canMove(overview.sections[0].rows[0], to: "AAAA-1111"), "not a ghost")
    }

    func testConnectedDisplaysFollowScreenOrder() {
        let overview = DisplayOverview(snapshot: Fixtures.twoDisplaysSnapshot, memory: DisplayMemory(), names: Names(),
                                       screenOrder: ["bbbb-2222", "AAAA-1111"], displayName: { $0.identifier })
        XCTAssertEqual(overview.sections.map(\.identifier), ["BBBB-2222", "AAAA-1111"])
        let unordered = DisplayOverview(snapshot: Fixtures.twoDisplaysSnapshot, memory: DisplayMemory(), names: Names(),
                                        screenOrder: ["BBBB-2222"], displayName: { $0.identifier })
        XCTAssertEqual(unordered.sections.map(\.identifier), ["BBBB-2222", "AAAA-1111"])
        XCTAssertEqual(DisplayOverview(snapshot: Fixtures.twoDisplaysSnapshot, memory: DisplayMemory(), names: Names(),
                                       displayName: { $0.identifier }).sections.map(\.identifier),
                       ["AAAA-1111", "BBBB-2222"], "macOS order when unknown")
    }
}
