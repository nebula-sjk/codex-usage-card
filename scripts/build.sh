#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Codex使用量卡片"
APP_PATH="$ROOT/build/$APP_NAME.app"
ARCH_BUILD="$ROOT/build/.architectures"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH_LIST="${CODEX_BUILD_ARCHS:-$(uname -m)}"

rm -rf "$APP_PATH" "$ARCH_BUILD"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$ARCH_BUILD"

BUILT_BINARIES=()
for ARCH in ${=ARCH_LIST}; do
  case "$ARCH" in
    arm64|x86_64) ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
  esac
  CLANG_MODULE_CACHE_PATH="$ARCH_BUILD/module-cache-$ARCH" swiftc \
    -sdk "$SDK" \
    -target "$ARCH-apple-macos13.0" \
    "$ROOT/Sources/CodexUsageCard.swift" \
    -o "$ARCH_BUILD/CodexUsageCard-$ARCH" \
    -framework Cocoa
  BUILT_BINARIES+=("$ARCH_BUILD/CodexUsageCard-$ARCH")
done

if (( ${#BUILT_BINARIES[@]} == 1 )); then
  cp "$BUILT_BINARIES[1]" "$APP_PATH/Contents/MacOS/CodexUsageCard"
else
  lipo -create "${BUILT_BINARIES[@]}" -output "$APP_PATH/Contents/MacOS/CodexUsageCard"
fi

cp "$ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
echo "Built app ($ARCH_LIST): $APP_PATH"
