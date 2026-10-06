# Implementation plan and status

This is the status of the source implementation, not a claim that QuickTile is ready for public distribution. Completed code, deterministic test coverage, physical verification, and signed release evidence are different milestones. The remaining gates are tracked in [RELEASE_GATES.md](RELEASE_GATES.md), with recorded runs in [VERIFICATION.md](VERIFICATION.md).

## Implemented in source

| Area | Current implementation |
|---|---|
| Native targets | iPhone SwiftUI app at iOS 18 and menu-bar/window macOS companion at macOS 14; local shared package; checked-in project/schemes; starter identities preserved |
| Local trust | Bonjour; TLS-PSK; expiring QR/full manual invitation; explicit Mac confirmation; per-device listeners; Keychain; revocation, pause, sleep/wake, and foreground reconnection |
| Boards and editing | Eight slots per page, portrait/landscape, gaps/page names, hold/drag and edge paging, remove/undo, duplication, destination selection, accessible move actions, list ordering, custom icons, and independent editable preset copies |
| Layouts and sharing | Schema 4 migration from versions 1–3; unknown-action preservation; atomic writes/known-good backup recovery; bounded data-only packages with custom assets, fresh imported IDs, and no pairing secrets |
| App and action library | Search/categories/recents, app/Shortcut catalogs, bundle variants and preferred app selection, editable vendor mappings, setup guidance, test action, and optional frontmost-app board switching |
| Execution | App launch, targeted physical keys, default media keys plus explicitly selected Spotify/Music controls/state, fixed system actions, Core Audio volume/mute, bounded UUID-based Shortcuts, HTTP(S) websites, and structured results; no remote shell/script source |
| Sequences | 1–12 targeted data-only steps, progress/cancellation, first-failure stop, and five-minute bound |
| Local timers | Persisted per-Mac deadlines/acknowledgement, pause/reset, foreground haptics, and optional completion notifications |
| Agent activity | Explicit hook install/repair/removal, bundled helper, minimal lifecycle metadata, turn/request reconciliation, health/source filtering, and bounded incremental Codex-log compatibility reader |
| Icons and performance | Original Mac icons, content-addressed caches, bounded direct website icons, custom images, lazy searchable lists, bounded requests, background IO/decoding, and local signposts |
| Companion settings | Permissions, external app locations, preferred app variants, launch at login, opt-in tracking, and manual review of a newer same-team Developer ID update |
| Release preparation | iPhone privacy manifest, offline policy and configured support/privacy/contact links, OS-only encryption declaration, preview board, archive/notarization scripts, action validation worksheet, and release gates |

Brightness is implemented through dynamically loaded private DisplayServices APIs with capability checks and readback. Its public distribution acceptability and supported hardware remain open gates. Vendor shortcut names and compilation do not establish correct behavior in a user's installed app or keymap.

## Required before a public release

1. Complete the action-validation matrix in disposable documents, including Final Cut Pro's reference workflow, app variants, customized keys, panel focus, activation failure, and real media-player behavior.
2. Exercise physical pairing/reconnect/revocation and signed Keychain/permission behavior; review the smallest supported iPhone, gestures, timer recovery, assistive technologies, and oldest supported OS runtimes.
3. Measure real-device tap/LAN latency, large-catalog performance, frame budget, and sustained memory/tasks. Review output/mute restoration, display selection, and hardware changes with deliberate operator control and saved original values.
4. Verify live agent lifecycle behavior, trusted hooks, concurrent desktop/terminal sessions, background work, interruption, crashes, repair, and safe uninstall with current vendor versions.
5. Resolve private brightness API policy/implementation decisions; audit final privacy reports and artwork rights; publish and verify the confirmed privacy/support URLs, and supply the application-source and signed companion-download URLs.
6. Validate an iPhone distribution archive and stable Developer ID companion/helper; notarize/staple, assess Gatekeeper on a clean Mac, and verify signed upgrades/uninstall. Credentials remain outside the repository.
7. Run onboarding/daily beta, prepare companion-dependent App Review instructions/screenshots/demo, and confirm Apple's SDK/submission requirements at submission time.

The recorded development environment uses Xcode 27.0 beta (27A5252f) and newer iPhone/macOS SDKs. Deployment-target builds do not verify iOS 18 or macOS 14 runtime behavior. Release preparation is implemented; no published release, App Store approval, Developer ID signature, or notarization is asserted here.
