# Native sailor presentation and Jolt impacts

Implemented and headless verified on Godot 4.7.2 / Jolt Physics, 2026-10-11. Scope is sailor presentation and visual impact physics. Original Three source remains read-only at `C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada`, baseline `9ad6a44daecd4ec36a8172d83ff27493feffe5dd`.

The migration follows `SailorDeckView.ts`, `SailorImpactPhysics.ts`, `NavalDeckSupport.ts` and physics/rendering inventory sections 6–7. Source was already reported UNINDEXED by the parent audit; this task used targeted RTK source reads. No CodeGraph result is asserted here.

## Presentation ownership

`game/presentation/crew/crew_view.gd` is a `Node3D`, parented under the corresponding `ShipView`. It loads the three original sailor GLBs through the existing cached `AssetLibrary`; every instance owns a separate `Skeleton3D` and `AnimationPlayer`. Authored vertex colors, eighteen bones, and the six original clips remain intact. Physics never traverses the visible mesh or imports game/presentation modules.

`deck_stations.gd` extracts actual local hull/deck triangles, samples their vertical intersections, and applies the original station ordering and named structure exclusions. Helm, mast workers, both cannon sides, lookout and a bounded aisle patrol are derived from loaded geometry. Near/middle authored plank caulking uses the original 0.026 m seam allowance, with feet another 0.005 m above support. World water/freeboard constants do not generate standing positions.

Visible personnel are bounded by floor(authoritative crew), positive hull health, station count and 24/8/2 near/middle/far limits. Hysteresis uses 90/110 m and 270/330 m; beyond 1800 m standing instances are released. The static `allocate_sailors()` function reserves vessel coverage then fills by distance/id within the original 120 standing sailor budget. Runtime must feed its allocations through `set_allocation()`.

## Stable runtime API

| API | Input / responsibility |
| --- | --- |
| `configure(kind, active_ship_model, asset_library=null) -> bool` | Actual loaded model; optional shared immutable AssetLibrary. Caller parents CrewView under ShipView first. |
| `set_ship_model(active_model) -> bool` | Call when ShipView changes GLB LOD; recomputes exact local support and replaces the owned detached collision definition. |
| `set_lod_distance(metres)` | Sailor hysteresis and visible cap. |
| `set_allocation(count)` | Caller-owned 120-person allocation. |
| `set_reduced_motion(enabled)` | Samples each authored clip at quarter duration; accepted phase continues independently. |
| `set_environment(water_callable)` | Same runtime wave sampler `(x, z, accepted_time) -> height`. No invented water surface fallback. |
| `apply_snapshot(ship, wind={}, consumed=0)` | Detached ship data. Include `id`, current accepted `time`, `crew`, `hull`, `visual.velocity`, `rudder`, `sailDeployment`, `sailAngle`, and `cooldownSeconds`. |
| `apply_events(events)` | Canonical `fire`/`hit` events after corresponding snapshot. Fire records projectileId/velocity; hit uses targetId, damage.crew, ammo, position and projectileId, or an injected hit velocity. |
| `dispose()` | Idempotent, releases only owned instances, native bodies and collision resources. Borrowed AssetLibrary remains caller-owned. |

AnimationPlayer uses manual callback mode. Clip sampling is `accepted_time + slot * 0.173`, modulo actual clip duration. First rendering at a late simulation time, repeated pause frames, LOD replacement and reduced-motion round trips do not start a second animation clock. Helm/sail/fire/cooldown/motion choose the actual authored work clip.

For each update, apply ShipView pose first, pass its active model if changed, then apply CrewView snapshot and events. Previous/current deck frames remain separate; a prior world contact point is transformed through the prior vessel frame rather than through the current frame twice.

Crew loss is observed from authoritative snapshots, and only that loss permits a casualty. A fractional damaging hit without personnel loss can cause the original nonlethal stumble. A terminal crew/hull wipe immediately hides standing personnel but retains their sampled skins for the current tick's hit transfer; unused retirees are released at the next snapshot. Replay IDs cannot produce duplicate impacts. The module never mutates hull, sail, crew, ammunition, combat state or campaign state.

