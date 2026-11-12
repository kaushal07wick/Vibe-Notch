# DynamicNotchKit

Vendored from https://github.com/MrKai77/DynamicNotchKit at
`cd0b3e52d537db115ad3a9d89601f20e0bee8d27`. Copyright Kai Azim; MIT license
is retained in LICENSE and included in the app's acknowledgments.

Local changes:

- Replace two `@Entry` declarations with equivalent `EnvironmentKey` properties.
- Guard the Xcode-only `#Preview` with `VIBENOTCH_ENABLE_PREVIEWS`.
- Package only runtime Swift sources; omit the documentation plugin, examples,
  tests, and documentation video from the application dependency.

These changes make clean-checkout builds independent of unavailable SwiftUI
macro plugins in Command Line Tools. No code or artwork from Aria is included.
