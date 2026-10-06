# Verification record

Environment used for this record: Xcode 27.0 beta (27A5252f), iOS Simulator SDK 27.0, macOS SDK 27.0, and an iPhone 17 Pro simulator (iOS 27.0). The repository started as an unmodified SwiftUI starter; no `AGENTS.md` or Git history was present.

## Current implementation coverage

The source now includes schema-4 boards/packages/backup recovery, direct hold/drag editing and undo, app profiles and vendor mappings, sequences, persistent timers, optional agent tracking, audio/display controls, explicitly selected Spotify/Music adapters, preview mode, and signed-update review. Test source covers package identity/gap preservation and invalid assets, known-good backup recovery, timer persistence, turn/request lifecycle reconciliation, hook preservation/removal, incremental Codex records, media-key event construction, player selection/state parsing, authenticated companion actions, and simulator board/timer/sequence/preview flows.

Coverage in source is not a recorded pass or real-app acceptance. Historical results below apply to their dated revisions. New run commands/counts/result bundles must be recorded for the final changed source before treating them as current. Physical/vendor/signing work stays open in [RELEASE_GATES.md](RELEASE_GATES.md).

Ordinary companion tests skip hardware changes. Setting `QUICKTILE_TEST_HARDWARE=1` explicitly enables audio/display checks; use deliberate operator control, record original output/display/level/mute state, and verify restoration even on failure. A current-level read/write on one Mac does not validate the hardware matrix.

## Recorded passed checks

### Agent requests, timer feedback, and editing follow-up (2026-10-05)

- Shared suite: **59 tests, zero failures**, including approval-wrapper correlation, ambiguous legacy-record recovery, pending question lifecycle, and backward-compatible timer haptic persistence. Log: `/private/tmp/quicktile-agent-replies-shared.log`.
- Mac suite: **31 tests, zero failures, 3 deliberate skips** (28 ran; two hardware checks and the opt-in live Groq check skipped). Includes control-protocol status/resolution, cancelled targets, original request/answer encoding, duplicate-response lockout and matching acknowledgement. Log: `/private/tmp/quicktile-agent-replies-mac-tests.log`.
- Focused iPhone tests: **3 passed** for request choices/send/return to Running, timer haptic selection/preview availability, and hold/drag/exit editing. Bundle: `.build/product-ios/Logs/Test/Test-QuickTile-2026.10.05_19-32-54--0400.xcresult`. The simplified request UI was then rerun successfully: `.build/product-ios/Logs/Test/Test-QuickTile-2026.10.05_19-37-28--0400.xcresult`. These use DEBUG fixtures, not live Codex answers or physical haptic measurements.
- The existing tracking helper was updated without modifying hook definitions or trust records. Live local metadata then showed Running with zero pending requests in both currently active Codex sessions. A subsequent merge regression was reproduced in the live companion and fixed by seeding from the fresh complete hook checkpoint rather than replaying its last event after a closed log turn. The restarted companion visibly showed Codex Running and Receiving lifecycle events. This is a point-in-time observation, not the complete lifecycle matrix.
- The current desktop Codex process has no supported control socket. Requests from that session are read-only; end-to-end reply delivery requires a compatible live control connection and remains unverified. Codex UI inspection was explicitly denied by the environment; no alternate UI automation was used. See [AGENT_REPLIES.md](AGENT_REPLIES.md).
- Timer tiles provide seven saved choices: Click, Double click, Soft tap, Firm pulse, Alert, Vibration, and None. Preview respects the haptics setting. Reminders are foreground-only; queued second clicks recheck acknowledgement/deletion/settings before firing. Stronger Alert/Vibration reminders use a two-second interval.
- Editing wiggle uses a paused clock-driven rotation, with zero rotation when inactive, instead of `repeatForever`. Reduce Motion disables it. Physical-device motion/frame-rate acceptance remains pending.
- Universal Mac Release and Apple Development iPhone archives succeeded. The iPhone archive is version 1.0/build 5 and was installed successfully on the connected Sahil’s iPhone. No physical launch or interaction acceptance is claimed. Support/privacy outputs were regenerated and exported locally with the new pending-request disclosure; nothing was published.


### Floating message redesign (2026-10-05)

Replaced the full-width safe-area banner with an inset, rounded native-material notice overlay. Messages wrap without truncation; the dismissal target remains 44 points. Opacity/short-offset motion respects Reduce Motion, and new messages are announced for VoiceOver. The overlay does not alter the tile grid geometry.

