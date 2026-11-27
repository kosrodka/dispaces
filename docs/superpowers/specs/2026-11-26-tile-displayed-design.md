# Tile displayed: letters instead of numbers (design)

Approved by the owner on 26 Nov 2026 ("go ahead").

## Intent

A logical space's menu bar tile shows its number (1, 2, 3). The owner wants to show a letter instead where it reads better: H for Home, M for Music, T for Technology. The numbering itself stays as it is.

## What changes

- **Tile displayed**, a third attribute of a logical space next to its number and its name. Empty by default; then the tile shows the number, as before. Otherwise the menu bar (and the floating bar) show it instead of the number.
- **Up to 2 characters** (the room a two-digit number takes): letters, digits or an emoji. Cleaned like names (no control or direction-override characters, spaces trimmed). Drawn smaller when it doesn't fit the square tile.
- **Manage displays and spaces:** the column heading becomes three rows, titled in the display-name column: *Tile number* (plain text), *Tile name* (the clickable, orange heading as before, without the number; double-click renames), *Tile displayed* (a text field; empty shows the number greyed). Enter, Tab or clicking elsewhere saves; Command-Z undoes.
- **Stored by logical space name** (its grouping key, the folded name) in the app's own preferences, key `tileLabels`. Renaming a logical space (its heading) moves the letter to the new name, unless that name already has one. Renaming one Space moves it into another logical space, which shows that one's letter. Clearing the name leaves the letter stored under the old name.
- **Not changed:** full-screen tiles, unplugged displays' tiles, the grid's Space cells (each desktop's own number), hover names and VoiceOver ("logical space 1").
- A second Space with the same name on one display has its own column; its field is disabled (rename it to give it a letter), so no odd keys are stored.

## Approaches

1. **By name (chosen):** the letter belongs to the logical space, which is defined by its name. Predictable; needs one extra step when the heading is renamed.
2. **Per Space, like names:** every Space in the column stores the letter. Follows renames for free, but a Space renamed into another column brings its letter along and two letters compete.
3. **Dialog instead of a field:** consistent with renames, but setting H, M, T would be three dialogs; a field lets Tab move to the next column.

## Also fixed: unreadable hover column in Dark mode

The hover column, the message box and the floating bar set their background as a fixed colour when shown, resolved with whatever light/dark appearance was current then. When macOS switches to Dark automatically after Dispaces started in light mode, the background stays white while the text turns white. The boxes now pick their colours inside `updateLayer()`, which AppKit runs with the box's own appearance and again when it changes.
