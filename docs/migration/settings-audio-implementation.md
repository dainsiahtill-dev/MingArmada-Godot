# Native settings and audio

Scope: Task10, target `C:/Users/dains/Documents/Git/ming-armada`, base `3801ec5`. Frozen source is read-only `C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada`, recorded source HEAD `9ad6a44daecd4ec36a8172d83ff27493feffe5dd` from the supplied brief. CodeGraph reported source UNINDEXED; root already reported both projects UNINDEXED. Discovery used RTK fallback; no indexing, source writes, existing scenes/runtime/UI/project edits, Git operations, GPU runs, exports, or full suite.

## Source evidence

SHA256 of actual source bytes read during implementation:

| Frozen source relative file | SHA256 |
| --- | --- |
| apps/game-client/src/simulation/GameSettings.ts | 56031b00eec5d4f2871f8d553b7862989f6a980b49a3f146392b7f5620eb09cf |
| apps/game-client/src/simulation/SailingAudio.ts | 7f4ce11d8b7fc32852093200b0b8c599b8f1c9ed5add574ee6ae9e1144bf9756 |
| apps/game-client/src/components/GameEntry.svelte | df09c6310a4d958bdee114dc9f5adb4f97dba9cc8e5394a33b05a24cd45966be |
| apps/game-client/src/components/MainMenu.svelte | 85350c6d1637cb62ca28558b221199e6e787eb4e28f8c7d97419ba4b6cd70877 |
| apps/game-client/src/simulation/MingqiSceneHelpers.ts | 69ef3decbed69cea217c3ae742acbf16425bcf07c17974058a0efa50b64f46bd |
| packages/scene-engine/src/engine/world/World.js | b088da0287cbebc80d123f24352dd98e4495c1eca1677c50b5930855b63aaa68 |

`NavalSceneView.ts` was also read for event routing and audio/listener lifetime. Actual source class is `SailingAudio`, referenced by `NavalSceneView`; there is no separate `NavalAudio` class in this source discovery.

## Settings contract

`game/persistence/user_settings.gd` is a RefCounted store:

```gdscript
var store = preload("res://game/persistence/user_settings.gd").new()
var loaded = store.load_settings() # {ok,reason,settings}; defaults survive read/parse/version failure
var receipt = store.update_settings({"musicVolume":0.4}) # verified disk write before live adoption
var detached = store.snapshot()
```

Default path `user://settings.json`; version envelope `{version:1,settings:{...}}`. This does not touch global Codex/OS configuration or career save files. `snapshot()` and receipts detach settings. `load_reason` exposes actual last load condition. Source `handling` is canonical; `handlingMode` is accepted as a patch/input alias, conflicting aliases are refused.

| Field | Source default | Valid values / range |
| --- | --- | --- |
| handling | assisted | assisted, realistic |
| quality | balanced | low, balanced, high |
| sound | true | boolean |
| music | true | boolean |
| soundVolume | 1 | finite number, clamped 0–1 |
| musicVolume | 0.7 | finite number, clamped 0–1 |
| reducedMotion | false | boolean |
| cameraShake | 0 | finite number, clamped 0–1 |
| cameraFollow | true | boolean |
| horizonStability | 1 | finite number, clamped 0–1 |
| captainName | 沈沧海 | source whitespace trim/collapse, 24 UTF16 units, blank fallback |

Load normalization matches source per-field defaults, booleans, enum fallback and numeric clamps. Native patch validation intentionally strengthens source update behavior: invalid types/enums/nonfinite values/unknown keys reject the whole patch; source web silently normalizes them and swallows localStorage errors. Actual directory/write/replace/readback/backup errors return a receipt; failed disk replacement leaves live state unchanged. Existing `SaveCoordinator` supplies staged write/readback, rollback replacement and previous-byte backup. A missing primary file reads a present rollback slot after interrupted replacement. Tests use unique files under `user://migration-verification`, remove their own files, and do not change the production settings slot.

