# Dispaces User Manual

Dispaces shows your Spaces (desktops) as small square tiles in the macOS menu bar and switches Space when you click one. Spaces with the same name on different displays form one logical space: one tile, and one click switches every display to it. There is no Dock icon except while one of its windows is open.

## Getting started

- **Turn on the desktop shortcuts.** System Settings › Keyboard › Keyboard Shortcuts › Mission Control: turn on "Switch to Desktop 1", "Switch to Desktop 2" and so on, one for each desktop. Dispaces switches by pressing these for you.
- **Allow Accessibility.** The first click on a tile asks for it. It's used only to press the Switch to Desktop shortcuts.
- **Name your Spaces.** Give the Spaces that belong together the same name on every display, for example Home, Music and Tech. Right-click a tile › Rename, or use Manage displays and spaces.
- **Check the setup.** Right-click the tiles › Setup check… shows what's on and what's missing. An amber **!** after the tiles means something needs attention; click it.
- **Keep it in view.** Hold Command and drag the tiles towards the clock. macOS hides the menu bar items furthest from the clock first when they don't fit (for example beside the notch), and Dispaces remembers where you put it.

## Logical spaces

- **Same name, same logical space.** A display's Space named Home and another display's Space named Home are one logical space, Home. Upper and lower case don't matter.
- **Numbered 1, 2, 3…** in the order the names first appear: the main display's Spaces from left to right in Mission Control, then names that only other displays have.
- **A display without that Space** simply isn't switched. Manage displays and spaces shows it as "Not assigned".
- **A Space you haven't named** ("Desktop N") is a logical space of its own, so it switches only its own display.
- **Two Spaces with the same name on one display:** the second one gets its own logical space.
- **Renaming a Space moves it** to the logical space with the new name.

## The tiles in the menu bar

- **One tile per logical space,** showing its number. After them come full-screen apps' Spaces (dashed border, "FS"), then the Spaces of unplugged displays.
- **Strong orange:** every display that has this logical space shows it.
- **Pale orange:** only some displays show it, for example after an Option-click. Two pale tiles can show at once.
- **Names:** point at a tile to see its name (in the apps column when Show apps on hover is on, otherwise as a tooltip).
- **First Space of a display:** the built-in display shows its first Space; external displays don't. To change that, see Settings in the preferences file.
- **Unplugged displays:** macOS moves an unplugged display's Spaces onto a connected display. Dispaces keeps them as a dimmed group at the end; each of those tiles switches just that one Space.
- **Plugging in or unplugging a display:** about a second later Dispaces redraws all tiles from scratch, as if it had been restarted.
- **The menu:** right-click (or Control-click) the tiles, or click in the gap between two groups.

## When the menu bar item is hidden

macOS decides which menu bar items are shown. It hides items that don't fit, hides the whole menu bar over full-screen apps or when it's set to hide automatically, and lets you switch items off in System Settings › Menu Bar.

- **Floating bar:** whenever macOS isn't showing the tiles for more than a second, a small floating bar with the same tiles appears at the top centre of the main display. It works the same way, and disappears as soon as the menu bar item is back.
- Turn it off with the menu › Floating bar when the menu bar item is hidden.

## Switching Space

- **Click a tile** to switch every display to its Space in that logical space. It doesn't matter which display's menu bar you click. The displays switch one after another; the display you clicked on goes last, so you stay where you are.
- **Option-click a tile** to switch only the display whose menu bar you clicked. If that display has no Space in that logical space, a short message says so.
- The switch happens when you let go of the button, within half a second and without moving. **Press and hold** doesn't switch.
- If a switch fails, the tile gets a red ring and a short message under the tiles names the display and says how to fix it. The other displays still switch.

## Naming Spaces and displays

- **Rename a logical space:** right-click its tile › Rename "…"…, or double-click its column heading in Manage displays and spaces. Every display's Space in it gets the new name. Up to 24 characters. Leave it empty to give each Space its default name ("Desktop N") back.
- **Rename one Space:** double-click it in Manage displays and spaces. It then belongs to the logical space with that name.
- **Rename a display:** in Manage displays and spaces, double-click its name or right-click it › Rename display…. Right-click › Reset to default name undoes it.

## Apps on a Space

- **Rest the pointer on a tile** for about a third of a second: a column opens under it with the name and the apps that have a window there, frontmost first. For a logical space on several displays, the apps are listed under each display's name.
- **Move into the column** and it stays open. Each app glows under the pointer.
- **Click an app** to switch there and bring the app to the front, as clicking it in the Dock would.
- Turn it off with the menu › Show apps on hover. Dispaces reads only which apps have windows where, never window titles or contents.

