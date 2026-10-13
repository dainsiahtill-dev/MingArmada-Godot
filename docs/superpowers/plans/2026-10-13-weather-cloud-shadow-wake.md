# Weather, Cloud, Shadow and Wake Godot Implementation Plan

> For agentic workers: use superpowers:subagent-driven-development. Work through each owned task, verify its diff, then run integration and a whole-change review.

Goal: integrate the accepted original weather/cloud/shadow/wake rules and assets into the existing playable Godot game through shared foundation modules.
Architecture: pure environment rules produce detached state at accepted simulation updates; scene renderer consumes state with per-pass camera inputs; gameplay adapters supply route, unit mapping, markers and lifecycle. Preserve physics/render separation, existing good ocean and mouse handling, and 3D deck crew.
Tech Stack: Godot 4.7.2, GDScript, existing native helpers and source assets, Forward+ Vulkan.
Spec: docs/migration/weather-cloud-shadow-wake-integration-2026-10-13.md and C:/Games/Pirates-REA-Reference-20261011/weather-cloud-shadow-wake-study-20261013/AGENT_HANDOFF.md.
Base: 1a596d02d8f364c33a0c9bcaae649414318f6e48, branch codex/godot-migration.

## Global Constraints
- Actual repo C:/Users/dains/Documents/Git/ming-armada. The no-hyphen cwd and its attached old worktree are another repository.
- All shell commands and chained segments start with rtk; CodeGraph already reports this Godot repo unindexed and instructs fallback.
- User explicitly requested full implementation with multiple experts after receiving the implementation sequence. Continue autonomously; no repeated design permission request.
- Work on the existing feature branch with exclusive file ownership. Do not stage/commit/reset/clean/push or modify user saves/original binaries. Preserve preexisting untracked migration docs.
- Do not operate shared game/editor windows from workers. Only root performs native UI/GPU scene acceptance after source integration.
- No new independent game demo or public menu entry. Existing formal/practice/QA paths consume shared modules.
- Source integer/f32/clock/INI/resource contracts are distinct from declared target unit/cadence/visual adaptations. No invention represented as recovered original behavior.
- Do not couple original wind producer to a hard player speed lock. Keep existing mouse handling assistance and 3D deck crew.
- Do not promise pixel/FPS equivalence from CPU fixtures. Keep original unknowns, zero-length non-equivalent diagnostic fallback and runtime source gaps explicit.

## Shared Interface
Environment producer: modules/environment_engine/weather_state.gd, RefCounted, configure(options:Dictionary={}) -> bool; advance(accepted_time:float, observer:Dictionary, wind:Dictionary, paused:bool=false) -> Dictionary; snapshot() -> Dictionary; reset(options:Dictionary={}) -> void. Returned state is detached.
Environment packet under native.environment: {revision, epoch, acceptedTime, sourceCallIndex, source, worldClouds, lighting, route}. source contains explicitly named source clocks/state; worldClouds carries resource, source/world pose, model scale and controller appTime; lighting carries explicit day mode/controller/material inputs plus declared target adaptation. Weather implementer freezes precise subfields and example packets in its report before root integration.
Renderer receives packet unchanged; source-call advancement happens in runtime/core accepted step, never inside an extra presentation callback. Existing environment absence remains supported for old fixtures until actual adapters supply it.
Wakes: preserve configure(water_sampler), configure_surface_filter, configure_sampling_scope, apply_snapshot(native), dispose public seam. Add explicit route and source attachment metadata, native histories behind this seam, original authored local froth as distinct resources. No weather/projection file edits by wake worker.
Projection: source_shadow_math.gd provides finite original CPU functions; source_shadow_renderer.gd configure(parent:Node3D, camera:Camera3D, options:Dictionary={}) -> Dictionary; apply_snapshot(native:Dictionary, actor_nodes:Dictionary={}, environment:Dictionary={}) -> void; diagnostics() -> Dictionary; dispose() -> void. Declare backend capability and original-vs-target adaptation, never claim stencil increment/decrement via a texture or generic shadow map.

## Review Focus
- Repeated snapshot, local fire, terminal visual continuation and quality rebuild do not advance weather/RNG twice or lose new environment fields.
- Pause/rewind/scene epoch and separate instance clocks do not corrupt controller history; source TRS f32 order matches original fixtures.
- Zero-length/startup, stop/reverse/teleport/wrap, model scale and absent marker/LOD paths remain finite without silently claiming native equivalence outside recovered domains.
- Shadow resource sibling hierarchy, per-pass camera, original alpha/depth and caster gates are not replaced by generic impostors; unsupported GPU operations are reported accurately.
- Full game entries retain crew3D and mouse movement assistance; preserved blue water does not become blanket-white and no developer demo replaces formal paths.

