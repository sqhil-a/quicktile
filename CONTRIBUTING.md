# Contributing

QuickTile is MIT licensed. Keep it free of ads, accounts, subscriptions, paid feature gates, and artificial page limits.

Use Swift/SwiftUI and public Apple APIs, prefer minimal dependencies, and keep permission requests tied to a feature the user invokes. Preserve monochrome chrome and untouched original Mac icons. Do not add third-party application icons to source control.

Before a change:

1. Read `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, and `docs/APPLE_APIS.md`.
2. Build both shared schemes at the deployment targets. Run `swift test --package-path Shared` and the relevant Xcode unit/UI tests.
3. Add meaningful tests for protocol, lifecycle, persistence, or action behavior changes. UI fixtures must remain DEBUG-only, disconnected, and explicitly launched by tests.
4. Check portrait/landscape, both appearances, accessibility text sizes, and VoiceOver. Never rely on color alone for status.
5. Record which checks were actually run and what still needs a physical device. Do not claim a command’s delivery proves its effects completed.

Do not commit build artifacts, signing keys, provisioning profiles, invitation strings, Keychain contents, real layouts, or sensitive logs. The original icon source is `Scripts/generate_icons.swift` and can be regenerated locally.

When changing protocol/schema, add migration or an explicit version rejection. Preserve unknown layout files. Security-related protocol changes require particular review: never replace TLS authentication with trust-on-first-network-contact, a bare short PIN, or a custom cipher.
