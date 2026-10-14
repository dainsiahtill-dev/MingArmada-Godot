# T2 — actual hull water interaction input

2026-10-14. Scope: shared-contract CPU producer for the approved interactive-wake-field experiment. No GPU execution or production routing change. Shadow candidates stay parked; ocean, field solver, crew, sailing controls and original wake history/math are unchanged by this task.

Frozen [CPU evidence manifest](../../../research/evidence/wake-flow/2026-10-14-t2-water-interaction/manifest.json) retains all test runs, eight source snapshots and hashes of all four original model assets. The pitch-only RED's source was not copied before its small fix; that limitation is explicit in the manifest rather than inventing a historical source freeze.

## Delivered interface

`modules/scene_engine/water/ship_water_interaction.gd` is a `RefCounted` owner with:

```gdscript
sample(id: String, attachment: Dictionary, seconds: float,
       water: Callable, hull_alive: bool = true) -> Dictionary
forget(id: String) -> void
clear() -> void
```

Input is the actual `ShipView.source_water_attachment()` packet. Only `attachment.surfaceProfile.sections`, its full `hullToWorld`, and the full-pose `attachment.bow` determine geometry. The original yaw-only `trail` and `flowStern` remain untouched and are not velocity sources. Water is called as `water(x, z, accepted_seconds)` and may return an existing numeric world height or `{height: float, flow: Vector2}`. Flow is world horizontal XZ metres/second. Default flow is zero; no vertical wave velocity is subtracted.

Output is `{emitters: Array, wake: Dictionary, diagnostics: Dictionary}`. Each emitter has the required `position: Vector3`, `velocity: Vector3`, `radius`, `wetness`, `weight`, and stable `id` (`actor:probeN`). `wake` has actual full-pose `stern`, normalized world-XZ hull `forward`, world `beam`, relative horizontal `speed`, stern `wetness`, and actor `id`. Empty wake means no fresh long-tail foam source; the field must continue aging its existing state independently.

Diagnostics include `accepted`, `advanced`, `reason`, accepted `time`/`dt`, `actor_count`, `probe_count`, `beam_m`, `length_m`, `radius_m`, `speed_mps`, `stern`, `stern_wetness`, `clamped_velocities`, and five probe receipts (local/world positions, actual 3D velocity, sampled height/flow/wetness). Rejected calls return empty emitters/wake plus reason and current actor count.

## Geometry and declared coefficients

All dimensions derive from actual cached model-local Y=0 sections. World beam is maximum section width multiplied by the complete transform's local-X basis length. Length is the full 3D distance between transformed waterline end centers; yaw/roll/pitch do not arbitrarily shorten these physical measurements. The authored bow marker identifies which end is stern.

Five probe centers use interpolated actual sections: both sides at 15% of stern-to-bow length, both sides at 50%, and center at 85%. Every point is multiplied by full `hullToWorld`, including pitch, heel, scale and parent transform. Probe centers are a sparse sphere approximation, not a hull collision mesh or a nominal 32×9-m box.

| Choice | Value / meaning |
| --- | --- |
| Probe radius | `clamp(world_beam * 0.20, 0.20, 2.0)` metres |
| Per-probe weight | `0.20`; five sum to 1 |
| Contact proxy | `max(0, 1 - ((probe_y - water_y) / radius)^2)` |
| Fresh wake gate | relative horizontal center speed >0.05 m/s and stern wetness >0 |
| Derivative interval | accepted dt from 0.00001 through 0.5 seconds; outside starts a new zero-velocity baseline |
| Teleport guard | any probe moves >`max(20m, world_length*1.5)` or implied speed >80 m/s |
| Numerical velocity ceiling | 20 m/s vector length per probe; wake speed also capped20; clamp count reported |
| Actor state bound | 64; a new actor at capacity is rejected without evicting another |
| Water queries | six per accepted valid geometry: five probes and actual stern |

Wetness is the normalized area of a sphere/plane intersection circle: area `pi*(r²-d²)` divided by `pi*r²`. It is an **artistic interface-coupling proxy, not a buoyancy/force law**. A sphere one radius above or below the sampled interface has no support. Deep-submersion zero applies only to this visual surface disturbance input, never ship buoyancy. Real ocean slope is approximated by each locally sampled horizontal height. Standard finite differences and this elementary geometry are independently implemented; no Crest implementation code was copied. Conceptual research and fixed-source provenance remain in [the approved research note](../../../research/wake-flow-online-research-2026-10-14.md).

All numerical thresholds above are explicit initial stability/art choices. Their visual amplitude, foam density and suitability across sea states remain GPU acceptance work. Velocity.y is not multiplied by an additional hidden artistic factor in this producer.

## Accepted time, ownership and lifecycle

Ordinary rate is `(current_world_probe - previous_world_probe) / accepted_dt`; only ambient horizontal flow is subtracted. Unchanged XZ with rising Y therefore remains a local force source even when wake.speed is zero. The wake uses the complete hull transform's origin for translational horizontal rate; it does not derive speed from yaw-only trail history. Midship point motion contains pitch/roll terms even with a fixed origin, so it cannot be used as forward travel. Ambient flow for the wake is the average sampled at its two midship probes.

