#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Codex使用量卡片"
ARCHIVE_NAME="CodexUsageCard-macos.zip"
DMG_NAME="CodexUsageCard-macos-universal.dmg"
DIST="$ROOT/dist"
DMG_ROOT="$ROOT/build/dmg-root"

if [[ "${CODEX_SKIP_BUILD:-0}" != "1" ]]; then
  "$ROOT/scripts/build.sh"
fi
if [[ ! -d "$ROOT/build/$APP_NAME.app" ]]; then
  echo "Missing app bundle: $ROOT/build/$APP_NAME.app" >&2
  exit 1
fi
rm -rf "$DIST"
mkdir -p "$DIST"
ditto -c -k --sequesterRsrc --keepParent \
  "$ROOT/build/$APP_NAME.app" \
  "$DIST/$ARCHIVE_NAME"

rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
ditto "$ROOT/build/$APP_NAME.app" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "Codex Usage Card" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DIST/$DMG_NAME"

echo "Packaged: $DIST/$ARCHIVE_NAME"
echo "Packaged: $DIST/$DMG_NAME"
