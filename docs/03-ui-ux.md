# 3. UI and UX

The setup check is a standard macOS alert, and failure messages appear in a small panel under the bar.

## 3.1 The bar

```
On the Studio Display:
┌──────────────────────────────────────────────────────────────┐
│ 👁 🔒 ↻ │ STUDIO DISPLAY [1 HOME][2 MUSIC][3 TECH][4 MAIL] [!] │
└──────────────────────────────────────────────────────────────┘
On the MacBook Pro:
┌─────────────────────────────────────────────────────┐
│ 👁 🔒 ↻ │ MACBOOK PRO [5 CHAT][6 NOTES][FS Safari]  │
└─────────────────────────────────────────────────────┘
Collapsed (Spaces hidden):
┌─────────┐
│ 👁 🔒 ↻ │
└─────────┘
```

- One floating bar per display, shown only on that display. 36 pt tall, rounded, dark or light following the system appearance.
- Control section on the far left, three tiny buttons:
  - **Show/hide Spaces** (eye): collapses this bar to just its controls, or expands it again. Remembered per display.
  - **Lock position** (padlock): stops moving and resizing this bar. Each bar has its own lock; the menu item locks or unlocks all of them.
  - **Refresh** (arrow): re-reads the Spaces now.
- Then a thin divider and the display name in small caps.
- One tile per Space: desktop number + name. Default name "Desktop N".
- Full-screen app Spaces: dashed outline, "FS" instead of a number, the app's name as the default name.
- Tiles shrink to a compact size when the bar would be wider than 90 % of the screen; long names end in "…" and the full name is in the tooltip.
- Amber **!** at the end only when setup needs attention.

## 3.2 Highlighting

| State | Look |
|---|---|
| Current Space on the display you're using | Solid blue (#0063CE, white text; 5.9:1 contrast) |
| Current Space on another display | Grey fill + blue outline |
| Other Spaces | No fill, grey outline |
| Switch failed | Amber outline for 3.5 s + message |
| Option-drag: tile under the held window | Solid yellow, black text (switches after 0.4 s) |
| Option-drag: bar under the pointer | Yellow tint and yellow border |

Colour is never the only signal: current tiles are also bold, and VoiceOver reads "current on this display".

## 3.3 Interactions

| Action | Result |
|---|---|
| Click a tile | Switch to that Space when the button is let go (within half a second, without moving off the tile). Pressing and holding doesn't switch; it's kept for grabbing. Instant feedback: the tile highlights as soon as macOS confirms. |
| Double-click a tile, or right-click › Rename Space… | Rename dialog (24 characters max). Empty = default name. |
| Right-click a display label › Rename display… / Reset to default name | Rename the area. |
| Drag a bar by its background or display name | Move it within its display. Position is remembered per display (as an offset from the display's top-left), and the bar keeps itself on its display's visible area. |
| Hover a bar's edge or corner, then drag | The pointer turns into a resize cursor and the bar's border turns the accent colour. Dragging resizes the bar (height 28–72 pt, width up to the screen); tiles stretch or shrink to fill it and text grows with the height. Remembered per display. Double-click the edge to go back to the natural size. Not available on a collapsed or locked bar. |
| Click the eye / padlock / arrow button | Hide or show this bar's Spaces / lock or unlock this bar's position and size / refresh now. |
| Click **!** | Setup check window. |
| Rest the pointer on a tile | After 0.35 s a column appears under the tile (above it near the bottom of the screen): the Space's full name, then each app with a window there (icon and name), front-most first, up to 12 then "+N more", or "No windows". It stays open while the pointer is on the tile or on the column, and disappears 0.25 s after the pointer leaves both, or when you click. Each app row glows (accent tint and soft halo) under the pointer; clicking it switches to that Space and brings the app to the front. The column replaces the tile's tooltip. |
| Hold Option, grab a window and drag it onto a tile (when "Option-drag windows to Spaces" is on) | The bar glows yellow; the tile under the pointer turns yellow and, after 0.4 s, that display switches to that Space with the window still in your hand. Let go to drop it there. Drag onto another display's bar to move it to a Space on that display. Option can be pressed before or after grabbing. (Control was rejected: Control held at the click makes it a right-click.) |
| Spaces of an unplugged display | Shown on the bar of the display macOS moved them to, after its own Spaces, under the unplugged display's name in dimmer text (tooltip explains). They switch like any tile. |
| Menu bar icon › Manage displays and spaces | A normal window (close, minimise, resize; Dispaces shows in the Dock while it's open), shown on every desktop like the bars. A copy of each display's bar, connected displays first (macOS display order), then disconnected ones (dashed border, "last connected" in the name's tooltip, Forget button). Equal-width name cells and Space cells. Click switches Space, hover shows apps, as on the bars; after a switch the window stays in front with the focus. Drag a disconnected display's Space onto the bar of the display it's on now (that bar lights up) to move it into that display's group; grouping only, windows and Spaces don't move. A "Show first Space" checkbox next to each display (on by default for every display) shows or hides that display's first Space here and on its bar. Command-Z undoes a move, Forget or checkbox change, Shift-Command-Z redoes it (until the window closes). Updates live. |
| Menu bar icon › Help › Current release | An alert with the version and what's in this release; "Open User Manual" opens the manual. |
| Menu bar icon › Help › User manual | A normal, read-only window with the user manual (built into the app, same text as docs/08-user-manual.md); text can be selected and copied. Command-W closes it, Command-M minimises it (also in the Manage window). |
| Menu bar icon (three Space tiles, the middle one filled) | Show bars ✓ (hides or shows all bars), Lock all bars ✓ (ticked when every bar is locked), Option-drag windows to Spaces ✓ (off by default), Show apps on hover ✓ (on by default), Launch at login, Manage displays and spaces, Setup check…, Refresh now, Help › (Current release, User manual), version line "no network access", Quit. |

Keyboard: the bars take no keyboard input (they never take focus, by design, so they can't steal your typing). The Manage and manual windows support Command-Z, Shift-Command-Z, Command-W and Command-M as described above.

## 3.4 Setup check

Four lines, each ✓ or ✕/! with the exact place to fix it:
1. Accessibility permission (needed only to press the Switch to Desktop shortcuts).
2. Switch to Desktop shortcuts on for every desktop you have (lists the ones that are off).
3. "Displays have separate Spaces" (informational; both settings work).
4. Reading the Space list works (time of last successful read).

Button "Open System Settings" opens the relevant pane (Accessibility or Keyboard) using Apple's `x-apple.systempreferences:` URL. No other URLs exist in the app.

## 3.5 First run

1. App starts, a bar appears top-centre of each display, the menu bar icon appears.
2. Spaces and highlights work immediately (reading needs no permission).
3. First click on a tile: if Accessibility isn't granted, macOS shows its own prompt, and the bar shows the amber **!**. Nothing else is asked for.

## 3.6 Coexistence

- **Mission Control:** the bar stays put and is not shown as a window in the spread.
- **Stage Manager:** the bar never becomes a stage; clicking it doesn't change the active stage.
- **Dock / Cmd-Tab:** the app has no Dock icon and is not in Cmd-Tab (menu-bar app), except while the Manage or manual window is open.
- **Full-screen apps:** the bar also shows over full-screen apps; hide it from the menu if it's in the way.