## Native impact seam

`modules/physics_engine/impacts/impact_pool.gd` accepts a detached definition containing eighteen sampled world `Transform3D`s, parent indices and names. It creates eighteen native `RigidBody3D`s and seventeen `PinJoint3D`s at the sampled animated pose. `impact_bone.gd` owns the native force integration. Animation pauses during handoff; the visible skin follows native world bone transforms. Nonlethal expiry clears overrides, returns the same skin to its station and resumes manual clip sampling. Casualty expiry releases it.

Every bone enables continuous collision detection. This is necessary for small arm/wrist spheres crossing a thin authored concave deck at cannon-hit speed; the native regression failed without CCD and passed with it. Deck collision is an owned `StaticBody3D` built from detached triangles, updated with the accepted ship frame. Bone collision queries use injected deck/water providers; neither physics file imports game code.

There is a static twelve-body cap across vessel-owned pools, not twelve per vessel. Optional `set_impact_pool(pool)` supports one externally owned pool; in that mode runtime advances the shared pool once and injects a deck callback routed by targetId. CrewView still registers its detached ship collision and samples its own visible bone poses.

The original visual impulse policy is retained: grape 7 m/s, solid/chain 10 m/s horizontal launch; casualty vertical 5.5/6 m/s, spin 2.3; reduced horizontal factor 0.65, vertical factor 0.7 and reduced spin 0.7. Nonlethal impulse is 0.4 horizontal / 0.7 vertical with lifetime 1.25 accepted seconds; casualty lifetime is 7 accepted seconds and wet expiry 1.2 seconds. Drag factors convert the original 120 Hz 0.94 water / 0.985 deck steps by exponentiating accepted delta. Supported wet nodes sink by `wet * 0.45 m`; fade tails preserve the original visual policy.

Accepted delta gates native integration and pause freezes bodies. Godot node transforms lag completed native steps, so visible poses and diagnostics read `PhysicsServer3D` state. Initial native state is explicitly initialized from the sampled animation. Newly created bodies start wave queries at the pool's current accepted phase. Nodes born underwater are not teleported onto water; only nodes previously above the prior phase's surface acquire one-way water support.

Jolt owns articulated positions, constraints and physical deck collision. This is not the original twelve-iteration PBD distance/hinge solver and does not claim node-by-node trajectory equality or its original 120 Hz numerical oracle. Tests below verify native behavior and authority/lifecycle gates. No second PBD, PhysicalBoneSimulator or automatic AnimationPlayer writes the same bones.

## Reproducible verification

Run only the dedicated suite while other migration agents are editing:

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_crew_impacts.gd
```

Latest result: `CREW_IMPACT_TESTS assertions=578 failures=0`, exit 0. The suite first failed for missing CrewView/impact modules, then exercised native implementation. Later RED→GREEN checks cover actual thin-deck CCD, current wave phase, previous vessel frame and terminal hit handoff.

Evidence includes six ship kinds × three active GLBs, each standing station supported by actual loaded triangles; unique live eighteen-bone rigs and six authored clips; visible count/health/floor/LOD rules; current clock, paused pose, reduced-motion and work-role selection; global 120 standing allocation; canonical hit transfer, replay suppression, nonlethal recovery and authoritative casualty; native eighteen rigid bodies/seventeen joints, real impulse displacement, frozen native state, twelve-body global cap, death/nonlethal/wet expiry and resource disposal.

The native concave-deck test ran 90 actual physics frames: lowest bone center `+0.050106 m`, maximum pin anchor error `0.037695 m`. Above-water fall ran 100 native frames: wet age `0.45 s`, lowest bone center `-0.125322 m` during bounded wet sinking. Submerged birth stayed underwater. These are native physics measurements, not original PBD trajectory parity.

This task did not run the whole changing project suite, start GUI, capture a native screenshot, or validate the complete player battle flow. Root integration must supply accepted time, water, LOD updates, global standing allocations and real combat events, then verify the visible colored sailors and cannon-hit motion in the native window. Full migration completion is not claimed by this module report.
