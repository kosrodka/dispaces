#!/bin/bash
# Source-level guard rails (run before building). Fails on APIs this app must never use.
set -euo pipefail
cd "$(dirname "$0")/.."
pattern='URLSession|NSURLConnection|import Network|NWConnection|NSAppleScript|OSAScript|Process\(|NSTask|dlopen|dlsym|CGEventTapCreate|NSUserAppleScriptTask|FileManager\.default\.removeItem|\.removeItem\(|CGSManagedDisplaySetCurrentSpace|CGSMoveWindowsToManagedSpace|AXUIElement|CGEventCreateMouseEvent|mouseEventSource|CGWarpMouseCursorPosition|addGlobalMonitorForEvents|kCGWindowName|CGWindowListCreateImage|SCScreenshotManager|SCStream|CGSAddWindowsToSpaces|CGSRemoveWindowsFromSpaces|CGSSetWindow|forceTerminate|\.terminate\(\)|\.hide\(\)|disable-library-validation|allow-dyld-environment-variables'
if grep -rnE "$pattern" Sources; then
  echo "FAIL  forbidden API found in Sources (see above)"
  exit 1
fi
echo "PASS  no forbidden APIs in Sources"

# Reading the window list (owner process and window number only) is allowed in one file.
window_reads="$(grep -rlE 'CGWindowListCopyWindowInfo|CGWindowListCreate|CGSCopySpacesForWindows' Sources \
  | grep -vE '^Sources/(SpacesBar/SpaceAppsReader\.swift|CGSPrivate/include/CGSPrivate\.h)$' || true)"
if [[ -n "$window_reads" ]]; then
  echo "FAIL  window list read outside SpaceAppsReader.swift: $window_reads"
  exit 1
fi
echo "PASS  window list read only in SpaceAppsReader.swift"

# Bringing another app to the front (apps column click) is allowed in one place only.
activations="$(grep -rlE 'yieldActivation|activate\(from:' Sources | grep -vE '^Sources/SpacesBar/System\.swift$' || true)"
if [[ -n "$activations" ]]; then
  echo "FAIL  other apps activated outside AppActivator (System.swift): $activations"
  exit 1
fi
echo "PASS  other apps activated only by AppActivator"
