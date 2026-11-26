import XCTest
@testable import SpacesCore

final class SwitchPlannerTests: XCTestCase {
    let snap = Fixtures.twoDisplaysSnapshot

    func hotkeys(_ entries: [String: Any]) -> HotkeyTable { HotkeyParser.parse(entries) }

    func entry(enabled: Bool, key: Int, mods: Int) -> [String: Any] {
        ["enabled": NSNumber(value: enabled), "value": ["parameters": [NSNumber(value: 65535), NSNumber(value: key), NSNumber(value: mods)], "type": "standard"] as [String: Any]]
    }

    func testAlreadyThere() {
        XCTAssertEqual(SwitchPlanner.plan(to: 3, in: snap, hotkeys: .defaults, pointerDisplay: nil), .alreadyThere)
    }

    func testUsesUserHotkey() {
        let table = hotkeys(["119": entry(enabled: true, key: 19, mods: 262144)])
        XCTAssertEqual(SwitchPlanner.plan(to: 2, in: snap, hotkeys: table, pointerDisplay: nil),
                       .pressHotkey(id: 119, combo: KeyCombo(keyCode: 19, modifiers: KeyCombo.control), desktop: 2))
    }

    func testDesktopOnSecondDisplayUsesGlobalNumber() {
        let table = hotkeys(["121": entry(enabled: true, key: 21, mods: 262144)])
        XCTAssertEqual(SwitchPlanner.plan(to: 4, in: snap, hotkeys: table, pointerDisplay: nil),
                       .pressHotkey(id: 121, combo: KeyCombo(keyCode: 21, modifiers: KeyCombo.control), desktop: 4))
    }

    func testUnknownSettingFallsBackToAppleDefaultKey() {
        XCTAssertEqual(SwitchPlanner.plan(to: 1, in: snap, hotkeys: .defaults, pointerDisplay: nil),
                       .pressHotkey(id: 118, combo: KeyCombo(keyCode: 18, modifiers: KeyCombo.control), desktop: 1))
    }

    func testShortcutOffElsewhereReportsShortcut() {
        let table = hotkeys(["118": entry(enabled: false, key: 18, mods: 262144)])
        XCTAssertEqual(SwitchPlanner.plan(to: 1, in: snap, hotkeys: table, pointerDisplay: "BBBB-2222"),
                       .unavailable(.shortcutOff(desktop: 1)))
    }

    func testShortcutOffOnPointerDisplayStepsInstead() {
        let table = hotkeys(["118": entry(enabled: false, key: 18, mods: 262144)])
        // Current is index 2 (space 3); target space 1 is index 0 → two steps left.
        XCTAssertEqual(SwitchPlanner.plan(to: 1, in: snap, hotkeys: table, pointerDisplay: "AAAA-1111"),
                       .step(id: 79, combo: KeyCombo(keyCode: 123, modifiers: KeyCombo.control | KeyCombo.function), count: 2))
    }

    func testFullScreenNeedsPointerDisplay() {
        XCTAssertEqual(SwitchPlanner.plan(to: 9, in: snap, hotkeys: .defaults, pointerDisplay: "BBBB-2222"),
                       .unavailable(.notOnPointerDisplay))
        XCTAssertEqual(SwitchPlanner.plan(to: 9, in: snap, hotkeys: .defaults, pointerDisplay: "AAAA-1111"),
                       .step(id: 81, combo: KeyCombo(keyCode: 124, modifiers: KeyCombo.control | KeyCombo.function), count: 1))
    }

    func testStepShortcutOff() {
        let table = hotkeys(["81": entry(enabled: false, key: 124, mods: 8650752)])
        XCTAssertEqual(SwitchPlanner.plan(to: 9, in: snap, hotkeys: table, pointerDisplay: "AAAA-1111"),
                       .unavailable(.stepShortcutOff))
    }

    func testUnknownSpace() {
        XCTAssertEqual(SwitchPlanner.plan(to: 12345, in: snap, hotkeys: .defaults, pointerDisplay: nil),
                       .unavailable(.unknownSpace))
    }

