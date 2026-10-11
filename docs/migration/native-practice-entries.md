# Native practice and ship inspection

Audited source: frozen committed `9ad6a44daecd4ec36a8172d83ff27493feffe5dd` under `C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada`. Original and frozen source remain read-only. CodeGraph reported no index for the frozen checkout; source discovery used RTK fallback reads.

## Entry and owner contract

`apps/game-client/src/components/GameEntry.svelte` routes `viewPractice` to `PracticeInspector.svelte` and `viewShips` to `ShipViewer.svelte`. MainMenu exposes ship inspection publicly; standalone minigame practice is a development/QA entry. Native router remains responsible for those entry gates, loading/error recovery, shared settings and music.

Native scenes:

- `res://game/scenes/practice/practice.tscn`
- `res://game/scenes/ship_book/ship_book.tscn`

Both are independently runnable Controls. Set `startup_options: Dictionary` and optional `settings_storage: RefCounted` before adding to the tree. `_ready` supplies `startup_receipt: Dictionary`; successful initialization returns `ok: true`, while ship asset failure returns a concrete reason. `main_menu_requested` returns navigation authority to the router. Neither scene accesses career persistence. Practice startup option `kind` selects one of the four kinds; ship book options `kind` and `lod` select the model. Ship book `dev`/`qa` options control visible LOD inspection controls; default debug-build behavior matches the source development gate.

## Standalone minigames

`PracticeInspector.svelte` uses the following exact standalone inputs:

| Kind | Source target | Seed | Difficulty | Extra context |
| --- | --- | --- | --- | --- |
| duel | voc-captain | 1661 | 1 / native normal | crew 48, enemyCrew 38, morale 100 |
| landBattle | taiwan-fort | 1661 | 1 / native normal | none |
| treasure | treasure-cove | 1661 | 1 / native normal | none |
| banquet | xiamen | 1661 | 1 / native normal | none |

`game/runtime/practice_runtime.gd` constructs the existing native `game/domain/encounters` models with those inputs. It uses the existing `game/ui/encounters/encounter_interface.gd` detached packet and native command vocabulary: action, pause, retreat, settle, retry and close. Packet fields include request identity, generation, native model state, actual result, practice flag, accepted seconds, started flag and revision. Old request identities, foreign generations, stale UI revisions and client-supplied results/rewards are refused. Focus suspension fences the model clock and actions. Retry and kind switches replace the model with a new identity.

Source `EncounterPanel.svelte` starts timed duel/banquet models only after an explicit Begin click. Native `encounter-begin` opens that authority gate; before it, clocks and game actions remain unchanged. The scene exposes a visible Begin button and renders waiting encounter controls disabled without altering the shared career encounter interface. Retry and mode switch reset the gate. Land battle and treasure begin immediately, as in the source.

Native keyboard routing uses physical key codes with logical-key fallback; focused selectors/text editors retain their own keyboard input, and modifier shortcuts are ignored. Source mappings include duel J/K/L/U/I/O/Space; treasure and banquet arrows or WASD; E digs in treasure or ends a land turn; 1/2 select melee/musketeer. Treasure movement/dig accepts repeated key events, while other game actions suppress repeats. These commands carry the current authoritative request identity.

Practice settlement reports actual model score and `paid: 0`. It owns no AdventureSession, simulation, career storage, silver or social reward authority. The scene confirms finished native results automatically so its reusable encounter UI enables retry/close. A scene-level restart also allows replacing an active practice, matching source mode-switch/restart behavior.

The legacy encounter coordinator was audited and deliberately remains the career authority. Its seed derives from voyage seed, target hash and day, and it initializes models inside a live career runtime. Reusing it for this standalone inspector would alter the frozen source's fixed seed/context and create unnecessary career dependencies. The standalone authority reuses the domain models and established presentation contract directly.

## Ship book

`ShipViewer.svelte` defines six ships: fuchuan, fisherman, merchant, voc, patrol and heavy. Native metadata preserves names, roles, descriptions and source length/beam/draft values. `asset_library.gd` instantiates the original `assets/models/ships/<kind>-lod<0|1|2>.glb` files. All eighteen assets remain actual authored GLBs; no replacement geometry represents a ship.

Preserved controls:

- Native selector for all six ships and three real distance models.
- Source camera presets quarter, bow, starboard, stern, port and underwater; framing uses the actual mesh bounds. Underwater preset hides the inspection sea and targets the source draft depth.
- Pointer drag orbits the native Camera3D; wheel zoom clamps to model scale times 0.25 through 4.
- Sail deployment slider drives authored `furl` and `inflate` morphs with source inflation `0.7 * (1 - furl)`.
- Rotation button turns the actual ship by PI/4; preset selection resets rotation as in the source.
- Authored rudder pivot follows source sinusoidal movement; cannon recoil drives actual barrel nodes for 400 ms, then restores their authored rest positions.
- Failed model loads retain the confirmed model; RetryModel retries the attempted ship/LOD independently of the confirmed selection.
- Responsive native sidebar and independent SubViewport keep controls separate from the model camera. Narrow screens use a scrollable top control area.

The source OrbitControls include damping and orbit panning. The native inspector currently implements immediate orbit and zoom; damped inertia and camera panning are not ported. Native lighting/tonemapping is adapted to Godot. GPU visual equivalence must be judged separately from headless model/transform evidence.

## Other battle practice entries (audit for application owner)

Source `GameScene.svelte` config uses seed 1661, duel enemyCount 1, fleet enemyCount 2, sail enemyCount 0, wind direction {-0.8,-0.6}, speed 14. Free sailing explicitly creates player fuchuan at {0,0}, neutral merchant at {140,100}, neutral fisherman at {60,-120}, fisherman heading PI/3 and deployment 0.65. Terrain authority is `simulation/world-layout.ts`, registered through `registerHeightSampler(terrainSample)` before World initialization.

Commands preserve held sailing keys, Q/E broadside, Space nearest hostile-side selection, ammo 1/2/3 and R trim. Escape, blur and hidden state pause. Surrender uses the real simulation preview, confirm/cancel and terminal result; restart reconstructs the simulation from the source configuration without career effects.

QA source: `apps/game-client/src/simulation/VisualScenarios.ts`; fifteen scenarios include six-ship fleet, damage, sink, impact, weak impact, benchmark, shore escape, two wave scenes and six crew scenes. This minigame/ship-book implementation does not claim a port of those naval QA scenes.

## Focused verification

Both test scripts first failed on absent native entries, then passed against the implementation. A later RED layout assertion exposed overlapping practice controls; native header-aware panel placement corrected it.

- `tests/test_practice_entries.gd`: real actions for all four models, fixed inputs, Begin clock/action gates and retry reset, actual native rhythm scoring, result-injection refusal, pause/suspension, settlement/retry identity, native buttons, mode switch, actual physical-key-only input for WASD/E/1/2, focused-selector isolation and owner navigation. Physical-key and Begin/shortcut regressions failed before the routing corrections, then passed.
- `tests/test_ship_book.gd`: all eighteen GLBs instantiate; authored sails/morphs, native pointer orbit/wheel zoom, all six camera presets, deployment, rotation, recoil/rudder, actual selection controls, source dimensions, bounded zoom and an injected failed asset load followed by actual retry recovery.

Runs use Godot 4.7.2 headless. No GPU capture or whole-suite claim belongs to this focused component checkpoint; the application owner performs those checks after router integration.
