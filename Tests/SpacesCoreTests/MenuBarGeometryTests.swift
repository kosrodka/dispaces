import XCTest
@testable import SpacesCore

final class MenuBarGeometryTests: XCTestCase {
    private let metrics = MenuBarGeometry.Metrics(tile: 16, gap: 3, groupGap: 9, subgroupGap: 6, inset: 3)

    func testMetricsFollowTheMenuBarHeight() {
        XCTAssertEqual(MenuBarGeometry.Metrics.forMenuBar(thickness: 22).tile, 16)
        XCTAssertEqual(MenuBarGeometry.Metrics.forMenuBar(thickness: 24).tile, 18)
        XCTAssertEqual(MenuBarGeometry.Metrics.forMenuBar(thickness: 0).tile, 12)
        XCTAssertEqual(MenuBarGeometry.Metrics.forMenuBar(thickness: 100).tile, 20)
    }

    func testOneDisplay() {
        let layout = MenuBarGeometry.layout([.init(count: 3, spacing: .group)], warning: false, metrics: metrics)
        XCTAssertEqual(layout.tileXs, [3, 22, 41])
        XCTAssertNil(layout.warningX)
        XCTAssertEqual(layout.width, 60) // 3 + 3 × 16 + 2 × 3 + 3
    }

    func testDisplaysAndUnpluggedGroupsGetWiderGaps() {
        let layout = MenuBarGeometry.layout([
            .init(count: 2, spacing: .group),
            .init(count: 1, spacing: .subgroup),
            .init(count: 1, spacing: .group),
        ], warning: false, metrics: metrics)
        // 3, 22 | +16+6 = 44 | +16+9 = 69
        XCTAssertEqual(layout.tileXs, [3, 22, 44, 69])
        XCTAssertEqual(layout.width, 88) // 69 + 16 + 3
    }

    func testEmptyRunsTakeNoRoom() {
        let layout = MenuBarGeometry.layout([
            .init(count: 0, spacing: .group),
            .init(count: 2, spacing: .group),
            .init(count: 0, spacing: .subgroup),
        ], warning: false, metrics: metrics)
        XCTAssertEqual(layout.tileXs, [3, 22])
    }

    func testUnpluggedGroupAfterAnEmptyDisplayStillGetsTheDisplayGap() {
        let layout = MenuBarGeometry.layout([
            .init(count: 1, spacing: .group),
            .init(count: 0, spacing: .group),
            .init(count: 1, spacing: .subgroup),
        ], warning: false, metrics: metrics)
        XCTAssertEqual(layout.tileXs, [3, 28]) // 3 + 16 + 9
    }

    func testWarningComesLast() {
        let layout = MenuBarGeometry.layout([.init(count: 1, spacing: .group)], warning: true, metrics: metrics)
        XCTAssertEqual(layout.warningX, 28) // 3 + 16 + 9
        XCTAssertEqual(layout.width, 47) // 28 + 16 + 3
    }

    func testWarningAlone() {
        let layout = MenuBarGeometry.layout([], warning: true, metrics: metrics)
        XCTAssertEqual(layout.tileXs, [])
        XCTAssertEqual(layout.warningX, 3)
        XCTAssertEqual(layout.width, 22)
    }

    func testNothingStillKeepsOneTileOfRoom() {
        let layout = MenuBarGeometry.layout([], warning: false, metrics: metrics)
        XCTAssertEqual(layout.width, 22)
    }

    func testHits() {
        let layout = MenuBarGeometry.layout([
            .init(count: 2, spacing: .group),
            .init(count: 1, spacing: .group),
        ], warning: true, metrics: metrics)
        // Tiles at 3, 22 | 47; warning at 72.
        XCTAssertEqual(MenuBarGeometry.hit(x: 10, in: layout, metrics: metrics), .tile(0))
        XCTAssertEqual(MenuBarGeometry.hit(x: 20, in: layout, metrics: metrics), .tile(0))
        XCTAssertEqual(MenuBarGeometry.hit(x: 21, in: layout, metrics: metrics), .tile(1))
        XCTAssertEqual(MenuBarGeometry.hit(x: 42, in: layout, metrics: metrics), .gap)
        XCTAssertEqual(MenuBarGeometry.hit(x: 50, in: layout, metrics: metrics), .tile(2))
        XCTAssertEqual(MenuBarGeometry.hit(x: 80, in: layout, metrics: metrics), .warning)
        XCTAssertEqual(MenuBarGeometry.hit(x: 0.5, in: layout, metrics: metrics), .gap)
        XCTAssertEqual(MenuBarGeometry.hit(x: 200, in: layout, metrics: metrics), .gap)
    }

    // MARK: What a click means

    func testOptionClickSwitchesOnlyTheClickedDisplay() {
        let option = KeyCombo.option, control = KeyCombo.control
        XCTAssertTrue(MenuBarGeometry.thisDisplayOnly(eventModifiers: option, liveModifiers: option))
        // macOS drops Option from a status item's click event; the keys held at that moment still count.
        XCTAssertTrue(MenuBarGeometry.thisDisplayOnly(eventModifiers: 0, liveModifiers: option))
        XCTAssertTrue(MenuBarGeometry.thisDisplayOnly(eventModifiers: option, liveModifiers: 0))
        XCTAssertFalse(MenuBarGeometry.thisDisplayOnly(eventModifiers: 0, liveModifiers: 0))
        XCTAssertFalse(MenuBarGeometry.thisDisplayOnly(eventModifiers: 0, liveModifiers: option | control),
                       "Control opens the menu instead")
        XCTAssertFalse(MenuBarGeometry.thisDisplayOnly(eventModifiers: control, liveModifiers: option))
    }

    // MARK: Apps column placement (screen coordinates, y up)

    func testAppsColumnGoesUnderTheTileWhenItFits() {
        let place = MenuBarGeometry.appsColumn(height: 300, tileBottom: 950, tileTop: 980,
                                               visibleBottom: 56, visibleTop: 949, gap: 4)
        XCTAssertEqual(place.y, 646)
        XCTAssertEqual(place.height, 300)
    }

    func testAppsColumnIsCutToTheRoomUnderAMenuBarTileAndScrolls() {
        let place = MenuBarGeometry.appsColumn(height: 2000, tileBottom: 950, tileTop: 980,
                                               visibleBottom: 56, visibleTop: 949, gap: 4)
        XCTAssertEqual(place.y, 56)
        XCTAssertEqual(place.height, 890)
    }

    func testAppsColumnGoesOverALowTileWhenOnlyThereItFits() {
        let place = MenuBarGeometry.appsColumn(height: 300, tileBottom: 200, tileTop: 226,
                                               visibleBottom: 56, visibleTop: 949, gap: 4)
        XCTAssertEqual(place.y, 230)
        XCTAssertEqual(place.height, 300)
    }

    func testAppsColumnTakesTheSideWithMoreRoomWhenItFitsNeither() {
        let place = MenuBarGeometry.appsColumn(height: 1000, tileBottom: 400, tileTop: 426,
                                               visibleBottom: 56, visibleTop: 949, gap: 4)
        XCTAssertEqual(place.y, 430)
        XCTAssertEqual(place.height, 519)
    }
}
