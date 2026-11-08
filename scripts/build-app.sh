#!/bin/bash
# Builds Glasswipe.app into ./build and signs it.
#   scripts/build-app.sh            build only
#   scripts/build-app.sh --install  build and copy to /Applications
# Signing identity, in order: $GLASSWIPE_SIGN_IDENTITY, an "Apple Development" identity,
# "Glasswipe Local Signing" (see create-signing-identity.sh), otherwise ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Glasswipe.app"
VERSION=$(git describe --tags --always 2>/dev/null | sed "s/^v//" || echo "0.1.0")
BUNDLE_ID="io.github.devendra-nationalwala.glasswipe"

echo "==> Building release binary"
swift build -c release --arch arm64 --product Glasswipe
BIN_DIR=$(swift build -c release --arch arm64 --show-bin-path)

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Glasswipe" "$APP/Contents/MacOS/Glasswipe"
cp -R "$BIN_DIR/Glasswipe_GlasswipeCore.bundle" "$APP/Contents/Resources/"

ICONSET="build/AppIcon.iconset"
if [ ! -f build/AppIcon.icns ] || [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then
  echo "==> Rendering icon"
  rm -rf "$ICONSET"
  swift scripts/make-icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Glasswipe</string>
  <key>CFBundleDisplayName</key><string>Glasswipe</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>Glasswipe</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>NSAppleEventsUsageDescription</key><string>Glasswipe asks for your administrator password through macOS to clean system folders.</string>
</dict>
</plist>
PLIST

IDENTITY="${GLASSWIPE_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')
fi
if [ -z "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q '"Glasswipe Local Signing"'; then
  IDENTITY="Glasswipe Local Signing"
fi
if [ -z "$IDENTITY" ]; then
  echo "warning: no signing identity found; signing ad hoc. Full Disk Access will be lost on every rebuild."
  echo "         Run scripts/create-signing-identity.sh once to fix this."
  IDENTITY="-"
fi
echo "==> Signing with: $IDENTITY"
codesign --force --deep --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP" && echo "==> Built $APP ($VERSION)"

if [ "${1:-}" = "--install" ]; then
  cat <<'NOTICE'

  ┌──────────────────────────────────────────────────────────────────────────┐
  │ DISCLAIMER: Glasswipe deletes files, moves files to the Trash, quits apps │
  │ and changes startup settings. It is provided "as is", without warranty.   │
  │ The authors are NOT responsible for any data loss or deleted files.       │
  │ Review every selection before cleaning up and keep a current backup.      │
  │ Installing it means you accept this. See README.md#disclaimer.            │
  └──────────────────────────────────────────────────────────────────────────┘

NOTICE
  pkill -x Glasswipe 2>/dev/null || true
  rm -rf /Applications/Glasswipe.app
  cp -R "$APP" /Applications/
  echo "==> Installed to /Applications/Glasswipe.app"
fi
