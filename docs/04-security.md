# 4. Security: threat model, controls and pen-test plan

## 4.1 What there is to protect

| Asset | Why it matters |
|---|---|
| Your keyboard and input | The app holds **Accessibility** permission, which allows posting keystrokes. If the app were hijacked, that power could type into other apps. This is the main risk. |
| Your windows, apps and files | Data loss would mean windows "lost" on hidden Spaces, or files changed. |
| The app binary and its build | A tampered build would inherit the Accessibility permission. |
| Your Space and display names | Low value, but should not leak (they can hint at what you work on). |

## 4.2 Attack surface (v0.1)

| Surface | Present? |
|---|---|
| Network (outgoing or listening) | **No.** No networking code, no network entitlement needed, verified on the binary in CI. |
| IPC: XPC, Mach services, Apple Events, URL schemes, distributed notifications | **No.** The app registers none and accepts none. |
| Files read | Own preferences; `com.apple.symbolichotkeys` (read-only). |
| Files written | Own preferences only (`~/Library/Preferences/io.github.kosrodka.SpacesBar.plist`), now including `displayMemory`: per display its id, name, last-connected time and its Spaces' keys, ids and names (validated on read, capped at 16 displays × 64 Spaces). |
| Processes launched | **None.** |
| Scripts | **None** (no AppleScript, no shell, no JavaScript). |
| Event taps (reading keyboard/mouse) | **None.** The app only *posts* events; it never listens to your typing. With "Option-drag windows to Spaces" on, it samples the pointer position, which mouse buttons are down and which modifier keys are held (public `NSEvent.mouseLocation`, `pressedMouseButtons`, `modifierFlags`) 20 times a second. No key codes, no typed text, no event tap or global monitor, no permission. |
| Private API | Three read-only calls: `CGSCopyManagedDisplaySpaces` (the Space list), `CGSGetActiveSpace` (which Space has focus) and `CGSCopySpacesForWindows` (which Space a window is on, for the hover icons). |
| Other apps' windows | Read only, on hover, in `SpaceAppsReader.swift`: the public window list's window number, owning process, layer, alpha and size, to work out which apps are on a Space. Never titles or contents (so no Screen Recording permission), never stored, never changed. Nothing else touches windows: Option-drag works because macOS itself carries a window you are holding when the Space changes. |
| User input | Names typed into the rename dialog. |
| Third-party code | **None.** |

## 4.3 Threats (STRIDE) and controls

