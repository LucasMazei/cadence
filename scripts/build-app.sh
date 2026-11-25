#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/Cadence.app"
source "$ROOT/scripts/toolchain.sh"

cd "$ROOT"
release_flags=(-c release -debug-info-format none "${swiftpm_flags[@]}" -Xswiftc -file-prefix-map -Xswiftc "$ROOT=.")
xcrun swift build "${release_flags[@]}" --product Cadence
BUILD_DIR="$(xcrun swift build "${release_flags[@]}" --show-bin-path)"

mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BUILD_DIR/Cadence" "$APP_DIR/Contents/MacOS/Cadence"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
