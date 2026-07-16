#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Codex使用量卡片"
APP_PATH="$ROOT/build/$APP_NAME.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"

swiftc \
  -sdk "$SDK" \
  "$ROOT/Sources/CodexUsageCard.swift" \
  -o "$APP_PATH/Contents/MacOS/CodexUsageCard" \
  -framework Cocoa

cp "$ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
echo "Built: $APP_PATH"
