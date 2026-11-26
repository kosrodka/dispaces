import XCTest
@testable import SpacesCore

final class LogicalSpacesTests: XCTestCase {
    /// Displays as (identifier, current Space id, Spaces as (id, name)); a nil name keeps "Desktop N".
    private func make(_ displays: [(String, Int, [(Int, String?)])], fullScreen: [String: Int] = [:])
        -> (Snapshot, Names) {
        let raw: [Any] = displays.map { identifier, current, spaces in
            var list = spaces.map { Fixtures.space($0.0, uuid: "U-\($0.0)") }
            if let fs = fullScreen[identifier] { list.append(Fixtures.space(fs, uuid: "U-\(fs)", type: 4)) }
            return Fixtures.display(identifier, current: current, spaces: list)
        }
        let snapshot = SnapshotParser.parse(raw)
        var stored: [String: String] = [:]
        for (_, _, spaces) in displays {
            for (id, name) in spaces {
                if let name, let space = snapshot.locate(spaceID: UInt64(id))?.space { stored[space.nameKey] = name }
            }
        }
        return (snapshot, Names(storedSpaces: stored, storedDisplays: nil))
    }

    private func logical(_ snapshot: Snapshot, _ names: Names, memory: DisplayMemory = DisplayMemory(),
                         screenOrder: [String] = ["AAAA-1111", "BBBB-2222"],
                         showsFirstSpace: (String) -> Bool = { _ in true }) -> LogicalSpaces {
        LogicalSpaces(snapshot: snapshot, memory: memory, names: names, screenOrder: screenOrder,
                      showsFirstSpace: showsFirstSpace)
    }

    private var homeMusicTech: (Snapshot, Names) {
        make([("AAAA-1111", 1, [(1, "Home"), (2, "Music"), (3, "Tech")]),
              ("BBBB-2222", 6, [(4, "Home"), (5, "Music"), (6, "Tech")])])
    }

    func testGroupsByNameAcrossDisplays() {
        let (snapshot, names) = homeMusicTech
        let result = logical(snapshot, names)
        XCTAssertEqual(result.columns.map(\.number), [1, 2, 3])
        XCTAssertEqual(result.columns.map(\.title), ["Home", "Music", "Tech"])
        XCTAssertEqual(result.columns[0].cells.map(\.space.managedID), [1, 4])
        XCTAssertEqual(result.columns[0].cells.map(\.display), ["AAAA-1111", "BBBB-2222"])
        XCTAssertEqual(result.columns[2].cells.map(\.space.managedID), [3, 6])
    }

    func testCaseInsensitive() {
        let (snapshot, names) = make([("AAAA-1111", 1, [(1, "Home")]), ("BBBB-2222", 4, [(4, "home")])])
        let result = logical(snapshot, names)
        XCTAssertEqual(result.columns.count, 1)
        XCTAssertEqual(result.columns[0].title, "Home")
        XCTAssertEqual(result.columns[0].cells.map(\.space.managedID), [1, 4])
    }

    func testOrderFollowsFirstDisplayThenNewNames() {
        let (snapshot, names) = make([("AAAA-1111", 1, [(1, "Home"), (2, "Tech")]),
                                      ("BBBB-2222", 4, [(4, "Music"), (5, "Home")])])
        XCTAssertEqual(logical(snapshot, names).columns.map(\.title), ["Home", "Tech", "Music"])
    }

    func testUnnamedSpacesAreOwnColumns() {
        let (snapshot, names) = make([("AAAA-1111", 1, [(1, nil)]), ("BBBB-2222", 2, [(2, nil)])])
        let result = logical(snapshot, names)
        XCTAssertEqual(result.columns.map(\.title), ["Desktop 1", "Desktop 2"])
        XCTAssertEqual(result.columns.map(\.cells.count), [1, 1])
    }

    func testDuplicateOnOneDisplayGetsOwnColumn() {
        let (snapshot, names) = make([("AAAA-1111", 1, [(1, "Home"), (2, "Home")]),
                                      ("BBBB-2222", 4, [(4, "Home")])])
        let result = logical(snapshot, names)
        XCTAssertEqual(result.columns.map(\.title), ["Home", "Home"])
        XCTAssertEqual(result.columns[0].cells.map(\.space.managedID), [1, 4])
        XCTAssertEqual(result.columns[1].cells.map(\.space.managedID), [2])
        XCTAssertNil(result.columns[0].duplicateOn)
        XCTAssertEqual(result.columns[1].duplicateOn, "AAAA-1111")
        XCTAssertNotEqual(result.columns[0].key, result.columns[1].key)
        XCTAssertEqual(result.column(key: result.columns[1].key)?.number, 2)
    }

    func testMissingCell() {
        let (snapshot, names) = make([("AAAA-1111", 1, [(1, "Home"), (2, "Music")]),
                                      ("BBBB-2222", 4, [(4, "Home")])])
        let music = logical(snapshot, names).columns[1]
        XCTAssertEqual(music.title, "Music")
        XCTAssertNil(music.cell(on: "BBBB-2222"))
        XCTAssertEqual(music.cell(on: "AAAA-1111")?.space.managedID, 2)
    }

