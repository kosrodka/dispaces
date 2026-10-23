# 2. Technology and architecture

## 2.1 Options considered

### How the app gets the list of Spaces

| Option | Verdict |
|---|---|
| Public API | **None exists.** macOS has no public API that lists Spaces. |
| `CGSCopyManagedDisplaySpaces` (private, in SkyLight, re-exported by CoreGraphics), plus `CGSGetActiveSpace` to know which display you are using | **Chosen.** Read-only, returns every display with its Spaces and its current Space. Used by many Spaces tools (Spaceman, yabai, Amethyst, Hammerspoon) for over 10 years, and works on macOS 26 and 27. Risk: Apple could change it; mitigated by defensive parsing and a clear "can't read Spaces" warning instead of a crash. |
| `CGSCopySpacesForWindows` (private, read-only) with the public window list (`CGWindowListCopyWindowInfo`), for the hover icons (F10) | **Chosen.** macOS has no public way to ask which Space a window is on. Only window numbers and owning processes are used; titles would need Screen Recording and are never read. Lives in `SpaceAppsReader.swift` only. Alternative considered: remember the apps seen on each Space while it was showing (public only, but stale). |
| Screen-scraping Mission Control / Accessibility tree of the Dock | Fragile, slow, needs more permissions. Rejected. |

### How the app switches Space

| Option | Permissions | Reliability | Verdict |
|---|---|---|---|
| Post the user's own "Switch to Desktop N" shortcut as a keyboard event (`CGEvent`) | Accessibility | High: it is exactly what macOS does when you press the keys. Requires the shortcut to be on. | **Chosen** for desktops 1–16. |
| Post "Move one Space left/right" N times (`CGEvent`) | Accessibility | Medium: visible steps, acts on the display under the mouse. | **Fallback** for full-screen Spaces and desktops > 16, only on the display under the pointer (with one bar per display, that is always the display whose bar was clicked). |
| AppleScript `tell System Events to key code …` (what Spaceman does) | Accessibility + Automation | Lower: slower (spawns Apple Events), a second permission, can time out. | Rejected. |
| Private `CGSManagedDisplaySetCurrentSpace` | none | **Low:** changes the picture but the Dock and window focus don't follow; windows end up on the wrong Space. | Rejected (data-loss-adjacent: windows appear "lost"). |
| yabai-style Dock injection | **SIP disabled** | High | Rejected: disabling System Integrity Protection is a major security downgrade. |
| Synthetic trackpad swipe events | Accessibility | Medium; depends on gesture settings | Rejected. |

The keyboard-shortcut method has one more advantage: the app can **read** your shortcut settings (`com.apple.symbolichotkeys`, read-only) and say before a click if a shortcut is off, instead of failing silently.

### UI technology

| Option | Verdict |
|---|---|
| WidgetKit desktop widget | Can't refresh faster than ~every 15 min, can't post keystrokes (sandbox), hidden behind windows. Rejected, see 01-requirements §1.4. |
| Menu bar only (like Spaceman) | Fine, but the menu bar is crowded and tiles with names don't fit well with notched MacBook displays. Kept as a small icon for the app menu only. |
| Floating `NSPanel`, AppKit views | **Chosen.** Small, always visible, non-activating (never steals focus), on all Spaces. Plain AppKit views give exact control over single-click vs. double-click vs. right-click, with no SwiftUI tap-gesture delay. |

### Language, build and dependencies

| Choice | Why |
|---|---|
| Swift 6 toolchain (Swift 5 language mode), AppKit, Foundation, CoreGraphics, ServiceManagement | All Apple system frameworks. No third-party code, so nothing to vet but our own. |
| Swift Package Manager, no `.xcodeproj` | A `Package.swift` is 30 readable lines; an Xcode project file is thousands of opaque lines. Builds the same on CI and on any Mac with `swift build`. |
| One tiny C target for the private, read-only function declarations | Correct C calling convention and CoreFoundation ownership rules (`CF_RETURNS_RETAINED`) instead of Swift `@_silgen_name` hacks. If Apple removes a symbol, the build fails loudly on CI instead of crashing on your Mac. |
| `scripts/bundle.sh` wraps the binary into `Dispaces.app` | Writes Info.plist, signs with hardened runtime. About 60 lines of readable shell. |

## 2.2 Architecture

