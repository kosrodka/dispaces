#!/bin/bash
# Builds Dispaces.app from the Swift package and signs it with the hardened runtime.
#
# Usage: scripts/bundle.sh [version]
#   SIGN_IDENTITY  code-signing identity (default "-" = ad-hoc). Use a stable
#                  self-signed certificate to keep the Accessibility grant across rebuilds.
#   ARCHS          architectures to build (default: this Mac's, e.g. arm64). "arm64 x86_64" = universal.
set -euo pipefail

VERSION="${1:-0.1.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ARCHS="${ARCHS:-$(uname -m)}"
BUNDLE_ID="io.github.kosrodka.SpacesBar"

cd "$(dirname "$0")/.."
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must look like 1.2.3" >&2
  exit 1
fi

ARCH_FLAGS=()
for arch in $ARCHS; do ARCH_FLAGS+=(--arch "$arch"); done
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

APP="build/Dispaces.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# The SwiftPM target is still called SpacesBar; the app and its process are Dispaces.
cp "$BIN_DIR/SpacesBar" "$APP/Contents/MacOS/Dispaces"
# App icon: PNGs rendered from Assets/AppIcon.svg.
iconutil -c icns Assets/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>Dispaces</string>
  <key>CFBundleExecutable</key><string>Dispaces</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Dispaces</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>Copyright 2026 Kamil Ośródka (github.com/kosrodka). MIT License.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"

# Hardened runtime, no entitlements.
codesign --force --options runtime --timestamp=none --identifier "$BUNDLE_ID" --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

(cd build && rm -f Dispaces.zip && ditto -c -k --keepParent Dispaces.app Dispaces.zip)
shasum -a 256 build/Dispaces.zip | tee build/Dispaces.zip.sha256
echo "Built $APP ($VERSION)"