    func testCellOnDisplay() {
        let (snapshot, names) = homeMusicTech
        XCTAssertEqual(logical(snapshot, names).columns[1].cell(on: "bbbb-2222")?.space.managedID, 5)
    }

    func testExcludesFullScreenHiddenFirstAndGhosts() {
        // B was unplugged: macOS moved its Spaces 4 and 5 onto A; the app remembers them as B's.
        let (before, _) = make([("AAAA-1111", 1, [(1, "Home")]), ("BBBB-2222", 4, [(4, "Home"), (5, "Music")])])
        var memory = DisplayMemory()
        memory.update(with: before, displayName: { $0.identifier }, spaceName: { "\($0.managedID)" }, now: 1)
        let (after, names) = make([("AAAA-1111", 1, [(1, "Home"), (2, "Music"), (4, "Home"), (5, "Music")])],
                                  fullScreen: ["AAAA-1111": 9])
        let result = logical(after, names, memory: memory)
        XCTAssertEqual(result.columns.map(\.title), ["Home", "Music"])
        XCTAssertEqual(result.columns.flatMap(\.cells).map(\.space.managedID), [1, 2])
        XCTAssertEqual(result.fullScreen.map(\.space.managedID), [9])

        let (snapshot, names2) = homeMusicTech
        let hidden = logical(snapshot, names2, showsFirstSpace: { $0 != "BBBB-2222" })
        XCTAssertNil(hidden.columns[0].cell(on: "BBBB-2222"), "B's first Space is hidden")
        XCTAssertEqual(hidden.columns[1].cell(on: "BBBB-2222")?.space.managedID, 5)
    }

    func testStates() {
        let (snapshot, names) = make([("AAAA-1111", 1, [(1, "Home"), (2, "Music"), (3, "Tech"), (7, "Solo")]),
                                      ("BBBB-2222", 4, [(4, "Home"), (5, "Music"), (6, "Tech")])])
        var result = logical(snapshot, names)
        XCTAssertEqual(result.columns.map(\.state), [.all, .none, .none, .none])
        XCTAssertEqual(result.columns[0].cells.map(\.isCurrent), [true, true])

        let (split, names2) = make([("AAAA-1111", 1, [(1, "Home"), (2, "Music"), (7, "Solo")]),
                                    ("BBBB-2222", 5, [(4, "Home"), (5, "Music")])])
        result = logical(split, names2)
        XCTAssertEqual(result.columns.map(\.state), [.some, .some, .none])

        let (solo, names3) = make([("AAAA-1111", 7, [(1, "Home"), (7, "Solo")]), ("BBBB-2222", 5, [(4, "Home")])])
        XCTAssertEqual(logical(solo, names3).columns.map(\.state), [.none, .all], "a one-cell column that's shown is all")
    }

    func testCustomNameForRenaming() {
        let (snapshot, names) = make([("AAAA-1111", 1, [(1, "Home"), (2, nil)]), ("BBBB-2222", 4, [(4, "home")])])
        let result = logical(snapshot, names)
        XCTAssertEqual(result.columns[0].customName(in: names), "Home", "the first stored name")
        XCTAssertNil(result.columns[1].customName(in: names), "an unnamed Space has no custom name to offer")
    }

    func testCombinedList() {
        let (snapshot, names) = make([("Main", 1, [(1, "Home"), (2, "Music"), (3, "Home")])])
        var memory = DisplayMemory()
        memory.update(with: snapshot, displayName: { _ in "x" }, spaceName: { _ in "y" }, now: 1)
        let result = logical(snapshot, names, memory: memory, screenOrder: [])
        XCTAssertEqual(result.columns.map(\.title), ["Home", "Music", "Home"])
        XCTAssertEqual(result.columns.map(\.cells.count), [1, 1, 1])
        XCTAssertEqual(result.columns[0].state, .all)
    }

    func testOrderedDisplaysFollowsScreenOrder() {
        let (snapshot, _) = homeMusicTech
        XCTAssertEqual(LogicalSpaces.orderedDisplays(snapshot, screenOrder: ["BBBB-2222", "AAAA-1111"]).map(\.identifier),
                       ["BBBB-2222", "AAAA-1111"])
        XCTAssertEqual(LogicalSpaces.orderedDisplays(snapshot, screenOrder: ["bbbb-2222"]).map(\.identifier),
                       ["BBBB-2222", "AAAA-1111"], "unknown displays go last, matching ignores case")
        let (names, order) = (homeMusicTech.1, ["BBBB-2222", "AAAA-1111"])
        XCTAssertEqual(logical(snapshot, names, screenOrder: order).columns[0].cells.map(\.display),
                       ["BBBB-2222", "AAAA-1111"])
    }
}
