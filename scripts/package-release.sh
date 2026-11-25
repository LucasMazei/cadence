#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh
codesign --verify --strict dist/Cadence.app
scripts/check-panel.sh dist/Cadence.app
version=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
arch="$(uname -m)"
name="Cadence-$version-macOS-$arch"
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
# Ship a private copy of uv so the first sync can provision Python on a clean Mac.
python3 -m pip --isolated download --index-url https://pypi.org/simple --only-binary=:all: \
    --require-hashes --no-deps -r packaging/macos/uv-requirements.txt -d "$work"
wheel=("$work"/uv-*.whl)
unzip -p "${wheel[0]}" 'uv-*.data/scripts/uv' > "$target/bin/uv"
chmod +x "$target/bin/uv"
for license in MIT APACHE; do
    unzip -p "${wheel[0]}" "uv-*.dist-info/licenses/LICENSE-$license" > "$target/bin/LICENSE-uv-$license"
done
"$target/bin/uv" --version

# Whitelist release files. The checkout and user caches never enter the archive.
(cd "$work" && /usr/bin/zip -Xqr "$name.zip" "$name")

# Installer runs the same checked, rollback-capable installation as the ZIP.
mkdir "$work/pkg-scripts"
mv "$target" "$work/pkg-scripts/Cadence"
cp packaging/macos/postinstall "$work/pkg-scripts/"
pkgbuild --nopayload --identifier com.lucasmazei.cadence.installer --version "$version" \
    --scripts "$work/pkg-scripts" "$work/Cadence-component.pkg"
sed "s/@ARCH@/$arch/g" packaging/macos/Distribution.xml > "$work/Distribution.xml"
productbuild --distribution "$work/Distribution.xml" --package-path "$work" "$work/$name.pkg"

for ext in zip pkg; do
    mv "$work/$name.$ext" "dist/$name.$ext"
    (cd dist && shasum -a 256 "$name.$ext" > "$name.$ext.sha256")
    echo "dist/$name.$ext"
done
