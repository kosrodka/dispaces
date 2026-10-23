import XCTest
@testable import SpacesCore

final class DragArmingTests: XCTestCase {
    func testArmsAtOnceAndFiresAfterDwellOnce() {
        var arming = DragArming()
        XCTAssertNil(arming.update(holding: true, spaceUnderPointer: 2, now: 10))
        XCTAssertEqual(arming.armedSpaceID, 2)
        XCTAssertNil(arming.update(holding: true, spaceUnderPointer: 2, now: 10.2))
        XCTAssertEqual(arming.update(holding: true, spaceUnderPointer: 2, now: 10.5), 2)
        XCTAssertNil(arming.update(holding: true, spaceUnderPointer: 2, now: 11), "fires once per visit")
        XCTAssertEqual(arming.armedSpaceID, 2)
    }

    func testMovingToAnotherTileRestartsTheDwell() {
        var arming = DragArming()
        _ = arming.update(holding: true, spaceUnderPointer: 2, now: 0)
        XCTAssertNil(arming.update(holding: true, spaceUnderPointer: 3, now: 0.3))
        XCTAssertEqual(arming.armedSpaceID, 3)
        XCTAssertNil(arming.update(holding: true, spaceUnderPointer: 3, now: 0.6))
        XCTAssertEqual(arming.update(holding: true, spaceUnderPointer: 3, now: 0.75), 3)
    }

    func testLettingGoOrLeavingDisarms() {
        var arming = DragArming()
        _ = arming.update(holding: true, spaceUnderPointer: 2, now: 0)
        XCTAssertNil(arming.update(holding: false, spaceUnderPointer: 2, now: 0.5))
        XCTAssertNil(arming.armedSpaceID)

        _ = arming.update(holding: true, spaceUnderPointer: 2, now: 1)
        XCTAssertNil(arming.update(holding: true, spaceUnderPointer: nil, now: 1.2))
        XCTAssertNil(arming.armedSpaceID)
        XCTAssertNil(arming.update(holding: true, spaceUnderPointer: 2, now: 1.3), "dwell starts again")
        XCTAssertEqual(arming.update(holding: true, spaceUnderPointer: 2, now: 1.75), 2)
    }
}
