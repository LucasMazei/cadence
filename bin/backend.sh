#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

umask 077
uv_bin=uv
if [[ -x "$ROOT/bin/uv" ]]; then
    uv_bin="$ROOT/bin/uv"
    export UV_MANAGED_PYTHON=1
fi
exec "$uv_bin" run --locked --project "$ROOT/backend" python "$ROOT/backend/fetch_calendar.py" "$@"