Captain names use existing `utf16_text.gd` and strict `json_numbers.gd`, preserving a split surrogate in JSON, rather than Godot's lossy JSON decoding. Internal exceptional strings use the existing Text codec; UI callers presenting a name should use `Text.display_text`; raw user input must follow the same `Text.encode_native` boundary as career rename. Source MainMenu currently trims/collapses/slices to **20** UTF16 units; source Adventure rename UI uses **24**. Store follows the brief's 24-unit persistence contract; root owns any distinct main-menu 20-unit input behavior. Native first-launch reducedMotion remains the source default false; browser `matchMedia` OS preference discovery is not copied.

## Settings panel

`game/ui/settings/settings_panel.gd` extends Control. `build()` is idempotent, `open(settings={},reason="")` captures previous focus and focuses first control, `close()` hides/restores focus, `apply_settings(settings,reason="")` silently updates confirmed values. Signals `settings_requested(Dictionary patch)` and `close_requested` contain intents only; caller persists/applies and reapplies confirmed snapshot/reason. No career state mutation or captain rename is embedded in the settings panel. Actual OptionButtons, CheckButtons, HSliders, vertical ScrollContainer with focus following, viewport sizing, Chinese labels and persistence failure text exist. All ten source settings are represented. Panel handles Escape when delivered to its GUI input; root must retain its modal/pause routing. Render/font readability, viewport edge cases and keyboard routing still require root's GPU/UI acceptance.

## Native audio contract

`game/presentation/audio/game_audio.gd` extends Node. Add it to the tree and call:

```gdscript
audio.apply_settings(store.snapshot())
audio.set_listener(camera.global_position)
audio.set_paused(runtime_paused) # starts paused
audio.apply_snapshot(accepted_naval_snapshot, accepted_seconds)
audio.apply_events(accepted_events)
audio.diagnostics()
audio.dispose() # idempotent; _exit_tree also disposes
```

No audio callback changes game state; no audio timer advances game time. Accepted positive delta while unpaused adopts explicit `naval.time` and wind speed; fallback clock advances only by supplied accepted delta when snapshot time is absent. Paused snapshots hold clock/gains and consume event IDs without queuing sound. BattleId/generation changes clear prior voices and dedupe state. Listener attenuation is source horizontal `1/(1+distance/100)` including updates to currently alive positioned voices. Unpositioned status feedback has full distance gain.

`sound_palette.gd` produces actual mono PCM16 AudioStreamWAV at 22050Hz; it caches per-type streams. Fire is 0.65s noise with exp(-normalizedAge*6), hit/splash 0.25s; offline lowpass 480/1100/1700Hz preserves cannon/impact/splash distinction. Status notes use the actual source bronze partial amplitudes .56/.23/.11, multipliers 1/2.76/4.07, exponential decays 5/10/15, 6ms attack, lowpass5200Hz. Source contours:

- order 440,554; reload330,440,330; dock392,523 with .18s spacing.
- victory392,523,659,784; defeat392,294,196,147; quest523,659,784; other melody spacing .14s.
- mission aliases quest, surrender aliases defeat.

Voice gain before user volume is fire .35, hit/splash .12, status .23. Native oldest-voice release caps 16 actual event players. IDs dedupe in a bounded 512-entry window with an eviction time floor; consumed muted/paused events never replay on resume. Root should provide stable `id` or `eventId`; otherwise identical payload SHA256 is used. Finished signals release real players; all public calls and late finished callbacks remain harmless after disposal.

Two looping native WAV ambient players share the actual two-second noise stream, with native lowpass sea and highpass280Hz/lowpass wind. Source strength clamp0–40, swell/gust frequencies .73/1.37, cutoff/gain formulas are preserved, phase reduced before trigonometry. Three temporary uniquely named native buses provide sea/wind filters plus effects compressor threshold-18/ratio6/attack3ms/release220ms. Effects is created before Sea/Wind: native Godot processes buses right to left and sends require an earlier destination. Sea, Wind and event players explicitly route to Effects; disposal removes owned buses without moving/removing unrelated buses. No project.godot bus registration is required.

