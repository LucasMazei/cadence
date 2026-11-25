#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
flags=()
for flag in "${compiler_flags[@]}"; do flags+=(-Xswiftc "$flag"); done
xcrun swift test --disable-xctest --sdk "$SDK" "${flags[@]}"