The focused assistant/offline UI regression passed, including unchanged tile position while a message appears and successful dismissal. Result: `.build/product-ios/Logs/Test/Test-QuickTile-2026.10.05_18-31-24--0400.xcresult`; reviewed screenshot: `.build/notice-screenshots/C3F6819E-EA22-4D1F-9F6E-34811BD8C52A.png`. The Apple Development-signed iPhone Release archive was refreshed as version 1.0/build 3. Physical-device appearance remains a release acceptance step.


### Rate-limit fix (2026-10-05, evening)

The assistant now sends a bounded, locally ranked app/Shortcut/action shortlist instead of the entire Mac catalog. A 120B HTTP 429 triggers one interpretation retry with `openai/gpt-oss-20b`, retained for the companion session. Neither interpretation attempt executes actions; the same strict parser and complete preflight apply before execution. Authentication, invalid responses and other failures do not trigger model retries.

The companion suite passed **27 tests with zero failures and 2 hardware skips** (25 ran), with `QUICKTILE_TEST_GROQ=1`. The explicitly enabled live check used the configured Keychain credential to interpret “Please open Safari,” returned the correct installed-app plan, and executed nothing. Large 1,500-app request bounding, fallback, and subsequent smaller-model use passed. Log: `/private/tmp/quicktile-rate-limit-tests.log`. This closes the previously recorded live Groq HTTP-429-only evidence, but not physical speech/end-to-end execution or future organization-wide quotas.


### Assistant and agent follow-up (2026-10-05)

- Shared suite: **54 tests, zero failures**, including canonical voice parsing, request validation, approval/tool correlation, overlapping requests, turn isolation, hook metadata persistence, and TLS. Log: `/private/tmp/quicktile-assistant-shared.log`.
- Companion suite: **24 tests, zero failures, 2 hardware skips**. Includes strict Groq response validation, refusal/limit/redirect/size handling, exact supplied-URL checks, preflight and authenticated assistant transport/replay protection. No live cloud call or hardware mutation is used by these mocks. Log: `/private/tmp/quicktile-assistant-mac-tests.log`.
- Full iPhone suite: **12 tests, zero failures**, plus **1 focused assistant presentation test, zero failures**. Result bundles: `.build/product-ios/Logs/Test/Test-QuickTile-2026.10.04_23-54-44--0400.xcresult` and `.build/product-ios/Logs/Test/Test-QuickTile-2026.10.05_00-00-40--0400.xcresult`. The DEBUG recording fixture verifies waveform presentation, navigation exclusion, processing cancellation, and edit cancellation; it does not verify live speech. Screenshot: `.build/assistant-screenshots/434FD328-9DE6-486F-B317-7BA2776E79DB.png`.
- Groq credential stored in Mac Keychain; running companion shows Configured. A harmless live interpretation probe returned **HTTP 429**. No Mac action ran. Successful live cloud execution remains open.
- Actual agent installation repaired via companion Settings: missing helper installed, outdated QuickTile-owned handlers updated, unrelated hooks preserved. User Codex hook trust and fresh live approval events remain pending.
- Both unsigned Release archives refreshed; Apple Development-signed iPhone Release archive succeeded as version 1.0/build 2. Its signature verifies team `M26FDHM6XS`. This is not an App Store distribution archive. Three icon variants and website publication-format checks passed. Updated sites exported to the two sibling development folders; no push/publication occurred.

Earlier sections below are historical evidence and do not replace these final-source counts or the open release gates.

### Product/release implementation (2026-10-04)

