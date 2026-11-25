#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/Cadence.app"
CACHE_DIR="$ROOT/.local-cache"
source "$ROOT/scripts/toolchain.sh"

cd "$ROOT"
mkdir -p "$BUILD_DIR" "$CACHE_DIR/clang" "$CACHE_DIR/swift"
CLANG_MODULE_CACHE_PATH="$CACHE_DIR/clang" \
SWIFT_MODULECACHE_PATH="$CACHE_DIR/swift" \
xcrun swiftc \
    -sdk "$SDK" \
    -target "$(uname -m)-apple-macosx14.0" \
    "${compiler_flags[@]}" \
    -parse-as-library \
    -file-prefix-map "$ROOT"=. \
    -O \
    -o "$BUILD_DIR/Cadence" \
    Sources/*.swift

mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BUILD_DIR/Cadence" "$APP_DIR/Contents/MacOS/Cadence"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
