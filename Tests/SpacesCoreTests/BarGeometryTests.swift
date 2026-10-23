import XCTest
@testable import SpacesCore

final class BarGeometryTests: XCTestCase {
    typealias Rect = BarGeometry.Rect
    let screen = Rect(x: 0, y: 0, width: 1440, height: 900)

    func testClampKeepsFrameInside() {
        XCTAssertEqual(BarGeometry.clamp(Rect(x: 100, y: 800, width: 300, height: 36), to: screen),
                       Rect(x: 100, y: 800, width: 300, height: 36))
        XCTAssertEqual(BarGeometry.clamp(Rect(x: -50, y: 880, width: 300, height: 36), to: screen),
                       Rect(x: 0, y: 864, width: 300, height: 36))
        XCTAssertEqual(BarGeometry.clamp(Rect(x: 1300, y: -10, width: 300, height: 36), to: screen),
                       Rect(x: 1140, y: 0, width: 300, height: 36))
    }

    func testClampWiderThanScreenKeepsLeftEdge() {
        let display = Rect(x: 1440, y: 0, width: 1000, height: 800)
        XCTAssertEqual(BarGeometry.clamp(Rect(x: 1500, y: 100, width: 1200, height: 36), to: display).x, 1440)
    }

    func testEdgesNearBorders() {
        func edges(_ x: Double, _ y: Double) -> ResizeEdges {
            BarGeometry.edges(x: x, y: y, width: 300, height: 36, zone: 5)
        }
        XCTAssertEqual(edges(150, 18), [])
        XCTAssertEqual(edges(2, 18), .left)
        XCTAssertEqual(edges(298, 18), .right)
        XCTAssertEqual(edges(150, 2), .bottom)
        XCTAssertEqual(edges(2, 34), [.left, .top])
        XCTAssertEqual(edges(298, 2), [.right, .bottom])
        XCTAssertEqual(edges(-1, 18), [])
        XCTAssertEqual(edges(150, 40), [])
    }

    func testResizedSizeFollowsDraggedEdges() {
        let start = Rect(x: 100, y: 500, width: 300, height: 36)
        func size(_ edges: ResizeEdges, _ dx: Double, _ dy: Double) -> [Double] {
            let s = BarGeometry.resizedSize(of: start, edges: edges, dx: dx, dy: dy)
            return [s.width, s.height]
        }
        XCTAssertEqual(size(.right, 50, 10), [350, 36])
        XCTAssertEqual(size(.left, 50, 10), [250, 36])
        XCTAssertEqual(size(.top, 50, 10), [300, 46])
        XCTAssertEqual(size([.left, .bottom], -20, -4), [320, 40])
        XCTAssertEqual(size(.right, -1000, 0), [BarGeometry.minBarWidth, 36])
    }

    func testResizedFrameKeepsOppositeEdgesStill() {
        let start = Rect(x: 100, y: 500, width: 300, height: 36)
        XCTAssertEqual(BarGeometry.resizedFrame(from: start, width: 400, height: 50, edges: .right),
                       Rect(x: 100, y: 486, width: 400, height: 50))
        XCTAssertEqual(BarGeometry.resizedFrame(from: start, width: 400, height: 50, edges: [.left, .top]),
                       Rect(x: 0, y: 500, width: 400, height: 50))
    }

    func testNaturalWidthsWhenTheyFit() {
        var askedForCompact = false
        let result = BarGeometry.tileWidths(natural: [80, 100], compact: { askedForCompact = true; return [50, 60] },
                                            start: 100, reserved: 20, gap: 4, minTile: 26, target: nil,
                                            screenWidth: 1440)
        XCTAssertEqual(result.widths, [80, 100])
        XCTAssertFalse(result.compact)
        XCTAssertFalse(askedForCompact)
    }

    func testCompactWidthsWhenTooWideForScreen() {
        let result = BarGeometry.tileWidths(natural: [500, 500], compact: { [50, 60] },
                                            start: 100, reserved: 20, gap: 4, minTile: 26, target: nil,
                                            screenWidth: 1000)
        XCTAssertEqual(result.widths, [50, 60])
        XCTAssertTrue(result.compact)
    }

    func testPickedWidthStretchesTiles() {
        // Room for tiles: 500 - 100 - 20 - 4 = 376 over a natural 188: factor 2.
        let result = BarGeometry.tileWidths(natural: [88, 100], compact: { [] },
                                            start: 100, reserved: 20, gap: 4, minTile: 26, target: 500,
                                            screenWidth: 1440)
        XCTAssertEqual(result.widths, [176, 200])
        XCTAssertFalse(result.compact)
    }

    func testPickedWidthShrinksTilesDownToMinimum() {
        let result = BarGeometry.tileWidths(natural: [100, 100], compact: { [] },
                                            start: 100, reserved: 20, gap: 4, minTile: 26, target: 150,
                                            screenWidth: 1440)
        XCTAssertEqual(result.widths, [26, 26])
        XCTAssertTrue(result.compact)
    }

    func testNoTiles() {
        let result = BarGeometry.tileWidths(natural: [], compact: { [] }, start: 100, reserved: 20, gap: 4,
                                            minTile: 26, target: 400, screenWidth: 1440)
        XCTAssertEqual(result.widths, [])
        XCTAssertFalse(result.compact)
    }
}
