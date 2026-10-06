# QuickTile

A free, open-source native iPhone control deck for your Mac. SwiftUI on both devices, Bonjour on your local network, and authenticated TLS. No QuickTile account, advertising, purchases, subscriptions, or page limits. Mac controls stay on your local network. The optional voice assistant sends command transcripts to Groq using your own API key.

The interface is monochrome. Application icons come from your own Mac in their original colors, proportions, and transparency.

## Run it

Requirements: iPhone with iOS 18 or later, a Mac with macOS 14 or later, and Xcode with the iOS 18/macOS 14 SDK APIs or newer. This project has been built with Xcode 27.0 beta (27A5252f) and the iOS/macOS 27 SDKs. Older OS runtime testing remains necessary; deployment-target compilation alone is not a runtime test.

1. Open `QuickTile.xcodeproj`. The shared Swift package is local; no third-party dependency downloads are needed.
2. Choose **QuickTileMac** and **My Mac**, then Run. The **QuickTile Mac** companion window opens and a four-square icon appears in the menu bar. Its native menu shows connection status, **Open Companion…**, pairing, pause/resume, refresh, and quit. Closing the window keeps the companion running; choose **Open Companion…** to reopen it.
3. Choose **QuickTile**, select your iPhone, select your development team in Signing & Capabilities, then Run. The existing starter bundle ID (`sahil.QuickTile`) and team are preserved; change them for your own account when needed.
4. Connect iPhone to Wi-Fi. The Mac may use Wi-Fi or Ethernet on the same reachable LAN. Allow Local Network access on both devices when requested.
5. Open the Mac menu → **Pair an iPhone…**. In the iPhone app choose **Pair with your Mac**, scan the QR, then explicitly choose **Connect** in the Mac companion's confirmation window. The QR expires after two minutes and is consumed on approval.
6. Choose an editable preset board or start with a blank board. Tap **Edit page**, then an empty slot to add an app, website, key, media control, dial, timer, agent status, or sequence. The board-icon menu → **Manage boards** adds boards and pages. Editing and timers work offline; browsing Mac catalogs and running Mac actions require authentication.

The Mac picker also accepts the *full* pairing invitation for an unavailable camera. This contains a temporary secret. It is not a short PIN. Keep it private and never paste it into an issue or log.

The app reconnects while foregrounded. It closes the connection when backgrounded, when the companion pauses/quits, or when the Mac sleeps. Actions are never queued for reconnection or retried automatically.

## Use your deck

- Eight slots fit on each page: two columns and four rows in portrait, four columns and two rows in landscape. Swipe, tap the page dots, or use the board-icon menu to navigate. Boards can contain multiple pages, including intentional empty slots; there is no vertical deck scrolling.
- Hold a tile or tap **Edit page** to enter editing. Keep holding and drag to a slot; pause at a horizontal edge to reach another page or board. Tap an empty slot to add a tile, use a tile's remove button to delete it, then **Undo** to restore a removal. Tap **Done editing** to finish. Holding never executes the tile.
- **Manage boards** provides renaming, icons, duplication, page names, blank pages, and board ordering. Its tile list and VoiceOver **Move tile**, **Duplicate tile**, **Edit tile**, and **Delete tile** actions provide alternatives to dragging. At least one board and one page per board are retained.
- The deck uses icons and specialized dial, timer, and agent status displays. Website tiles use the fetched icon by default, with a globe fallback. Apps, websites, keyboard tiles, and boards can use supported custom images or symbols; built-in controls keep semantic symbols. Names remain available to VoiceOver and in the editor. System/light/dark appearance, haptics, timer notifications, and foreground-only keep-awake are saved per Mac.
- Preset boards create independent editable copies. App profiles resolve supported bundle variants and allow a preferred installed app; optional board switching follows the Mac's frontmost app and waits while editing or interacting. Vendor shortcut mappings still require the real-app checks in [release gates](docs/RELEASE_GATES.md).
- Import/export uses data-only `.quicktile` files containing boards, mappings, website URLs, and selected images. Imports create new board/tile identifiers and disable automatic switching. Review names and URLs before sharing; pairing credentials and agent history are excluded.
- **Preview board** works without a Mac and is visibly labeled. Timers run locally; other preview tiles show a preview message.
- The Mac companion manages paired phones and revocation. Its menu pauses/resumes connections and refreshes catalogs; **Settings…** contains permissions, preferred apps, opt-in agent tracking, launch at login, and manual signed-update verification.

## Voice assistant

