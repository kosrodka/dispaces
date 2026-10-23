import XCTest
@testable import SpacesCore

final class BarLayoutTests: XCTestCase {
    func testRoundTrip() {
        var layout = BarLayout()
        layout.setOffset(fromLeft: 120, fromTop: 8, for: "display:A")
        layout.setCollapsed(true, for: "display:B")
        let restored = BarLayout(storedOffsets: layout.storedOffsets, storedCollapsed: layout.storedCollapsed)
        XCTAssertEqual(restored, layout)
        XCTAssertEqual(restored.offsets["display:A"], BarLayout.Offset(fromLeft: 120, fromTop: 8))
        XCTAssertTrue(restored.isCollapsed("display:B"))
        XCTAssertFalse(restored.isCollapsed("display:A"))
    }

    func testUncollapse() {
        var layout = BarLayout()
        layout.setCollapsed(true, for: "k")
        layout.setCollapsed(false, for: "k")
        XCTAssertFalse(layout.isCollapsed("k"))
    }

    func testRejectsBadStoredValues() {
        let offsets: [String: Any] = [
            "ok": [NSNumber(value: 10), NSNumber(value: 20)],
            "nan": [Double.nan, 1.0],
            "inf": [1.0, Double.infinity],
            "huge": [1e9, 1.0],
            "short": [1.0],
            "text": "garbage",
            "": [1.0, 2.0],
        ]
        let layout = BarLayout(storedOffsets: offsets, storedCollapsed: [1, "", "x", String(repeating: "k", count: 500)] as [Any])
        XCTAssertEqual(Array(layout.offsets.keys), ["ok"])
        XCTAssertEqual(layout.collapsed, ["x"])
        XCTAssertEqual(BarLayout(storedOffsets: 5, storedCollapsed: "x"), BarLayout())
    }

    func testRejectsBadOffsets() {
        var layout = BarLayout()
        layout.setOffset(fromLeft: .nan, fromTop: 0, for: "a")
        layout.setOffset(fromLeft: 0, fromTop: 1e12, for: "a")
        XCTAssertTrue(layout.offsets.isEmpty)
    }

    func testCaps() {
        var stored: [String: Any] = [:]
        for i in 0..<1_000 { stored["k\(i)"] = [1.0, 2.0] }
        var layout = BarLayout(storedOffsets: stored, storedCollapsed: nil)
        XCTAssertEqual(layout.offsets.count, BarLayout.maxEntries)
        layout.setOffset(fromLeft: 1, fromTop: 1, for: "new")
        XCTAssertNil(layout.offsets["new"])
    }

    func testSizesAndLocksRoundTrip() {
        var layout = BarLayout()
        layout.setSize(BarLayout.Size(width: 500, height: 48), for: "bar:A")
        layout.setLocked(true, for: "bar:A")
        let restored = BarLayout(storedOffsets: nil, storedSizes: layout.storedSizes,
                                 storedCollapsed: nil, storedLocked: layout.storedLocked)
        XCTAssertEqual(restored, layout)
        XCTAssertEqual(restored.sizes["bar:A"], BarLayout.Size(width: 500, height: 48))
        XCTAssertTrue(restored.isLocked("bar:A"))
        XCTAssertFalse(restored.isLocked("bar:B"))
    }

    func testLocksAreIndependent() {
        var layout = BarLayout()
        layout.setLocked(true, for: "bar:A")
        layout.setLocked(true, for: "bar:B")
        layout.setLocked(false, for: "bar:A")
        XCTAssertFalse(layout.isLocked("bar:A"))
        XCTAssertTrue(layout.isLocked("bar:B"))
    }

    func testSizeValidation() {
        var layout = BarLayout()
        layout.setSize(BarLayout.Size(width: 300, height: 500), for: "tall")
        layout.setSize(BarLayout.Size(width: 300, height: 1), for: "flat")
        layout.setSize(BarLayout.Size(width: .infinity, height: 36), for: "inf")
        layout.setSize(BarLayout.Size(width: -5, height: 36), for: "neg")
        XCTAssertEqual(layout.sizes["tall"]?.height, BarLayout.heights.upperBound)
        XCTAssertEqual(layout.sizes["flat"]?.height, BarLayout.heights.lowerBound)
        XCTAssertNil(layout.sizes["inf"])
        XCTAssertNil(layout.sizes["neg"])
        layout.setSize(nil, for: "tall")
        XCTAssertNil(layout.sizes["tall"])

        let stored: [String: Any] = ["ok": [200.0, 40.0], "nan": [Double.nan, 40.0], "text": "x"]
        let parsed = BarLayout(storedOffsets: nil, storedSizes: stored, storedCollapsed: nil, storedLocked: "garbage")
        XCTAssertEqual(Array(parsed.sizes.keys), ["ok"])
        XCTAssertTrue(parsed.locked.isEmpty)
    }
}
