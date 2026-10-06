# Action library

The phone offers Apps & links, Media, Mac controls, Video editing, Photo & design, Development, Everyday, and AI agents. Search matches every typed word across the action, app, and category. The last six chosen actions appear in Recent. The deck uses icons plus specialized dials/timers/agent displays; descriptive names remain available to VoiceOver and in editing screens.

Built-in controls use fixed semantic symbols. App presets cover supported video, photo/design, and development profiles. App-profile resolution handles listed bundle variants and preferred installed versions; the tile editor permits a target override and **Customize shortcut**. The app is activated before its configured/default key event is posted. The relevant timeline/editor must already have focus. QuickTile does not infer selection or guarantee that an application accepted a key event. Every bundled vendor mapping remains `needsRuntimeVerification` until its real-app result is recorded in [ACTION_VALIDATION.csv](ACTION_VALIDATION.csv); see [RELEASE_GATES.md](RELEASE_GATES.md).

Preset boards create independent editable copies with page names and optional app links. Users can add gaps/pages, rename, duplicate, customize images, and optionally follow the Mac's frontmost app. Future preset changes do not overwrite saved boards.

Source references:
- [Final Cut Pro shortcuts](https://support.apple.com/en-euro/guide/final-cut-pro/ver90ba5929/mac)
- [Premiere shortcuts](https://helpx.adobe.com/au/premiere/desktop/get-started/keyboard-shortcuts/default-keyboard-shortcuts.html)
- [VS Code default shortcuts](https://code.visualstudio.com/docs/reference/default-keybindings)
- [Xcode shortcuts](https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/xcode_help-command_shortcuts/MenuCommands/MenuCommands014.html)
- [Resolve editor guide](https://documents.blackmagicdesign.com/UserManuals/DaVinciResolveEditorsGuide.pdf)

Default **Mac playback** supports play/pause, next, and previous using system media keys with unknown playback state. The media tile's **Player** picker optionally selects Spotify or Music for fixed AppleScript controls and observed state after an explicit command/Automation approval. Permission/read failure shows unknown state; these adapters never replace the default automatically. There is no universal fixed-duration seek. Real player/multiple-source behavior remains pending. System actions include lock, sleep display, desktop, appearance, and screenshots. Screenshot selection occurs on the Mac. Appearance may request Automation. Display/output hardware support varies; brightness currently depends on private DisplayServices and remains a release gate.

Timers run locally with persistent deadlines and optional completion notifications. Sequences allow up to 12 app/key/website/Shortcut/wait steps, stop at the first failure, report progress, and permit cancellation; completed effects cannot be undone. Agent tiles require opt-in Mac tracking and show phase/health/source instead of assuming that an open app is working.

Saved layouts migrate to schema **4** without changing board or tile identifiers. Music tiles become media tiles; old volume buttons become dials. Unknown saved actions retain their payload and appear as unavailable until replaced. `.quicktile` imports validate mappings/images, preserve gaps, create fresh identifiers, and disable automatic switching. Both apps must use protocol **2**. Actions are allowlisted; neither library nor protocol accepts executable paths or arbitrary script source.
