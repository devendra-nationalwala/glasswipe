#!/bin/bash
# Builds Glasswipe.app and packages it as build/Glasswipe.dmg (drag the app onto Applications to install).
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R build/Glasswipe.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
Glasswipe — install

1. Drag Glasswipe onto the Applications folder.
2. Open Glasswipe from Applications. macOS will say it can't verify the developer,
   because Glasswipe is free open-source software and is not notarized by Apple.
3. Open System Settings → Privacy & Security, scroll down and click "Open Anyway",
   then confirm. You only need to do this once.
4. In Glasswipe, click "Open Settings" on the banner and turn on Full Disk Access.

DISCLAIMER: Glasswipe deletes files, moves files to the Trash, quits apps and changes
startup settings. It is provided "as is", without warranty of any kind. The authors are
not responsible for any data loss or deleted files. Review every selection before
cleaning up and keep a current backup.

https://github.com/devendra-nationalwala/glasswipe
TXT

rm -f build/Glasswipe.dmg
hdiutil create -volname "Glasswipe" -srcfolder "$STAGE" -ov -format UDZO -fs APFS build/Glasswipe.dmg >/dev/null

IDENTITY=$(codesign -dv build/Glasswipe.app 2>&1 | awk -F= '/^Authority/ {print $2; exit}')
[ -n "$IDENTITY" ] && codesign --force --sign "$IDENTITY" build/Glasswipe.dmg
echo "==> Built build/Glasswipe.dmg ($(du -h build/Glasswipe.dmg | cut -f1))"
