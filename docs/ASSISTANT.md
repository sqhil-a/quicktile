# Voice assistant

Add a tile → AI → Assistant. Tap to speak, then tap again to finish. The waveform follows microphone level. While processing, tap to cancel future actions. Recording stops after 60 seconds, when editing begins, on disconnection, or when the app leaves the foreground.

## Setup

In QuickTile Mac Settings → Assistant, save your own Groq API key. It is stored in Mac Keychain and can be removed there. QuickTile uses `openai/gpt-oss-120b`, with `openai/gpt-oss-20b` as a rate-limit fallback; Groq account limits and usage charges apply. Both apps must support the voice-assistant protocol. The iPhone asks for transcript-processing consent, Microphone, and Speech Recognition access when first used.

Speech recognition must be available on-device for the current language. Audio is not uploaded. After recording ends, the transcript travels over the authenticated local connection to the Mac. The Mac sends the transcript and available app, Apple Shortcut, and supported action names to Groq. It does not send agent conversations, catalog identifiers, or the audio. QuickTile keeps no transcript history. Groq processes requests under its own policies; see the published privacy policy before enabling this feature.

## Supported examples

- “Open Safari.”
- “Set volume to 40 percent.”
- “Mute” or “Unmute.”
- “Set brightness to 60 percent” on a supported display.
- “Pause in Spotify” or “Play in Apple Music.”
- “Enable dark mode.”
- “Run shortcut My Workspace” when that named Apple Shortcut exists.
- “Build in Xcode” when the installed profile and permission are available.

A request can contain up to eight supported actions. All steps are checked before anything runs. Missing apps, ambiguous names, unsupported settings, and unavailable permissions produce a concise explanation. Website commands require the full HTTPS address supplied by the user. The assistant does not execute arbitrary scripts or shell commands and cannot control every Mac setting. Keyboard actions retain the same application/keymap/focus limits as normal tiles.

Cancellation or disconnection prevents future steps but cannot undo effects already completed. Requests are never queued for reconnect or automatically replayed after a failure.

## Recorded verification and remaining acceptance

Strict response parsing, provider errors, URL restrictions, bounded responses, preflight, replay protection, and UI cancellation have deterministic regression coverage. The recording screenshot uses a DEBUG-only fixture; it is not evidence of actual speech recognition.

The supplied credential is configured in Keychain. After reducing the catalog and adding a one-time GPT-OSS 20B rate-limit fallback, a live interpretation request succeeded on October 5, 2026; no Mac action was executed by this check. The companion retains the smaller model for its current session after a 120B rate limit rather than repeatedly trying the limited model. Catalog selection prioritizes names relevant to the request and caps its size. Provider/account-wide limits can still apply. Real voice-to-Mac execution remains a physical-device acceptance step. Physical tests must cover consent, denied permissions, supported/unsupported recognition languages, interruption, backgrounding, connection loss, and successful execution in disposable documents.