    func testDesktopBeyond16HasNoShortcut() {
        let spaces = (1...20).map { Fixtures.space($0) }
        let big = SnapshotParser.parse([Fixtures.display("A", current: 1, spaces: spaces)])
        XCTAssertEqual(SwitchPlanner.plan(to: 17, in: big, hotkeys: .defaults, pointerDisplay: "B"),
                       .unavailable(.noShortcut(desktop: 17)))
        if case .step(_, _, let count) = SwitchPlanner.plan(to: 17, in: big, hotkeys: .defaults, pointerDisplay: "A") {
            XCTAssertEqual(count, 16)
        } else {
            XCTFail("expected stepping on the pointer display")
        }
    }

    // MARK: Logical spaces

    private func cell(_ id: UInt64, current: Bool = false) -> LogicalSpaces.Cell {
        let found = snap.locate(spaceID: id)!
        return LogicalSpaces.Cell(display: found.display.identifier, space: found.space, isCurrent: current)
    }

    func testOrderPutsPointerDisplayLastAndSkipsCurrent() {
        let cells = [cell(2), cell(4), cell(5, current: true)]
        XCTAssertEqual(SwitchPlanner.order(cells, pointerDisplay: "aaaa-1111").map(\.space.managedID), [4, 2])
        XCTAssertEqual(SwitchPlanner.order([cell(3, current: true), cell(4)], pointerDisplay: "AAAA-1111")
                        .map(\.space.managedID), [4], "nothing to press on a display already there")
    }

    func testOrderWithoutPointerKeepsDisplayOrder() {
        XCTAssertEqual(SwitchPlanner.order([cell(2), cell(4)], pointerDisplay: nil).map(\.space.managedID), [2, 4])
        XCTAssertEqual(SwitchPlanner.order([cell(2), cell(4)], pointerDisplay: "CCCC").map(\.space.managedID), [2, 4])
    }

    func testRefocusPressesOwnShortcutWhenFocusIsElsewhere() {
        // A shows 3, B shows 5, and B has the focus.
        let focusedB = SnapshotParser.parse(Fixtures.twoDisplays, activeSpaceID: 5)
        let table = hotkeys(["120": entry(enabled: true, key: 20, mods: 262144)])
        XCTAssertEqual(SwitchPlanner.refocusPlan(on: 3, in: focusedB, hotkeys: table),
                       .pressHotkey(id: 120, combo: KeyCombo(keyCode: 20, modifiers: KeyCombo.control), desktop: 3))
    }

    func testRefocusDoesNothingWhenNotNeededOrNotPossible() {
        let focusedA = SnapshotParser.parse(Fixtures.twoDisplays, activeSpaceID: 3)
        XCTAssertNil(SwitchPlanner.refocusPlan(on: 3, in: focusedA, hotkeys: .defaults), "already focused")
        let focusedB = SnapshotParser.parse(Fixtures.twoDisplays, activeSpaceID: 5)
        XCTAssertNil(SwitchPlanner.refocusPlan(on: 2, in: focusedB, hotkeys: .defaults), "not shown on its display")
        XCTAssertNil(SwitchPlanner.refocusPlan(on: 3, in: snap, hotkeys: .defaults), "focus unknown")
        let off = hotkeys(["120": entry(enabled: false, key: 20, mods: 262144)])
        XCTAssertNil(SwitchPlanner.refocusPlan(on: 3, in: focusedB, hotkeys: off), "shortcut off")
    }

    func testFocusStaysOnClickedDisplayEvenWithoutACell() {
        // A logical space with a Space only on B, clicked on A's menu bar: focus goes back to A's current Space.
        let column = LogicalSpaces(snapshot: snap, memory: DisplayMemory(),
                                   names: Names(storedSpaces: [snap.locate(spaceID: 4)!.space.nameKey: "Music"],
                                                storedDisplays: nil),
                                   screenOrder: [], showsFirstSpace: { _ in true })
            .columns.first { $0.title == "Music" }!
        XCTAssertEqual(SwitchPlanner.focusTarget(column, pointerDisplay: snap.displays[0]), 3)
        XCTAssertEqual(SwitchPlanner.focusTarget(column, pointerDisplay: snap.displays[1]), 4, "the clicked display's cell")
        XCTAssertNil(SwitchPlanner.focusTarget(column, pointerDisplay: nil))
    }