Add an Assistant tile from the action library. Configure your own Groq key in Mac Settings, agree to transcript processing on the iPhone, then tap to record and tap again to send. Tap the spinner to cancel. The waveform responds to microphone amplitude; audio is transcribed on-device and is never uploaded. The Mac sends the transcript and available app/Shortcut/action names to Groq’s `openai/gpt-oss-120b`, with `openai/gpt-oss-20b` as a rate-limit fallback. QuickTile validates all plans against existing controls before execution; it cannot execute arbitrary shell commands or arbitrary settings. The key stays in Mac Keychain and is excluded from layouts/exports. Groq usage may incur charges.

## Permissions and action behavior

**Local Network:** discovery and local transport only. iPhone camera access is requested only for scanning. Optional voice commands request Microphone and Speech Recognition for on-device transcription. There is no screen recording or input-monitoring request.

**Applications:** `NSWorkspace` resolves bundle identifiers and opens/activates apps. Discovery merges standard directories, CoreServices, the system Safari location, Spotlight-indexed applications, running applications, and manually added locations. Symlinked installations are resolved and duplicate bundle identifiers are merged; embedded helpers and iPhone-only builds are excluded. Refresh in the iPhone app picker rescans the Mac. For an unindexed app in another folder, use **Settings… → Applications → Add an app from another folder…** in the companion. Missing apps produce an error; moved apps can be found through Launch Services.

**Keyboard:** the first key action checks/request prompts for macOS Accessibility permission. Enable QuickTileMac in System Settings → Privacy & Security → Accessibility, then retry. The current-foreground option targets the frontmost app at tap time. A selected target is activated first; if activation is not confirmed, no keys are sent. Key labels represent physical ANSI positions. Secure input or an application may ignore synthetic events. “Key events posted” does not mean the app performed the shortcut.

**Playback:** **Mac playback** sends media-key events to the current player and requires Accessibility. Its state remains unknown; “Sent” means an event was posted. A media tile's **Player** picker can explicitly choose Spotify or Music instead. These fixed player adapters use supported AppleScript controls, may request Automation on first use, and report observed playing/paused state when readable; unavailable state stays unknown. Background reads check permission without prompting and do not launch a player app that isn't running. Player acceptance and multi-player behavior still need real-app verification. Existing Music tiles migrate to default Mac playback. Update both apps together for protocol version 2 and negotiated player-adapter support.

**Volume:** the dial reads and changes the default output's settable Core Audio master or conventional stereo channel volume. Turning it to zero uses master mute and records the previous level per output; raising it unmutes. Output changes refresh the state. Digital/HDMI devices can lack these properties; failed or unsupported controls show guidance. Older volume-button tiles migrate to volume dials.

**Brightness:** the dial lists displays and controls a supported selected display, with a readback after a change. The current Mac adapter dynamically loads private DisplayServices APIs. This is an implementation limitation that needs a distribution-policy review and hardware testing before release; it is not a promise of public-API support for arbitrary monitors. See [Apple API decisions](docs/APPLE_APIS.md).

**Timers:** one second to 60 minutes, managed on iPhone with persisted deadlines, pause/reset, and acknowledgement. Haptic reminders repeat only while QuickTile is open. Optional completion notifications require permission; timers do not keep background code running.

**Sequences:** up to 12 data-only steps can open apps/websites, send targeted keys, run an Apple Shortcut, or wait. The Mac reports the current step, stops at the first failure, and enforces a five-minute limit. **Stop sequence**, disconnect, pause, and revocation cancel remaining work; already completed effects cannot be undone.

**Agent status:** explicitly enable tracking in Mac settings to install QuickTile-owned local hooks for Codex and Claude Code. Codex hooks also require user trust in its hooks UI. Tiles show lifecycle phase, tracking health, and optional desktop/terminal filtering; waiting sessions take priority. The local Codex-log compatibility reader is bounded and depends on an unsupported log format. Prompts, tool arguments, and transcripts are not retained or sent to iPhone. Opening an agent tile launches its configured app, without a promise to focus a specific terminal session.

**Apple Shortcuts:** the Mac runs `/usr/bin/shortcuts list --show-identifiers` and `run <UUID>` using `Process.arguments`, never a shell command string. Renaming a shortcut does not change its saved UUID. A shortcut may need input/permission on the Mac. Accepted and completed are separate states. Execution is monitored for five minutes. A timeout/disconnect cannot undo effects already performed by a shortcut; inspect the Mac before retrying.

**Websites:** HTTP(S) only, opened by the Mac’s default browser. Credentials in URLs and whitespace/control characters are rejected. iPhone fetches the site's home page and declared touch icon/favicon over HTTPS, with bounded response sizes, timeouts, two concurrent website loads, and a local image cache. It never sends the saved URL's private path/query for icon discovery, uses no third-party favicon lookup service, and executes no website scripts. Sites without a usable icon show a globe. Loading website icons requires internet connectivity; the Mac control connection remains local.

