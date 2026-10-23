#!/bin/bash
# Static checks on the built app (security controls C1–C4 in docs/04-security.md).
# Fails if the binary can reach the network, run scripts or processes, load code,
# tap input events, or isn't signed with the hardened runtime and no entitlements.
set -euo pipefail

APP="${1:-build/SpacesBar.app}"
BIN="$APP/Contents/MacOS/SpacesBar"
fail=0
pass() { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; fail=1; }

[[ -x "$BIN" ]] || { echo "missing $BIN"; exit 2; }

# Undefined (imported) symbols, for every architecture in the binary.
SYMS="$(for a in $(lipo -archs "$BIN"); do nm -u -arch "$a" "$BIN"; done | sed 's/^_//' | sort -u)"

check_absent() { # label, regex
  local hits
  hits="$(grep -E "$2" <<<"$SYMS" || true)"
  if [[ -z "$hits" ]]; then pass "$1"; else bad "$1: $(tr '\n' ' ' <<<"$hits")"; fi
}

# C1: networking
check_absent "C1 no BSD sockets / DNS" '^(socket|connect|bind|listen|accept|getaddrinfo|gethostbyname|sendto|recvfrom)$'
check_absent "C1 no URLSession / CFNetwork / Network.framework" '(URLSession|NSURLConnection|CFStream|CFHTTP|CFSocket|nw_connection|nw_listener|NWConnection|NWListener)'
# C3: scripts, processes, dynamic code
check_absent "C3 no process launching" '^(system|popen|posix_spawn|posix_spawnp|execv|execve|execvp|fork|vfork)$|NSTask|\$s10Foundation7Process'
check_absent "C3 no AppleScript / Apple Events sending" '(NSAppleScript|OSAScript|AESend|AECreateAppleEvent|NSAppleEventDescriptor)'
check_absent "C3 no dynamic loading" '^(dlopen|dlsym|NSAddImage|NSCreateObjectFileImageFromMemory)$'
# C4: input monitoring
check_absent "C4 no event taps" '^(CGEventTapCreate|CGEventTapCreateForPid|CGEventTapCreateForPSN|IOHIDManagerCreate)$'

# Linked libraries: only system frameworks/libraries.
# (Indented lines only: a universal binary prints one header line per architecture.)
LIBS="$(otool -L "$BIN" | grep -E '^[[:space:]]' | awk '{print $1}' | sort -u)"
nonsystem="$(grep -vE '^(/System/Library/|/usr/lib/)' <<<"$LIBS" || true)"
if [[ -z "$nonsystem" ]]; then pass "only system libraries linked"; else bad "non-system libraries: $nonsystem"; fi
netlibs="$(grep -E '(Network\.framework|CFNetwork\.framework|WebKit\.framework)' <<<"$LIBS" || true)"
if [[ -z "$netlibs" ]]; then pass "C1 no networking frameworks linked directly"; else bad "networking frameworks linked: $netlibs"; fi

# C2: hardened runtime, no entitlements
FLAGS="$(codesign -dv "$APP" 2>&1 | grep -E '^CodeDirectory' || true)"
if grep -q 'runtime' <<<"$FLAGS"; then pass "C2 hardened runtime"; else bad "C2 hardened runtime missing ($FLAGS)"; fi
ENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
if [[ -z "$(tr -d '[:space:]' <<<"$ENTS")" ]] || ! grep -q '<key>' <<<"$ENTS"; then
  pass "C2 no entitlements"
else
  bad "C2 entitlements present: $ENTS"
fi

# Info.plist sanity: no URL schemes, no services, no XPC.
PLIST="$APP/Contents/Info.plist"
for key in CFBundleURLTypes NSServices NSAppleScriptEnabled NSAppTransportSecurity; do
  if /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" >/dev/null 2>&1; then bad "Info.plist has $key"; else pass "Info.plist has no $key"; fi
done
if [[ -d "$APP/Contents/XPCServices" || -d "$APP/Contents/Library/LoginItems" || -d "$APP/Contents/Frameworks" || -d "$APP/Contents/PlugIns" ]]; then
  bad "bundle contains helpers, frameworks or plug-ins"
else
  pass "bundle contains only the app binary"
fi

exit $fail
