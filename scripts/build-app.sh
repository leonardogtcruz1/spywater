#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/build/SpyWater.app"

cd "$ROOT_DIR/app"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/SpyWater"
if [ ! -x "$BIN_PATH" ]; then
  BIN_PATH="$ROOT_DIR/app/.build/release/SpyWater"
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/SpyWater"
cp "$ROOT_DIR/app/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

codesign --force --deep --sign - "$APP_BUNDLE"

mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/SpyWater.app"
cp -R "$APP_BUNDLE" "$HOME/Applications/"

echo "App instalado em $HOME/Applications/SpyWater.app"
