# 1. Requirements analysis

Dispaces (formerly Spaces Bar) v0.1. Written 19 Oct 2026 for a user on macOS 27.0.1 who uses Spaces, Mission Control, Stage Manager and the Dock.

Priorities, in order: **security** (no breaches, no data loss) > **reliability** > **simplicity**. Every trade-off below is decided by that order.

## 1.1 Functional requirements

| ID | Requirement (as asked) | Interpretation and acceptance criteria |
|---|---|---|
| F1 | Works in a widget mode | Small, always-available, widget-like bar that floats over the desktop on every Space. See §1.4: a real WidgetKit widget cannot meet F6, N1. |
| F2 | Small horizontal widget divided into areas, one per display | One horizontal bar per connected display, shown only on that display (changed 20 Oct 2026; v0.1 had one bar with an area per display). Each bar starts with a small control section (show/hide Spaces, lock position, refresh), then the display's name, then its Spaces. Each bar can be resized by dragging its edges and locked on its own. |
| F3 | Each area divided into Spaces; each Space is a small rectangle | One tile (≈64×26 pt) per Space, in Mission Control order. Tile shows the desktop number and name. Full-screen app Spaces are shown with a dashed outline and "FS" instead of a number. |
| F4 | On a display only its own Spaces are visible | Tiles are grouped by the display that owns the Space. When "Displays have separate Spaces" is off, macOS has one shared list; one bar labelled "All displays" is shown on the main display. |
| F5 | Displays and Spaces can be named | Right-click or double-click a display label or tile → Rename. Max 24 characters. Empty name = default ("Desktop N", or the macOS display name). Names survive reboots and display re-plugging. |
| F6 | The widget displays the names | Names shown on tiles and labels; truncated with an ellipsis if too long, full name in the tooltip. |
| F7 | Click a Space → macOS navigates to it | One click switches that display to that Space. The app verifies the switch happened; if not, it retries once and then tells the user exactly why (missing permission, shortcut turned off). |
| F8 | Current Space highlighted | Each display has its own current Space. Current Space on the display you are using: solid blue. Current Space on other displays: outlined. |
| F9 | Option-drag a window to a Space (opt-in, added 20 Oct 2026) | Off until the user ticks "Option-drag windows to Spaces" in the menu. The user holds Option (before or after grabbing a window) and drags the window onto a desktop tile on any display's bar. The bar glows yellow while the pointer is over it; the tile under the pointer turns yellow, and after resting there for 0.4 s the app switches that display to that Space, so macOS carries the held window along. The user then lets go. The app never reads, moves or clicks windows itself. Full-screen Space tiles don't arm. |
| F10 | Apps on a Space shown on hover (added 20 Oct 2026) | Resting the pointer on a tile for 0.35 s shows a column under it: the Space's full name, then one row (icon and name) per app with a window on that Space, front-most first, up to 12 plus "+N more". Read fresh on every hover; nothing is stored. Menu: "Show apps on hover" (on by default). App names and icons only, never window titles, so no Screen Recording permission. The column stays open while the pointer is on it; each app row glows under the pointer, and clicking it switches to that Space and brings the app to the front (as a Dock click would). |
| F11 | Disconnected displays keep their Spaces together (added 20 Oct 2026) | The app remembers which Spaces belong to which display. When a display is unplugged, macOS moves its Spaces onto a connected display; the app can't prevent that, but keeps them grouped under the unplugged display's name: on the bar they follow the host display's own Spaces as a separate, dimmed group, and they don't join the host display in the app's memory. Menu "Manage displays and spaces" opens a normal window (close, minimise, resize) showing a copy of every display's bar: connected displays first in macOS's display order (menu-bar display first), then disconnected ones, each with a Forget button. All name cells share one width and all Space cells another. Clicking a Space switches to it and hovering shows its apps, as on the bars; after the switch the window keeps the focus (21 Oct 2026). A disconnected display's Space can be dragged onto the bar of the connected display it's on now, which moves it into that display's group. Moving only changes the app's grouping (21 Oct 2026): macOS gives apps no way to move a Space to another display, so it can only go to the display macOS already put it on. Command-Z / Shift-Command-Z undo and redo moves, Forget and the first-Space setting while the window is open. A "Show first Space" checkbox next to each display in the window shows or hides that display's first Space, on its bar and in the window, connected or not; it is on for every display by default (21 Oct 2026, built-in and external alike). The window shows on every desktop. Not kept: grouping after a Mac restart for a display's first desktop (macOS gives it no lasting id), and when shared Spaces ("Displays have separate Spaces" off) is used. |
| F12 | Help (added 21 Oct 2026) | Menu "Help" holds "Current release" (version and what's in this release) and "User manual" (a read-only window with how to use the app, navigate, shortcuts and features). The manual is built into the app, works offline and matches docs/08-user-manual.md. |
| F13 | Fresh bars after display changes (added 22 Oct 2026) | About 1 s after a display is connected or disconnected (not on resolution or arrangement changes), the app throws all bars away and builds them again from a fresh read, the same as relaunching it, inside the running app. No process is launched and no other app (such as the Dock) is restarted. |

## 1.2 Non-functional requirements

| ID | Requirement | Interpretation and acceptance criteria |
|---|---|---|
| N1 | Refreshed in the background, every 60 s (was ~10 s until 20 Oct 2026) | Event-driven refresh on every Space change, display change and wake from sleep (instant, typically < 100 ms). Plus a 60-second timer as a safety net, and a Refresh button on each bar. Reading the Space list costs < 1 ms. |
| N2 | Compliant with macOS 26 and 27 | Deployment target macOS 26.0. Built with the Xcode 26 SDK on GitHub's `macos-26` runner. Tested by hand on macOS 27.0.1. No API deprecated in 26 is used. |
| N3 | Security: no breaches | No network code at all, no third-party dependencies, no listening sockets, no IPC, no scripts. Smallest permission set (Accessibility only). Hardened runtime. See [04-security.md](04-security.md). |
| N4 | Security: no data loss | The app writes only its own preferences (names, bar position). It never reads, moves, closes or deletes windows, apps or files. A corrupt preferences file falls back to defaults instead of crashing. |
| N5 | Reliability over fancy | No animations beyond the system's own. Defensive parsing of the private Space list. Verification after every switch. A visible warning (amber "!") when setup is incomplete, instead of failing silently. |
| N6 | Simplicity | One small native app, ≈1,750 lines of Swift including comments, no Xcode project file, no dependencies, one build script. |
| N7 | Coexist with Mission Control, Stage Manager, Dock | Bar is a non-activating panel: clicking it never steals focus, never creates a Stage Manager stage, does not appear in the Dock or Cmd-Tab, and is excluded from Mission Control's window spread. |

## 1.3 Assumptions (please correct if wrong)

- A1. Up to 16 desktops in total. macOS has "Switch to Desktop N" shortcuts only for 1–16. Desktops beyond 16, and full-screen app Spaces, are reached by pressing "Move one Space left/right" the right number of times. That works but is slower and shows each step.
- A2. You are fine with turning on the "Switch to Desktop N" keyboard shortcuts (System Settings › Keyboard › Keyboard Shortcuts › Mission Control). macOS has no public API to change Space; pressing its own shortcut is the most reliable method that doesn't need SIP disabled.
- A3. You are fine with granting Accessibility permission. It is required to press those shortcuts programmatically. The app uses it for nothing else, and the code is small enough to verify that.
- A4. Single user Mac, app installed in /Applications, built from source you can read.
- A5. No App Store distribution and no Apple Developer account (so no notarisation). The app is ad-hoc signed by CI or by you.

## 1.4 Can it be a real macOS widget (WidgetKit)?

**No, not without breaking F7 and N1.** Checked against Apple's WidgetKit documentation ("Keeping a widget up to date"):

- **Refresh:** WidgetKit gives a frequently viewed widget about 40–70 reloads per day, roughly one every 15–60 minutes, with timeline entries "at least about 5 minutes apart". A 10-second refresh is impossible. The app could push reloads on every Space change, but those still count against the budget and get throttled.
- **Switching:** widget buttons run an App Intent inside a sandboxed extension. Sandboxed code can't post keyboard events, and Accessibility permission can't be granted to a widget extension. So a widget can't switch Spaces by itself; it would have to launch the main app first, which steals focus and is slow.
- **Visibility:** desktop widgets sit behind your windows. You'd only see them on an empty desktop or after "Show Desktop".

**Decision (overridable):** a native app with a small floating, widget-like bar (`NSPanel`) plus a menu bar icon. It looks and behaves like a widget, stays visible on every Space, refreshes instantly, and can switch reliably. If you'd still like a WidgetKit widget as an extra read-only view later, it can be added in v0.2 without changing the core.

## 1.5 Out of scope for v0.1

- Creating, deleting or reordering Spaces (needs private write APIs or Dock scripting; risky).
- Moving windows between Spaces.
- Showing window thumbnails or app icons inside tiles (needs Screen Recording permission; not worth the privacy cost).
- Auto-update (deliberately excluded: updates come only from code you review).
- App Store, notarisation, localisation.
