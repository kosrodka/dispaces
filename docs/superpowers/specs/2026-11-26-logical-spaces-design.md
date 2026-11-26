# Logical spaces: design

Date: 26 Nov 2026. Status: draft for the owner's approval.

## 1. Intent

The owner keeps the same set of contexts (for example Home, Music, Tech) on every display, each as a separate macOS Space per display, named the same. Today every menu bar tile is one macOS Space on one display, so moving the whole desk to "Music" takes one click per display.

A **logical space** is the set of macOS Spaces, one per display at most, that share a name. The menu bar shows one numbered tile per logical space. One click switches every display to its own Space of that logical space.

Terms used below: **Space** means a macOS Space (desktop) on one display. **Logical space** means the group. **Column** means a logical space as shown in the Manage window grid.

## 2. Goals

- G1. The menu bar (and the fallback bar) shows one tile per logical space, numbered 1, 2, 3 … in column order, instead of one tile per Space.
- G2. Clicking a logical tile switches every connected display that has a Space in that logical space to it. The result is the same whichever display's menu bar was clicked.
- G3. Option-click switches only the display whose menu bar (or fallback bar) was clicked.
- G4. Dragging a window to another Space moves from Option to Option+Control, and switches only the display under the pointer.
- G5. The current-state highlight turns orange. It is strong when every display that has the logical space shows it, and pale when only some do.
- G6. In the Manage window, the connected displays become a grid: one column per logical space, one row per display. Where a display has no Space for a column, the cell reads "Not assigned – <display name>".
- G7. The first Space rule is fixed by default: the built-in display shows its first Space, external displays don't. The checkbox leaves the window, and the setting moves to the preferences file (section 4.6).

## 3. Non-goals, anti-goals, constraints

**Non-goals**
- No stored list of logical spaces. They are derived from Space names only.
- No setting to bring back per-display tiles. With one display, the bar looks and behaves as it does today.
- No all-display switching of full-screen Spaces or desktops above 16. macOS can only reach those by stepping the display under the pointer.
- No creating, deleting or moving Spaces between displays. macOS doesn't let apps do this.

**Anti-goals** (failure even if it technically works)
- A click that leaves some displays unswitched without saying so.
- Focus ending up on a display other than the one the user clicked on.
- Losing existing Space names, display names or remembered displays. The bundle ID and preference keys stay the same.
- Any weakening of `scripts/source-check.sh` or `scripts/security-check.sh`.

**Constraints** (from CLAUDE.md, unchanged)
- No dependencies.
- Only the `HotkeyID` shortcuts are posted.
- Only the existing read-only private calls are used.
- The app writes only its own preferences.
- The window drag reads only `NSEvent` class properties.
- Testable logic goes in `SpacesCore` with tests.
- No force unwraps on data from macOS or preferences.
- `UserManual.swift` must match `docs/08-user-manual.md`.

**macOS facts the design rests on**
- "Switch to Desktop N" switches whichever display owns desktop N. Switching three displays therefore takes three presses.
- Control-clicking a title bar is a right-click. With Option+Control, the user grabs the window first, then presses the keys.

## 4. Approaches

**Which Spaces form a logical space** (the owner picked by name)
- **By name (chosen).** No new state, and the owner's Spaces are already named this way. Moving a Space to another column means renaming it. An unnamed Space ("Desktop N") is a column of its own, so it behaves like today.
- **By position:** the first Space on every display is logical 1, and so on. Rejected: it can't leave a gap in the middle, and reordering means dragging in Mission Control.
- **Assigned in the grid** (a separate stored list). Rejected: it's a second list to keep in step with macOS, and every new Space needs an assignment rule.

**How all displays are switched** (builder's pick, owner didn't object)
- **One display at a time, each confirmed before the next (chosen).** Reuses today's press, check and retry once. Takes roughly 0.25 to 0.5 s per display.
- **All presses back to back, then confirm and re-press misses.** Faster, but macOS can drop a press during its slide animation. Kept as a later speed-up if A feels slow.

**Where the grouping lives:** one pure type in `SpacesCore` that the bar, the grid, the switcher and the tests all use. Computing it in the AppKit layer would break the project's rule that testable logic goes in `SpacesCore`.

## 5. Design

### 5.1 Grouping: `SpacesCore/LogicalSpaces.swift` (new)

**Inputs**
- the `Snapshot`
- `Names`
- `DisplayMemory`
- the display order (macOS display order, the same `screenOrder` the Manage window already uses)
- whether a display's first Space is shown (section 5.6)

**Which Spaces take part**
- For each connected display in display order, take its Spaces in Mission Control order, but skip:
  - full-screen Spaces
  - the display's first Space when it's hidden
  - Spaces that belong to a disconnected display (`DisplayMemory.ghostOwner`)
- When Spaces span all displays (the `Main` list), everything works the same with a single display.