- Shared Swift suite: **36 tests, zero failures**, including the real TLS round trip/wrong-key rejection, schema/mapping compatibility, profile aliases, all bundled preset references, bounded sequences, import validation/new identities, backup recovery, persistent timers, observed-player parsing/availability, and agent request/turn reconciliation. Hook cleanup preserves unrelated commands even when they mention QuickTile. Final command: `swift test --package-path Shared`; execution required the local-network sandbox exception.
- Current iPhone UI suite: **7 tests, zero failures** on iPhone 17 Pro/iOS 27 simulator. Covers eight icon-only slots in portrait/landscape, swipe forward/back after rotation, continuous hold/drag and destination placement, editing remaining on its page, removal/Undo, preset board/icon selection, forward category/app/timer navigation, sequence validation, searching the 1,500th catalog entry, and preview controls never executing. Result bundle: `.build/product-ios/Logs/Test/Test-QuickTile-2026.10.04_06-22-36--0400.xcresult`. Exported native screenshots were visually inspected; they are test fixtures, not App Store marketing assets.
- Companion suite: **11 tests, zero failures, 2 deliberate hardware-test skips** (9 checks ran). Covers minimal agent metadata, incremental large-header/partial-record reading, app discovery, paired TLS approval/catalog/icon transfer, real TextEdit opening, replay/stale-session/revocation/reconnect protection, explicit pause/rejection/revocation messages before socket closure, resume with a new session, argument/timeout handling, media-key press/release events, and changed app-identity rejection. Command: `xcrun xctest .build/product-mac/Build/Products/Debug/QuickTileMacTests.xctest` after `build-for-testing`. The hardware environment flag remained unset; the integration flow also avoids audio writes by default.
- Raster alignment verification: **all three iPhone icon variants passed** `swift Scripts/verify-icon-geometry.swift`; checks equal square dimensions, aligned rows/columns, equal spacing, and centering in the generated PNGs. Xcode compiled both asset catalogs, including the shared-geometry menu-bar template mark.
- Unsigned **Release archives succeeded** for the device iPhone target and universal Mac companion. The Mac app and event helper contain both `arm64` and `x86_64` slices. The iPhone archive includes the privacy manifest and exported `.quicktile` JSON document declaration. These are local build artifacts, not signed distribution archives.
- Plist validation and shell syntax checks passed. `security find-identity -v -p codesigning` reported **0 valid identities**. Developer ID signing, notarization, App Store archive validation and TestFlight cannot be inferred from unsigned builds.

The rotating pager regression was reproduced and fixed with native horizontal paging. A headless Mac launch test also exposed the need to separate successful application opening from confirmed keyboard focus: app opening now reports its framework result, while targeted keys and sequence activation still require the intended app to become foreground. No keystroke-success claim is made by the launch test.

A final transport check found that local socket-close reasons were not transmitted to the phone. Server-initiated pause, denial, expiry, and revocation now send an authenticated terminal message and allow a bounded drain, while immediately revoking local work. The real companion test asserts the paused reason, successful resumed session, rejection reason, and revoked reason. Shared and companion suites were rerun after this fix; both unsigned Release archives were refreshed. Physical scanning and lifecycle acceptance remain open.

### Board controls follow-up (2026-10-04)

The bottom-left board icon now presents a native board picker. Management switches within the same sheet instead of attempting presentation during Menu dismissal. Page selection is applied after the picker dismisses. The new regression creates a blank board, switches to it, returns to the original board, and reopens management.

The complete iPhone simulator UI suite passed **8 tests with zero failures**, including existing editing, rotation/swiping, presets/icons, timers, sequence navigation, catalog search, and preview behavior. Result bundle: `.build/product-ios/Logs/Test/Test-QuickTile-2026.10.04_09-30-24--0400.xcresult`. These changes have not been installed or checked on a physical iPhone during this follow-up.

### Page edges and Undo follow-up (2026-10-04)

The horizontal pager is clipped at the grid viewport so neighboring pages cannot draw into landscape safe-area margins. Removal history now retains multiple layout checkpoints; each Undo restores the preceding removal and stays available while earlier checkpoints remain. Closing inline editing or board management clears the history.

The complete simulator UI suite passed **9 tests with zero failures**. The new test removes two tiles, undoes each in reverse order, then verifies that closing and reopening editing does not retain Undo. Portrait/landscape fit, swiping, dragging, and board navigation also passed. Exported landscape screenshots were inspected and show no neighboring tiles in the margins. Result bundle: `.build/product-ios/Logs/Test/Test-QuickTile-2026.10.04_10-08-30--0400.xcresult`. Physical-device verification remains pending.

### Polish and submission preparation (2026-10-04)

This record applies to the polish revision before a subsequently reported Codex approval/waiting tile update regression. That regression is under investigation; relevant tests and archives must be refreshed for changed source before these results are treated as the final changed-source evidence.

The final iPhone simulator UI suite passed **11 tests with zero failures**. In addition to the earlier board, paging, rotation, dragging, removal/Undo, preset, timer, sequence, search, and Preview regressions, the suite verifies that tapping a tile while editing opens its configuration, a failed test action reports its result inline, and the offline privacy policy is available without a connection. Result bundle: `.build/product-ios/Logs/Test/Test-QuickTile-2026.10.04_11-33-50--0400.xcresult`; log: `/private/tmp/quicktile-final-polish-ui-v2.log`.

