import XCTest
@testable import SpacesCore

final class NamesTests: XCTestCase {
    func testSanitizeBasics() {
        XCTAssertEqual(NameSanitizer.sanitize("  HOME  "), "HOME")
        XCTAssertEqual(NameSanitizer.sanitize("a\n\tb"), "a b")
        XCTAssertEqual(NameSanitizer.sanitize("a\u{0}\u{7}b"), "ab")
        XCTAssertEqual(NameSanitizer.sanitize(""), "")
    }

    func testSanitizeRemovesDirectionOverrides() {
        XCTAssertEqual(NameSanitizer.sanitize("evil\u{202E}txt.exe"), "eviltxt.exe")
        XCTAssertEqual(NameSanitizer.sanitize("\u{2066}x\u{2069}\u{200B}"), "x")
    }

    func testSanitizeLength() {
        XCTAssertEqual(NameSanitizer.sanitize(String(repeating: "x", count: 200)).count, NameSanitizer.maxLength)
        // Grapheme-safe: flags and combined characters are never split.
        let flags = String(repeating: "🇵🇱", count: 30)
        let cut = NameSanitizer.sanitize(flags)
        XCTAssertEqual(cut.count, NameSanitizer.maxLength)
        XCTAssertTrue(cut.allSatisfy { $0 == "🇵🇱" })
    }

    func testFormatStringsAreJustText() {
        XCTAssertEqual(NameSanitizer.sanitize("%@%n%s"), "%@%n%s")
    }

    func testDefaultNames() {
        let snap = Fixtures.twoDisplaysSnapshot
        let names = Names()
        XCTAssertEqual(names.name(for: snap.displays[1].spaces[1]), "Desktop 5")
        XCTAssertEqual(names.name(for: snap.displays[0].spaces[3]), "Safari")
        XCTAssertEqual(names.name(for: snap.displays[0], defaultName: "Studio Display"), "Studio Display")
    }

    func testSetAndClear() {
        let snap = Fixtures.twoDisplaysSnapshot
        let space = snap.displays[0].spaces[0]
        var names = Names()
        names.setName("  MUSIC ", for: space, liveKeys: [])
        XCTAssertEqual(names.name(for: space), "MUSIC")
        names.setName("   ", for: space, liveKeys: [])
        XCTAssertEqual(names.name(for: space), "Desktop 1")
        names.setName("Studio", for: snap.displays[0], liveKeys: [])
        XCTAssertEqual(names.name(for: snap.displays[0], defaultName: "x"), "Studio")
    }

    func testSetNameByKeyAndClear() {
        var names = Names()
        names.setName(" Home ", forSpaceKey: "U-1", liveKeys: [])
        XCTAssertEqual(names.storedName(forSpaceKey: "U-1"), "Home")
        names.setName("", forSpaceKey: "U-1", liveKeys: [])
        XCTAssertNil(names.storedName(forSpaceKey: "U-1"))
    }

    func testValidatesStoredValues() {
        let stored: [String: Any] = ["space:ok": "HOME", "space:num": 5, "space:long": String(repeating: "y", count: 99),
                                     "": "empty-key", "space:blank": "  "]
        let names = Names(storedSpaces: stored, storedDisplays: "garbage")
        XCTAssertEqual(names.spaces["space:ok"], "HOME")
        XCTAssertNil(names.spaces["space:num"])
        XCTAssertEqual(names.spaces["space:long"]?.count, NameSanitizer.maxLength)
        XCTAssertNil(names.spaces[""])
        XCTAssertNil(names.spaces["space:blank"])
        XCTAssertTrue(names.displays.isEmpty)
    }

    func testCapsStoredEntries() {
        var big: [String: Any] = [:]
        for i in 0..<10_000 { big["space:\(i)"] = "n\(i)" }
        let names = Names(storedSpaces: big, storedDisplays: nil)
        XCTAssertEqual(names.spaces.count, Names.maxEntries)
    }

    func testCapDropsStaleNamesFirst() {
        var stored: [String: Any] = [:]
        for i in 0..<Names.maxEntries { stored["space:old\(i)"] = "n" }
        var names = Names(storedSpaces: stored, storedDisplays: nil)
        let space = Fixtures.twoDisplaysSnapshot.displays[0].spaces[1]
        names.setName("NEW", for: space, liveKeys: ["space:old0", space.nameKey])
        XCTAssertEqual(names.name(for: space), "NEW")
        XCTAssertEqual(names.spaces["space:old0"], "n")
        XCTAssertLessThanOrEqual(names.spaces.count, Names.maxEntries)
    }

    // MARK: Tile labels (Tile displayed)

    func testTileLabelSanitize() {
        XCTAssertEqual(TileLabel.sanitize(" h "), "h")
        XCTAssertEqual(TileLabel.sanitize("Home"), "Ho")
        XCTAssertEqual(TileLabel.sanitize("10"), "10")
        XCTAssertEqual(TileLabel.sanitize("🇵🇱🇵🇱🇵🇱"), "🇵🇱🇵🇱", "never splits a character")
        XCTAssertEqual(TileLabel.sanitize("A\u{202E}B"), "AB")
        XCTAssertEqual(TileLabel.sanitize("A B"), "A", "a space left at the end is trimmed")
        XCTAssertEqual(TileLabel.sanitize("\n\t"), "")
    }

    func testSetAndClearLabel() {
        var names = Names()
        names.setLabel(" H ", forLogicalKey: "home", liveKeys: [])
        XCTAssertEqual(names.label(forLogicalKey: "home"), "H")
        names.setLabel("", forLogicalKey: "home", liveKeys: [])
        XCTAssertNil(names.label(forLogicalKey: "home"))
    }

    func testValidatesStoredLabels() {
        let stored: [String: Any] = ["home": "H", "music": "Music", "tech": 7, "blank": " ", "": "E"]
        let names = Names(storedSpaces: nil, storedDisplays: nil, storedLabels: stored)
        XCTAssertEqual(names.labels, ["home": "H", "music": "Mu"])
        XCTAssertTrue(Names(storedSpaces: nil, storedDisplays: nil, storedLabels: "garbage").labels.isEmpty)
    }

    func testApplyStoresNamesAndLabelsAndReturnsTheInverse() {
        let before = Names(storedSpaces: ["U-1": "Home"], storedDisplays: nil, storedLabels: ["home": "H"])
        var names = before
        let change = NameChange(spaces: ["U-1": "House", "U-2": "House"], labels: ["house": "H", "home": ""])
        let inverse = names.apply(change, liveSpaceKeys: [], liveLabelKeys: [])
        XCTAssertEqual(names.storedName(forSpaceKey: "U-1"), "House")
        XCTAssertEqual(names.storedName(forSpaceKey: "U-2"), "House")
        XCTAssertEqual(names.label(forLogicalKey: "house"), "H")
        XCTAssertNil(names.label(forLogicalKey: "home"))
        XCTAssertEqual(inverse, NameChange(spaces: ["U-1": "Home", "U-2": ""], labels: ["house": "", "home": "H"]))
        names.apply(inverse, liveSpaceKeys: [], liveLabelKeys: [])
        XCTAssertEqual(names, before)
    }
}