## Task 1: Weather, clocks and atmosphere (weather expert)
Files: new modules/environment_engine/*; modify modules/scene_engine/fidelity_fx/cloud_native.gd, cloud_render_compiler.gd, atmosphere.gd and its shader/owned weather renderer; source atmosphere assets/manifest only when required; tests/test_source_weather*.gd, tests/test_source_atmosphere*.gd and justified existing atmosphere tests.
Do not edit encounter.gd, WorldView, NavalWorldView, gameplay runtimes/scenes, crew or wake/projection files: root integrates those.
- [ ] Import small original-byte fixtures with source identity/probe bounds; write failing tests for int32/fixedTrig/RNG weather slices and TRS/persistent clock regression.
- [ ] Run RED and record output; port pure producer and explicitly configured target scheduling/units adapter, detach snapshots and preserve dedupe/pause/rewind state.
- [ ] Correct original translation rotation/f32/scale order and persistent per-instance clocks without sharing mutable state between phase instances.
- [ ] Preserve domecloud ring and connect world cloud00/storm resources, parent chains/material/UV/mips, independent world movement, source cloud shadows and source day/light fields; no generalized sky wind drift.
- [ ] Freeze environment packet and renderer inputs with sample packet/report. Coordinate shadow ownership: weather displays resource-baked cloud_sh/stormshadow; projection owns stencil and ship texture shadow.
- [ ] Run focused tests and report RED/GREEN, finite adaptations, changed files, source boundaries and diagnostics for live acceptance.

## Task 2: Native wake routes and authored froth (wake expert)
Files: new modules/scene_engine/water/source_* and required original fixtures/assets; modify game/presentation/water/wake_trails.gd, ship_wave_geometry.gd only if needed; new tests/test_source_wake*.gd, test_source_froth*.gd and justified wake tests. Ship model importer/provider, ShipView and WorldView hooks are root-owned.
- [ ] Write failing original fixture tests for 30 ring distance equality/strict jump/same clock/rewind rejection/reverse/wrap/two scale width branches/update-count alpha/f32 stores, plus 90 history/hold/7x3 draw arguments.
- [ ] Port histories, LUTs, finite profiles, topology/head/nearby self-cross from provided source and preserve explicit unresolved boundaries. Engine functions do not require EXE/Python at runtime.
- [ ] Replace selected routes behind existing Wakes seam, not a third independent demo. Explicit packet route; original model/root scale and markers, not ship width.
- [ ] Render independent bowfroth/9 ship-family sidefroth from existing authored NIF/controller/texture data using shared resource capabilities. Ask root for any attachment adapter needs.
- [ ] Preserve blue water and declare stop-fade/water-fit choices as target adaptations; no removal/hiding of crew or foam for performance. Stable topology uses buffer region strategy where valid.
- [ ] Run focused tests; report source math limits, first-frame finite guard, visual diagnostics, needed root hooks and original-vs-target behavior.

## Task 3: Projection and GPU shadow backend (shadow expert)
Files: new modules/scene_engine/fidelity_fx/source_shadow_math.gd, source_shadow_renderer.gd and owned shaders/helper files; owned ship-shadow resource manifest; tests/test_source_shadow*.gd. No atmosphere/WorldView/NavalWorldView/ShipView edits; root attaches integration hooks.
- [ ] Test RED then port original finite edge cancellation/volume/rebuild/registration predicates using original fixtures and explicit caster directions.
- [ ] Preserve selected original ship texture-plane parent/TRS/material contract; cloud shadow resources remain weather-owned.
- [ ] Inspect installed Godot renderer/stencil capabilities, consult official primary docs/source when needed. Implement real available two-face stencil/quad backend if supported, with explicit state/camera/depth/buffer lifecycle and no unsupported calls.
- [ ] If source exact stencil requires unavailable renderer exposure, implement the supported reusable backend/capability contract and source volume preparation; document precise missing GPU operation and a separately named visible target adaptation. Never call a shadow map original stencil.
- [ ] Test repeat/pose/rotation/gate/missing caster/dispose/backend capability. Report shader compile/live GPU procedure and exact integration hooks.

## Task 4: Shared packets and formal integration (root)
Files: modules/contracts environment/attachment packet helpers; modules/naval_simulation/encounter.gd accepted environment owner; runtime adapters only as required; game/presentation/world/naval_world_view.gd; modules/scene_engine/world/world_view.gd; game/presentation/ships/ship_view.gd and ship_model_provider marker access; existing direct WorldView entry; integration tests and accepted source documentation.
- [ ] Pin repeated snapshots, local fire, terminal visual time, quality rebuild and route/epoch behavior with failing integration tests.
- [ ] Consume weather expert packet in core accepted logic without changing handling wind assistance; forward all fields unchanged in normal and reconfigure presentation.
- [ ] Attach source actor/marker/root scale data to shared ship presentation for wake/shadow consumers; preserve source pose and CrewView path.
- [ ] Integrate all modules in actual game, restore/dispose owned resources, reuse existing primary/practice/QA entries; no new public demo.
- [ ] Review each task diff independently for spec/quality, fix findings through owner; run full tools/verify-godot.mjs suite once integrated and investigate failures.
- [ ] Run actual Forward+ Godot scene and capture controlled open-water navigation/weather/shadow/froth, pause/rebuild/cleanup; original coast-blocked sample never used as normal reference. Record frame/GPU measurements separately.
- [ ] Complete report with code, fixtures, source/target decisions, actual verification and remaining original unknowns; do not label incomplete GPU/source coverage all-fixed.