**Grouping key:** the name the bar shows (`DisplayOverview.spaceName`), compared case-insensitively (builder's call). The column title is the spelling of the first Space found.

**Column order:** the order in which names are first met while walking displays in display order and Spaces in Mission Control order. The number is the position + 1. For the owner's setup that gives 1 Home, 2 Music, 3 Tech.

**The same name twice on one display:** the first one (in Mission Control order) is in the column. Each later one starts a column of its own, with the same title, at the point where it's met. Spaces with that name on other displays still join the first column. The grid marks the duplicate (section 5.5).

**Output per column**
- number
- title
- one cell per display that has a Space in it: display identifier, Space id, desktop number
- **state:**
  - `all`: every display with a cell shows that cell's Space
  - `some`: at least one display shows its cell's Space, but not all
  - `none`: no display shows it

**Also produced:** the Spaces outside all columns (full-screen Spaces per display, and ghost groups as today), so the bar and grid can show them as single tiles.

### 5.2 Switching

**Click (all displays).**
- `SwitchPlanner` gains a function that, for a column, returns an ordered list of per-display plans. It builds each with today's `plan(to:in:hotkeys:pointerDisplay:)`.
- Displays already on their cell are skipped.
- The display under the pointer (where the click happened) goes **last**, so it keeps the focus. The others follow display order.
- `SpaceSwitcher` gains `switchAll`. It runs the plans one at a time, re-reading the snapshot before each, with the existing press, verify (1 s) and retry once.
- A failure on one display doesn't stop the others.
- At the end:
  - If anything failed, the logical tile turns red for 3.5 s.
  - The message panel shows the first problem, prefixed with the display name when there's more than one display. For example: "LC27G7XT: Turn on "Switch to Desktop 6" in System Settings › …".
- While a switch is running, other clicks are ignored, as today.
- **Keeping the focus** (builder's call, after the review). Often the clicked display needs no press because it already shows its Space, and pressing another display's shortcut can move the focus there. So after the run, take the clicked display's cell, or the Space that display shows now when it has no cell (added after the final review). If that Space isn't the focused Space (`Snapshot.activeSpaceID`), press that display's own "Switch to Desktop N" once more. No error is shown if it doesn't take.

**Option-click (one display).**
- In the bar's click handlers, Option without Control means: target only the display under the pointer.
- If that display has a cell in the column, switch to it with today's `switchTo`.
- If it doesn't, show the message "<display> has no Space named "<title>"." Nothing is pressed.
- Control (with or without Option) still opens the menu, as today.

**Single tiles** (full-screen Spaces, unplugged displays' Spaces) switch only their own Space, as today, with or without Option.

**Right-click › Rename on a logical tile** (builder's call, after the review) renames every Space in the column, like the grid heading. The prompt says how many displays it applies to.

### 5.3 Option+Control drag

- `holding` becomes: left button down **and** `NSEvent.modifierFlags` contains both `.option` and `.control`.
- A logical tile arms only when the display under the pointer has a cell in that column. Firing switches just that cell's Space.
- Single tiles arm as today. Full-screen tiles never arm.
- The menu item is renamed "Option-Control-drag windows to Spaces". The preference key `dragWindows` is unchanged, so the user's on/off survives.
- In CLAUDE.md, update only the name "Option-drag" in the hard rule. What the rule says stays the same.

### 5.4 Menu bar and fallback bar

**Layout**
- First run: the logical tiles, showing the column number.
- Then one run with the full-screen tiles of all displays, in display order, showing "FS".
- Then the unplugged displays' groups, dimmed, as today.
- Spacing uses the existing `MenuBarGeometry` runs.

**Looks.** These replace the blue focused/current pair, for the bar and the Manage window alike:

| State | Look |
|---|---|
| `all` | Strong orange fill (`systemOrange` or close), black bold number |
| `some` | Pale orange fill (same orange at about 35 % opacity), label-colour bold number |
| `none` | As today: outline only |
| A single tile that is current | Same as `all`, since it exists on one display |
| Switch failed | Red ring (`systemRed`) for 3.5 s, replacing amber |
| Drag armed | Thick (about 2.5 pt) ring in the label colour, no fill, replacing solid yellow |

The amber **!** for setup problems stays amber. The builder checks contrast in light and dark menu bars and may tune the values.

**Hover apps column**
- For a logical tile, the column lists apps from every Space in the column, under a small heading per display. The heading is left out when there's only one cell.
- Clicking an app does the all-display switch, then `AppActivator.bringToFront` as today.
- `SpaceAppsReader` gains a version that takes several Space ids and reads the window list once. It still reads only window number, owner, layer, alpha and size, and stays the only window-list reader.

**VoiceOver**
- A logical tile's label is like "Home, logical space 1, on all displays" or "… on Built-in Retina Display only".
- The item's summary lists the current logical spaces.

### 5.5 Manage window: grid

**Header row.** One header per column, showing "1 Home".
- Click: switches all displays. Afterwards the window comes back to the front as it does today.
- Hover: shows the column's apps.
- Double-click or right-click › Rename: renames every Space in the column to the typed name, as one undo step ("Rename Logical Space"). An empty name resets each of those Spaces to its default name, which splits the column. That is allowed.

**One row per connected display**, in display order.
- Each row starts with the display name label, renamable as today.
- Then one cell per column:
  - **The display's Space:** the tile as today, showing desktop number and name. Click switches only that display. Hover shows its apps. Double-click or right-click › Rename renames that Space, and it moves to the column with the new name.
  - **"Not assigned – <display name>":** dimmed, dashed outline, not clickable. Its tooltip says to name one of this display's Spaces "<title>", or to drag one here.
- After the columns, the display's full-screen Spaces as single tiles.

**Dragging.** Drag a Space from a cell onto a "Not assigned" cell **in the same row** to rename it to that column's title. That cell lights up while a drop is possible. Dropping anywhere else does nothing.

**Undo.** Rename (cell and header) and drag-to-assign are undoable with Command-Z and Shift-Command-Z, like Forget and the moves.

**Duplicates.** A duplicate's column header gets a tooltip like "Built-in Retina Display has two Spaces named Home; the second one has its own column", and the hint line under the grid says the same.

**Disconnected displays section:** unchanged (bars, drag to move into a connected display's group, Forget, undo), except the checkbox is gone.

**Layout.** All cells are one width, as today. The window already scrolls horizontally when columns don't fit.

### 5.6 First Space

**Defaults.** The built-in display shows its first Space and external displays don't. When Spaces span all displays (`Main`), the first Space is always shown.

**Detecting built-in.** `CGDisplayIsBuiltin` (public CoreGraphics) on the screen's display id.

The owner confirmed this default after hearing that a Mac without a built-in screen, or with the lid closed, then hides every first Space. That case is covered by the settings below.

**Settings in the preferences file.** Two keys in the app's own domain `io.github.kosrodka.SpacesBar`, both optional Bools, read with type checks:
- `firstSpaceBuiltIn`: default true
- `firstSpaceExternal`: default false

The user changes them in Terminal, for example `defaults write io.github.kosrodka.SpacesBar firstSpaceExternal -bool true`. The app reads them on each rebuild, so the next refresh (or menu › Refresh now) applies the change. Nothing in the UI writes them.

**Unplugged displays.**
- `DisplayMemory.Record` gains `builtIn: Bool`, stored as `"builtIn"`.
- It is set while the display is connected.
- A missing or malformed value reads as false (external).
- The same two keys then decide whether that display's first Space shows in its ghost group and in the Disconnected section.

**Removed.**
- `FirstSpaces.swift` and its tests.
- `Preferences.firstSpaces`.
- The checkbox and its undo action.
- `BarController.setShowsFirstSpace`.

The old `firstSpaces` key is left in the preferences file, unused, like the old floating-bar keys, so an older build still finds it.

### 5.7 Docs and release notes

- **User manual:** `UserManual.swift` and `docs/08-user-manual.md` change together. They cover:
  - logical spaces and naming
  - click vs Option-click
  - Option+Control drag, grabbing the window first
  - the colours
  - the grid
  - the two `defaults write` lines
- **`docs/01-requirements.md`:** new F-row for logical spaces, and updates to F8, F9 and F11.
- **`docs/02-architecture.md`:** `LogicalSpaces`, the all-display switch flow, the `builtIn` field.
- **`docs/03-ui-ux.md`:** layout sketch, highlight table, interactions.
- **`docs/06-operations.md`:** the drag row.
- **`ReleaseNotes.highlights`:** updated.

### 5.8 Tests (`Tests/SpacesCoreTests`)

**`LogicalSpaces`**
- grouping by name, case-insensitive
- column order
- unnamed Spaces each get their own column
- duplicates on one display
- full-screen Spaces, hidden first Spaces and ghosts are left out
- a single combined (`Main`) list
- state `all`, `some` and `none`, including a column with one cell

**`SwitchPlanner`:** the all-display plan puts the pointer display last, skips displays already there, and reports a desktop above 16 on another display as unavailable.

**`DisplayMemory`:** `builtIn` round trip, and older stored data without it.

**First-Space rule:** defaults, both keys, malformed values, the combined list.

**`UserManualTests`:** keeps the two texts in step.

## 6. Left to the builder

- Exact orange values and opacity, ring widths.
- Type names, for example a tile target enum (logical column or single Space) replacing the bare `spaceID` in `TileModel`, `HoverTile` and the click callbacks.
- Grid metrics and header styling.
- Case-insensitive comparison details. Plain Unicode case folding is fine.
- Checking on a real Mac whether pressing another display's "Switch to Desktop N" moves the focus. Section 5.2's ordering is right either way.
- Whether to watch `UserDefaults.didChangeNotification` for the two keys, or rely on the next refresh.

## 7. Risks

- **Three displays switching one after another may feel slow.** Mitigation: the back-to-back approach in section 4, as a follow-up.
- **Renaming a Space moves it between columns.** That is the point, but a typo splits a column. The grid makes this visible, and undo fixes it.
