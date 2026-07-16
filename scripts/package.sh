#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Codex使用量卡片"
DIST="$ROOT/dist"

"$ROOT/scripts/build.sh"
rm -rf "$DIST"
mkdir -p "$DIST"
ditto -c -k --sequesterRsrc --keepParent \
  "$ROOT/build/$APP_NAME.app" \
  "$DIST/$APP_NAME-macos.zip"
echo "Packaged: $DIST/$APP_NAME-macos.zip"
