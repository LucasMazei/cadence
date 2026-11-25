#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swift-format lint --strict --recursive Sources Tests/Swift
scripts/test-swift.sh
uv run --locked --project backend python -m unittest discover -s Tests/Python
scripts/build-app.sh
codesign --verify --strict dist/Cadence.app
scripts/check-panel.sh dist/Cadence.app
