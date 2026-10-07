# Voice assistant

Add a tile → AI → Assistant. Tap to speak, then tap again to finish. The waveform follows microphone level. While processing, tap to cancel future actions. Recording stops after 60 seconds, when editing begins, on disconnection, or when the app leaves the foreground.

## Setup

In QuickTile Mac Settings → Assistant, save your own Groq API key. It is stored in Mac Keychain and can be removed there. QuickTile uses `openai/gpt-oss-120b`, with `openai/gpt-oss-20b` as a rate-limit fallback; Groq account limits and usage charges apply. Both apps must support the voice-assistant protocol. The iPhone asks for transcript-processing consent, Microphone, and Speech Recognition access when first used.

Speech recognition must be available on-device for the current language. Audio is not uploaded. After recording ends, the transcript travels over the authenticated local connection to the Mac. The Mac sends the transcript and available app, Apple Shortcut, and supported action names to Groq. It does not send agent conversations, catalog identifiers, or the audio. QuickTile saves no transcript history; unresolved clarification context stays briefly in memory for a follow-up reply. Groq processes requests under its own policies; see the published privacy policy before enabling this feature.

## Supported examples

- “Open Safari.”
- “Set volume to 40 percent.”
- “Mute” or “Unmute.”
- “Set brightness to 60 percent” on a supported display.
- “Pause in Spotify” or “Play in Apple Music.”
- “Enable dark mode.”
- “Run shortcut My Workspace” when that named Apple Shortcut exists.
- “Build in Xcode” when the installed profile and permission are available.

A request can contain up to eight supported actions. All steps are checked before anything runs. Missing apps, ambiguous names, unsupported settings, and unavailable permissions produce a concise explanation. Website commands accept common names such as YouTube, supplied domains, or full HTTPS addresses. The assistant does not execute arbitrary scripts or shell commands and cannot control every Mac setting. Keyboard actions retain the same application/keymap/focus limits as normal tiles.

Cancellation or disconnection prevents future steps but cannot undo effects already completed. Requests are never queued for reconnect or automatically replayed after a failure.

## Recorded verification and remaining acceptance

Strict response parsing, provider errors, URL restrictions, bounded responses, preflight, replay protection, and UI cancellation have deterministic regression coverage. The recording screenshot uses a DEBUG-only fixture; it is not evidence of actual speech recognition.

The supplied credential is configured in Keychain. After reducing the catalog and adding a one-time GPT-OSS 20B rate-limit fallback, a live interpretation request succeeded on October 5, 2026; no Mac action was executed by this check. The companion retains the smaller model for its current session after a 120B rate limit rather than repeatedly trying the limited model. Catalog selection prioritizes names relevant to the request and caps its size. Provider/account-wide limits can still apply. Real voice-to-Mac execution remains a physical-device acceptance step. Physical tests must cover consent, denied permissions, supported/unsupported recognition languages, interruption, backgrounding, connection loss, and successful execution in disposable documents.

## October 7 command reliability update

The interpreter uses Groq Chat Completions with strict JSON Schema, GPT-OSS 120B and the existing one-time 20B rate-limit fallback. Normal app quitting uses macOS's termination request for the resolved installed bundle; it does not force quit or dismiss unsaved-document prompts. Common website names (including YouTube), supplied domains, and explicit HTTPS addresses are resolved locally and checked against the request before opening. Installed app names take precedence for ordinary “Open Spotify”; “Go to Spotify” explicitly opens the website.

Clarification context is scoped to the authenticated phone connection, kept only in memory, bounded, and expires for use after two minutes. The next recorded reply includes the original request and question, so “yes” is no longer sent as an unrelated request. Successful planning clears that context. An explicit new request supersedes the old one. Supported settings remain volume, brightness and appearance; arbitrary settings require a configured Apple Shortcut and never pretend to execute after a confirmation.
