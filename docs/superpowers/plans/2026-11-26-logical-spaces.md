# Logical Spaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One menu bar tile per logical space (Spaces sharing a name across displays). A click switches every display, an Option-click switches only the clicked display. The Manage window becomes a displays × logical spaces grid.

**Architecture:**
- The pure grouping (`LogicalSpaces`), the first-Space rule, switch ordering and drag arming live in `SpacesCore` with XCTest.
- The AppKit layer (`BarController`, `SpaceTilesView`, `TileView`, `ManageWindowController`, `SpaceSwitcher`) consumes them.
- A tile is addressed by `TileTarget` (`.logical(key)` or `.space(id)`) instead of a bare Space id.

**Tech Stack:** Swift 6 toolchain (Swift 5 mode), AppKit, Foundation, CoreGraphics, SwiftPM, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-26-logical-spaces-design.md`

## Global Constraints

- No third-party dependencies, and no new private API.
- Post only `HotkeyID` shortcuts. Write only the app's own preferences.
- `scripts/source-check.sh` and `scripts/security-check.sh` must pass unchanged.
- No force unwraps on data from macOS or preferences. Doc comments on anything non-obvious. Match the existing style.
- Keep these keys: bundle ID / prefs domain `io.github.kosrodka.SpacesBar`, `spaceNames`, `displayNames`, `displayMemory`, `dragWindows`.
- New keys:
  - `firstSpaceBuiltIn`: Bool, default `true`
  - `firstSpaceExternal`: Bool, default `false`
  - `builtIn` inside each `displayMemory` record: Bool, missing reads as `false`
- Leave the old `firstSpaces` key unused, and don't delete it.
- `UserManual.markdown` must equal `docs/08-user-manual.md`.
- Colours:

  | State | Look |
  |---|---|
  | `all` / single current | `systemOrange` fill, black bold number |
  | `some` | `systemOrange` at 0.35 alpha, label-colour bold number |
  | Failed | `systemRed` ring for 3.5 s |
  | Drag armed | 2.5 pt label-colour ring, no fill |
  | Setup `!` | stays `Palette.warning` |

## Review Focus

1. **A rename that turns one name into another that already exists on the same display** (a duplicate). The bar must not lose a tile, and the second Space gets its own column. Tested in Task 2 by `testDuplicateOnOneDisplayGetsOwnColumn`.
2. **A logical click when one display's shortcut is off.** The other displays still switch, and the message names the failing display. Covered by the switcher loop in Task 4; the pure order is tested in Task 3.
3. **Option-click or drag over a column the pointer's display lacks.** Nothing is pressed and a message says so (click); the tile doesn't arm (drag). Tested by `testCellOnDisplay` in Task 2.
4. **Spaces spanning all displays (`Main`).** Columns are still built, the first Space is shown, and Option-click acts like a click. Tested by `testCombinedListShowsFirstSpace` (Task 1) and `testCombinedList` (Task 2).
5. **Stored preferences of the wrong type** (`firstSpaceExternal` = "yes", `builtIn` = 3) fall back to the defaults. Tested in Task 1.

---

### Task 1: First-Space rule and built-in memory

**Files:**
- Create: `Sources/SpacesCore/FirstSpaceRule.swift`
- Delete: `Sources/SpacesCore/FirstSpaces.swift`, `Tests/SpacesCoreTests/FirstSpacesTests.swift`
- Modify: `Sources/SpacesCore/DisplayMemory.swift` (Record gets `builtIn`; `update` gets an `isBuiltIn` param)
- Test: `Tests/SpacesCoreTests/FirstSpaceRuleTests.swift`, `Tests/SpacesCoreTests/DisplayMemoryTests.swift`

**Interfaces:**
- Produces:
  - `public struct FirstSpaceRule: Equatable, Sendable`, with:
    - `var builtIn: Bool`
    - `var external: Bool`
    - `init(storedBuiltIn: Any?, storedExternal: Any?)`
    - `static let defaults` (true, false)
    - `func isShown(identifier: String, builtIn: Bool) -> Bool`, which returns true for `Display.combinedIdentifier`
  - `DisplayMemory.Record.builtIn: Bool`, with an init param `builtIn: Bool = false`.
  - `DisplayMemory.update(with:displayName:spaceName:isBuiltIn: (Display) -> Bool = { _ in false }, now:)`: a changed `builtIn` counts as a change.

- [ ] Tests in `FirstSpaceRuleTests`:
  - `testDefaults`: built-in shown, external hidden.
  - `testStoredValues`: `true`/`false` NSNumber both honoured.
  - `testMalformedValuesFallBack`: `"yes"`, `3` and `nil` give the defaults.
  - `testCombinedListShowsFirstSpace`: `Main` is shown even when both are false.
- [ ] Tests in `DisplayMemoryTests`:
  - `testRemembersBuiltIn`: update with `isBuiltIn` true for A; `records["AAAA-1111"]?.builtIn == true` and B false.
  - `testBuiltInRoundTrip`: `DisplayMemory(stored: memory.stored)` keeps it.
  - `testOldRecordsWithoutBuiltInReadAsExternal`.
- [ ] Run `swift test`. The new tests fail.
- [ ] Implement. `stored` writes `"builtIn": record.builtIn`, and `init(stored:)` reads it with `as? Bool ?? false`.
- [ ] Run `swift test`. Everything passes, except that `BarController`/`Core.swift` still reference `FirstSpaces`; that's fixed in Task 4. A `swift build` error is acceptable until then.

### Task 2: `LogicalSpaces` and `TileTarget`

**Files:**
- Create: `Sources/SpacesCore/LogicalSpaces.swift`
- Modify: `Sources/SpacesCore/DisplayOverview.swift` (use the shared ordering helper)
- Test: `Tests/SpacesCoreTests/LogicalSpacesTests.swift`

**Interfaces:**
- Produces:
  - `public enum TileTarget: Hashable, Sendable { case logical(String), space(UInt64) }`
  - `public struct LogicalSpaces: Equatable, Sendable`:
    - `struct Cell: Equatable, Sendable { let display: String; let space: Space; let isCurrent: Bool }`
    - `enum State: Equatable, Sendable { case all, some, none }`
    - `struct Column: Equatable, Sendable`, with:
      - `let key: String`
      - `let number: Int`
      - `let title: String`
      - `let cells: [Cell]`
      - `let state: State`
      - `let duplicateOn: String?` (identifier of the display holding a second Space with this name, for the column started by it)
      - `func cell(on display: String) -> Cell?` (case-insensitive identifier match)
    - `let columns: [Column]`
    - `let fullScreen: [Cell]` (display order, Mission Control order)
    - `init(snapshot: Snapshot, memory: DisplayMemory, names: Names, screenOrder: [String], showsFirstSpace: (String) -> Bool)`
    - `func column(key: String) -> Column?`
    - `static func orderedDisplays(_ snapshot: Snapshot, screenOrder: [String]) -> [Display]`: moved out of `DisplayOverview.init`, which then calls it.
    - `static func groupingKey(_ name: String) -> String`: `name.folding(options: [.caseInsensitive], locale: nil)`
- Column key: `groupingKey(title)` for the first column with a name, and `groupingKey(title) + "\u{1F}" + String(n)` for the n-th (n ≥ 2). U+001F is a control character the name sanitizer removes, so it can't clash with a real name.
- Matching: a Space joins the first column with its grouping key that its display hasn't filled yet. Otherwise it starts a new column, with `duplicateOn` set when an earlier column with the same key exists.
- Eligible Spaces:
  - `kind == .desktop`
  - not the hidden first Space
  - not a ghost (`memory.ghostOwner`), except when the display `spansAllDisplays`
- Names: `DisplayOverview.spaceName(space, names: names, remembered: nil)`.

- [ ] Tests, with fixtures built like `Fixtures.display/space` and names via `Names(storedSpaces:storedDisplays:)` keyed by `nameKey`:
  - `testGroupsByNameAcrossDisplays`: A{Home, Music, Tech} and B{Home, Music, Tech} give 3 columns. Numbers 1, 2, 3; titles Home, Music, Tech; each with 2 cells in display order.
  - `testCaseInsensitive`: "home" on B joins "Home". The title keeps A's spelling.
  - `testOrderFollowsFirstDisplayThenNewNames`: A{Home, Tech} and B{Music, Home} give Home, Tech, Music.
  - `testUnnamedSpacesAreOwnColumns`: default names "Desktop 1" and "Desktop 4" give separate columns.
  - `testDuplicateOnOneDisplayGetsOwnColumn`: A{Home, Home} and B{Home} give 2 columns; B's Home is in column 1; column 2 has `duplicateOn == "AAAA-1111"` and a key different from column 1's.
  - `testMissingCell`: B lacks Music, so `column(Music).cell(on: "BBBB-2222") == nil`.
  - `testCellOnDisplay`: matches case-insensitively.
  - `testExcludesFullScreenHiddenFirstAndGhosts`: full-screen goes to `fullScreen`; `showsFirstSpace` false for B drops B's first Space; ghost Spaces are excluded.
  - `testStates`: both current → `.all`; one → `.some`; none → `.none`; a single-cell current column → `.all`.
  - `testCombinedList`: a single `Main` display: columns by name, nothing dropped as a ghost.
  - `testOrderedDisplaysFollowsScreenOrder`: screen order [B, A] → B first; unknown displays last.
- [ ] Run `swift test --filter LogicalSpacesTests`. The tests fail.
- [ ] Implement.
- [ ] Run `swift test --filter "LogicalSpacesTests|DisplayMemoryTests|SnapshotParserTests"`. They pass.

### Task 3: Switch order, drag arming over targets, name writes by key

**Files:**
- Modify: `Sources/SpacesCore/SwitchPlanner.swift`, `Sources/SpacesCore/DragArming.swift`, `Sources/SpacesCore/Names.swift`
- Test: `Tests/SpacesCoreTests/SwitchPlannerTests.swift`, `Tests/SpacesCoreTests/DragArmingTests.swift`, `Tests/SpacesCoreTests/NamesTests.swift`

**Interfaces:**
- Produces:
  - `SwitchPlanner.order(_ cells: [LogicalSpaces.Cell], pointerDisplay: String?) -> [LogicalSpaces.Cell]`: cells not current, in the given order, with the pointer display's cell (case-insensitive) moved last.
  - `SwitchPlanner.noSpaceMessage(display: String, title: String) -> String`, returning: `"\(display) has no Space named “\(title)”."`
  - `DragArming`: `armed: TileTarget?` (replaces `armedSpaceID`); `update(holding: Bool, target: TileTarget?, now: TimeInterval) -> TileTarget?`.
  - `Names.setName(_ name: String, forSpaceKey key: String, liveKeys: Set<String>)` and `Names.storedName(forSpaceKey:) -> String?`.

- [ ] Tests:
  - `testOrderPutsPointerDisplayLastAndSkipsCurrent`
  - `testOrderWithoutPointerKeepsDisplayOrder`
  - `DragArmingTests` rewritten with `.space(2)`, `.space(3)` and a `.logical("home")` case. Same timings as today.
  - `testSetNameByKeyAndClear`
- [ ] Run `swift test`. The new tests fail.
- [ ] Implement. `setName(for space:)` calls `setName(_:forSpaceKey:)`.
- [ ] Run `swift test`. The SpacesCore tests pass.

### Task 4: App plumbing (preferences, screens, switcher, apps reader)

**Files:**
- Modify:
  - `Sources/Dispaces/Core.swift`: `Preferences.firstSpaceRule` (computed, read each time); drop `firstSpaces`; `SpaceSwitcher.switchAll`.
  - `Sources/Dispaces/System.swift`: `Screens.isBuiltIn(_ identifier: String) -> Bool?`, using `CGDisplayIsBuiltin`; nil when no screen.
  - `Sources/Dispaces/SpaceAppsReader.swift`: `apps(on spaceIDs: [UInt64]) -> [UInt64: [NSRunningApplication]]`, which reads the window list once and caches each window's Spaces.

**Interfaces:**
- Produces:
  - `SpaceSwitcher.switchAll(_ spaceIDs: [UInt64]) async -> [(spaceID: UInt64, outcome: Outcome)]`. It is busy-guarded once for the whole run (returns `[]` with nothing pressed when busy). Each target is planned on a fresh `peek()` with the current pointer display, then pressed and verified like `switchTo`. It refreshes once at the end.
  - Factor the body of `switchTo` into `private func perform(_ spaceID: UInt64) async -> Outcome`, without the busy guard, used by both.
- [ ] Implement.
- [ ] `swift build` compiles `Core.swift`/`System.swift` (the bar may still fail until Task 5).

### Task 5: Menu bar and fallback bar

**Files:**
- Modify: `Sources/Dispaces/BarViews.swift`, `Sources/Dispaces/MenuBarItem.swift`, `Sources/Dispaces/BarController.swift`, `Sources/Dispaces/AppDelegate.swift`

**Decisions:**
- `TileModel.spaceID` becomes `target: TileTarget`.
- `TileModel.State` becomes `.all`, `.some`, `.normal`.
- `HoverTile.spaceID` becomes `target`.
- `SpaceTilesView`:
  - `onClick: ((TileTarget, _ thisDisplayOnly: Bool) -> Void)?`, where `thisDisplayOnly` = Option held and Control not held.
  - `onMenu: ((TileTarget?, NSEvent) -> Void)?`
  - `hoveredTarget`
- `Palette`: remove `focusFill`/`ring`; add `strong`, `pale`, `failed`. `drawTile` and `TileView.draw` use the colour table in Global Constraints.
- `BarController.rebuild()`:
  - computes `logical = LogicalSpaces(...)` with `screenOrder: NSScreen.screens.compactMap(Screens.identifier(of:))` and keeps it.
  - Runs: logical tiles (number = column number, `.group`), then full-screen tiles (`.group`, "FS", strong when current), then ghost groups (`.subgroup`, dimmed), using the existing ghost code.
  - `memory.update(... isBuiltIn: { Screens.isBuiltIn($0.identifier) ?? false } ...)`.
- `showsFirstSpace(id)` = `prefs.firstSpaceRule.isShown(identifier: id, builtIn: Screens.isBuiltIn(id) ?? prefs.memory.records[id]?.builtIn ?? false)`. Remove `setShowsFirstSpace`.
- Click:
  - `.space` → today's `click`.
  - `.logical`:
    - If Option and the snapshot doesn't span displays: find the cell on the pointer display. If found, `click(id)`; otherwise show `noSpaceMessage`.
    - Otherwise `switchAll(SwitchPlanner.order(column.cells, pointerDisplay:).map(\.space.managedID))`.
  - On any failure: `failedTarget = .logical(key)`; the message is the first failure's text, prefixed `"<display name>: "` when there's more than one display.
- Drag:
  - `holding` = button 1 and `modifierFlags.contains([.option, .control])`.
  - A logical tile arms only if the pointer display has a cell; at fire time it resolves to that cell's id.
- Hover: a logical tile's column shows sections per cell (a display-name heading only when there's more than one cell). `AppsPanel.show(title:sections:[(heading: String?, apps: [NSRunningApplication])], tile:screen:)`. A click on an app switches all, then `AppActivator.bringToFront`.
- Menu: `AppDelegate.menuSpaceID` becomes `menuTarget: TileTarget?`; `bar.tileName(_:)`; `bar.rename(_ target:)`.
  - `bar.askNames(for target: TileTarget) -> [String: String]?` returns key → typed name: one key for `.space`, every cell's key for `.logical`.
  - `bar.applySpaceNames(_ names: [String: String]) -> [String: String]` writes them and returns the previous stored values (`""` when none), for undo.
- Menu title: "Option-Control-drag windows to Spaces".
- VoiceOver:
  - Logical tile label: `"\(title), logical space \(number)"`, plus `", on all displays"` (`.all`, more than one cell), `", on <names>"` (`.some`), or `", current"` (`.all` with one cell).
  - Summary: `"Dispaces Spaces, current: …"` built from the column titles with state ≠ `.none`.
- [ ] Implement.
- [ ] Run `swift build`. Only `ManageWindow.swift` errors remain.

### Task 6: Manage window grid

**Files:**
- Modify: `Sources/Dispaces/ManageWindow.swift` (and `BarViews.swift` for a `NotAssignedView`)

**Decisions:**
- `reload` compares `(overview, logical)` against what's shown.
- Layout:
  - Connected section: a header row (blank label width, then one `TileView` per column with model number `"\(n)"`, name = title, state = column state, target `.logical(key)`).
  - Then one `ManageBarView` row per connected display: label, then per column either a `TileView` for the cell (number = desktop number, name = the Space's name, state `.all` if current), or a `NotAssignedView("Not assigned – <display>")`.
  - Then the display's full-screen tiles.
  - All cells share one width.
- Headers:
  - Click → `bar.click(.logical(key), thisDisplayOnly: false, switched: refocus)`.
  - Hover → apps.
  - Double-click or right-click Rename → `applyNames(bar.askNames(for: .logical(key)), action: "Rename Logical Space")`.
  - A header with `duplicateOn` gets the tooltip: "<display> has two Spaces named <title>; the second one has its own column."
- Cells:
  - Click → that Space only.
  - Double-click or Control-click → `applyNames(..., "Rename Space")`.
  - Drag (via `onPress` and the generalized `track`) onto a `NotAssignedView` in the same row, which highlights → `applyNames([space.nameKey: column.title], "Assign Space")`.
- `applyNames(_:action:)` registers its own inverse with the undo manager (redo falls out).
- Disconnected section unchanged, minus the checkbox; ghost rename also goes through `applyNames`.
- Remove `firstSpaceBox`, `toggleFirstSpace` and `setFirstSpace`.
- Hint text:
  - "Click a column heading to switch every display; click a Space to switch only its display. Double-click to rename. Drag a Space onto “Not assigned” in its row to give it that column's name."
  - plus the existing ghost-drag sentence when there are disconnected displays
  - plus a duplicate note when any column has `duplicateOn`.
- [ ] Implement.
- [ ] Run `swift build`. Clean.
- [ ] Run `swift test`. All pass.

### Task 7: Docs, manual, release notes

**Files:** `Sources/SpacesCore/UserManual.swift`, `docs/08-user-manual.md`, `docs/01-requirements.md`, `docs/02-architecture.md`, `docs/03-ui-ux.md`, `docs/06-operations.md`, `CLAUDE.md` (the rename "Option-drag" → "Option-Control drag" only).

- [ ] The manual (both copies identical) covers:
  - logical spaces by name
  - click vs Option-click
  - colours
  - Option-Control drag (grab first, then keys)
  - the grid and its renames/drag/undo
  - first Space rule with the two `defaults write` lines
- [ ] `ReleaseNotes.highlights` updated (drop the checkbox line; add logical spaces, Option-click, Option-Control drag).
- [ ] Docs 01/02/03/06 updated per spec §5.7.
- [ ] Run `swift test --filter UserManualTests`. It passes.

### Task 8: Verify

- [ ] Run `swift test`. 0 failures.
- [ ] Run `scripts/source-check.sh`. All PASS.
- [ ] Run `scripts/bundle.sh 0.1.0 && scripts/security-check.sh build/Dispaces.app`. All PASS.
- [ ] Report to the owner what was checked by hand and what wasn't. Clicking and multi-display switching need a real multi-display Mac.
- [ ] Commit only when the owner asks.