| # | Threat | Control |
|---|---|---|
| T1 | **Code injection into the app** to borrow its Accessibility permission (`DYLD_INSERT_LIBRARIES`, malicious plugin) | Hardened runtime on (`--options runtime`), no entitlements that weaken it (no `disable-library-validation`, no `allow-dyld-environment-variables`, no `get-task-allow`). App loads no plugins or bundles. CI fails if the binary isn't signed this way. |
| T2 | **Tampered binary** (swapped build, CI compromise) | Build only from source you can read; GitHub Actions pinned to full commit SHAs; SHA-256 published with each build and printed in the CI log and backed by a build provenance attestation; building from source on your Mac remains the strongest option; macOS TCC ties the Accessibility grant to the code signature, so a swapped binary loses the permission. |
| T3 | **Keystroke abuse** (the app made to type something other than a Space shortcut) | `KeyPoster` can only post key codes that come from your own Mission Control shortcut settings (IDs 79, 81, 118–133) or Apple's documented defaults; anything else is rejected. One switch at a time; clicks during a switch are ignored; at most 32 key presses per switch. |
| T4 | **Malicious names** (very long, control characters, right-to-left override spoofing, format strings) | `NameStore.sanitize`: strip control characters and Unicode bidi overrides (U+202A–U+202E, U+2066–U+2069), trim, cut to 24 characters (by grapheme). Names are only ever displayed as plain text; never interpreted. Unit-tested. |
| T5 | **Tampered preferences file** (another process writes junk) | On load, every value is type-checked and re-sanitised; invalid entries are dropped; at most 256 entries; invalid bar position falls back to default. Any local process running as you could already do worse, so this is about not crashing, not about trust. |
| T6 | **Private API changes shape** in a macOS update | Parser checks every type, skips unknown entries, never force-unwraps; if nothing usable is returned the bar shows "Can't read Spaces" and the amber **!**. Unit tests cover malformed input. |
| T7 | **Data loss**: windows stranded or files changed | The app never moves, closes or hides windows and never touches files except its own preferences. Switching uses macOS's own shortcuts, so macOS's own logic decides what's shown. Rejected `CGSManagedDisplaySetCurrentSpace` for exactly this reason. |
| T8 | **Information disclosure** of names | Names stay in the app's own preferences; no logging of names; no network. Unified log messages contain only counts and error codes. |
| T9 | **Supply chain** (dependency or CI) | Zero dependencies. Workflows use least privilege (`permissions: contents: read` by default), no secrets, no `pull_request_target`, no self-hosted runners. Dependabot watches only GitHub Actions pins. CodeQL scans the Swift code. |
| T10 | **Denial of service** (flood of Space-change notifications, display hot-plugging) | Refreshes are coalesced (at most one read per 100 ms); redraw only when the snapshot actually changed. |
| T11 | **Elevation** | App runs as you, never asks for admin rights, installs no helpers, launch agents or daemons (launch at login uses Apple's `SMAppService.mainApp`, which you can see and turn off in System Settings › General › Login Items). |
| T12 | **Unintended switch** while dragging (Option-drag) | Off by default; needs the left button and Option held together and the pointer resting 0.4 s on a desktop tile; fires once per tile visit; presses only the allowed Switch to Desktop shortcut, the same as a click. |
| T13 | **Information disclosure** (hover icons reveal which apps are open) | Shown only on your own screen, only while you hover; read fresh each time, never stored or logged; only app names and icons, never window titles or contents. Can be turned off in the menu. |
| T14 | **Unintended app activation** (apps column) | Only on a click on an app row; brings that app to the front through the public `NSRunningApplication` API, as a Dock click does; never quits, hides or changes the app or its windows. Only `AppActivator` may do it (`source-check.sh`). |

## 4.4 Security controls checklist (each one is checked somewhere)

| ID | Control | Where checked |
|---|---|---|
| C1 | No networking symbols in the binary (`socket`, `connect`, `URLSession`, `NWConnection`, `CFStream`, `getaddrinfo`…) | CI `security-check.sh`, pen test P1 |
| C2 | Hardened runtime flag set, no entitlements | CI `security-check.sh`, pen test P3 |
| C3 | No `NSAppleScript`, `Process`/`NSTask`, `system`, `popen`, `dlopen`, `NSBundle load` | CI `security-check.sh` |
| C4 | No event taps (`CGEventTapCreate`) | CI `security-check.sh` |
| C5 | Only allow-listed hotkey IDs posted | Unit tests (`SwitchPlannerTests`) |
| C6 | Names sanitised | Unit tests (`NameStoreTests`), pen test P5 |
| C7 | Preferences validated | Unit tests, pen test P6 |
| C8 | Parser never crashes on malformed data | Unit tests (`SnapshotParserTests`) incl. randomised fuzz test |
| C9 | Actions pinned to SHAs, least-privilege workflows | Review + Dependabot |
| C10 | Build integrity: SHA-256 per build, pinned actions, provenance when public | Release workflow, pen test P2 |
| C12 | Forbidden APIs never appear in source | CI `source-check.sh` |
| C13 | No window access, mouse-event posting, cursor warping or global event monitors (`AXUIElement`, `CGEventCreateMouseEvent`, `mouseEventSource`, `CGWarpMouseCursorPosition`, `addGlobalMonitorForEvents`) | CI `source-check.sh`, pen test P13 |
| C14 | Window list read in one file only; window titles, screen capture and private window-changing calls never appear (`kCGWindowName`, `CGWindowListCreateImage`, ScreenCaptureKit, `CGSAddWindowsToSpaces`, `CGSSetWindow…`) | CI `source-check.sh`, pen test P14 |
| C15 | Other apps are brought to the front only by `AppActivator`; quitting, force-quitting or hiding apps never appears (`forceTerminate`, `.terminate()`, `.hide()`) | CI `source-check.sh`, pen test P15 |
| C11 | Static analysis | CodeQL (Swift) on every push |

## 4.5 Pen-test plan

Automated (run on every push by CI on a macOS 26 runner): C1–C8, C11, C12, plus a launch smoke test that fails if the app opens any socket.

Manual (on your Mac, macOS 27.0.1; ~20 minutes; exact commands in `docs/06-operations.md` §6.8):

| ID | Test | Pass when |
|---|---|---|
| P1 | **No network:** run the app, switch Spaces a few times, then `lsof -i -a -p $(pgrep -x SpacesBar)` and `nettop -p $(pgrep -x SpacesBar) -l 1` | No sockets listed, no traffic |
| P2 | **Integrity:** compare `shasum -a 256 SpacesBar.zip` to the release page and CI log (or build from source) | Hashes match |
| P3 | **Signature and hardening:** `codesign -dv --verbose=4` and `codesign -d --entitlements -` on the app | `flags=0x10000(runtime)`, no entitlements |
| P4 | **Library injection:** `DYLD_INSERT_LIBRARIES=/tmp/x.dylib /Applications/SpacesBar.app/Contents/MacOS/SpacesBar` | Library is ignored (hardened runtime strips DYLD vars) |
| P5 | **Hostile names:** rename a Space to 200 characters, to text containing U+202E, to `%@%n%s`, to emoji/combining characters | Stored ≤ 24 characters, overrides removed, displayed literally, no crash |
| P6 | **Corrupt preferences:** `defaults write io.github.kosrodka.SpacesBar spaceNames -string garbage`, also an array of 10,000 items, then relaunch | App starts with defaults, no crash |
| P7 | **Keystroke scope:** with TextEdit focused, click tiles quickly 20 times | Only Space switches happen; no characters typed into TextEdit |
| P8 | **Permission revoked mid-run:** remove Accessibility while running, click a tile | No crash; amber **!** and clear message |
| P9 | **Shortcut off:** turn off "Switch to Desktop 3", click tile 3 | Message names the shortcut to turn on; nothing else pressed |
| P10 | **Display hot-plug and sleep/wake:** unplug/replug the external display, sleep/wake | Bar redraws correct areas within a second, names kept |
| P11 | **Data loss check:** before/after a session of switching, compare window counts per app (`Window` menu) | Nothing closed, nothing missing |
| P12 | **Persistence check:** `sfltool dumpbtm \| grep -i spaces` after enabling/disabling Launch at login | Only the app itself is registered; nothing left after disabling |
| P13 | **Option-drag scope:** with the setting off, Option-drag a window over the bar; then turn it on, sweep a held window quickly across the tiles, then rest on one | Off: nothing happens. On: no switch while sweeping; one switch after resting; window arrives with its size and content unchanged; Option-clicking a tile without holding a window just switches, as a plain click does |
| P14 | **Hover icons scope:** hover tiles of several Spaces, then open System Settings › Privacy & Security › Screen Recording | Each column lists the right apps; no Screen Recording prompt; Dispaces is not in the Screen Recording list; windows unchanged |
| P15 | **Apps column clicks:** hover a tile, move into the column, hover each row, click one; repeat for a Space on another display | Rows glow one at a time; nothing happens on hover alone; a click shows that Space and brings only that app to the front; no app quits, hides or loses a window |

Results are recorded in `docs/07-pen-test-report.md`.
