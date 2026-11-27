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

    func testFullScreenAndHiddenFirstSpacesAreNotInColumns() {
        let (snapshot, names) = make([("AAAA-1111", 1, [(1, "Home"), (2, "Music")])], fullScreen: ["AAAA-1111": 9])
        let result = logical(snapshot, names)
        XCTAssertEqual(result.columns.flatMap(\.cells).map(\.space.managedID), [1, 2])
        XCTAssertEqual(result.fullScreen.map(\.space.managedID), [9])

        let (snapshot2, names2) = homeMusicTech
        let hidden = logical(snapshot2, names2, showsFirstSpace: { $0 != "BBBB-2222" })
        XCTAssertNil(hidden.columns[0].cell(on: "BBBB-2222"), "B's first Space is hidden")
        XCTAssertEqual(hidden.columns[1].cell(on: "BBBB-2222")?.space.managedID, 5)
    }

    // MARK: Unplugged displays

    /// B (whose first Space is `bSpaces[0]`) was unplugged: macOS moved its
    /// Spaces onto A, and the app remembers them as B's.
    private func unplugged(_ bSpaces: [(Int, String?)], bFullScreen: Int? = nil,
                           after aSpaces: [(Int, String?)], aCurrent: Int = 1, aFullScreen: Int? = nil)
        -> (Snapshot, Names, DisplayMemory) {
        let (before, _) = make([("AAAA-1111", 1, [(1, "Home")]), ("BBBB-2222", bSpaces[0].0, bSpaces)],
                               fullScreen: bFullScreen.map { ["BBBB-2222": $0] } ?? [:])
        var memory = DisplayMemory()
        memory.update(with: before, displayName: { $0.identifier }, spaceName: { "\($0.managedID)" }, now: 1)
        let (after, names) = make([("AAAA-1111", aCurrent, aSpaces)],
                                  fullScreen: aFullScreen.map { ["AAAA-1111": $0] } ?? [:])
        return (after, names, memory)
    }

    private var homeMusicUnplugged: (Snapshot, Names, DisplayMemory) {
        unplugged([(4, "Home"), (5, "Music")], after: [(1, "Home"), (2, "Music"), (4, "Home"), (5, "Music")])
    }

    func testUnpluggedDisplaysSpacesStayInTheirLogicalSpaces() {
        let (after, names, memory) = unplugged([(4, "Home"), (5, "Music")], bFullScreen: 8,
                                               after: [(1, "Home"), (2, "Music"), (4, "Home"), (5, "Music")],
                                               aFullScreen: 8)
        let result = logical(after, names, memory: memory)
        XCTAssertEqual(result.columns.map(\.title), ["Home", "Music"], "no columns of their own")
        let home = result.columns[0]
        XCTAssertEqual(home.cells.map(\.space.managedID), [1, 4])
        XCTAssertEqual(home.cells.map(\.display), ["AAAA-1111", "BBBB-2222"], "listed under the unplugged display")
        XCTAssertEqual(home.cells.map(\.onDisplay), ["AAAA-1111", "AAAA-1111"], "where macOS has it now")
        XCTAssertEqual(home.cells.map(\.isDisconnected), [false, true])
        XCTAssertEqual(home.cell(on: "BBBB-2222")?.space.managedID, 4)
        XCTAssertEqual(result.columns[1].cells.map(\.space.managedID), [2, 5])
        XCTAssertEqual(result.fullScreen.map(\.space.managedID), [8], "its full-screen Space is an FS tile where it is now")
        XCTAssertEqual(result.fullScreen.map(\.display), ["AAAA-1111"])
    }

    func testAClickSwitchesOnlyConnectedDisplaysOwnSpaces() {
        let (after, names, memory) = homeMusicUnplugged
        let home = logical(after, names, memory: memory).columns[0]
        XCTAssertEqual(home.switchCells.map(\.space.managedID), [1], "A shows its own Home, B's stays where it is")
        XCTAssertEqual(home.switchCell(on: "AAAA-1111")?.space.managedID, 1)
    }

    func testALogicalSpaceOnlyAnUnpluggedDisplayHasSwitchesItWhereItIs() {
        let (after, names, memory) = unplugged([(4, "Home"), (5, "Gaming")], after: [(1, "Home"), (4, "Home"), (5, "Gaming")])
        let result = logical(after, names, memory: memory)
        XCTAssertEqual(result.columns.map(\.title), ["Home", "Gaming"])
        let gaming = result.columns[1]
        XCTAssertEqual(gaming.number, 2)
        XCTAssertEqual(gaming.switchCells.map(\.space.managedID), [5])
        XCTAssertEqual(gaming.switchCell(on: "AAAA-1111")?.space.managedID, 5, "found by the display it's on now")
        XCTAssertNil(gaming.switchCell(on: "BBBB-2222"))
    }

    func testHighlightCountsAnUnpluggedDisplaysSpaceOnTheDisplayShowingIt() {
        let (after, names, memory) = unplugged([(4, "Home"), (5, "Music")],
                                               after: [(1, "Home"), (2, "Music"), (4, "Home"), (5, "Music")], aCurrent: 4)
        let result = logical(after, names, memory: memory)
        let home = result.columns[0]
        XCTAssertEqual(home.cells.map(\.isCurrent), [false, true])
        XCTAssertEqual(home.highlight(seenFrom: "AAAA-1111"), .here, "A shows B's Home")
        XCTAssertEqual(home.state, .all)
        XCTAssertEqual(result.columns[1].highlight(seenFrom: "AAAA-1111"), .none)
    }

    func testASpaceIsStrongOnlyWhenItIsTheOneOnScreen() {
        // A shows B's Home (4), not its own (1).
        let (after, names, memory) = unplugged([(4, "Home"), (5, "Music")],
                                               after: [(1, "Home"), (2, "Music"), (4, "Home"), (5, "Music")], aCurrent: 4)
        let home = logical(after, names, memory: memory).columns[0]
        XCTAssertEqual(home.cells.map { home.highlight(of: $0) }, [.elsewhere, .here])

        // Connected only: A shows Home (1), B shows Tech (6).
        let (snapshot, plain) = homeMusicTech
        let columns = logical(snapshot, plain).columns
        XCTAssertEqual(columns[0].cells.map { columns[0].highlight(of: $0) }, [.here, .elsewhere])
        XCTAssertEqual(columns[1].cells.map { columns[1].highlight(of: $0) }, [.none, .none])
        XCTAssertEqual(columns[2].cells.map { columns[2].highlight(of: $0) }, [.elsewhere, .here])
    }

    func testUnpluggedDisplaysFirstSpaceFollowsTheFirstSpaceRule() {
        let (after, names, memory) = homeMusicUnplugged
        let result = logical(after, names, memory: memory, showsFirstSpace: { $0 != "BBBB-2222" })
        XCTAssertEqual(result.columns[0].cells.map(\.space.managedID), [1], "B's first Space (4) is hidden")
        XCTAssertEqual(result.columns[1].cells.map(\.space.managedID), [2, 5])
    }

    func testKnowsWhenItHasAnUnpluggedDisplaysSpace() {
        let (after, names, memory) = unplugged([(4, "Home"), (5, "Gaming")],
                                               after: [(1, "Home"), (2, "Music"), (4, "Home"), (5, "Gaming")])
        let result = logical(after, names, memory: memory)
        XCTAssertEqual(result.columns.map(\.title), ["Home", "Music", "Gaming"])
        XCTAssertEqual(result.columns.map(\.includesUnplugged), [true, false, true])
    }

    func testRenamingALogicalSpaceRenamesTheUnpluggedDisplaysSpaceToo() {
        let (after, names, memory) = homeMusicUnplugged
        let home = logical(after, names, memory: memory).columns[0]
        XCTAssertEqual(Set(home.renameChange(to: "House", names: names).spaces.keys),
                       Set([1, 4].compactMap { after.locate(spaceID: UInt64($0))?.space.nameKey }))
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

    func testHighlightFollowsTheDisplayYouAreOn() {
        // A shows Home, B shows Music.
        let (snapshot, names) = make([("AAAA-1111", 1, [(1, "Home"), (2, "Music")]),
                                      ("BBBB-2222", 5, [(4, "Home"), (5, "Music")])])
        let columns = logical(snapshot, names).columns
        XCTAssertEqual(columns.map { $0.highlight(seenFrom: "AAAA-1111") }, [.here, .elsewhere])
        XCTAssertEqual(columns.map { $0.highlight(seenFrom: "bbbb-2222") }, [.elsewhere, .here])
    }

    func testHighlightAfterANormalSwitchIsTheSameEverywhere() {
        let (snapshot, names) = homeMusicTech  // A shows Home, B shows Tech
        let (both, names2) = make([("AAAA-1111", 2, [(1, "Home"), (2, "Music")]), ("BBBB-2222", 5, [(4, "Home"), (5, "Music")])])
        for display in ["AAAA-1111", "BBBB-2222"] {
            XCTAssertEqual(logical(both, names2).columns.map { $0.highlight(seenFrom: display) }, [.none, .here])
        }
        XCTAssertEqual(logical(snapshot, names).columns.map { $0.highlight(seenFrom: "AAAA-1111") },
                       [.here, .none, .elsewhere])
    }

    func testHighlightWhenADisplayHasNoSpaceForTheNumber() {
        // A has Home and Music, B only Home. After switching to Music, A shows Music and B stays on Home.
        let (snapshot, names) = make([("AAAA-1111", 2, [(1, "Home"), (2, "Music")]), ("BBBB-2222", 4, [(4, "Home")])])
        let columns = logical(snapshot, names).columns
        XCTAssertEqual(columns.map { $0.highlight(seenFrom: "AAAA-1111") }, [.elsewhere, .here])
        XCTAssertEqual(columns.map { $0.highlight(seenFrom: "BBBB-2222") }, [.here, .elsewhere])
    }

    func testHighlightOfASingleSpace() {
        XCTAssertEqual(LogicalSpaces.highlight(isCurrent: true, on: "AAAA-1111", seenFrom: "aaaa-1111"), .here)
        XCTAssertEqual(LogicalSpaces.highlight(isCurrent: true, on: "AAAA-1111", seenFrom: "BBBB-2222"), .elsewhere)
        XCTAssertEqual(LogicalSpaces.highlight(isCurrent: false, on: "AAAA-1111", seenFrom: "AAAA-1111"), .none)
        XCTAssertEqual(LogicalSpaces.highlight(isCurrent: true, on: "AAAA-1111", seenFrom: nil), .here,
                       "focus unknown: showing counts as here")
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

    // MARK: Tile displayed

    private func labelled(_ names: Names, _ labels: [String: String]) -> Names {
        var names = names
        for (key, label) in labels { names.setLabel(label, forLogicalKey: key, liveKeys: []) }
        return names
    }

    func testDisplayedShowsTheLabelOrTheNumber() {
        let (snapshot, plain) = homeMusicTech
        let names = labelled(plain, ["home": "H", "tech": "T"])
        let result = logical(snapshot, names)
        XCTAssertEqual(result.columns.map { $0.displayed(in: names) }, ["H", "2", "T"])
        XCTAssertEqual(result.columns.map(\.number), [1, 2, 3], "the numbering doesn't change")
    }

    func testLabelBelongsToTheNameIgnoringCase() {
        let (snapshot, plain) = make([("AAAA-1111", 1, [(1, "HOME")]), ("BBBB-2222", 4, [(4, "Home")])])
        let names = labelled(plain, [LogicalSpaces.groupingKey("home"): "H"])
        XCTAssertEqual(logical(snapshot, names).columns[0].displayed(in: names), "H")
    }

    func testDuplicateColumnHasNoLabel() {
        let (snapshot, plain) = make([("AAAA-1111", 1, [(1, "Home"), (2, "Home")])])
        let names = labelled(plain, ["home": "H"])
        let result = logical(snapshot, names)
        XCTAssertEqual(result.columns[0].labelKey, "home")
        XCTAssertNil(result.columns[1].labelKey)
        XCTAssertEqual(result.columns.map { $0.displayed(in: names) }, ["H", "2"])
    }

    func testRenameMovesTheLabelToTheNewName() {
        let (snapshot, plain) = homeMusicTech
        let names = labelled(plain, ["home": "H"])
        let home = logical(snapshot, names).columns[0]
        let change = home.renameChange(to: " House ", names: names)
        XCTAssertEqual(change.spaces, Dictionary(uniqueKeysWithValues: home.cells.map { ($0.space.nameKey, " House ") }))
        XCTAssertEqual(change.labels, ["house": "H", "home": ""])
    }

    func testRenameOntoANameWithALabelKeepsThatLabel() {
        let (snapshot, plain) = homeMusicTech
        let names = labelled(plain, ["home": "H", "music": "M"])
        let home = logical(snapshot, names).columns[0]
        XCTAssertEqual(home.renameChange(to: "music", names: names).labels, [:])
    }

    func testRenameMovesNoLabelWhenThereIsNothingToMove() {
        let (snapshot, plain) = homeMusicTech
        let names = labelled(plain, ["home": "H"])
        let result = logical(snapshot, names)
        XCTAssertEqual(result.columns[1].renameChange(to: "Songs", names: names).labels, [:], "Music has no label")
        XCTAssertEqual(result.columns[0].renameChange(to: "HOME", names: names).labels, [:], "same name")
        XCTAssertEqual(result.columns[0].renameChange(to: "  ", names: names).labels, [:], "cleared: stays stored")
    }
}