**Catalog performance:** app/shortcut selection uses separate searchable lists with lazy rows and debounced background filtering. Catalog chunks are assembled before publication. Icons have individual observation scopes, background decoding, a bounded decoded-image cache, and six queued Mac requests at a time with timeout/retry support. Disk cache reads, writes, and pruning run off the UI thread.

## Build and test

```sh
# Shared logic plus actual TLS round-trip and wrong-key tests
swift test --package-path Shared

# Unsigned builds for local verification
xcodebuild -project QuickTile.xcodeproj -scheme QuickTile \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO build
xcodebuild -project QuickTile.xcodeproj -scheme QuickTileMac \
  -destination 'platform=macOS' \
  -derivedDataPath .build/mac CODE_SIGNING_ALLOWED=NO build

# Companion integration tests use temporary Keychain entries, actual TLS,
# local app/icon catalogs, and a real TextEdit launch. Build the bundle, then
# invoke it directly: Xcode 27 beta's xcodebuild test wrapper currently
# mis-resolves this hostless macOS XCTest bundle's executable path.
xcodebuild -project QuickTile.xcodeproj -scheme QuickTileMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/mac-tests \
  build-for-testing
xcrun xctest .build/mac-tests/Build/Products/Debug/QuickTileMacTests.xctest

# Substitute an available iPhone simulator name from `xcrun simctl list devices available`.
xcodebuild -project QuickTile.xcodeproj -scheme QuickTile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO -derivedDataPath .build/ios test
```

`Scripts/verify.sh` runs shared tests, unsigned app builds, and the Mac integration suite. Audio/display-changing tests are opt-in and are excluded from ordinary regression runs. Test results and physical-device checks are recorded in [docs/VERIFICATION.md](docs/VERIFICATION.md); outstanding public-release work is tracked in [docs/RELEASE_GATES.md](docs/RELEASE_GATES.md). Signing is required for a physical iPhone. An unsigned build is not a signed, notarized, or distributable release.

The Xcode project and shared schemes are checked in. To reproduce the target setup after deliberately modifying the starter project, run `python3 Scripts/configure_project.py` followed by `python3 Scripts/add_test_targets.py`. These scripts retain the original target identity. Regenerate the original app icons with `xcrun swift Scripts/generate_icons.swift "$PWD"`.

## Troubleshooting

- **“Hello, world!” window:** this is an old macOS build of the starter **QuickTile** target. Quit that app and run the **QuickTileMac** scheme with **My Mac** selected. The current **QuickTile** scheme is the iPhone app; the companion window is titled **QuickTile Mac**.
- **Mac not found:** open the companion menu and generate a QR. A fresh companion advertises only while an invitation is active; paired-device services are advertised while running. Check both Local Network permissions, firewall, VPN, guest Wi-Fi/client isolation, and Mac sleep. Discovery does not need the Mac itself to be on Wi-Fi.
- **Local Network denied:** enable QuickTile in Settings/System Settings → Privacy & Security → Local Network, return to the foreground, and retry discovery. Apple provides no general permission-query API. The simulator cannot verify this permission’s physical-device behavior.
- **Pairing fails:** generate a new QR and scan within two minutes. Check clock accuracy if invitations appear expired. Revoked devices must pair again.
- **Icons/catalog stale:** refresh apps, shortcuts, and icons from the Mac menu. Catalogs are also refreshed on app launch/termination, volume mount/unmount, and companion appearance changes. A custom icon changed while the companion’s panel is closed may need manual refresh.
- **Shortcut waiting:** check the Mac’s Shortcuts app for input and permission prompts. Do not repeatedly tap the tile.
- **Mac unsigned/rebuilt:** consistent Local Network, Accessibility, and Automation identity requires stable signing. Apple-issued signing identities are recommended for reliable permission tracking. Move the signed companion to `/Applications` before enabling launch at login.

## More

[Architecture and protocol](docs/ARCHITECTURE.md) · [Security and privacy](docs/SECURITY.md) · [Apple API research and icon limitations](docs/APPLE_APIS.md) · [Distribution](docs/DISTRIBUTION.md) · [Verification](docs/VERIFICATION.md) · [Contributing](CONTRIBUTING.md)

The implemented scope and remaining verification/distribution work are listed in [the implementation plan](docs/IMPLEMENTATION_PLAN.md). Settings includes an offline privacy policy and configured support/privacy URLs; the support and privacy pages are published and verified on GitHub Pages. Source is available at https://github.com/sqhil-a/quicktile. A signed, notarized companion download remains a release requirement.

MIT © 2026 Sahil Ambegaonkar (the original starter source’s named author). No third-party Mac application icons are included in this repository.
