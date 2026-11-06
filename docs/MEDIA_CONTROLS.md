# Playback controls

Mac playback automatically prefers an observed playing Spotify or Music session. It resumes the last controlled running player when appropriate, and supports browser media through the Mac media-key fallback. Explicit player selection remains available. A closed player is never launched by the native adapter; the existing legacy Music action uses automatic routing too.

Play/pause uses pause bars while confirmed playing, a triangle while confirmed paused, and a neutral symbol when state cannot be observed. Saved custom artwork cannot cover this functional control. The Mac publishes player changes immediately and observes running players while an authenticated phone is connected. Command completion also publishes current capabilities before the result. Widgets retain the last reported playback state and update after commands; WidgetKit controls refresh scheduling and animation in StandBy/Always-On.

Spotify's installed scripting dictionary supplies `playpause`, `play`, `pause`, track navigation and readable `player state`. These commands require macOS Automation permission. Passive permission probes never prompt, never block action execution, and are bounded to one in-flight probe per player process-wide. Successful explicit controls authorize the next state read. Older reads are discarded after a newer read or control to prevent stale state overwrites. Disconnected phones stop polling.

Browser media-key dispatch still requires Accessibility. macOS owns routing for sources without a supported state adapter; QuickTile cannot claim an observed universal browser playback state. Start media on the Mac first. This public-interface implementation does not use private MediaRemote APIs or claim to observe every player.

Verification: deterministic active-player selection, closed-player exclusion, pause/play glyph mapping, existing matching media-key press/release tests and the companion suite pass. A passive live Spotify read test is opt-in; this run skipped it because the test process did not have Spotify Automation permission. No playback was changed during the test run. Physical Spotify toggle/permission and browser/simultaneous-source checks remain release gates.

The follow-up motion fix uses one stable SwiftUI image with a 120 ms opacity transition, shared by media/timer controls and widgets. Reduce Motion disables it. There is no stacked spring or travelling symbol-replacement effect. Native control and state readback share one AppleScript transaction; polling is suppressed during the command, and transient read failures retain a confirmed state for at most five seconds before returning unknown. No optimistic playback flip is invented.

Spotify playback-change notifications also trigger a short coalesced, verified state read; notification metadata is ignored. This avoids waiting for the periodic fallback poll after external changes.

Widget feedback occupies the existing fixed-height header rather than inserting/removing a footer, so acknowledgement updates do not resize the controls or move the playback glyph.
