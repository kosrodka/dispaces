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
}