    func testNoSpaceMessage() {
        XCTAssertEqual(SwitchPlanner.noSpaceMessage(display: "LC27G7XT", title: "Music"),
                       "LC27G7XT has no Space named \u{201C}Music\u{201D}.")
    }

    // MARK: Security: only allow-listed shortcuts and modifier bits

    func testParserIgnoresNonSpaceShortcuts() {
        let table = hotkeys(["64": entry(enabled: true, key: 49, mods: 1048576), // Spotlight
                             "118": entry(enabled: true, key: 18, mods: 262144)])
        XCTAssertEqual(table.settings.keys.sorted(), [118])
        XCTAssertFalse(HotkeyID.isAllowed(64))
        XCTAssertTrue(HotkeyID.isAllowed(133))
        XCTAssertFalse(HotkeyID.isAllowed(134))
    }

    func testParserStripsUnknownModifierBitsAndBadKeyCodes() {
        let table = hotkeys(["118": entry(enabled: true, key: 18, mods: 262144 | 0x1),
                             "119": entry(enabled: true, key: 5000, mods: 262144)])
        XCTAssertEqual(table.setting(for: 118).combo, KeyCombo(keyCode: 18, modifiers: KeyCombo.control))
        XCTAssertNil(table.setting(for: 119).combo)
    }

    func testParserHandlesGarbage() {
        XCTAssertEqual(HotkeyParser.parse("x"), .defaults)
        let table = hotkeys(["118": "x", "abc": 1, "119": ["value": ["parameters": [1]]]])
        XCTAssertNil(table.setting(for: 119).combo)
    }

    func testMessagesNameTheFix() {
        XCTAssertTrue(SwitchPlanner.message(for: .shortcutOff(desktop: 4)).contains("Switch to Desktop 4"))
    }

    /// The wording users see is unchanged since the messages moved here.
    func testMessageWording() {
        XCTAssertEqual(SwitchPlanner.message(for: .noShortcut(desktop: 12)),
                       "Give \"Switch to Desktop 12\" a key in System Settings › Keyboard › Keyboard Shortcuts › Mission Control.")
        XCTAssertEqual(SwitchPlanner.message(for: .stepShortcutOff),
                       "Turn on \"Move left a space\" and \"Move right a space\" in System Settings › Keyboard › Keyboard Shortcuts › Mission Control.")
        XCTAssertEqual(SwitchPlanner.permissionMessage,
                       "Dispaces needs Accessibility permission to switch Spaces. Allow it in System Settings › Privacy & Security › Accessibility, then click again.")
        XCTAssertEqual(SwitchPlanner.desktopShortcutFailedMessage(desktop: 3),
                       "Didn't switch to Desktop 3. Check that \"Switch to Desktop 3\" is turned on in System Settings › Keyboard › Keyboard Shortcuts › Mission Control.")
        XCTAssertEqual(SwitchPlanner.stepFailedMessage,
                       "Didn't reach that Space. Check that \"Move left a space\" and \"Move right a space\" are on in System Settings › Keyboard › Keyboard Shortcuts › Mission Control.")
    }

    func testDesktopsWithoutConfirmedShortcut() {
        // Apple's defaults mention no desktop shortcut as on.
        XCTAssertEqual(HotkeyTable.defaults.desktopsWithoutConfirmedShortcut(count: 3), [1, 2, 3])
        let table = hotkeys(["118": entry(enabled: true, key: 18, mods: 262144),
                             "119": entry(enabled: false, key: 19, mods: 262144),
                             "120": entry(enabled: true, key: 5000, mods: 262144)])
        XCTAssertEqual(table.desktopsWithoutConfirmedShortcut(count: 4), [2, 3, 4])
    }

    func testDesktopsWithoutConfirmedShortcutLimits() {
        XCTAssertEqual(HotkeyTable.defaults.desktopsWithoutConfirmedShortcut(count: 0), [])
        XCTAssertEqual(HotkeyTable.defaults.desktopsWithoutConfirmedShortcut(count: -2), [])
        XCTAssertEqual(HotkeyTable.defaults.desktopsWithoutConfirmedShortcut(count: 20), Array(1...16))
    }
}
