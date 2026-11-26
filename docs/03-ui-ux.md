# 3. UI and UX

The Spaces live in the macOS menu bar as one status item. The setup check is a standard macOS alert, and failure messages appear in a small panel under the tiles.

## 3.1 The menu bar item

```
Menu bar, two displays, three logical spaces (Home, Music, Tech) and a full-screen app:
  … [1][2][3]   [FS]   [4][5]  !   🔋 Wi-Fi  Sat 7 Nov 17:20
    └ logical ┘  └ FS ┘ └ unplugged display (dimmed) ┘
```

- One status item holding a small square tile per logical space (Spaces with the same name on different displays; 16 pt in a 22 pt menu bar, 18 pt beside the notch), 3 pt apart, numbered 1, 2, 3 … in the order the names first appear (main display first, Mission Control order).
- Then the full-screen app Spaces (dashed outline and "FS"), 9 pt away, each switching only its own display.
- Spaces of an unplugged display that macOS moved onto a connected display come last as a separate group, 6 pt away, drawn dimmed; each switches only itself.
- Amber **!** after the tiles only when setup needs attention (or the Space list can't be read).
- Drawn by the app in the menu bar's own light or dark look. Command-drag moves it along the menu bar; the position is remembered (`autosaveName`). It can't be dragged out of the menu bar.
- Space names appear on hover: in the apps column when "Show apps on hover" is on, otherwise as each tile's tooltip.

### Fallback bar

macOS decides whether a status item is on screen: it hides items that don't fit (a crowded menu bar, the notch), hides the whole menu bar over full-screen apps or when it's set to hide automatically, and lets the user switch items off in System Settings › Menu Bar. No app can force its item to stay visible.

So whenever the item has been off screen for 1 s (its window isn't visible, is occluded, or isn't on any screen; checked on every occlusion change and every 2 s), a small floating bar with the same tiles appears, centred at the top of the main display, just under the menu bar (or at the very top when the menu bar is hidden). It is a non-activating panel on every Space, also over full-screen apps, and behaves exactly like the item. It hides as soon as the item is back. Menu: "Floating bar when the menu bar item is hidden" (on by default).

## 3.2 Highlighting

Changed 26 Nov 2026 (logical spaces) from the blue focused/current pair:

| State | Look |
|---|---|
| Logical space shown on every display that has it (or a single Space that's showing) | Solid orange (`systemOrange`), black bold number |
| Logical space shown on only some displays (e.g. after an Option-click) | Pale orange fill (35 %), orange ring, bold number |
| Other tiles | No fill, outline in the menu bar's text colour |
| Unplugged display's Spaces | As above, dimmed |
| Switch failed | Red ring for 3.5 s + message naming the display |
| Option-Control drag: tile under the held window | Thick ring in the text colour (switches after 0.4 s) |

Colour is never the only signal: current tiles have a bold number, and VoiceOver reads the current Spaces in the item's label. Per-tile VoiceOver access is in the Manage window.

## 3.3 Interactions

| Action | Result |
|---|---|
| Click a tile | Every display that has a Space in that logical space switches to it, one after another, the clicked display last (it keeps the focus), when the button is let go (within half a second, without moving). Pressing and holding doesn't switch. The tile turns orange as soon as macOS confirms. |
| Option-click a tile | Only the display whose menu bar (or floating bar) was clicked switches. If it has no Space in that logical space, a short message says so. |
| Right-click or Control-click the tiles, or click in a gap between groups | The menu. When a tile was right-clicked, the menu starts with Rename "name"…. |
| Click **!** | Setup check window. |
| Command-drag the item | Moves it along the menu bar (macOS's own behaviour); remembered. |
| Rest the pointer on a tile | After 0.35 s a column appears under the tile: the Space's full name, then each app with a window there (icon and name), front-most first, up to 12 then "+N more", or "No windows". It stays open while the pointer is on the tile or on the column, and disappears 0.25 s after the pointer leaves both, or when you click. Each app row glows under the pointer; clicking it switches to that Space and brings the app to the front. The column replaces the tile's tooltip. |
| Grab a window, then hold Option and Control and drag the pointer onto a tile (when "Option-Control-drag windows to Spaces" is on) | The tile under the pointer gets a thick ring and, after 0.4 s, the display under the pointer switches to its Space in that logical space with the window still in your hand. Let go to drop it there. Only that display switches; a tile whose logical space has no Space there doesn't react. Works on the menu bar item and on the fallback bar. |
| Menu › Manage displays and spaces | A normal window (close, minimise, resize; Dispaces shows in the Dock while it's open), shown on every desktop. Connected displays form a grid: a heading per logical space ("1 Home", coloured like the menu bar tile), one row per display (macOS display order) with that display's Space in each column or a dashed "Not assigned – <display>" cell, then its full-screen Spaces. Click a heading: every display switches; click a Space: only its display. Hover shows apps; after a switch the window stays in front with the focus. Double-click or right-click a heading to rename every Space in the column, a Space to rename just it (it moves to the column with that name), a display name to rename the display. Drag a Space onto "Not assigned" in its own row (it lights up) to give it that column's name. Disconnected displays follow (dashed border, "last connected" in the name's tooltip, Forget button); drag one of their Spaces onto the row of the display it's on now to move it into that display's group (grouping only). Command-Z undoes renames, drags and Forget, Shift-Command-Z redoes them (until the window closes). Updates live. |
| Menu › Help › Current release | An alert with the version and what's in this release; "Open User Manual" opens the manual. |
| Menu › Help › User manual | A normal, read-only window with the user manual (built into the app, same text as docs/08-user-manual.md); text can be selected and copied. Command-W closes it, Command-M minimises it (also in the Manage window). |
| The menu | (Rename "name"… when a tile was right-clicked), Floating bar when the menu bar item is hidden ✓ (on by default), Show apps on hover ✓ (on by default), Option-Control-drag windows to Spaces ✓ (off by default), Launch at login, Manage displays and spaces, Setup check…, Refresh now, Help › (Current release, User manual), version line "no network access", Quit. |

Keyboard: the tiles take no keyboard input (they never take focus, by design, so they can't steal your typing). The Manage and manual windows support Command-Z, Shift-Command-Z, Command-W and Command-M as described above.

## 3.4 Setup check

Four lines, each ✓ or ✕/! with the exact place to fix it:
1. Accessibility permission (needed only to press the Switch to Desktop shortcuts).
2. Switch to Desktop shortcuts on for every desktop you have (lists the ones that are off).
3. "Displays have separate Spaces" (informational; both settings work).
4. Reading the Space list works (time of last successful read).

Button "Open System Settings" opens the relevant pane (Accessibility or Keyboard) using Apple's `x-apple.systempreferences:` URL. No other URLs exist in the app.

## 3.5 First run

1. App starts and its tiles appear in the menu bar (new items start at the left end of the status area; Command-drag them towards the clock so macOS hides them last).
2. Spaces and highlights work immediately (reading needs no permission).
3. First click on a tile: if Accessibility isn't granted, macOS shows its own prompt, and the amber **!** appears after the tiles. Nothing else is asked for.

## 3.6 Coexistence

- **Mission Control:** the menu bar item is part of the menu bar; the fallback bar stays put and is not shown as a window in the spread.
- **Stage Manager:** clicking the tiles never creates a stage or changes the active stage.
- **Dock / Cmd-Tab:** the app has no Dock icon and is not in Cmd-Tab (menu-bar app), except while the Manage or manual window is open.
- **Full-screen apps and an auto-hiding menu bar:** the menu bar, and the item with it, slides away; the fallback bar stands in after a second and goes away when the menu bar comes back. Turn the fallback off in the menu if it's in the way.
- **Crowded menu bar or the notch:** macOS hides the items furthest from the clock first; the fallback bar stands in.
