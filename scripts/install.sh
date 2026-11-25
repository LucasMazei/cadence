#!/usr/bin/env bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.lucasmazei.cadence"
DOMAIN="gui/$(id -u)"
APPLICATIONS_DIR="${CADENCE_APPLICATIONS_DIR:-$HOME/Applications}"
SUPPORT_DIR="${CADENCE_SUPPORT_DIR:-$HOME/.local/share/cadence}"
CONFIG_DIR="${CADENCE_CONFIG_DIR:-$HOME/.config/cadence}"
CACHE_DIR="${CADENCE_CACHE_DIR:-$HOME/.cache/cadence}"
AGENT_DIR="$HOME/Library/LaunchAgents"
APP_PATH="$APPLICATIONS_DIR/Cadence.app"
AGENT_PATH="$AGENT_DIR/$LABEL.plist"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v uv >/dev/null; then
    echo "Install uv first (brew install uv), then run this installer again." >&2
    exit 1
fi
if [[ "${1:-}" == --prebuilt ]]; then
    bundle="$ROOT/Cadence.app"
else
    "$ROOT/scripts/build-app.sh"
    bundle="$ROOT/dist/Cadence.app"
fi
codesign --verify --strict "$bundle"
"$ROOT/scripts/check-panel.sh" "$bundle"

mkdir -p "$APPLICATIONS_DIR" "$SUPPORT_DIR/backend" "$SUPPORT_DIR/bin" "$CONFIG_DIR" "$CACHE_DIR" "$AGENT_DIR"
stage=$(mktemp -d "$APPLICATIONS_DIR/.cadence-install.XXXXXX")
files=(backend/fetch_calendar.py backend/pyproject.toml backend/uv.lock bin/backend.sh bin/sync.sh)
replacing=false
was_running=false
cleanup() {
    result=$?
    if [[ "$result" != 0 && "$replacing" == true ]]; then
        launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
        if [[ -d "$stage/previous.app" ]]; then
            rm -rf "$APP_PATH"
            mv "$stage/previous.app" "$APP_PATH"
        elif [[ ! -d "$stage/new.app" ]]; then
            rm -rf "$APP_PATH"
        fi
        for path in "${files[@]}"; do
            if [[ -f "$stage/previous/$path" ]]; then
                cp -p "$stage/previous/$path" "$SUPPORT_DIR/$path"
            else
                rm -f "$SUPPORT_DIR/$path"
            fi
        done
        if [[ -f "$stage/previous.plist" ]]; then
            cp -p "$stage/previous.plist" "$AGENT_PATH"
            if [[ "$was_running" == true ]]; then launchctl bootstrap "$DOMAIN" "$AGENT_PATH"; fi
        else
            rm -f "$AGENT_PATH"
        fi
    fi
    rm -rf "$stage"
}
trap cleanup EXIT
ditto "$bundle" "$stage/new.app"
mkdir -p "$stage/previous/backend" "$stage/previous/bin"
for path in "${files[@]}"; do
    [[ -f "$ROOT/$path" ]]
    if [[ -f "$SUPPORT_DIR/$path" ]]; then cp -p "$SUPPORT_DIR/$path" "$stage/previous/$path"; fi
done
if [[ -f "$AGENT_PATH" ]]; then cp -p "$AGENT_PATH" "$stage/previous.plist"; fi
cp "$ROOT/Resources/$LABEL.plist" "$stage/agent.plist"
plutil -replace ProgramArguments.0 -string "$APP_PATH/Contents/MacOS/Cadence" "$stage/agent.plist"
plutil -replace StandardOutPath -string "$CACHE_DIR/app.out.log" "$stage/agent.plist"
plutil -replace StandardErrorPath -string "$CACHE_DIR/app.err.log" "$stage/agent.plist"
if [[ ! -f "$CONFIG_DIR/config.json" ]]; then cp "$ROOT/Resources/config.example.json" "$CONFIG_DIR/config.json"; fi

if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
    was_running=true
    launchctl bootout "$DOMAIN/$LABEL"
fi
replacing=true
if [[ -d "$APP_PATH" ]]; then mv "$APP_PATH" "$stage/previous.app"; fi
mv "$stage/new.app" "$APP_PATH"
for path in "${files[@]}"; do cp -p "$ROOT/$path" "$SUPPORT_DIR/$path"; done
cp "$stage/agent.plist" "$AGENT_PATH"
launchctl bootstrap "$DOMAIN" "$AGENT_PATH"
sleep 2
launchctl print "$DOMAIN/$LABEL" | grep -E '^[[:space:]]*state = running$' >/dev/null
echo "Cadence is running. Open the gear in the menu bar to connect a Google account."
