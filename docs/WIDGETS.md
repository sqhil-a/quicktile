# Home Screen and StandBy widgets

Enable **Settings → Home Screen & StandBy → Enable widget controls** in QuickTile, then add a QuickTile widget from the Home Screen or StandBy widget gallery. Touch and hold a widget and choose Edit Widget to select a board, page, or tile. The selected Mac in QuickTile is the widget target.

- **Board controls:** choose any board and page. Medium/large widgets show all eight slots. Small and StandBy widgets show four; select the starting half, then use the header arrow to cycle through all pages and both halves directly in the widget. Empty slots remain empty.
- **Single tile:** a large, configurable action button, also available in StandBy.
- **Mac controls:** playback, next track, volume and brightness. Minus/plus changes the freshly read level by five percentage points. Tap the speaker to mute/restore using the normal Mac mute implementation.

App launchers, websites, keyboard commands, engine/editor presets, short system controls and media run through authenticated local connections. Voice recording, timer interaction, agent requests, Apple Shortcuts and action sequences open QuickTile, preserving their existing UI and avoiding the widget execution-time limit. If the app needs reconnection, it asks for another tap after connecting instead of queuing the action.

iOS requires authentication for interactive controls on locked phones, including StandBy. QuickTile does not bypass Face ID, force an unlock, wake the Mac, guarantee execution when iOS suspends it, or promise continuous widget networking/background haptics. The Mac must be awake, unpaused and reachable on the same LAN. Widgets show last-action feedback and last reported playback state, not a fabricated persistent Connected state. Media controls use the same active-player routing as the app; see MEDIA_CONTROLS.md. Live refresh timing is controlled by WidgetKit.

## Security and storage

Widget controls are off until enabled. Disabling clears shared widget data and blocks stale buttons/deep links immediately. Board edits/removals and selected-Mac changes update the snapshot; a removed configured board/tile is not replaced with an unrelated action. Cached artwork is bounded and refreshed as app icons arrive.

The App Group `group.sahil.QuickTile` contains board/tile configuration, cached artwork and concise feedback. It contains no pairing keys or Groq key. App Intents execute in the containing app using `LiveActivityIntent`; current SDKs explicitly use background mode. The app reads its existing device-only Keychain credential and creates a fresh TLS-PSK Bonjour connection per action. The widget extension has no Keychain-sharing entitlement. The transaction verifies Mac identity, receives a new session, preserves target/configured keys, limits control steps, waits for command completion/readback and closes. It never retries. A lost acknowledgement is reported as unconfirmed, never as proof that nothing happened.

## Verification

- Shared policy and real TLS fixture tests cover target/key preservation, fresh session/time, control read/adjust/readback, wrong-Mac rejection, foreground-only routing and level bounds.
- iPhone app and embedded extension compile for simulator and device; automatic provisioning includes the App Group.
- The new setup UI test is present; this run's simulator UI-test service failed to attach. It is not recorded as passed. Manual Device Hub review confirmed the settings opt-in and the small board and medium Mac-controls gallery layouts, using simulator-only data without credentials.
- Physical locked/StandBy authentication, background/cold launch, Local Network denial, paused/asleep/unreachable/revoked Mac, widget customization, large text, tinted/night appearance and every app action remain release checks.

References: [interactive widgets](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [StandBy appearance](https://developer.apple.com/documentation/widgetkit/adding-standby-and-carplay-support-to-your-widget), [intent runtime](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents).

Reproduce project membership with `python3 Scripts/add_widget_target.py` after regenerating the base project. Both the app and widget extension use the same App Group entitlement; distribution profiles must include it. The extension ships inside the iPhone app, not as a separate download.

November 6 record: 69 shared tests passed, including real TLS widget transactions and revocation during connection. The Mac suite ran 34 tests with zero failures and four intentional skips (two hardware checks, live Groq, and live Spotify observation without test-process Automation permission). The app and widget extension both have valid development signatures and the shared App Group entitlement. iPhone build 10 and Mac build 9 are the local development versions.
