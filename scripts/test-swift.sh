#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
# CLT 27 keeps Swift Testing's macros outside the compiler's default plugin path.
testing_plugin="$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools && -f "$testing_plugin" ]]; then
    swiftpm_flags+=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
fi
xcrun swift test --disable-xctest "${swiftpm_flags[@]}"