Imported `大明逐浪.mp3` and `破浪赤焰.mp3` load through ResourceLoader as AudioStreamMP3. Source music factor `musicVolume*.35` is preserved. Explicit `naval.combat` or `musicMode` wins; otherwise live projectiles or hostile/player ships within600m select combat. Root can specify combat for standalone modes. Music toggles preserve playback position; track replacement resets it. Effects/musical ambience freeze on native pause; mute releases effects. Diagnostics expose actual voices, gains, cutoffs, track, accepted clock, load reason and lifetime; `audibleVerified:false` explicitly indicates that headless checks did not measure a real device.

Native differences: PCM is quantized16-bit at22.05kHz; deterministic cached RNG replaces browser random noise; source WebAudio filter/compressor transfer functions and smoothing/knee12 cannot be bit-identical to native effects/offline biquad. Native music follows explicit combat facts and pause, while source GameEntry picks music at route start and leaves HTML music running across menu pauses. Neither difference changes game rules. Root owns quality/render/camera consumers and audible acceptance.

## Focused verification

Godot actual binary `C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`, version4.7.2.stable.official.ed1daf0bf. Commands start RTK:

```text
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --audio-driver Dummy --path C:/Users/dains/Documents/Git/ming-armada --script tests/test_user_settings.gd --quit-after 300
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --audio-driver Dummy --path C:/Users/dains/Documents/Git/ming-armada --script tests/test_game_audio.gd --quit-after 300
```

Initial RED runs exited1 with expected missing settings/audio implementation assertions, before production code. Settings GREEN `USER_SETTINGS_TESTS assertions=21 failures=0`; final scoped audio GREEN after review fixround1 `GAME_AUDIO_TESTS assertions=26 failures=0`, exit0 with completion marker and no Godot script/error/warning logs. Settings tests exercise real persistence/reload, source bounds/defaults, atomic malformed patches, detached snapshots, exceptional UTF16 disk roundtrip, real rollback recovery, corrupt/future-version load, actual directory failure, readonly panel and native toggle intent. Audio tests inspect actual PCM bytes/frame durations, native MP3s, gain/distance/position, source voice cap, dedupe/pause/mute, explicit accepted clock, combat track, battle handoff, native natural finish, late callback, idempotent disposal and exact bus-count restoration. Review fixround1 additionally reads real AudioEffectCapture mixed PCM at Effects/Master with music disabled, proving audible-path routing and preservation of an existing unrelated bus. This is native signal evidence, not real-device audibility.

During development a GDScript inferred-bool parse error was fixed; a partial wind snapshot incorrectly looked like a battle replacement until omitted identity fields were preserved. A test's freed-node late signal access was corrected to retain/call the actual callback. Fast same-frame play/stop tests initially reported AudioServer playback resources at process exit; production teardown now unpauses/stops/clears streams, and tests yield40ms across lifecycle transitions plus150ms after teardown to allow the independent native mixing thread to retire playback objects. Those waits do not advance shared game state; actual natural finish retains clock0. Final strict logs are clean.

Review fixround1 reproduced P2 before production edits with the new capture regression: Effects RMS0, Master RMS0.01453640020268; `GAME_AUDIO_TESTS assertions=26 failures=2`, exit1. Minimal creation-order fix plus explicit event Effects binding yielded Effects RMS0.01453640020268 identical to Master; `GAME_AUDIO_TESTS assertions=26 failures=0`, exit0, clean logs. Captures are process-local test effects, removed at teardown; production uses no capture/test-only helpers. Only game_audio.gd, its focused audio test and owned documents changed in this fixround. No settings/panel/scene/UI scope expansion or full-suite/GPU run.

Pending root acceptance: audible output/device behavior, audio mixing/clipping by ear, GPU/UI/font/resize/focus/Escape interaction, scene/menu integration, actual quality/camera consequences. No audible or performance proof is claimed here.
