# Sourced by the release build and Swift tests.
SDK="$(xcrun --sdk macosx --show-sdk-path)"
swiftpm_flags=(-Xswiftc -warnings-as-errors)
# CLT 27 ships SwiftUI interfaces referring to an Xcode-only macro plugin.
# Preserve the working local toolchain when the compatible SDK is installed.
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools && "$(xcrun --show-sdk-version)" == 27.* && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
    swiftpm_flags+=(-Xswiftc -interface-compiler-version -Xswiftc 6.3.2)
fi
swiftpm_flags+=(--sdk "$SDK")
