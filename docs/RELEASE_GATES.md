# Public release gates

Implementation is not evidence of physical-device behavior, vendor shortcut correctness, signing, or App Store acceptance. Keep the following gates open until their recorded evidence exists.

| Gate | Evidence required | Current state |
|---|---|---|
| Real action mappings | App/OS/keymap version, disposable document, panel focus, expected effect, result for every shipped mapping | Pending real-app verification |
| Media players | System-key/browser behavior; selected Spotify/Music Automation denial/approval, unknown-state fallback, duplicate tiles, and multiple simultaneous sources | Adapter/parser implementation; real-player matrix pending |
| FCP reference workflow | Installed bundle variant resolution; three-page board; activation failure; customized keys; all mappings | Pending physical workflow |
| Agents | Desktop coding and terminal prompt/work/input/resolve/complete/interruption/crash/concurrency, trusted Codex hooks, Claude background work | Deterministic reducer/reader tests; approval correlation regressions passed; missing helper/old handlers repaired; user hook trust and full live matrix pending |
| Agent phone replies | Exact live question/approval, choices/free text, stale/cancelled request, acknowledgement, disconnect, installed Codex version | Protocol/UI tests passed; current desktop has no control socket; live replies pending |
| Voice assistant | On-device speech on real iPhone; first-use consent/permissions; successful Groq interpretation; action verification; disconnect/background/cancellation | Implemented and deterministic tests passed; live Groq interpretation passed after rate-limit fix; physical voice and end-to-end execution pending |
| Pairing/reconnect | QR/manual, approval/denial/expiry/repeat, lost ack, sleep/wake, revoked phone, paused overlay | Integration tests and physical matrix required |
| Hardware | Internal/headphone/Bluetooth/USB/HDMI mute, restore, device changes; supported/multiple displays | Pending; preserve/restore original values |
| Brightness API | Review private DisplayServices dependency and decide acceptable distribution/implementation path; confirm failure behavior when absent | Pending; current setter uses private API |
| iPhone UX | Smallest/oldest supported iPhone, portrait/landscape, visible continuous drag, edge paging, menus, timer recovery | Simulator tests plus physical review required |
| Accessibility | VoiceOver/Voice Control/Switch Control, large text, Reduce Motion, high contrast, light/dark | Pending physical assistive testing |
| Performance | <50 ms local tap response; p95 LAN <300 ms excluding launches; 1500-entry search; frame budget; 10-minute memory/tasks | Instrumented; real-device measurements pending |
| Runtime baseline | iOS 18 and current iOS; macOS 14 and current macOS | Deployment targets compile; runtime matrix pending |
| Privacy | Final signed archive report, accurate labels, public policy/support/source/download URLs, actual contact and in-app policy access, artwork rights | Manifest, offline policy, confirmed contact and configured policy/support URLs; publication/reachability verified; source repository configured; signed download, rights and final report pending |
| Export compliance | Final archive declaration matching the reviewed OS-only encryption; re-evaluate if cryptographic code, dependencies or features change | Source reviewed and `ITSAppUsesNonExemptEncryption=false` configured; confirm final archive, no current encryption-documentation requirement |
| Release signatures | iPhone archive validation, Developer ID hardened companion/helper, notarization/staple, clean Gatekeeper | iPhone App Store IPA exported with Cloud Managed Apple Distribution and signature verified; App Store Connect validation, Developer ID and notarization pending |
| Upgrade/uninstall | Keychain/layout/icon/timer preservation, permissions/login/hooks, signed manual update | Pending signed clean-machine test |
| Beta/review | Moderated pairing+useful board in <5 min; daily creative/dev beta; exact companion reviewer instructions/screenshots | Pending TestFlight and review assets |

## Verification record

Use `docs/ACTION_VALIDATION.csv` for the catalog and record actual results rather than replacing “pending” based on a compilation test. Similar shortcut names do not establish identical mappings. Bundled presets are editable starting mappings and are not advertised as verified until this gate closes.

Use disposable projects for third-party app tests. Audio/display tests save the original output/display and level, restore them even on failure, and require a deliberate operator action. Ordinary regression suites do not run hardware-changing tests.

## Build and submission

Run `bash Scripts/archive-release.sh iphone TEAM_ID BUILD_NUMBER` and validate/export the resulting archive in Xcode Organizer using the appropriate App Store profile. Run the same script with `mac` for a universal Developer ID companion. Notarize with `bash Scripts/notarize-companion.sh APP_PATH KEYCHAIN_PROFILE OUTPUT_DIRECTORY`; the profile is stored in Keychain, never in the repository. Verify the final nested helper signature as well as the app.

At submission time, use an SDK Apple accepts then; the installed beta SDK is not proof of submission eligibility. Confirm [Apple's submission requirements](https://developer.apple.com/news/upcoming-requirements/) and [review guidelines](https://developer.apple.com/app-store/review/guidelines/).

The listing/reviewer draft and local-export template are in [APP_STORE_SUBMISSION.md](APP_STORE_SUBMISSION.md). Publish and verify the confirmed policy/support URLs, supply the application-source and signed companion-download URLs, and complete the remaining private reviewer contact fields before submission; the template does not upload or publish.

App Review setup: install the signed companion, use a reachable local network, pair on iPhone, approve on Mac, and allow Accessibility for keyboard actions or system media keys. Explicitly selected Music/Spotify controls request Automation for that player instead. The clearly labeled iPhone Preview board lets a reviewer inspect layout and timers without a Mac; its other controls never claim real execution. Provide a short real-device demonstration for companion-dependent behavior.

## Distribution and maintenance

Publish a stable HTTPS companion download and support page owned by the project. Updates remain user initiated. Distribute only signed/notarized bundles; verify the signature, bundle ID, version, and team before replacement. Do not ship an unverified download/execution updater or silently change trusted agent hooks. Keep a previous signed release for recovery. The current companion reviews a user-selected signed update; if online update checks are added, configure and test the project-owned feed before shipping them.

Disable Launch at Login in companion settings, disable agent tracking to remove only QuickTile hooks, quit, then remove the application. Optional local files are under `~/Library/Application Support/QuickTile`; credentials remain in the QuickTile Keychain service until explicitly forgotten. Do not delete `.codex` or `.claude` directories when uninstalling QuickTile.
