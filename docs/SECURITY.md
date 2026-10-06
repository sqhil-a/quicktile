# Security and privacy

QuickTile has no backend, telemetry, analytics, internet API, or account. Bonjour and TLS run on the reachable local network. Website and user-authored Shortcut actions may themselves use the internet. The phone’s camera is used only for QR recognition, not image storage or upload.

## Trust model

Pair only while you control both devices. The QR is a full-strength temporary secret; anyone who sees it can ask to pair during its validity window. Approve only the phone you just scanned with. The requested name alone is not proof of identity. Explicit approval is always required, and invitation channels cannot access catalogs or actions.

Transport uses Apple’s TLS implementation and random 256-bit PSKs, not a PIN-derived encryption key or custom cipher. Certificate verification is never disabled: this is the standard mutually authenticated PSK mode, with no certificates. Session tickets/resumption are disabled, TLS 1.2 has no 0-RTT data, and each application connection receives a new session identifier.

**Verified design limitation:** the selected TLS 1.2 PSK cipher does not provide forward secrecy. Compromise of a retained PSK could expose previously recorded sessions using it. This is explicit rather than claiming properties the chosen public API configuration does not supply. A reviewed future protocol version could migrate to TLS 1.3 PSK-DHE or mutually authenticated certificate credentials. No homegrown key exchange should be added.

Separate per-device listeners keep the negotiated TLS credential bound to authorization. Untrusted Bonjour metadata, client names, and hello bodies do not select an authorization record. Revocation closes both listeners and existing channels. The command gate checks current authorization, fresh session, age, unique request ID, and action validity before execution. Actions awaiting target activation recheck authorization immediately before posting keys.

No arbitrary shell execution is exposed. App launches resolve bundle identifiers; websites allow HTTP(S) without embedded credentials; keys use an explicit key-code allowlist. Shortcuts run by catalog UUID via structured arguments. Built-in system/player scripts are fixed and allowlisted, without interpolation of remote script source. Sequence steps are validated data and do not expose executable paths or script source.

Website tile icons are fetched by iPhone directly over HTTPS from the site's origin and its declared image URLs. The saved page path, query, and fragment are stripped before discovery. The ephemeral URL session stores no cookies and executes no scripts; there is no third-party favicon lookup service. Downloads are capped at 256 KiB per response and decoded to at most 256 pixels. This optional website-icon traffic is separate from the authenticated local Mac connection; unavailable icons use a globe placeholder.

## Local data

- Secrets: Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synchronizable.
- Layouts: local Application Support JSON (names, IDs, settings, URLs). OS backups may include these ordinary files.
- Icons: local Caches PNG files received after authentication. They may reveal installed app choices to someone with access to the unlocked phone/filesystem.
- Catalogs: read from the Mac and disclosed only to paired, authenticated channels; current implementation retains them in phone memory for the live selection.
- Timers: persisted local deadlines and acknowledgement, with optional local completion notifications.
- Agent tracking: opt-in QuickTile hooks/helper and minimal local lifecycle records; a bounded Codex compatibility reader discards transcript content. Only lifecycle/health/source snapshots are sent to an authenticated phone. Hook changes require an explicit user action, preserve unrelated handlers, and are not silently rewritten on update.
- Board exports: data-only names, mappings, website URLs, and selected images; no pairing credentials or agent history. Imports are bounded/validated and create new identities.
- Temporary subprocess output: private local files, removed after completion/cancellation, bounded during execution. Shortcuts may have their own data and privacy behavior.

The app deliberately does not log credentials, invitation strings, command payloads, or catalog contents. Never include a pairing QR, invitation, Keychain dump, or sensitive shortcut output in a bug report.

## Limits

A paired phone intentionally has broad control over the Mac’s applications and existing shortcuts. Revoke a lost phone from the Mac menu. Local attackers can still interfere with Bonjour/TCP or consume bounded connection slots, causing denial of service; authentication prevents them from running commands. This implementation has functional security tests but has not undergone an independent security audit.

Report security issues privately to the repository maintainer. A dedicated security contact has not yet been configured; do not post live secrets or exploitable details publicly.