Final shared checks passed **36 tests with zero failures**, including real authenticated TLS/wrong-key rejection, and final companion checks completed **11 tests with zero failures and 2 deliberate hardware skips** (9 checks ran). Logs: `/private/tmp/quicktile-final-audit-shared.log` and `/private/tmp/quicktile-final-audit-mac-tests.log`. All **three iPhone icon variants** passed the geometry verifier.

The final UI changes use a static UIKit snapshot for finger-following tile movement without updating SwiftUI state for each movement; tile content keeps a stable structure across editing, pages load lazily, removal controls are simpler, and edit haptics are prepared before use. The editing drag gesture uses a 6-point movement threshold so taps and removal controls remain usable. Tile configuration displays actual test completion/failure, an in-flight spinner, cancellation, and sequence progress. The General action-picker entries were restored, Mac appearance changes no longer resend the full catalog, and iPhone Settings guidance is shown only after camera denial. These implementation choices and simulator passes do **not** establish measured frame rate or real-device gesture/performance acceptance.

Both final unsigned Release archives were rebuilt successfully: `.build/releases/QuickTile-unsigned.xcarchive` and `.build/releases/QuickTileMac-unsigned.xcarchive`. Build logs `/private/tmp/quicktile-final-release-ios.log` and `/private/tmp/quicktile-final-release-mac.log` contain `ARCHIVE SUCCEEDED`. Archive inspection confirmed version **1.0**, build **1**, iPhone minimum **iOS 18.0**, and Mac minimum **macOS 14.0**; neither archive contains an XCTest bundle. The iPhone includes its privacy manifest, confirmed policy/support URLs and contact email, and `ITSAppUsesNonExemptEncryption=false`. The Mac app and `Contents/Helpers/QuickTileAgentEvent` each contain `arm64` and `x86_64` slices. There are **0 valid code-signing identities** recorded; these builds do not validate Developer ID, notarization, provisioning, or App Store distribution.

The running native QuickTileMac dashboard and Settings were inspected and showed the current companion rather than the starter screen. During the active work session, Codex showed **Running** through **Compatibility tracking**; Claude showed unavailable while awaiting its first event. This is a live status observation, not the complete vendor hook/lifecycle acceptance matrix.

Both static website outputs passed local publication-format checks and were exported into the sibling development folders `quicktile-support` and `quicktile-privacy`. No Git repository was initialized, and no content was pushed or published. Browser review at **320, 390, and 1280 pixels**, in light and dark appearance, found no horizontal overflow; the native support disclosure/accordion controls worked. Reviewed screenshots: `.build/website/screenshots/support-desktop-light.jpg` and `.build/website/screenshots/support-phone-dark.jpg`. Remote Pages reachability, application-source and signed companion-download URLs, screenshots of the final submitted app, physical acceptance, and signing remain open. See [FINAL_AUDIT.md](FINAL_AUDIT.md) and [RELEASE_GATES.md](RELEASE_GATES.md).

### Eight-tile deck and application discovery update (2026-09-06)

- `swift test --package-path Shared`: 10 tests passed, including lossless eight-tile pagination and empty-page preservation.
- iPhone UI suite in `.build/ui-polish-results`: 4 tests passed. All eight app buttons were hittable and inside the screen in portrait (2 × 4) and landscape (4 × 2); app tiles had no text children; the ninth tile remained reachable through the page menu. Exported screenshots were visually inspected.
- Mac tests in `.build/catalog-fix/Build/Products/Debug/QuickTileMacTests.xctest`: 4 tests passed. Discovery merges external paths and symlinks, excludes embedded helpers and iPhone-only builds, and includes installed Safari and Finder in the real catalog. Pairing, icon transfer, real app launch, revocation, and process checks also passed.
- Both development-signed app builds succeeded. The updated companion was restarted, and `devicectl` installed the updated iPhone app on the connected physical iPhone. Launch was refused because the iPhone was locked; visual and connection verification on that physical device remain pending.

### Performance and icon update (2026-09-06)

- `QuickTileUITests`: 6 tests passed, including swipe-left/right navigation, long-press Edit/Delete without executing the action, a 1,500-app searchable catalog, website tile label suppression, and website icon caching.
- The large-catalog measurement averaged 0.175 s CPU time, 51.7 MB peak physical memory, and 914k retired instructions while scrolling the picker and filtering an item near the end of the catalog. The run used XCTest CPU/memory metrics; the complete run also passed on the iPhone 17 Pro simulator.
- `swift test --package-path Shared`: 13 tests passed, including icon queue overflow/retry behavior and website-origin/icon candidate validation.
- Final unsigned iOS and macOS builds succeeded; the final development-signed iPhone build succeeded and was installed on the connected device.

