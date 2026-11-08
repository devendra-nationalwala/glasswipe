#!/bin/bash
# Publishes a GitHub Release with Glasswipe.dmg attached.
#   scripts/release.sh 1.0.0
# Needs `gh` logged in to an account that can push to the repo (or GH_TOKEN set).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version, e.g. 1.0.0>}"
TAG="v$VERSION"

if [ -n "$(git status --porcelain)" ]; then echo "error: commit your changes first"; exit 1; fi
git fetch -q --tags origin
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "error: $TAG already exists (latest: $(git describe --tags --abbrev=0)). Pick a newer version."; exit 1
fi
git tag -a "$TAG" -m "Glasswipe $VERSION"
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

Glasswipe is free. If it saved you some space, you can [☕ buy me a coffee](https://donate.stripe.com/4gMdRa8GPapX8oSgoO8og01).

> [!CAUTION]
> Glasswipe deletes files, moves files to the Trash, quits apps and changes startup settings. It is provided "as is", without warranty. The authors are **not responsible for any data loss or deleted files**. Review every selection before cleaning up and keep a current backup. See the [disclaimer](https://github.com/devendra-nationalwala/glasswipe#disclaimer).
NOTES

gh release create "$TAG" "build/Glasswipe.dmg" "build/Glasswipe-$VERSION.dmg" \
  --title "Glasswipe $VERSION" --notes-file "$NOTES" --latest
echo "==> Released $TAG"
