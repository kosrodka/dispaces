# Dispaces

The app's visible name is Dispaces. The bundle ID `io.github.kosrodka.SpacesBar`, the `SpacesBar` target and executable and `SpacesBar.app` keep the name SpacesBar so preferences, Space names and the Accessibility grant stay valid; don't rename them.

A small macOS menu-bar app that shows every Space per display in a floating bar and switches Space on click. Owner: Kamil Ośródka (kosrodka).

## Priorities (in this order)
1. Security: no breaches, no data loss.
2. Reliability over fancy.
3. Simplicity: less is more.

## Hard rules
- **No third-party dependencies.** Apple frameworks only.
- **No networking, scripts, process launching, dynamic loading or event taps.** `scripts/source-check.sh` and `scripts/security-check.sh` enforce this; never weaken them to make a change pass.
- Never add entitlements, never turn off the hardened runtime, never add auto-update.
- Only the Mission Control shortcuts in `HotkeyID` may ever be posted (`KeyPoster`).
- The app writes only its own preferences. Never touch the user's windows or files.
- Window list: only `SpaceAppsReader.swift` may read it (hover icons), and only each window's number, owning process, layer, alpha and size. Never titles or contents, never Screen Recording. `source-check.sh` enforces this.
- Other apps: only `AppActivator` (System.swift) may bring one to the front, and only when the user clicks it in the apps column. Never quit, hide or force-quit apps (`source-check.sh` enforces this).
- Option-drag (opt-in) only reads pointer position, mouse buttons and modifier flags via public `NSEvent` class properties and presses a Switch to Desktop shortcut; macOS carries the window the user is holding. No AX, no mouse events, no global monitors (`source-check.sh` enforces this).
- Private API: only the read-only `CGSMainConnectionID`, `CGSCopyManagedDisplaySpaces`, `CGSGetActiveSpace` and `CGSCopySpacesForWindows` (hover icons; approved by the owner on 20 Oct 2026). Don't add private write calls (e.g. `CGSManagedDisplaySetCurrentSpace`).
- The only regular windows are "Manage displays and spaces" (`ManageWindow.swift`) and the User manual (`HelpWindow.swift`), both `AppWindow`; the app shows in the Dock only while one is open. The manual text lives in `UserManual.swift` and must match `docs/08-user-manual.md` (a test checks); update both when behaviour changes. Disconnected displays' Spaces are remembered in `DisplayMemory` (own preferences); macOS still moves them, the app only groups them; dragging or forgetting in that window changes only this grouping.
- Pin GitHub Actions by full commit SHA with the version in a comment.

## Layout
- `Sources/SpacesCore`: pure logic (Foundation only) with unit tests in `Tests/SpacesCoreTests`. Put anything that can be tested here.
- `Sources/SpacesBar`: AppKit glue (panel, views, menu, key posting, monitor).
- `Sources/CGSPrivate`: C header for the private read-only call.
- `Assets/`: app icon (`AppIcon.svg`, rendered to `AppIcon.iconset` PNGs that `bundle.sh` turns into `AppIcon.icns`) and the menu bar glyph's source (`MenuBarGlyph.svg`, drawn in code by `MenuBarGlyph.swift`).
- `scripts/`: `bundle.sh` (build + sign), `security-check.sh` (binary checks), `source-check.sh` (forbidden APIs).
- `docs/`: requirements, architecture, UI/UX, security + pen-test plan, CI/CD, operations, pen-test report.

## Build and test
macOS 26+ with Xcode 26:
```sh
swift test
scripts/bundle.sh 0.1.0
scripts/security-check.sh build/SpacesBar.app
```
Cloud sessions can't compile macOS code: push a branch and read the CI run (`.github/workflows/ci.yml`) instead. CI is the source of truth for "it builds".

## Style
Match the existing code: small types, doc comments on anything non-obvious, no force unwraps on data from macOS or preferences.
