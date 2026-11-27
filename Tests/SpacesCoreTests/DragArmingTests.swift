import XCTest
@testable import SpacesCore

final class DragArmingTests: XCTestCase {
    func testArmsAtOnceAndFiresAfterDwellOnce() {
        var arming = DragArming()
        XCTAssertNil(arming.update(holding: true, target: .space(2), now: 10))
        XCTAssertEqual(arming.armed, .space(2))
        XCTAssertNil(arming.update(holding: true, target: .space(2), now: 10.2))
        XCTAssertEqual(arming.update(holding: true, target: .space(2), now: 10.5), .space(2))
        XCTAssertNil(arming.update(holding: true, target: .space(2), now: 11), "fires once per visit")
        XCTAssertEqual(arming.armed, .space(2))
    }

    func testMovingToAnotherTileRestartsTheDwell() {
        var arming = DragArming()
        _ = arming.update(holding: true, target: .space(2), now: 0)
        XCTAssertNil(arming.update(holding: true, target: .logical("home"), now: 0.3))
        XCTAssertEqual(arming.armed, .logical("home"))
        XCTAssertNil(arming.update(holding: true, target: .logical("home"), now: 0.6))
        XCTAssertEqual(arming.update(holding: true, target: .logical("home"), now: 0.75), .logical("home"))
    }

    func testLettingGoOrLeavingDisarms() {
        var arming = DragArming()
        _ = arming.update(holding: true, target: .space(2), now: 0)
        XCTAssertNil(arming.update(holding: false, target: .space(2), now: 0.5))
        XCTAssertNil(arming.armed)

        _ = arming.update(holding: true, target: .space(2), now: 1)
        XCTAssertNil(arming.update(holding: true, target: nil, now: 1.2))
        XCTAssertNil(arming.armed)
        XCTAssertNil(arming.update(holding: true, target: .space(2), now: 1.3), "dwell starts again")
        XCTAssertEqual(arming.update(holding: true, target: .space(2), now: 1.75), .space(2))
    }
}