First sample, rewind, interval outside the range, changed local probe geometry and large jump accept a new baseline with zero velocity and no fresh wake. Ordinary future samples then resume normally. Exact repeated time returns `accepted=false`, no inputs and no history mutation, even if the caller supplies a different pose. No wall clock is owned here.

The complete attachment and all six water results are validated before any history commit. A malformed later probe/water result cannot partially advance the actor. Stored Vector3 positions and local points are independently held; mutating returned emitter dictionaries does not affect the next derivative. `hull_alive=false` removes only that actor even at repeated time; `forget`/`clear` release lifetime/capacity. Owners must call them on removal/session reset.

## Actual four-model evidence

Fixed fixture `tests/fixtures/ship_water_interaction_dimensions.json` was measured from imported hull profiles before producer implementation. Identity ship pose, same bundled models, Godot 4.7.2. Source hashes and receipts are in the evidence manifest.

| Gameplay kind / current model | World beam m | Waterline length m | Probe radius m |
| --- | ---: | ---: | ---: |
| fuchuan / barque | 4.972724 | 20.732496 | 0.994545 |
| fisherman / sloop1 | 3.881930 | 12.814256 | 0.776386 |
| merchant / ship_merman | 8.660094 | 31.363083 | 1.732019 |
| heavy / treasure_galleon | 11.863267 | 32.735489 | 2.000000 |

The earlier research note's 17.7-m length was an estimate, not the current measured fuchuan waterline; use20.732496m for this fixture. Uniform scale2 gives doubled measured beam/length. Full rotation tests preserve physical beam and verify all probes against the actual transform. Each model produced vy=1m/s for0.1m rise in0.1s, approximately5m/s for0.3m X/−0.4m Z movement in0.1s, and wetness0 when fully clear of the water.

`test_ship_water_interaction.gd` was written first. Initial RED was missing new producer (1 assertion/1 failure), not an existing production algorithm failure. A further real pitch-only fixture exposed the initial use of midship position as travel:220 assertions/1 failure. The source was corrected to use the hull transform origin only for long-wake speed, while probe velocities retain full angular motion. Final GREEN has220 assertions/0 failures: four actual models, real units, full pose, stationary heave/pitch, stop, dry/deep-submerged support, current subtraction, scale, repeated time, atomic malformed geometry/water, caller mutation, warp/recovery, rewind, interval gaps, numerical cap, actor capacity/removal. Existing hull-waterline tests (2 scripts) and attachment regression (1 script) also pass. No visual-success or complete-game performance conclusion follows from these CPU results.

Commands used, with separate retained receipts:

```powershell
rtk proxy node tools/verify-godot.mjs --filter ship_water_interaction --output Temp/research/t2-ship-water-interaction-red.json
rtk proxy node tools/verify-godot.mjs --filter ship_water_interaction --output Temp/research/t2-ship-water-interaction-green-final.json
rtk proxy node tools/verify-godot.mjs --filter hull_waterline --output Temp/research/t2-ship-water-waterline-regressions.json
rtk proxy node tools/verify-godot.mjs --filter wake_flow_attachment --output Temp/research/t2-ship-water-attachment-regression.json
```

## Read-only production seam recommendation

The real ordering in `NavalWorldView.apply_snapshot` first updates each `ShipView` full pose, then calls `wakes.apply_snapshot(WaterPacket.compose(native,ships,camera))`. This is the right accepted-pose boundary. `SourceWaterPacket.compose` is stateless and currently converts original wake/bow markers to native units; do **not** use its `sourcePosition`, nominal dimensions or `froth.enabled` for this producer. The last gate also depends on speed/sail state and would suppress stopped heave.

For a future explicit candidate packet, preserve world-space attachment `{surfaceProfile, bow}` alongside the original packet. A persistent owner must call this producer after full poses have been applied, using `environment.acceptedTime` consistently with the field. `WakeTrails.apply_snapshot` has an early return for source routes; interaction work added only below that return would never run in actual gameplay. Put the opt-in shared field/producer stage before the route branch, or keep a separate persistent owner at the world boundary. No static state inside `SourceWaterPacket.compose`.

Near-view eligibility should be deterministic. Initial field budget16 allows three complete5-probe ships plus one spare, so select actors before sampling or deliberately report per-emitter truncation. Field-disabled/far ships retain the source route. When the field is actually ready, hide only the eligible actors' original tail draw; keep original history advancing and local contact froth independent. Never hide3D crews or all wake children as a fallback shortcut.

On actor removal call `forget`; on epoch/session reset clear producer and field together. Quality rebuild currently transfers only `SourceWakeRenderer` through `take_source_state`/`restore_source_state`; a new producer/field owner needs explicit retention or reset semantics as well. Failed/invalid packets emit nothing and keep their last accepted state; disabled-candidate reentry should explicitly clear/forget if a gap is intended to reset. These are integration recommendations only; no production caller was edited.