```
┌───────────────────────────── Dispaces.app (one process, no network) ────────────────────────────┐
│                                                                                                   │
│  AppKit layer (target: SpacesBar)                         Pure logic (target: SpacesCore)         │
│                                                                                                   │
│  AppDelegate ── owns everything, wires callbacks          Model        Snapshot / Display / Space │
│     │                                                     SnapshotParser  raw dictionaries → Model│
│     ├─ SpaceMonitor ── on change ─▶ BarController         NameStore    names, sanitising, JSON    │
│     │    • NSWorkspace activeSpaceDidChange               Hotkeys      parse symbolichotkeys      │
│     │    • screen parameters change, wake                 SwitchPlanner Space → keys to press     │
│     │    • 60 s timer (safety net)                                                                │
│     │    └─ SpaceReader ──▶ CGSPrivate (C) ──▶ CGSCopyManagedDisplaySpaces (read-only)            │
│     │                                                                                             │
│     ├─ BarController ── one DisplayBar (NSPanel) per display: controls, label, tiles; rename      │
│     │                                                                                             │
│     ├─ SpaceSwitcher ── plans with SwitchPlanner, posts CGEvents, verifies, retries once          │
│     │    └─ KeyPoster ──▶ CGEvent.post(.cghidEventTap)   (needs Accessibility)                    │
│     │                                                                                             │
│     ├─ Menu bar icon ── Show bars, Lock all bars, options, Manage window, Setup check, Help, Quit │
│     ├─ Setup check ── Accessibility granted? shortcuts on? "Displays have separate Spaces" on?    │
│     └─ Preferences ── UserDefaults (own domain only) via Names and BarLayout validation           │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Why the split:** everything that can be wrong in subtle ways (parsing the private data, numbering desktops, mapping to shortcuts, cleaning names) lives in `SpacesCore`, which uses only Foundation and has unit tests. The AppKit layer is thin glue. Bar geometry (keeping a bar on its display, edge resizing, fitting tiles into a bar) is in `SpacesCore/BarGeometry.swift` for the same reason; the AppKit floating panels (bars, apps column, messages) share one `FloatingPanel` base so they all stay non-activating.

## 2.3 Key flows

**Refresh**
1. Trigger: Space changed / displays changed / Mac woke / 60 s timer / Refresh button or "Refresh now".
2. `SpaceReader` calls `CGSCopyManagedDisplaySpaces` (< 1 ms).
3. `SnapshotParser` turns it into a `Snapshot`. Unknown or malformed entries are skipped, never force-unwrapped.
4. If the snapshot differs from the last one, `BarController` redraws: one bar per display, each placed on its own screen (saved offset from that screen's top-left, clamped to the visible area). Bars for unplugged displays are closed. Otherwise nothing happens.

**Switch (click on a tile)**
1. `SwitchPlanner` decides:
   - Desktop N (1–16) with its shortcut on → press that shortcut.
   - Full-screen Space or desktop > 16, on the display under the mouse → press "Move left/right a Space" k times.
   - Otherwise → don't press anything; explain why.
2. `KeyPoster` posts the key events with exactly the key code and modifiers stored in your shortcut settings.
3. `SpaceSwitcher` re-reads the Space list every 50 ms for up to 1 s. Success = that display's current Space is the target.
4. Not switched → one retry after 300 ms → still not switched → amber outline on the tile and a message with the exact fix.
5. Clicks while a switch is in progress are ignored, so fast clicking can't queue a storm of keystrokes.

**Rename**
Right-click or double-click → small dialog → name cleaned by `NameStore.sanitize` (trim, max 24 characters, control and text-direction override characters removed) → saved to the app's own preferences → bar redraws.

## 2.4 How names are remembered

| Thing | Key | Survives |
|---|---|---|
| Display | macOS display UUID (`CGDisplayCreateUUIDFromDisplayID`, same value as the Space list's "Display Identifier"); `Main` when Spaces span displays | Reboots, re-plugging, changing ports |
| Space | The Space's `uuid` from the Space list | Reboots, reordering Spaces |
| Space whose `uuid` is empty (macOS leaves it empty for the first desktop of a display) | display UUID + position, e.g. `…#1` | Reboots. Moves with position if you reorder |

Deleting a Space in Mission Control leaves its old name unused in preferences; it is ignored. Old entries are capped at 256 so the file can't grow forever.

## 2.5 Tech stack summary

| Layer | Choice |
|---|---|
| OS | macOS 26.0+ (built and tested on 26 in CI, checked by hand on 27) |
| Language | Swift (Swift 6 toolchain, Swift 5 language mode) |
| UI | AppKit (`NSPanel`, `NSView`, `NSStatusItem`, `NSAlert`) |
| System | CoreGraphics (`CGEvent`, window list, private read-only `CGS…` calls), AppKit (`NSRunningApplication` for the apps column), ServiceManagement (`SMAppService` for launch at login) |
| Storage | `UserDefaults`, own domain `io.github.kosrodka.SpacesBar` |
| Build | Swift Package Manager + `scripts/bundle.sh`, ad-hoc code signing with hardened runtime |
| Tests | XCTest (unit tests for `SpacesCore`), `scripts/security-check.sh` (binary checks) |
| CI/CD | GitHub Actions on `macos-26`, CodeQL for Swift, SHA-256 per build, Dependabot for Actions |
| Third-party dependencies | **none** |
