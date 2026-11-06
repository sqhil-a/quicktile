# Game development presets

Add tile → Game development → Godot, Unity, or Unreal Engine. Preset boards also include each engine as a separate, editable two-page board. Existing boards are unchanged.

| Engine | Pages | Actions |
|---|---|---|
| Godot | Run & debug; Scene | 16: run project/current scene, pause/stop, save/all scenes, quick open, command palette, 2D/3D/script editor, selection/move/rotate/focus, undo |
| Unity | Run & debug; Scene | 16: play/pause/step, save, duplicate, undo/redo, Game/Scene views, hand/move/rotate/scale/rect/transform tools, frame selection |
| Unreal Engine | Viewport; Playtest | 13: selection/translate/rotate/scale, focus/cycle tools, game/immersive view, play/simulate/stop, eject/possess, viewport screenshot |

Every page has eight slots; Unreal’s shorter Playtest page leaves three free. Buttons use functional symbols without labels. These are keyboard commands, not live engine-state integrations. Focus the correct editor panel; customized shortcuts can be set in tile configuration. QuickTile activates the resolved editor before sending keys and requires Accessibility permission.

App profiles recognize Unity’s installed `com.unity3d.UnityEditor5.x` identifier and alternate identifier, Godot/.NET bundle variants, and Unreal/UE4 Editor variants. Unity Hub and Epic Games Launcher are not treated as editors. Missing apps remain visible with the existing setup/availability handling.

Mapping references:

- [Godot Mac shortcuts](https://docs.godotengine.org/en/4.5/tutorials/editor/default_key_mapping.html): macOS run uses Command-B/Command-R, not the Windows F5/F6 mapping.
- [Unity shortcut reference](https://docs.unity3d.com/2018.4/Documentation/Manual/UnityHotkeys.html) and [current shortcut manager](https://docs.unity3d.com/Manual/UnityHotkeys.html).
- [Unreal viewport controls](https://dev.epicgames.com/documentation/en-us/unreal-engine/viewport-controls-in-unreal-engine) and [playing/simulating](https://dev.epicgames.com/documentation/unreal-engine/playing-and-simulating-in-unreal-engine).

Source/reference checks and deterministic layout/target tests are complete. Actual effects in each engine version, customized keymaps, and focused panels remain runtime checks in ACTION_VALIDATION.csv; no real project was changed during verification.
