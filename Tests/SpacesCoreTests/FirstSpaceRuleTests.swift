import XCTest
@testable import SpacesCore

final class FirstSpaceRuleTests: XCTestCase {
    func testDefaults() {
        let rule = FirstSpaceRule(storedBuiltIn: nil, storedExternal: nil)
        XCTAssertEqual(rule, FirstSpaceRule.defaults)
        XCTAssertTrue(rule.isShown(identifier: "MAC", builtIn: true))
        XCTAssertFalse(rule.isShown(identifier: "EXT", builtIn: false))
    }

    func testStoredValues() {
        let rule = FirstSpaceRule(storedBuiltIn: NSNumber(value: false), storedExternal: NSNumber(value: true))
        XCTAssertFalse(rule.isShown(identifier: "MAC", builtIn: true))
        XCTAssertTrue(rule.isShown(identifier: "EXT", builtIn: false))
    }

    func testMalformedValuesFallBack() {
        XCTAssertEqual(FirstSpaceRule(storedBuiltIn: "no", storedExternal: "yes"), .defaults)
        XCTAssertEqual(FirstSpaceRule(storedBuiltIn: NSNumber(value: 3), storedExternal: [1]), .defaults)
    }

    func testCombinedListShowsFirstSpace() {
        let rule = FirstSpaceRule(storedBuiltIn: NSNumber(value: false), storedExternal: NSNumber(value: false))
        XCTAssertTrue(rule.isShown(identifier: Display.combinedIdentifier, builtIn: false))
    }
}