## Moving a window to another Space (Option-Control drag)

- Turn it on once: the menu › Option-Control-drag windows to Spaces.
- **Grab a window** by its title bar first, then hold Option and Control, and drag the pointer onto a tile in the menu bar (or on the floating bar). Grab first: Control-clicking a title bar is a right-click.
- The tile gets a thick ring; when it has had it for a moment, the display you're dragging on switches to its Space in that logical space, and macOS carries the window along. Then let go.
- Only that display switches. A tile whose logical space has no Space on that display doesn't react.
- Dispaces never moves windows itself; you hold the window and it presses the desktop shortcut.

## Manage displays and spaces

The menu › Manage displays and spaces opens a normal window you can close, minimise and resize. It opens in front of all other windows, ready to use. Like the manual window, it shows on every desktop, so it stays with you when you switch Space.

- **A grid of the connected displays:** one column per logical space, with its number and name as the heading, and one row per display, in macOS's display order. Each cell is that display's Space, or "Not assigned" with the display's name when it has none.
- **Click a column heading** to switch every display; **click a Space** to switch only its display. **Rest on either** to see the apps, the same as in the menu bar. After a switch the window comes back in front of other windows and keeps the focus.
- **Double-click a heading** to rename the logical space on every display; **double-click a Space** to rename just that one.
- **Drag a Space onto "Not assigned"** in its own row: it gets that column's name and moves into that column.
- **Disconnected displays** follow, each as a bar with a dashed border. Drag one of their Spaces onto the row of the display macOS moved it to (that row lights up): it then belongs to that display. Windows and Spaces don't move; macOS doesn't let apps move a Space to another display.
- **Forget:** drops an unplugged display you won't use again. Its Spaces join the displays they're on.
- **Undo and redo:** Command-Z undoes a rename, drag or Forget; Shift-Command-Z redoes it, while the window is open.
- A desktop shown dimmed as "–" was deleted by macOS when the display was unplugged (macOS removes an unplugged display's first desktop).

## Settings in the preferences file

Whether a display's first Space is shown is set in Dispaces' preferences file, not in a window. Type these in Terminal; Dispaces picks the change up on its next refresh (or the menu › Refresh now).

- **Show external displays' first Space:** defaults write io.github.kosrodka.SpacesBar firstSpaceExternal -bool true
- **Hide the built-in display's first Space:** defaults write io.github.kosrodka.SpacesBar firstSpaceBuiltIn -bool false
- **Back to the defaults:** defaults delete io.github.kosrodka.SpacesBar firstSpaceExternal (and the same with firstSpaceBuiltIn).
- A Mac without a built-in display (or with its lid closed) has only external displays, so by default no first Space is shown. A hidden first Space is still there: its Switch to Desktop shortcut and Mission Control still reach it.

## Help

- **Help › Current release** shows the version you're running and what's in it.
- **Help › User manual** opens this manual.

## Keyboard and mouse shortcuts

- **Click a tile:** switch every display to that logical space.
- **Option-click a tile:** switch only the display whose menu bar you clicked.
- **Right-click or Control-click the tiles:** the menu, with Rename for the tile you clicked.
- **Command-drag the tiles:** move them along the menu bar.
- **Double-click a heading, Space or display name in Manage displays and spaces:** rename it.
- **Grab a window, then hold Option and Control and drag it onto a tile:** move it to that Space (when turned on).
- **Command-Z / Shift-Command-Z:** undo / redo in Manage displays and spaces.
- **Command-W / Command-M:** close / minimise the Manage and manual windows.
- **Command-Q** (in the menu): quit Dispaces.
- **Control-1, Control-2 …** (macOS's own Switch to Desktop shortcuts) keep working as usual.

## The menu

- **Floating bar when the menu bar item is hidden**, **Show apps on hover**, **Option-Control-drag windows to Spaces**, **Launch at login:** on/off switches.
- **Manage displays and spaces**, **Setup check…**, **Refresh now**, **Help**, and **Quit Dispaces**.

## Privacy and limits

- No network access, no scripts, no other permissions than Accessibility. Dispaces writes only its own preferences.
- Desktops 1 to 16 switch with one shortcut. macOS has no shortcut beyond 16, so those desktops, like a full-screen app's Space, are reached step by step, and only on the display under the pointer.
- macOS has no shortcut that switches all displays at once, so a logical space is switched one display after another.
- macOS alone decides whether the menu bar item fits; when it doesn't, the floating bar stands in.
- The name of a display's first desktop follows the display, since macOS gives that desktop no lasting id.
