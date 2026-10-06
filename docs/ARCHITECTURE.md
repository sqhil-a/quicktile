# Architecture and protocol

## Modules

- **QuickTile (iOS):** SwiftUI deck and hold/drag editing, board/page/tile management, connection/QR UI, presets and action search, `PhoneModel` lifecycle, per-Mac layouts, local timers, authenticated Mac controls, and bounded icon caches.
- **QuickTileMac:** menu-bar/companion/settings windows, `MacServer` trust/lifecycle, `Catalog` app discovery/original icons, `ActionExecutor`, bounded `ProcessJob`, audio/brightness and optional player adapters, agent tracking/helper, and manual signed-update review.
- **Shared / QuickTileCore:** models, action registry/app profiles, presets, sequences/timer persistence, board packages, agent reducers/hooks, wire messages, TLS/framed channels, Bonjour, Keychain, atomic layout migration/backup recovery, and command admission.

Observable UI/network state is main-actor-owned. Network callbacks hop onto that actor. `LayoutWriter` serializes layout encoding and IO; image IO/decoding and agent-record parsing run outside the UI actor. Catalog icon extraction yields between apps. Process execution uses asynchronous termination callbacks and a cancellable deadline monitor. No action executor accepts remote shell source or executable paths.

The iPhone uses native horizontal scroll paging; hold recognition is scoped to its grid. Editing disables ordinary page scrolling, while drag edge dwell changes the controlled page. Shared tile metrics define spacing, icon scale, surface, and corner geometry. Final action feedback occupies a fixed centered region, independent of Undo visibility. A short background task protects a pending layout flush; selected-document reading and imported image processing run off the UI actor.

App opening uses the catalog URL and verifies its bundle identity before and after the framework call. An opened app may remain in the background if macOS declines activation. Targeted keyboard actions and sequence activation require confirmed foreground identity and never send keys following activation failure.

## Pairing and trust

The Mac generates a 256-bit `SecRandomCopyBytes` secret and random invitation UUID. An expiring QR/manual invitation contains invitation format version 1, stable Mac UUID, display name, secret, and expiry, without an IP address. The invitation format version is independent of the wire protocol. The phone resolves its UUID through `_quicktile._tcp` Bonjour.

Every invitation and paired device has a separate `NWListener` configured with exactly **one** TLS PSK. This binds authorization to the accepting listener without trusting a client-supplied device name or identity. Listener ports are dynamic and Bonjour updates them across launches. Discovery TXT metadata contains only public device/service metadata, never secrets, applications, or shortcuts.

The invitation listener accepts only a pair request and keepalive traffic. Local Mac approval creates a new independent 256-bit per-device credential, saves it in Keychain, starts a device listener, and transmits the credential over the invitation’s authenticated TLS channel. The invitation is consumed. The phone saves its credential in Keychain and establishes a new channel to the paired endpoint. Display names are untrusted labels, not authentication evidence.

Revocation first persists credential removal, then cancels the device listener, revokes every associated session, and closes its channels/cancels pending work. Failure to persist is shown rather than claiming durable revocation. Pause, sleep, and quit close channels and stop listeners; resume/wake starts new listeners. No queued commands survive reconnection.

## Wire protocol v2

Transport: TCP + TLS 1.2 with `TLS_PSK_WITH_AES_128_GCM_SHA256`, implemented by Security/Network frameworks. Each application message is a 4-byte unsigned big-endian byte length followed by UTF-8 JSON for `Envelope(version, id, payload)`. Swift Codable encodes typed enum cases. Protocol 1 peers are rejected with update guidance; both apps must use protocol 2.

`hello` optionally advertises feature identifiers. Optional capability fields preserve compatibility with older protocol-2 payloads. The companion gates sequences and newer state/display fields according to the peer's features; feature negotiation does not permit incompatible envelope versions.

Selected Spotify/Music media actions also require the negotiated `media-player-adapters.v1` feature and a fixed allowlisted `targetBundleID`. Default system keys always report unknown state. Selected-player snapshots use shared target identity, observed state, and a nonprompting Automation check before background reads; they do not infer state from taps or launch a player app for polling.

| Message | Direction | Meaning |
| --- | --- | --- |
| `pairRequest(Hello)` | phone → invitation listener | Ask for explicit local approval; no action authorization |
| `paired(Credential)` | Mac → phone | New permanent credential, over authenticated invitation TLS |
| `hello(Hello)` | phone → paired listener | Greet after TLS authentication, with optional feature identifiers |
| `welcome(Welcome)` | Mac → phone | Mac ID, new session UUID, server time, current capabilities |
| `catalogRequest` / `catalog(CatalogChunk)` | authenticated only | Generation, chunk index, up to 100 apps/100 shortcuts, final marker, optional note |
| `iconRequest(version)` / `icon(IconAsset)` | authenticated only | SHA-256-addressed 256px original PNG; unchanged images reused locally |
| `command(Command)` | authenticated phone → Mac | Request ID/session/timestamp/action, optional target/custom mapping |
| `result(ActionResult)` | Mac → phone | Same request ID; `accepted`, then `completed`/`failed`; optional outcome/sequence progress |
| `cancelCommand(requestID)` | authenticated phone → Mac | Cancel remaining work for this peer's running request |
| `controlsRequest` / `controls(ControlState)` | authenticated | Output volume/mute/restore state and supported display values |
| `adjustControl(ControlAdjustment)` | authenticated phone → Mac | Session/timestamp-validated volume or selected-display adjustment |
| `selectedDisplay(displayID)` | authenticated phone → Mac | Select a supported display for this connection |
| `capabilities` | Mac → phone | Permissions/features, frontmost app, optional playback and agent health/source state |
| `ping` / `pong` | either | Liveness only |
| `closed` or EOF/error | either | Stop session and invalidate outstanding work |

