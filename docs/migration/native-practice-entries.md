# Native practice and ship inspection

Audited source: frozen committed `9ad6a44daecd4ec36a8172d83ff27493feffe5dd` under `C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada`. Original and frozen source remain read-only. CodeGraph reported no index for the frozen checkout; source discovery used RTK fallback reads.

## Entry and owner contract

`apps/game-client/src/components/GameEntry.svelte` routes `viewPractice` to `PracticeInspector.svelte` and `viewShips` to `apps/game-client/src/components/adventure/ShipViewer.svelte`. MainMenu exposes ship inspection publicly; standalone minigame practice is a development/QA entry. Native router remains responsible for those entry gates, loading/error recovery, shared settings and music.

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
- Desktop pointer controls preserve the installed Three 0.181.2 OrbitControls: left drag orbits, right drag pans camera and target in the screen plane, middle drag dollies. Ctrl/Meta/Shift swap left/right orbit and pan; Alt does not. The first mouse-button press selects gesture mode; additional held buttons neither switch nor end it. Gesture ends after the last held button is released, including when the original button was released earlier. This matches the source's one mouse-pointer tracking despite native GUI delivering individual button events.
- Orbit and pan apply 5% of pending motion on each pointer event and animation-frame update, then multiply pending motion by 0.95. Motion continues after pointer release. Both axes normalize by displayed view height; render downsampling and viewport aspect do not distort pointer sensitivity. Native camera uses the source's 45-degree vertical perspective FOV.
- Wheel/middle dolly has the source exponential `0.95 ** normalizedTravel`, applies immediately, and clamps to model scale times 0.25 through 4. Native wheel `factor` maps one step to a normalized 100-pixel source wheel delta; native wheel events do not expose browser pixel/line/page units. Middle drag retains the exact pixel rule `abs(deltaY) * 0.01`. Wheel is ignored during an active drag. Synthetic Ctrl-wheel without a physical Control key uses the source's tenfold pinch delta; passive Control-key tracking does not consume sidebar keys. `zoomToCursor` remains false, so zoom preserves target.
- Sail deployment slider drives authored `furl` and `inflate` morphs with source inflation `0.7 * (1 - furl)`.
- Rotation button turns the actual ship by PI/4; preset selection resets rotation as in the source.
- Authored rudder pivot follows source sinusoidal movement; cannon recoil drives actual barrel nodes for 400 ms, then restores their authored rest positions.
- Failed model loads retain the confirmed model; RetryModel retries the attempted ship/LOD independently of the confirmed selection.
- Responsive native sidebar and independent SubViewport keep controls separate from the model camera. Narrow screens use a scrollable top control area.

Frozen `apps/game-client/src/components/adventure/ShipViewer.svelte` enables damping but leaves the installed OrbitControls damping factor, rotate/pan/zoom speeds and screen-space panning at their defaults. Its `setAngle()` changes the initial mount polar limit from `PI * 0.55` to `PI`; native loaded inspection therefore permits the entire polar range 0 through PI with Three's spherical safety epsilon `1e-6`. Default azimuth limits and maximum target radius are infinite; native panning has no invented model-bound target clamp. The camera basis is built explicitly at the poles to preserve this epsilon without Godot's nearly collinear `look_at` rejection.

Source `setAngle()` replaces camera position/target and calls `controls.update()` once. It does **not** clear pending spherical/pan damping or the active pointer gesture. Native presets and successful model selection preserve those residuals and perform the same single update; failed loads retain the confirmed presentation and attempted-retry transaction. Only leaving/disposal fences subsequent motion and clears the disposed owner's pending state. Lost native application focus cancels the active mouse gesture, all tracked held buttons and physical-Control state; damped inertia remains, as with the source `pointercancel` handler in installed OrbitControls lines 470 and 1502–1517. Model-view input uses native GUI routing, starts only from a press inside the model view, and does not take keyboard focus from sidebar controls. Source never calls `listenToKeyEvents`; arrow keys do not pan the native camera.

Native lighting/tonemapping is adapted to Godot. GPU visual equivalence must be judged separately from headless model/transform evidence.

## Other battle practice entries (audit for application owner)

Source `GameScene.svelte` config uses seed 1661, duel enemyCount 1, fleet enemyCount 2, sail enemyCount 0, wind direction {-0.8,-0.6}, speed 14. Free sailing explicitly creates player fuchuan at {0,0}, neutral merchant at {140,100}, neutral fisherman at {60,-120}, fisherman heading PI/3 and deployment 0.65. Terrain authority is `simulation/world-layout.ts`, registered through `registerHeightSampler(terrainSample)` before World initialization.

Commands preserve held sailing keys, Q/E broadside, Space nearest hostile-side selection, ammo 1/2/3 and R trim. Escape, blur and hidden state pause. Surrender uses the real simulation preview, confirm/cancel and terminal result; restart reconstructs the simulation from the source configuration without career effects.

QA source: `apps/game-client/src/simulation/VisualScenarios.ts`; fifteen scenarios include six-ship fleet, damage, sink, impact, weak impact, benchmark, shore escape, two wave scenes and six crew scenes. This minigame/ship-book implementation does not claim a port of those naval QA scenes.

## Focused verification

Both test scripts first failed on absent native entries, then passed against the implementation. A later RED layout assertion exposed overlapping practice controls; native header-aware panel placement corrected it.

- `tests/test_practice_entries.gd`: real actions for all four models, fixed inputs, Begin clock/action gates and retry reset, actual native rhythm scoring, result-injection refusal, pause/suspension, settlement/retry identity, native buttons, mode switch, actual physical-key-only input for WASD/E/1/2, focused-selector isolation and owner navigation. Physical-key and Begin/shortcut regressions failed before the routing corrections, then passed.
- `tests/test_ship_book.gd`: 229 assertions, zero failures, exit 0 under Godot 4.7.2 headless with no Godot diagnostics. All eighteen GLBs instantiate; authored sails/morphs, deployment, rotation, recoil/rudder, actual selection controls, source dimensions and failed attempted-asset/retry recovery remain covered. Actual InputEvent tests cover precise orbit/pan recurrence across repeated frames and release, height normalization, render downsampling, Ctrl/Meta/Shift/Alt gestures, middle dolly, wheel factors and pinch discrimination, exact preset position/target, pending orbit/pan during all six preset resets and model replacement, source polar epsilon, unrestricted target pan, bounded zoom and disposed-owner input fencing. Root-routed events additionally prove sidebar wheel/key isolation, model-view pointer delivery, preserved sidebar focus, perspective aspect/FOV and sensitivity through a scaled window plus downsampled viewport. `Input.parse_input_event` regressions cover left/right/middle-first mouse chords, both original/secondary release orders, exact orbit recurrence, last-release completion and focus/disposal cancellation with consistent held-button masks. Initial new interaction tests failed 32 assertions before the port; synthetic Ctrl-wheel failed before passive Control-key discrimination was added. The mouse-chord review regression failed seven assertions before tracking the held-button set and retaining the first gesture.

Runs above use Godot 4.7.2 headless. Root subsequently ran all53 native tests and personally inspected four actual D3D12 ship-book viewport captures after root-routed rotate/chord, pan and wheel events. Evidence is under `docs/migration/evidence/shipbook-orbit/`; see [native-chart-v2-verification.md](native-chart-v2-verification.md). This confirms the native input/camera behavior and actual frames, without claiming identical Godot/Three lighting or FPS acceptance.