### Initial implementation

| Check | Command / method | Result |
| --- | --- | --- |
| Shared protocol, security, validation, persistence, and migration tests | `swift test --package-path Shared` | 9 tests, 0 failures |
| iOS target compilation | `xcodebuild -project QuickTile.xcodeproj -scheme QuickTile -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/final-ios CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO build` | `BUILD SUCCEEDED` |
| macOS target compilation | `xcodebuild -project QuickTile.xcodeproj -scheme QuickTileMac -destination 'platform=macOS' -derivedDataPath .build/final-mac CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO build` | `BUILD SUCCEEDED` |
| Mac integration build | `xcodebuild -project QuickTile.xcodeproj -scheme QuickTileMac -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/final-mac-tests CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO build-for-testing` | `TEST BUILD SUCCEEDED` |
| Mac integration execution | `xcrun xctest .build/final-mac-tests/Build/Products/Debug/QuickTileMacTests.xctest` | 3 tests, 0 failures |
| iPhone UI tests | `xcodebuild -project QuickTile.xcodeproj -scheme QuickTile -destination 'platform=iOS Simulator,id=CD7FEB95-01A4-4AD3-AE4A-E0A9A13A4C72' -parallel-testing-enabled NO test` | 3 tests, 0 failures |
| Asset catalogs and Info.plists | Xcode `actool` during both builds; `plutil -lint` on plist files | Asset catalogs compiled; plist files valid |
| Companion launch fix (2026-09-06) | Built `QuickTileMac` with configured development signing, quit both previously running apps, and launched the exact rebuilt product; inspected its native accessibility tree | `BUILD SUCCEEDED`; **QuickTile Mac** window visible with **Ready to pair**, **Pair an iPhone**, permissions, and connection help. The old **Hello, world!** window belonged to a stale `QuickTile.app` starter process. |

The TLS integration test uses real Network.framework sockets and a wrong-key client. The companion integration tests create an expiring invitation, approve it, establish the new credential session, receive app/catalog/icon data, launch TextEdit through its bundle identifier, reject a duplicate request, reject a stale session, and revoke the device. The process test checks structured arguments with shell punctuation and timeout termination.

The iPhone UI suite exercises the empty pairing/help state, page creation, website URL rejection, tile creation, portrait and landscape screenshots, dark appearance, a disconnected action error, and an accessibility-size launch. Screenshots were attached to the Xcode result bundle during the run.

The Xcode 27 beta `xcodebuild test` wrapper was also tried for the Mac bundle. Its runner reported that the executable could not be located even though `Contents/MacOS/QuickTileMacTests` existed and `xcrun xctest` ran the same bundle successfully. The reproducible command above therefore uses `build-for-testing` plus direct `xctest`; this is recorded as a toolchain limitation rather than a test-code result.

## Not verified here

- Physical iPhone Bonjour discovery, iOS Local Network permission prompts, camera scanning, Keychain behavior under a signed provisioning profile, background/foreground transitions, and sleep/wake reconnection.
- A signed Developer ID Mac app/helper, real Accessibility/synthetic-key behavior, Automation for selected media/system controls, launch at login, Gatekeeper/notarization, signed update review/replacement, and clean-machine upgrade/uninstall.
- Exact icon comparison against Finder/Dock rendering, dark/tinted/Liquid Glass app icon variants, external displays, HDMI/digital output volume devices, and shortcuts that pause for interactive input.
- iOS 18 and macOS 14 runtime behavior. The source compiles with deployment targets iOS 18.0 and macOS 14.0; the available simulator/runtime used for UI checks was newer.
- Vendor action mappings across app/keymap versions, focus/activation failure, the full Final Cut Pro workflow, and multi-player media behavior.
- Persistent timer notifications/recovery on a physical iPhone, continuous drag/edge paging under physical touch and assistive input, and sustained real-device performance.
- Live Codex/Claude Code hook trust, concurrency, background work, interruption/crash/recovery, and compatibility-reader behavior with current vendor versions.
- Private DisplayServices distribution acceptability and supported/multiple-display behavior. Capability checks and readback do not establish a supported public API.

These are physical-device and signed-distribution follow-ups. The dated development builds/install attempts above are historical evidence only; no completed physical acceptance matrix, Developer ID release, notarization, App Store approval, or public release is claimed.
