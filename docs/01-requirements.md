# 1. Requirements analysis

Dispaces v0.1, for macOS 26 and 27, for people who use Spaces, Mission Control, Stage Manager and the Dock.

Priorities, in order: **security** (no breaches, no data loss) > **reliability** > **simplicity**. Every trade-off below is decided by that order.

## 1.1 Functional requirements

| ID | Requirement | Interpretation and acceptance criteria |
|---|---|---|
| F1 | Works in a widget mode | Always available in the macOS menu bar, on every Space (changed 7 Nov 2026 from floating bars at the owner's request). Where macOS doesn't show the menu bar item, a small floating bar with the same tiles stands in (F14). See §1.4: a real WidgetKit widget cannot meet F7 and N1. |
| F2 | Small horizontal widget divided into areas, one per display | One menu bar status item, spread horizontally. Each display's Spaces form a group, with a wider gap between groups, ordered as the displays are arranged left to right. |
| F3 | Each area divided into Spaces; each Space is a small square | One square tile (16 pt in a 22 pt menu bar) per Space, in Mission Control order, showing its desktop number. Full-screen app Spaces are shown with a dashed outline and "FS". |
| F4 | Spaces grouped by display | Tiles are grouped by the display that owns the Space. When "Displays have separate Spaces" is off, macOS has one shared list, shown as one group. |
| F5 | Displays and Spaces can be named | Right-click a tile › Rename, or rename Spaces and displays in Manage displays and spaces (double-click or right-click). Max 24 characters. Empty name = default ("Desktop N", or the macOS display name). Names survive reboots and display re-plugging. |
| F6 | The widget displays the names | Hovering a tile shows its Space's name: in the apps column (F10) or, with that off, as a tooltip. Display names are shown in the Manage window. |
| F7 | Click a Space → macOS navigates to it | One click switches that display to that Space. The app verifies the switch happened; if not, it retries once and then tells the user exactly why (missing permission, shortcut turned off). |
| F8 | Current Space highlighted | Each display has its own current Space. Current Space on the display you are using: solid blue. Current Space on other displays: outlined. |
| F9 | Option-drag a window to a Space (opt-in) | Off until the user ticks "Option-drag windows to Spaces" in the menu. The user holds Option (before or after grabbing a window) and drags the pointer onto a desktop tile in the menu bar (or on the fallback bar). The tile under the pointer turns yellow, and after resting there for 0.4 s the app switches that display to that Space, so macOS carries the held window along. The user then lets go. The app never reads, moves or clicks windows itself. Full-screen Space tiles don't arm. |
| F10 | Apps on a Space shown on hover | Resting the pointer on a tile for 0.35 s shows a column under it: the Space's full name, then one row (icon and name) per app with a window on that Space, front-most first, up to 12 plus "+N more". Read fresh on every hover; nothing is stored. Menu: "Show apps on hover" (on by default). App names and icons only, never window titles, so no Screen Recording permission. The column stays open while the pointer is on it; each app row glows under the pointer, and clicking it switches to that Space and brings the app to the front (as a Dock click would). |
| F11 | Disconnected displays keep their Spaces together | The app remembers which Spaces belong to which display. When a display is unplugged, macOS moves its Spaces onto a connected display; the app can't prevent that, but keeps them grouped under the unplugged display's name: in the menu bar they follow the host display's own Spaces as a separate, dimmed group, and they don't join the host display in the app's memory. Menu "Manage displays and spaces" opens a normal window (close, minimise, resize) showing a bar for every display: connected displays first in macOS's display order (menu-bar display first), then disconnected ones, each with a Forget button. All name cells share one width and all Space cells another. Clicking a Space switches to it and hovering shows its apps, as in the menu bar; after the switch the window keeps the focus. A disconnected display's Space can be dragged onto the bar of the connected display it's on now, which moves it into that display's group. Moving only changes the app's grouping: macOS gives apps no way to move a Space to another display, so it can only go to the display macOS already put it on. Command-Z / Shift-Command-Z undo and redo moves, Forget and the first-Space setting while the window is open. A "Show first Space" checkbox next to each display in the window shows or hides that display's first Space, in the menu bar and in the window, connected or not; it is on for every display by default, built-in and external alike. The window shows on every desktop. Not kept: grouping after a Mac restart for a display's first desktop (macOS gives it no lasting id), and when shared Spaces ("Displays have separate Spaces" off) is used. |
| F12 | Help | Menu "Help" holds "Current release" (version and what's in this release) and "User manual" (a read-only window with how to use the app, navigate, shortcuts and features). The manual is built into the app, works offline and matches docs/08-user-manual.md. |
| F13 | Fresh tiles after display changes | About 1 s after a display is connected or disconnected (not on resolution or arrangement changes), the app throws all passing state away and draws the tiles again from a fresh read, the same as relaunching it, inside the running app. No process is launched and no other app (such as the Dock) is restarted. |
| F14 | Always visible | The item is narrow, can't be dragged out of the menu bar, and remembers where the user Command-drags it. macOS can still hide it (crowded menu bar or notch, full-screen apps, auto-hiding menu bar, System Settings › Menu Bar), so after it has been off screen for 1 s a small floating bar with the same tiles appears at the top centre of the main display and works the same way, until the item is back. On by default; menu "Floating bar when the menu bar item is hidden". |

## 1.2 Non-functional requirements

| ID | Requirement | Interpretation and acceptance criteria |
|---|---|---|
| N1 | Refreshed in the background | Event-driven refresh on every Space change, display change and wake from sleep (instant, typically < 100 ms). Plus a 60-second timer as a safety net, and Refresh now in the menu. Reading the Space list costs < 1 ms. |
| N2 | Compliant with macOS 26 and 27 | Deployment target macOS 26.0. Built with the Xcode 26 SDK on GitHub's `macos-26` runner. Checked by hand on macOS 27 (see [07-pen-test-report.md](07-pen-test-report.md)). No API deprecated in 26 is used. |
| N3 | Security: no breaches | No network code at all, no third-party dependencies, no listening sockets, no IPC, no scripts. Smallest permission set (Accessibility only). Hardened runtime. See [04-security.md](04-security.md). |
| N4 | Security: no data loss | The app writes only its own preferences (names, settings, which Spaces belong to which display). It never reads, moves, closes or deletes windows, apps or files. A corrupt preferences file falls back to defaults instead of crashing. |
| N5 | Reliability over fancy | No animations beyond the system's own. Defensive parsing of the private Space list. Verification after every switch. A visible warning (amber "!") when setup is incomplete, instead of failing silently. |
| N6 | Simplicity | One small native app, ≈4,400 lines of Swift including comments, no Xcode project file, no dependencies, one build script. |
| N7 | Coexist with Mission Control, Stage Manager, Dock | A menu bar status item plus, only when needed, a non-activating fallback panel: clicking either never steals focus, never creates a Stage Manager stage, does not appear in the Dock or Cmd-Tab, and the panel is excluded from Mission Control's window spread. |

## 1.3 Constraints

- C1. macOS has "Switch to Desktop N" shortcuts only for desktops 1–16. Desktops beyond 16, and full-screen app Spaces, are reached by pressing "Move one Space left/right" the right number of times, only on the display under the pointer. That is slower and shows each step.
- C2. The "Switch to Desktop N" keyboard shortcuts must be turned on (System Settings › Keyboard › Keyboard Shortcuts › Mission Control). macOS has no public API to change Space; pressing its own shortcut is the most reliable method that doesn't need SIP disabled.
- C3. Accessibility permission is required to press those shortcuts programmatically. The app uses it for nothing else, and the code is small enough to verify that.
- C4. Designed for a single-user Mac with the app installed in /Applications, built from source or downloaded from a release.
- C5. No App Store distribution and no notarisation. The app is ad-hoc signed by CI or by whoever builds it.

## 1.4 Can it be a real macOS widget (WidgetKit)?

**No, not without breaking F7 and N1.** Checked against Apple's WidgetKit documentation ("Keeping a widget up to date"):

- **Refresh:** WidgetKit gives a frequently viewed widget about 40–70 reloads per day, roughly one every 15–60 minutes, with timeline entries "at least about 5 minutes apart". Updating within a second of every Space change is impossible. The app could push reloads on every Space change, but those still count against the budget and get throttled.
- **Switching:** widget buttons run an App Intent inside a sandboxed extension. Sandboxed code can't post keyboard events, and Accessibility permission can't be granted to a widget extension. So a widget can't switch Spaces by itself; it would have to launch the main app first, which steals focus and is slow.
- **Visibility:** desktop widgets sit behind your windows. You'd only see them on an empty desktop or after "Show Desktop".

**Decision:** a native app whose Spaces live in the menu bar as small square tiles (since 7 Nov 2026; before that a floating bar per display), with a floating fallback bar when macOS hides the item. It stays visible on every Space, refreshes instantly, and can switch reliably. A WidgetKit widget could be added later as an extra read-only view without changing the core.

## 1.5 Out of scope for v0.1

- Creating, deleting or reordering Spaces (needs private write APIs or Dock scripting; risky).
- Moving windows between Spaces by the app itself (Option-drag, F9, only lets macOS carry a window the user is holding).
- Window thumbnails or titles (need Screen Recording permission; not worth the privacy cost).
- Auto-update (deliberately excluded: updates come only from code the user can review).
- App Store, notarisation, localisation.
