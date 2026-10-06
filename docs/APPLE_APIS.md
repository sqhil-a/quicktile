# Apple API decisions

Reviewed against Apple's documentation and the installed Xcode 27.0 SDK headers on September 6, 2026. The product reference at [choclift.com](https://choclift.com/) was read for category context only. QuickTile uses original code, interface, and artwork.

The implementation details below have been aligned with the current source. The dated SDK/documentation research is not proof of current submission eligibility or physical compatibility; [RELEASE_GATES.md](RELEASE_GATES.md) tracks those checks.

## Discovery and local network permission

Use `NWBrowser` / `NWListener` and the declared `_quicktile._tcp` Bonjour service. Include `NSLocalNetworkUsageDescription` and `NSBonjourServices` in each application's Info.plist. Fixed-service Bonjour browsing does not require the restricted arbitrary-multicast entitlement. Do not hardcode `en0` or require the Mac's Wi-Fi interface; Ethernet on the same LAN works. Peer-to-peer discovery is disabled.

Apple documents a Bonjour waiting error (`kDNSServiceErr_PolicyDenied`, -65570) and Network path behavior for denied access. There is no general Local Network permission-state query API. QuickTile shows actionable guidance and retries on foreground/reconnect. Local network privacy starts at macOS 15; there is no corresponding macOS 14 permission switch. Simulator permission behavior does not prove physical-iPhone behavior. See [TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

## Secure pairing and transport

Use the platform's TLS PSK support: [`sec_protocol_options_add_pre_shared_key`](https://developer.apple.com/documentation/security/sec_protocol_options_add_pre_shared_key(_:_:_:)) and [Network security options](https://developer.apple.com/documentation/network/security-options). The public `sec_protocol_options_set_pre_shared_key_selection_block` is a **client** identity-hint selection hook, not a server-side authorization callback. Consequently each credential has its own listener with exactly one accepted key. This prevents incorrectly trusting an application-layer identity supplied by a peer with a different PSK.

The cipher constant `TLS_PSK_WITH_AES_128_GCM_SHA256` is in the installed public Security/CipherSuite.h; it is converted to `tls_ciphersuite_t`. TLS 1.2 PSK interoperability was exercised over real Network.framework sockets. There is no certificate-verification callback returning unconditional true, no short code as encryption key, and no custom key agreement. Forward secrecy is not supplied by this selected cipher; see [SECURITY.md](SECURITY.md).

## Mac application icons

[`NSWorkspace.icon(forFile:)`](https://developer.apple.com/documentation/appkit/nsworkspace/icon(forfile:)) returns the icon associated with a local file. Its initial logical size is 32×32. QuickTile draws the image representations into a transparent 256×256 PNG, preserving aspect ratio. A SHA-256 of the actual PNG versions the transfer cache. Catalog refresh recomputes the image so relevant app/icon changes can propagate.

**Exact Dock appearance is not guaranteed.** The public API's contract does not promise the active Dock rendering, a selected tinted/clear variant, dynamically composed Liquid Glass, live Dock badges, or every representation in an Icon Composer asset. Apple's [Icon Composer documentation](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer) describes authoring and platform appearance variants; it is not a supported API for scraping another app's active Dock compositing. QuickTile uses the best original file-icon image exposed by NSWorkspace. It never adds a fabricated glass layer, monochrome filter, or theme-driven recoloring.

Refresh on relevant workspace notifications and companion panel appearance change, plus explicit manual refresh. Exact third-party icon appearance variants require physical Mac/iPhone comparisons across OS versions. No private IconServices/CoreUI/Dock APIs are used.

## Keyboard and Accessibility

[`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) can request an asynchronous Accessibility prompt; returning from it does not imply approval. QuickTile checks trust each time and reports a permission error until enabled. [`CGEvent.post(tap:)`](https://developer.apple.com/documentation/coregraphics/cgevent/post(tap:)) posts Quartz events; it does not acknowledge that an app handled them. All key-up and modifier-release events are allocated before any key-down and posted in a `defer`, with no suspension point during the pressed interval. Target activation is checked before posting.

## Apple Shortcuts

Apple supports [running shortcuts from the command line](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac). Installed `/usr/bin/shortcuts list --help` confirms `--show-identifiers`; `run --help` accepts a shortcut name **or identifier**. QuickTile uses the UUID so names containing spaces, quotes, parentheses, dollar signs, and shell punctuation are never command syntax. Its parser matches only the terminal `(UUID)` in catalog output. UI-input shortcuts can wait on the Mac. Process exit zero is reported as successful CLI completion, distinct from transport acceptance.

## Media and volume

`MPRemoteCommandCenter` receives commands for an app’s own playback; it is not a global player controller. Default **Mac playback** sends system-defined media-key press/release events using `NSEvent`/`CGEvent` and the SDK's NX play/next/previous codes. Accessibility is required. Posting does not confirm player acceptance or state, so the system playback snapshot remains unknown. There is no automatic Music fallback or universal seek promise.

An explicitly selected **Spotify** or **Music** media tile uses that player's AppleScript dictionary through fixed allowlisted bundle IDs and play/pause/next/previous verbs. First use can request Automation. The companion observes player state only after a successful selected-player command, using a nonprompting `AEDeterminePermissionToAutomateTarget` check before polling an already-running player. Permission/read failures, an app that is not running, and unrecognized state report unknown; a readable `stopped` state maps to paused. Duplicate play/pause tiles share the snapshot by playback target rather than guessing from taps. Fixed appearance scripts still target System Events without user interpolation. Real player behavior and multiple simultaneous media sources remain verification gates.

For output volume, use Core Audio [`AudioObjectIsPropertySettable`](https://developer.apple.com/documentation/coreaudio/audioobjectispropertysettable(_:_:_:)), `kAudioDevicePropertyVolumeScalar`, `kAudioDevicePropertyMute`, and the default-output-device property. Query support each time. The dial supports a settable master or conventional stereo volume channels, verifies readback, uses actual master mute at zero, and remembers the pre-mute level per output UID. Digital/HDMI outputs can be unsupported and receive guidance. Device changes and mute restoration still require a physical hardware matrix.

**Brightness uses a private API.** `BrightnessControl` dynamically loads `/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices` and its get/set functions. It enumerates displays, disables unsupported controls, and confirms readback, but this does not turn the dependency into a documented public API or establish compatibility across OS versions/monitors. Resolve its distribution-policy/implementation path before releasing; supported/multiple-display testing remains separate evidence. The public `NSScreen`/Core Graphics enumeration APIs alone do not provide this implementation's brightness setter.

## Timers, agents, and update review

Local timers persist deadlines and acknowledgement. UserNotifications schedules optional completion alerts after the user enables them; foreground haptics do not imply continuous background execution.

Agent status is derived from minimal local hook lifecycle metadata. Explicit install/repair preserves unrelated handlers; disable removes only QuickTile handlers. Codex hook trust remains a separate user step. The local Codex-log reader is a bounded compatibility adapter for an unsupported format, with health/source state and deterministic reducer/reader tests. Live vendor behavior is still a release gate.

Manual companion update review uses fixed `codesign`/`spctl` executable paths and structured arguments to check a newer bundle against the installed release's bundle ID and Developer ID team. It reveals the app for manual replacement, without downloading or executing it. Final signed/notarized update behavior needs clean-machine validation.

## Sandbox, login, and distribution

The Mac companion intentionally uses direct distribution without App Sandbox: cross-app synthetic keyboard control and executing the user's existing automations do not fit a simple sandboxed utility's permissions. It enables hardened runtime with only the Apple Events entitlement, and uses `SMAppService.mainApp` for optional launch at login. It does not request full disk access or disable library validation for release.

References: [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox), [configuring hardened runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime), and [notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). No App Store approval, signing, or notarization is implied by successful compilation.
