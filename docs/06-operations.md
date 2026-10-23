# 6. Operations: install, set up, use, update, troubleshoot, uninstall

For macOS 26 and 27. Everything here runs on your Mac.

## 6.1 Install

### Option A: build from source (strongest, recommended)

Needs Xcode 26 or newer (App Store) and its command-line tools (`xcode-select --install`).

Paste this as one block. Each step runs only if the previous one succeeded, so nothing is installed if a test or security check fails.

```sh
git clone https://github.com/kosrodka/dispaces.git && cd dispaces &&
git log -1 --format='%H %s' &&
swift test &&
scripts/bundle.sh 0.1.0 &&
scripts/security-check.sh &&
cp -R build/SpacesBar.app /Applications/ &&
open /Applications/SpacesBar.app
```

What to look for: `git log` prints the commit you are building; `swift test` ends with all tests passed; every `security-check.sh` line says PASS.

Already cloned? Run `cd dispaces && git pull` and then the same block from `git log` on.

### Option B: download a CI build

1. GitHub › [kosrodka/dispaces](https://github.com/kosrodka/dispaces) › Releases (or Actions › latest green run › Artifacts).
2. Download `SpacesBar.zip`, then check the hash matches the one on the release page / in the CI log:
   ```sh
   shasum -a 256 ~/Downloads/SpacesBar.zip
   ```
3. Unzip, move `SpacesBar.app` to /Applications.
4. The app is not notarised (no Apple developer account), so remove the download quarantine for this one app:
   ```sh
   xattr -dr com.apple.quarantine /Applications/SpacesBar.app
   open /Applications/SpacesBar.app
   ```

## 6.2 First-run setup (once)

1. **Turn on the Space shortcuts:** System Settings › Keyboard › Keyboard Shortcuts… › Mission Control › tick **Switch to Desktop 1** … up to your number of desktops (macOS shows entries only for desktops that exist). Leave the default keys (Control-1, Control-2, …) or pick your own; the app reads whatever you set. Also keep **Move left a space / Move right a space** ticked (used for full-screen Spaces).
2. **Click any tile.** macOS asks for **Accessibility** access for SpacesBar. Allow it (System Settings › Privacy & Security › Accessibility). Click the tile again.
3. **Name things:** double-click a tile (or right-click › Rename Space…). Right-click a display name › Rename display….
4. **Place the bars:** each display has its own bar; drag it by its background or display name, and drag its edges to resize it. Click its padlock when you're happy (menu bar icon › Lock all bars locks every bar).
5. **Optional:** menu bar icon › Launch at login.

Check everything at once: menu bar icon › **Setup check…**. All four lines should show ✓ and the amber **!** disappears from the bar.

## 6.3 Daily use

| Do | How |
|---|---|
| Switch Space | Click its tile |
| Rename | Double-click a tile, or right-click › Rename |
| Hide/show one bar's Spaces | Click the eye at the left of that bar |
| Lock/unlock a bar | Click its padlock (each bar separately), or menu bar icon › Lock all bars |
| Resize a bar | Hover its edge until the pointer changes, then drag. Double-click the edge for the natural size |
| Hide/show all bars | Menu bar icon › Show bars |
| Move a window to another Space | Turn on menu bar icon › Option-drag windows to Spaces (once). Hold Option, grab the window by its title bar and drag onto a tile (on any display's bar). Wait until the tile has been yellow for a moment and the Space changes, then let go |
| See which apps are on a Space | Rest the pointer on its tile. Turn off with menu bar icon › Show apps on hover |
| Jump to an app on a Space | Rest on the tile, move into the column and click the app |
| Read the manual or check the version | Menu bar icon › Help › User manual, or Help › Current release |
| See all displays, including unplugged ones | Menu bar icon › Manage displays and spaces. Forget drops an unplugged display you won't use again; dragging one of its Spaces onto the bar of the display it's on now stops grouping that Space (windows don't move) |
| Force a refresh | Click the arrow on a bar, or menu bar icon › Refresh now (normally automatic within 0.1 s, plus every 60 s) |

## 6.4 Update

1. Pull or download the new version and repeat §6.1.
2. Quit the old app first (menu bar icon › Quit).
3. **Accessibility after an update:** macOS ties the permission to the app's signature, and each ad-hoc signed build has a new one. If clicks stop switching after an update: System Settings › Privacy & Security › Accessibility › select SpacesBar › **−**, then click a tile and allow it again. (To avoid this, sign with your own stable certificate: create a "Code Signing" certificate in Keychain Access › Certificate Assistant, then `SIGN_IDENTITY="Your Cert Name" scripts/bundle.sh 0.1.1`.)

## 6.5 Troubleshooting

| Symptom | Fix |
|---|---|
| Amber **!** on the bar | Click it; the Setup check names what's missing. |
| Click does nothing, message "Didn't switch to Desktop N" | Turn on "Switch to Desktop N" (§6.2 step 1). If it is on, check no other app uses the same key combination. |
| Message about Accessibility | §6.2 step 2, or §6.4 step 3 after an update. |
| Full-screen app tile says "only from its own display" | macOS steps through Spaces on the display under the pointer. Click the tile on that display's own bar, or use Mission Control. |
| "Can't read Spaces" on the bar | macOS didn't return the Space list (possible after a major macOS update). Quit and reopen; if it persists, open an issue with your macOS version. |
| A bar is off-screen or in a strange place | Each bar keeps itself on its own display's visible area. To reset all positions and sizes: quit the app, run `defaults delete io.github.kosrodka.SpacesBar barOffsets && defaults delete io.github.kosrodka.SpacesBar barSizes` and reopen. |
| Names gone after moving a Space | The first desktop of each display has no stable id in macOS, so its name follows its position. Rename it again. |

Logs (no names are ever logged): `log stream --predicate 'subsystem == "io.github.kosrodka.SpacesBar"'`

## 6.6 Back up and restore names

```sh
defaults export io.github.kosrodka.SpacesBar ~/spaces-bar-backup.plist
defaults import io.github.kosrodka.SpacesBar ~/spaces-bar-backup.plist
```

## 6.7 Uninstall (leaves nothing behind)

1. Menu bar icon › untick Launch at login › Quit.
2. `rm -rf /Applications/SpacesBar.app`
3. `defaults delete io.github.kosrodka.SpacesBar`
4. System Settings › Privacy & Security › Accessibility › remove SpacesBar.
5. Optionally turn the Switch to Desktop shortcuts back off.

## 6.8 Pen tests on your Mac (P1–P12 from docs/04-security.md)

Run with the app installed and running. Record results in `docs/07-pen-test-report.md`.

```sh
APP=/Applications/SpacesBar.app; PID=$(pgrep -x SpacesBar)

```

P1 no network: expect no output from lsof, no rows with traffic in nettop:
```sh
lsof -nP -i -a -p "$PID"; nettop -p "$PID" -l 1 -x

```

P2 integrity: hash must match the release page / CI log:
```sh
shasum -a 256 ~/Downloads/SpacesBar.zip

```

P3 signature: expect flags=0x10000(runtime) and no entitlements:
```sh
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E 'flags|Identifier|Signature'
codesign -d --entitlements - "$APP"
scripts/security-check.sh "$APP"

```

P4 injection: build a dummy dylib that logs if loaded; expect no "INJECTED":
```sh
printf '#include <stdio.h>\n__attribute__((constructor)) static void x(void){fprintf(stderr,"INJECTED\\n");}\n' > /tmp/inj.c
clang -dynamiclib /tmp/inj.c -o /tmp/inj.dylib
osascript -e 'quit app "SpacesBar"' 2>/dev/null; pkill -x SpacesBar
DYLD_INSERT_LIBRARIES=/tmp/inj.dylib "$APP/Contents/MacOS/SpacesBar" & sleep 3; pkill -x SpacesBar
open "$APP"

```

P5 hostile names: rename a Space by hand to each of these (copy/paste), check it shows ≤ 24 chars, literally, no crash:
```sh
printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\nabc‮exe.txt\n%%@%%n%%s%%x\n🇵🇱🇵🇱👩‍👩‍👧‍👦é\n'

```

P6 corrupt preferences: expect the app to start with default names, no crash:
```sh
pkill -x SpacesBar
defaults export io.github.kosrodka.SpacesBar /tmp/sb-backup.plist
defaults write io.github.kosrodka.SpacesBar spaceNames -string garbage
defaults write io.github.kosrodka.SpacesBar barOffsets -string nope
open "$APP"; sleep 3; pgrep -x SpacesBar && echo "still running: PASS"
pkill -x SpacesBar; defaults import io.github.kosrodka.SpacesBar /tmp/sb-backup.plist; open "$APP"

```

P12 login items: after enabling then disabling Launch at login:
```sh
sfltool dumpbtm 2>/dev/null | grep -i -A3 spacesbar
```

Manual ones:
- **P7 keystroke scope:** open TextEdit with an empty document, click tiles quickly 20 times. Expect: Spaces switch, no characters appear in TextEdit.
- **P8 permission revoked:** remove SpacesBar from Accessibility while it runs, click a tile. Expect: message, amber !, no crash.
- **P9 shortcut off:** untick "Switch to Desktop 3", click tile 3. Expect: message naming "Switch to Desktop 3"; re-tick afterwards.
- **P10 hot-plug, sleep:** unplug/replug the external display; sleep and wake. Expect: correct areas within a second, names kept.
- **P11 data loss:** note window counts per app (Window menu) before and after 5 minutes of switching. Expect: identical.
- **P13 Option-drag scope:** see docs/04-security.md P13.
- **P14 hover icons scope:** see docs/04-security.md P14.
- **P15 apps column clicks:** see docs/04-security.md P15.