The welcome timestamp supplies a clock offset for phone command timestamps. Invitation expiry still requires approximately correct device clocks. A `commandSent` outcome means events were posted, not that a vendor app accepted the shortcut.

## Bounds and failure handling

- Maximum JSON frame: 2 MiB. Read/validate the length before requesting body bytes.
- Maximum PNG: 256 KiB; receiver validates SHA-256, PNG decoding, and dimensions up to 512px.
- Output backpressure: at most 8 MiB of outstanding channel sends.
- Up to 16 simultaneous channels, four pending approvals, four in-flight actions per device/eight overall, and bounded per-minute request admission. These are security/resource bounds, not page or tile feature gates.
- Pairing QR expires in 120 seconds. Invite creation has a three-second cooldown.
- Greeting timeout: 12–15 seconds. Pair approval deadline: invitation expiry. Liveness: 15-second pings, 45-second receive timeout; TCP keepalive supplements this.
- Commands older than 10 seconds or more than two seconds in the future are rejected. Session mismatch is unauthorized. Up to 512 admitted IDs are retained for 60 seconds, longer than a valid command’s lifetime. Duplicate IDs are rejected, never replayed.
- Non-idempotent commands are sent once. Disconnect clears the client’s pending requests. A missing reply is an unknown outcome, not proof of nonexecution.
- Ordinary phone action wait: 30 seconds. Shortcuts/sequences execute for at most 300 seconds, with 310-second phone waits. Sequences allow 1–12 steps; waits are greater than zero and at most ten seconds each; keys require an app target. Keyboard workflows are serialized and stop at the first failure.
- Process output is redirected to private temporary files, bounded to 1 MiB per stream by a 250ms monitor; only bounded error excerpts return. Dial adjustments use the same session/timestamp/replay admission as tile commands.
- On cancellation QuickTile terminates its local process. This cannot undo effects already performed or guarantee cancellation of automation spawned by Shortcuts.

## Persistence

The stable Mac UUID is local UserDefaults metadata. Credentials live in device-only Keychain generic-password items. Layout JSON in iPhone Application Support/QuickTile/Layouts is named by Mac UUID. Schema **4** reads versions 1–4, preserves board/tile identities, migrates Music actions to media and old volume actions to dials, and retains unknown action payloads as unavailable tiles. Atomic writes preserve a known-good previous layout in `.backup.json`; loading can recover that backup. Unsupported future/corrupt files are preserved, with saving disabled when no valid layout is available.

The persisted `DeckPage` type represents a board. Ordered nullable slots preserve gaps and split into eight-slot `DeckScreen` pages. Board/page names, app-profile linkage, and icon references are saved with the board. Optional switching follows the authenticated frontmost-app identity and waits during editing or active interactions.

Board packages use format version 1, bounded to 32 MiB, 256 boards/4,096 tiles per import, and validated content-addressed assets. Import creates fresh identities, preserves gaps, and disables automatic switching. Packages include names, URLs, mappings, and selected images; they contain no credential or agent-history types.

The phone’s PNG cache is content-addressed in Caches/MacIcons, bounded to 128 MiB on catalog refresh. Interface themes do not change PNG pixels. Layouts contain application/shortcut identifiers and website URLs; they never contain pairing credentials.

Timers store per-Mac deadlines and acknowledgement separately in Application Support/QuickTile/Timers. They recover elapsed time without continuous background execution and optionally schedule local completion notifications.

## Agent tracking and hardware adapters

Tracking is opt-in. Explicit settings actions install the bundled event helper and QuickTile-owned local hooks, preserve other handlers and pre-install backups, and remove only QuickTile handlers on disable. Launch/upgrade does not silently rewrite trusted hooks. Codex trust is a separate user step.

Hooks retain provider/session/source/turn/request/time lifecycle metadata. Reducers reconcile input resolution, completion, interruption, and stale concurrent sessions, with waiting taking priority. A bounded incremental Codex-log reader supplies compatibility evidence; its unsupported format can change. Prompts, tool arguments, and transcripts are not retained or transmitted as snapshots.

Core Audio confirms supported output volume/mute values. The brightness adapter dynamically loads **private DisplayServices** functions, enumerates displays, and checks capability/readback. Public-distribution policy, supported display behavior, real agents, and signed updates remain open gates; see [APPLE_APIS.md](APPLE_APIS.md) and [RELEASE_GATES.md](RELEASE_GATES.md).
