# Sourced by the release build and Swift tests.
SDK="$(xcrun --sdk macosx --show-sdk-path)"
compiler_flags=(-warnings-as-errors)
# CLT 27 ships SwiftUI interfaces referring to an Xcode-only macro plugin.
# Preserve the working local toolchain when the compatible SDK is installed.
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools && "$(xcrun --show-sdk-version)" == 27.* && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
    compiler_flags+=(-interface-compiler-version 6.3.2)
fi
