#!/bin/bash
# Publishes a GitHub Release with Glasswipe.dmg attached.
#   scripts/release.sh 1.0.0
# Needs `gh` logged in to an account that can push to the repo (or GH_TOKEN set).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version, e.g. 1.0.0>}"
TAG="v$VERSION"

if [ -n "$(git status --porcelain)" ]; then echo "error: commit your changes first"; exit 1; fi
git tag -a "$TAG" -m "Glasswipe $VERSION" 2>/dev/null || echo "Tag $TAG already exists; reusing it"
git push origin "$TAG"

scripts/make-dmg.sh
cp build/Glasswipe.dmg "build/Glasswipe-$VERSION.dmg"

NOTES=$(mktemp)
trap 'rm -f "$NOTES"' EXIT
cat > "$NOTES" <<NOTES
## Download

**[Glasswipe.dmg](https://github.com/devendra-nationalwala/glasswipe/releases/download/$TAG/Glasswipe.dmg)** — macOS 26 (Tahoe) or later, Apple Silicon.

## Install

1. Open the .dmg and drag **Glasswipe** onto **Applications**.
2. Open Glasswipe. macOS says it can't verify the developer, because the app is not notarized.
3. Go to **System Settings → Privacy & Security**, click **Open Anyway**, and confirm (only once).
4. In Glasswipe, click **Open Settings** on the banner and turn on **Full Disk Access**.

> [!CAUTION]
> Glasswipe deletes files, moves files to the Trash, quits apps and changes startup settings. It is provided "as is", without warranty. The authors are **not responsible for any data loss or deleted files**. Review every selection before cleaning up and keep a current backup. See the [disclaimer](https://github.com/devendra-nationalwala/glasswipe#disclaimer).
NOTES

gh release create "$TAG" "build/Glasswipe.dmg" "build/Glasswipe-$VERSION.dmg" \
  --title "Glasswipe $VERSION" --notes-file "$NOTES" --latest
echo "==> Released $TAG"
