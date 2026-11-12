#!/usr/bin/env bash
# Shared by build/check scripts; no downloads or machine configuration changes.
VN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VN_SWIFT_FLAGS=()
if [ -n "${VIBENOTCH_SDK:-}" ]; then
  VN_SWIFT_FLAGS+=(--sdk "$VIBENOTCH_SDK")
elif [ -z "${SDKROOT:-}" ]; then
  VN_DEFAULT_SDK="$(xcrun --show-sdk-path)"
  VN_INTERFACE="$VN_DEFAULT_SDK/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface"
  VN_CORE_INTERFACE="$VN_DEFAULT_SDK/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"
  # Some CLT SDK 27 installations ship the @State macro without its plugin.
  # The installed SDK 26.5 supplies the property wrapper used by this app.
  if grep -qs 'macro State()' "$VN_INTERFACE" "$VN_CORE_INTERFACE"; then
    VN_DEVELOPER="$(xcode-select -p)"
    if [ "$VN_DEVELOPER" = /Library/Developer/CommandLineTools ] && [ -d "$VN_DEVELOPER/SDKs/MacOSX26.5.sdk" ]; then
      VN_SWIFT_FLAGS+=(--sdk "$VN_DEVELOPER/SDKs/MacOSX26.5.sdk")
      echo "Using installed macOS 26.5 SDK for Command Line Tools compatibility." >&2
    fi
  fi
fi
if [ -n "${VIBENOTCH_BUILD_DIR:-}" ]; then VN_SWIFT_FLAGS+=(--scratch-path "$VIBENOTCH_BUILD_DIR"); fi
vn_swift() { command swift "$@" "${VN_SWIFT_FLAGS[@]}"; }
