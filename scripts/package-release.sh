#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh
codesign --verify --strict dist/Cadence.app
scripts/check-panel.sh dist/Cadence.app
version=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
name="Cadence-$version-macOS-$(uname -m)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
target="$work/$name"
mkdir -p "$target"/{bin,backend,Resources,scripts}
ditto dist/Cadence.app "$target/Cadence.app"
cp bin/{backend,sync}.sh "$target/bin/"
cp backend/{fetch_calendar.py,pyproject.toml,uv.lock} "$target/backend/"
cp Resources/{config.example.json,com.lucasmazei.cadence.plist} "$target/Resources/"
cp scripts/{install,check-panel}.sh "$target/scripts/"
cp README.md "$target/"
cat > "$target/Install.command" <<'INSTALL'
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
exec ./scripts/install.sh --prebuilt
INSTALL
chmod +x "$target/Install.command"
# Whitelist release files. The checkout and user caches never enter the archive.
(cd "$work" && /usr/bin/zip -Xqr "$name.zip" "$name")
mv "$work/$name.zip" "dist/$name.zip"
(cd dist && shasum -a 256 "$name.zip" > "$name.zip.sha256")
echo "dist/$name.zip"
