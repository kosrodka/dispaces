# Dispaces User Manual

Dispaces shows every Space (desktop) of each display as a row of small square tiles in the macOS menu bar and switches Space when you click one. There is no Dock icon except while one of its windows is open.

## Getting started

- **Turn on the desktop shortcuts.** System Settings › Keyboard › Keyboard Shortcuts › Mission Control: turn on "Switch to Desktop 1", "Switch to Desktop 2" and so on, one for each desktop. Dispaces switches by pressing these for you.
- **Allow Accessibility.** The first click on a tile asks for it. It's used only to press the Switch to Desktop shortcuts.
- **Check the setup.** Right-click the tiles › Setup check… shows what's on and what's missing. An amber **!** after the tiles means something needs attention; click it.
- **Keep it in view.** Hold Command and drag the tiles towards the clock. macOS hides the menu bar items furthest from the clock first when they don't fit (for example beside the notch), and Dispaces remembers where you put it.

## The tiles in the menu bar

- **One tile per Space,** in Mission Control order, each showing its desktop number. A full-screen app's Space has a dashed border and "FS" instead of a number.
- **The current Space** of the display you're using is filled blue; the current Space of another display has a blue ring.
- **Several displays:** each display's Spaces are a group, with a wider gap between groups, in the order the displays are arranged in System Settings › Displays.
- **Names:** point at a tile to see its Space's name (in the apps column when Show apps on hover is on, otherwise as a tooltip).
- **First Space of a display:** shown by default. To hide it, untick "Show first Space" next to that display in Manage displays and spaces.
- **Unplugged displays:** macOS moves an unplugged display's Spaces onto a connected display. Dispaces keeps them as a dimmed group after that display's own Spaces.
- **Plugging in or unplugging a display:** about a second later Dispaces redraws all tiles from scratch, as if it had been restarted.
- **The menu:** right-click (or Control-click) the tiles, or click in the gap between two displays' groups.

## When the menu bar item is hidden

macOS decides which menu bar items are shown. It hides items that don't fit, hides the whole menu bar over full-screen apps or when it's set to hide automatically, and lets you switch items off in System Settings › Menu Bar.

- **Floating bar:** whenever macOS isn't showing the tiles for more than a second, a small floating bar with the same tiles appears at the top centre of the main display. It works the same way, and disappears as soon as the menu bar item is back.
- Turn it off with the menu › Floating bar when the menu bar item is hidden.

## Switching Space

- **Click a tile** to switch to that Space. The switch happens when you let go of the button, within half a second and without moving.
- **Press and hold** doesn't switch.
- If a switch fails, the tile turns amber and a short message under the tiles says why and how to fix it.

## Naming Spaces and displays

- **Rename a Space:** right-click its tile › Rename "…"…, or double-click it in Manage displays and spaces. Up to 24 characters. Leave it empty to go back to "Desktop N".
- **Rename a display:** in Manage displays and spaces, double-click its name or right-click it › Rename display…. Right-click › Reset to default name undoes it.

## Apps on a Space

- **Rest the pointer on a tile** for about a third of a second: a column opens under it with the Space's full name and the apps that have a window there, frontmost first.
- **Move into the column** and it stays open. Each app glows under the pointer.
- **Click an app** to switch to that Space and bring the app to the front, as clicking it in the Dock would.
- Turn it off with the menu › Show apps on hover. Dispaces reads only which apps have windows where, never window titles or contents.

## Moving a window to another Space (Option-drag)

- Turn it on once: the menu › Option-drag windows to Spaces.
- **Hold Option**, grab a window by its title bar and drag the pointer onto a tile in the menu bar (or on the floating bar). The tile turns yellow; when it has been yellow for a moment, the Space switches and macOS carries the window along. Then let go.
- Dispaces never moves windows itself; you hold the window and it presses the desktop shortcut.

## Manage displays and spaces

The menu › Manage displays and spaces opens a normal window you can close, minimise and resize. It opens in front of all other windows, ready to use. Like the manual window, it shows on every desktop, so it stays with you when you switch Space.

- **A bar for every display,** with its name and its Spaces: connected displays first, in macOS's display order, then unplugged ones with a dashed border.
- **Click a Space** to switch to it, and **rest on it** to see its apps, the same as in the menu bar. After a switch the window comes back in front of other windows and keeps the focus, so you can click the next Space straight away.
- **Show first Space:** the checkbox next to each display shows or hides its first Space here and in the menu bar.
- **Move an unplugged display's Space:** drag it onto the bar of the display macOS moved it to (that bar lights up). It then belongs to that display's group. Windows and Spaces don't move; macOS doesn't let apps move a Space to another display.
- **Forget:** drops an unplugged display you won't use again. Its Spaces join the groups of the displays they're on.
- **Undo and redo:** Command-Z undoes a move, Forget or checkbox change; Shift-Command-Z redoes it, while the window is open.
- A desktop shown dimmed as "–" was deleted by macOS when the display was unplugged (macOS removes an unplugged display's first desktop).

## Help

- **Help › Current release** shows the version you're running and what's in it.
- **Help › User manual** opens this manual.

## Keyboard and mouse shortcuts

- **Click a tile:** switch to that Space.
- **Right-click or Control-click the tiles:** the menu, with Rename for the tile you clicked.
- **Command-drag the tiles:** move them along the menu bar.
- **Double-click a Space or display name in Manage displays and spaces:** rename it.
- **Option + drag a window onto a tile:** move it to that Space (when turned on).
- **Command-Z / Shift-Command-Z:** undo / redo in Manage displays and spaces.
- **Command-W / Command-M:** close / minimise the Manage and manual windows.
- **Command-Q** (in the menu): quit Dispaces.
- **Control-1, Control-2 …** (macOS's own Switch to Desktop shortcuts) keep working as usual.

## The menu

- **Floating bar when the menu bar item is hidden**, **Show apps on hover**, **Option-drag windows to Spaces**, **Launch at login:** on/off switches.
- **Manage displays and spaces**, **Setup check…**, **Refresh now**, **Help**, and **Quit Dispaces**.

## Privacy and limits

- No network access, no scripts, no other permissions than Accessibility. Dispaces writes only its own preferences.
- Desktops 1 to 16 switch with one shortcut. macOS has no shortcut beyond 16, so those desktops, like a full-screen app's Space, are reached step by step.
- macOS alone decides whether the menu bar item fits; when it doesn't, the floating bar stands in.
- The name of a display's first desktop follows the display, since macOS gives that desktop no lasting id.
