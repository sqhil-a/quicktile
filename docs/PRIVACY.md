# QuickTile privacy policy

QuickTile is free, open source, and uses a local connection between an iPhone and a Mac. It has no QuickTile account, advertising, subscription, or analytics upload. Optional voice interpretation uses the user’s Groq account. This document describes the current source as of October 4, 2026. Its prepared public location is the [privacy policy page](https://sqhil-a.github.io/quicktile/privacy.html); publication and public reachability must be verified before App Store submission. iPhone Settings includes an offline policy so the disclosure is available without the website.

## Data on your devices

Pairing credentials are stored in device-only Keychain entries. Layouts, timer deadlines, selected icon images, app catalogs, and preferences are stored locally. Layout backups allow recovery after a damaged write. QuickTile sends action requests and the Mac's minimal control, application identity, and optional agent lifecycle metadata over an authenticated encrypted local connection. Actions are never queued for later reconnection.

Agent tracking is opt-in. QuickTile-owned hooks write provider, session identity, lifecycle state, source, turn/request identifiers, and event time. The Codex compatibility adapter reads local session records only to derive lifecycle metadata. It does not retain or transmit prompts, tool arguments, or agent output. Source formats can change; unavailable or stale tracking is shown explicitly. Hook installation requires a user action and Codex trust; disabling tracking removes QuickTile handlers while preserving unrelated configuration.

## Internet requests

Choosing a website favicon makes direct HTTPS requests to that site's origin and declared icon locations, which can include the site's chosen asset host. The saved URL's private path/query is not used for discovery. Requests use no cookies and no third-party favicon service. The contacted servers can receive ordinary connection metadata such as the device's IP address. Select a symbol or your own image to avoid favicon requests for that tile. Opening a website on the Mac is a separate user-requested browser action.

## Optional voice assistant

After explicit first-use consent, the iPhone transcribes speech using Apple on-device recognition. Audio is not uploaded. The finished transcript travels over the authenticated local connection to the Mac, which sends it and available app, Apple Shortcut, and supported action names to Groq’s GPT OSS 120B API (GPT OSS 20B on rate limit). No agent questions, answers, prompts, or output are included in Groq requests. QuickTile keeps no recording or transcript history. The Mac stores the user’s Groq key in Keychain; the phone, layout exports, and websites never contain it. Removing the key disables interpretation.

Groq receives request, connection, and account metadata under its [data policy](https://console.groq.com/docs/your-data). QuickTile cannot promise Groq zero retention; the user controls their account’s retention settings. Groq usage may incur charges, independent of the free app.

## Permissions

Local Network enables discovery and control. Camera access is used only to scan pairing codes. Mac Accessibility is needed for keyboard actions and default system media keys. Explicitly selected Music/Spotify controls and their state reads use Automation; appearance uses System Events Automation. Optional notification permission enables timer completion notifications; timers cannot provide continuous background haptics. Microphone and Speech Recognition are requested only for optional on-device voice transcription. QuickTile does not request screen recording access.

## Sharing, deletion, and diagnostics

Board exports include names, action mappings, website URLs, and selected icon images. They exclude pairing secrets, agent transcripts, and execution history. Review names and URLs before sharing. Imported boards create new identities and do not overwrite existing boards. Forget a Mac to remove its pairing credential; remove boards or uninstall the iPhone app to remove its local layouts. On Mac, disable tracking and launch at login before uninstalling. See the distribution guide for local data locations.

Local layouts, timer state, selected images, and agent configuration recovery backups remain until removed by the user or their app-container/local-file cleanup. Icon caches can be pruned and reloaded. Disabling tracking removes QuickTile-owned hooks/helper and stops tracking; it does not delete unrelated agent configuration or the pre-install recovery backup. Pairing credentials remain in Keychain until explicitly forgotten/revoked. The project receives no automatic copy of these local records.

Performance signposts remain in the local system logging tools and contain no action titles, URLs, prompts, or payloads. No diagnostics are uploaded automatically. Share redacted diagnostic details only when you choose to do so.

## Contact

For support or privacy questions, email [sahilambegaonkar@gmail.com](mailto:sahilambegaonkar@gmail.com). When you email support, the recipient receives your email address and the details you choose to send; QuickTile does not automatically attach diagnostics or local records. Send only the information needed to describe the issue. The [support page](https://sqhil-a.github.io/quicktile/support.html) is configured in the app; its publication and public reachability are still pending.

## Submission declarations

The iPhone privacy manifest declares app-owned UserDefaults (`CA92.1`), app-container file metadata (`C617.1`), and document-picker file metadata (`3B52.1`). With optional Groq interpretation, **Data Not Collected is no longer the prepared declaration**. The conservative manifest draft declares Other User Content (transcripts) and Other Usage Data (available application/Shortcut/action names), for App Functionality, linked to the Groq account and not used for tracking. The publisher must confirm final labels and any provider-retained metadata against the final archive and current Groq settings. Direct website requests are disclosed above; they are not an advertising/tracking system. Confirm final labels against Apple's definitions at submission.

Reference: [Apple required-reason API documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons).

## Pending agent requests

Tapping a waiting agent tile fetches its bounded pending questions, options, approval description and displayed command over the existing authenticated local connection. These details are not added to general capability broadcasts or board exports, and are never included in Groq requests. Compatibility hook metadata may cache pending details locally until the request resolves; disabling tracking removes QuickTile-owned cached metadata. Live control requests and answers are held in memory. Replies require a supported live Codex control channel and confirmation from `serverRequest/resolved`; stale requests cannot be replayed. There is no general keyboard/Accessibility automation fallback for replying to Codex.
