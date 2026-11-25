#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

umask 077
exec uv run --locked --project "$ROOT/backend" python "$ROOT/backend/fetch_calendar.py" "$@"
