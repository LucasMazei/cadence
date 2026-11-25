#!/usr/bin/env bash
set -euo pipefail
app="$(cd "$1" && pwd)"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cd "$scratch"
printf '%s\n' '{"cacheDirectory":".","syncScript":"/dev/null","accounts":[]}' > config.json
printf '[]\n' > events.json
printf '[]\n' > tasks.json
CADENCE_CONFIG_PATH="$PWD/config.json" "$app/Contents/MacOS/Cadence" --check-panel
