# 7. Pen-test report: v0.1.0

Plan: [04-security.md §4.5](04-security.md). Commands: [06-operations.md §6.8](06-operations.md).

## 7.1 Automated (GitHub Actions, macOS 26.6.2, Xcode 26.6, Swift 6.3.3), 19 Oct 2026

These results are from the first CI runs on `main` on 19 Oct 2026. CI repeats the checks on every push (Actions tab › CI); the unit test suite and `source-check.sh` (C13–C15) have grown since.

| Control | Check | Result |
|---|---|---|
| C12 | No forbidden APIs in source (`source-check.sh`) | PASS |
| C5–C8 | 35 unit tests: parser robustness incl. 2,000-case random fuzz, malformed and oversized input; name sanitising (bidi overrides, control chars, 24-char grapheme-safe cut, format strings); preference validation and 256-entry cap; switch planning incl. allow-list of shortcut ids and modifier bits | PASS |
| C1 | No socket/DNS imports; no URLSession / CFNetwork / Network.framework symbols; no networking frameworks linked | PASS |
| C1 | Launch smoke test: app runs 5 s, `lsof -i` shows **no sockets** | PASS |
| C2 | Hardened runtime flag set; **no entitlements** | PASS |
| C3 | No process launching, no AppleScript / Apple Events, no `dlopen`/`dlsym` | PASS |
| C4 | No event taps or HID managers (app never reads input) | PASS |
| — | Only `/System/Library` and `/usr/lib` libraries linked; bundle holds only the binary (no helpers, frameworks, plug-ins); Info.plist has no URL schemes, services, AppleScript or ATS exceptions | PASS |
| C11 | CodeQL 2.27.2, security-and-quality queries on all app and core sources | PASS: 0 error-level findings |

## 7.2 Manual on a real Mac (macOS 27): not yet recorded

| ID | Test | Result | Notes |
|---|---|---|---|
| P1 | No network (`lsof`, `nettop`) | ☐ | |
| P2 | SHA-256 matches CI / release | ☐ | |
| P3 | Signature: runtime flag, no entitlements | ☐ | |
| P4 | `DYLD_INSERT_LIBRARIES` ignored | ☐ | |
| P5 | Hostile names | ☐ | |
| P6 | Corrupt preferences | ☐ | |
| P7 | Keystroke scope (TextEdit stays empty) | ☐ | |
| P8 | Permission revoked mid-run | ☐ | |
| P9 | Shortcut off → clear message | ☐ | |
| P10 | Display hot-plug, sleep/wake | ☐ | |
| P11 | No windows lost | ☐ | |
| P12 | Login item cleaned up | ☐ | |
| P13 | Option-drag scope | ☐ | |
| P14 | Hover icons: no Screen Recording, windows unchanged | ☐ | |
| P15 | Apps column clicks | ☐ | |

Functional checks on macOS 27 at the same time:

| Check | Result |
|---|---|
| One bar per display, Spaces in Mission Control order | ☐ |
| Tile numbers match "Switch to Desktop N" (click 4 on the second display goes there) | ☐ |
| Highlight follows Space changes made with the keyboard, trackpad and Mission Control | ☐ |
| Full-screen app shows as dashed "FS" tile | ☐ |
| Clicking the bar never steals focus from the app you're typing in | ☐ |
| Bar stays put in Mission Control; no Stage Manager stage is created | ☐ |

## 7.3 Findings

| # | Severity | Finding | Status |
|---|---|---|---|
| 1 | Low (build only) | `security-check.sh` misread `otool` output for universal binaries and failed the build | Fixed in CI before release |
| 2 | Info | CodeQL job lacked `actions: read` | Fixed |
| — | — | No security findings in the app code from automated tests | — |

## 7.4 Residual risks (accepted for v0.1)

1. **Private API.** A future macOS could change `CGSCopyManagedDisplaySpaces`. Impact: the bar shows "Can't read Spaces"; no crash, no data loss.
2. **Accessibility is powerful.** Mitigated by code size (about 4,400 lines of Swift including comments), the key allow-list, no event reading, hardened runtime, and CI binary checks. Review any future change to `KeyPoster`.
3. **Not notarised.** Downloads need the quarantine flag removed. Building from source avoids this.
4. **Ad-hoc signature.** Accessibility must be re-granted after each update unless you sign with your own certificate (06-operations §6.4).
5. **CI isn't a real macOS 27 desktop.** Switching, highlighting and Stage Manager behaviour can only be verified on a real Mac (§7.2).
