# T3 — interactive field in the existing wake-flow laboratory

Date: 2026-10-14. Scope: implementation and headless contracts only; this worker did not run GPU. No journey changes, save access, commits, catalog, host, ocean, producer or field-backend edits.

## Implemented

- Extended `game/research/demos/wake_flow_experiment.gd`, retaining its real Ship/Crew/Ocean/SailingRuntime owner and existing source baseline.
- `field_enabled=false` remains the default. `flow_enabled` is explicitly labeled the archived, rejected center-trail v2. Enabling both is rejected. Candidate selection requests the existing clean-reset workflow.
- Separate local contact foam/spray visibility and `field_debug=none|height|foam|normal` controls. Existing ship/scenario/camera factors remain. Carrier selection explicitly distinguishes the original 1200m plane and 384m close-view plane, both with 512 subdivisions; the latter is not silently applied to the baseline.
- Each accepted pose passes the real waterline attachment to `ship_water_interaction.sample`. Actual probe positions, full 3D velocities, measured world dimensions and accepted-time receipt remain visible in inspection. Nonempty wake input is appended; empty first/duplicate/stationary/dry input is not invented.
- Requests use the authoritative native time and a texel-snapped center behind the actual stern. There is no new simulation clock. First observer step is 0.03125s; first native/field request is 0.025s, asserted against the real runtime.
- An asynchronously configured field remains visibly pending or error until a real published surface is available. The original tail history and geometry keep updating. The original SceneStrip is hidden only after ocean binding returns true. Local contact remains independent.
- The publication handshake is `acquire_surface()` → bind that packet's texture/bounds → `acknowledge_surface(generation)`. The demo stores the last bound bounds and generation in its receipt; it does not derive bounds from a future requested center. It does not wait for `!pending` before acquiring/acknowledging the first published surface.
- Camera/paused observer calls may poll publication, but do not advance accepted time. Reset unbinds the ocean before field disposal, clears the producer, and increments a generation guard. Deferred QA readbacks from the prior reset return `stale-field-readback` rather than being accepted into the new experiment.

## Headless evidence

All logs retained under `Temp/research/`; no failed results were overwritten.

| Evidence | Result |
| --- | --- |
| `t3-interactive-wake-red.json` | New-factor RED: 16 assertions, 11 expected failures; no script error |
| `t3-interactive-producer-mutation-red.json` | Deliberately omitted producer call: 27 assertions, 4 failures; invocation restored immediately |
| `t3-interactive-producer-green.json` | Real producer invocation restored: 27/0 |
| `t3-interactive-carrier-red.json` / `...-green.json` | Missing explicit carrier reset factor: 28/1 → 28/0 |
| `t3-interactive-request-time-red.json` / `...-green.json` | Missing submitted-time receipt: 29/1 → 29/0 |
| `t3-interactive-readback-epoch-mutation-red.json` | Deliberately removed generation comparison: 30/1; guard restored immediately |
| `t3-interactive-driver-red.json` | Missing driver: 1/1 |
| `t3-interactive-readback-red.json` / `...-green.json` | Missing raw readback guard: 11/1 → 14/0 |
| `t3-interactive-final-green.json` | Four focused suites passed: capture guard 14/0, T1 field 24/0, root ocean 20/0, T3 lab 30/0 |
| `t3-interactive-final-source-regression.json` | Existing source/historical-v2 experiment regression 41/0 |
| `t3-interactive-lease-final-green.json` | During T1's publication change: T3 capture14/0, ocean20/0, lab30/0; T1 new RED26/2 retained (ACK ownership and unrepresentable gap guards) |
| `t3-interactive-lease-final-green-2.json` | Final ACK contract rerun: capture14/0, T1 field29/0, ocean20/0, T3 lab30/0; all four suites passed |

The headless field returns `Global RenderingDevice unavailable in headless mode`; the lab keeps the source tail visible. This proves explicit fallback and real CPU input wiring, not GPU readiness. Publication handshake was added after the first final receipts; the last row is the accepted focused rerun.

Frozen T3 source SHA256 for root's first real-scene run: `wake_flow_experiment.gd` = `6d3ffcce5e4d73ad4a674f410b0660fefa9d7971894ec9a3c05bd312d6dbeab1`; `verify-interactive-wake-lab-gpu.gd` = `9cfe2ca00dd94dfb73d4d62b7e49ae1d4abdc7895791a527a4db4fd987384a2e`.

## GPU driver for root

New `tools/verify-interactive-wake-lab-gpu.gd` runs only on a real display/GPU. It rejects an existing output directory and writes the manifest only when this invocation created the directory. Zero, missing, duplicate or out-of-order captures cannot pass. Modes are `source`, `field`, and `historical-v2`; default is source. Unique completion marker is `INTERACTIVE_WAKE_LAB_GPU captures=N failures=N`.

Fixed observer step is 1/32s. For field mode, each step waits for published native requested time, ready/bound state, no render work pending, and zero dropped steps before the next physics step. This avoids coalescing force inputs in the QA sequence. `--every=1` saves consecutive accepted observation frames; larger intervals are explicitly labeled sparse captures.

Each raw PNG has SHA256, observer/native/requested times, actual input probes, field diagnostics and bound surface generation/bounds, full native ship state/hash, control state/hash, camera transform and projection. The source freeze includes demo, runtime, Ship/Crew/packet, original wake/history/geometry/contact, T1/T2 modules, compute shaders, projected ocean, main ocean shader and `interactive_wake_surface.gdshaderinc`. Final QA readback saves the actual RGBA32F bytes and checks complete finite channels, ±0.25m height and [0,1] foam. CPU advance timings exclude waiting for the GPU and are not presented as GPU cost or whole-game FPS.

First real moving probes occur at observer tick 1 / native 0.025s. Suggested first high-view probe is `--camera=high --zoom=0.65 --no-contact`, with 384m carrier explicitly fixed by the driver. Tick 64 is about2s, tick128 is4s (existing turn/reef commands begin), tick256 is8s. Always choose a new output directory:

```powershell
rtk proxy $env:GODOT_EXE --path . --script res://tools/verify-interactive-wake-lab-gpu.gd -- --mode=field --debug=none --ticks=256 --every=4 --camera=high --zoom=0.65 --no-contact --output=res://docs/research/evidence/wake-flow/NEW-RUN/field-normal
rtk proxy $env:GODOT_EXE --path . --script res://tools/verify-interactive-wake-lab-gpu.gd -- --mode=field --debug=height --ticks=64 --every=1 --camera=high --zoom=0.65 --no-contact --output=res://docs/research/evidence/wake-flow/NEW-RUN/field-height
rtk proxy $env:GODOT_EXE --path . --script res://tools/verify-interactive-wake-lab-gpu.gd -- --mode=field --debug=foam --ticks=64 --every=1 --camera=high --zoom=0.65 --no-contact --output=res://docs/research/evidence/wake-flow/NEW-RUN/field-foam
```

For an exact baseline use the same arguments except `--mode=source` and a different output directory. The same driver supports `--scenario=cruise|slow|turn|stop|reentry`, `--kind=fisherman` or the other existing ship kinds, `--quality=low|balanced|high`, `--carrier=1200|384`, and side/high/front cameras. Reentry is the existing explicit2m presentation stress overlay; it is not native airborne physics. Stop means the real sail command at4s; inspect actual recorded speed rather than claiming it reaches zero at a fixed time.

## Remaining acceptance

Root owns GPU execution and visual judgment. T3 does not claim that the new field produces acceptable dual arms, that stop foam or oscillating height looks natural, that GPU resources are leak-free under real queued reset/disposal, or that the normal game meets a frame-time target. The lab is deep open water; coastal propagation/wet masking and formal production default-on remain separate gates. User-confirmed dual-side wake structure remains the intended art direction; archived center-trail v2 is not adopted.

## Follow-up: full-vessel framing and paired turns

After root's first valid real-scene GPU run, the image at `docs/research/evidence/wake-flow/interactive-lab-1/cruise/t0256.png` visibly cropped the main sail. The two parallel wake bands were also not visually accepted; this follow-up changes only lab camera/turn controls and the capture driver, not the field algorithm.

- `turn_direction=right|left` is a clean-reset factor. Default right preserves the previous fixture. For the turn scenario, the derived demo owns the existing bounded 1/32s advance branch and commands the real runtime with0 through observation tick127, then +0.45 or−0.45 from tick128 onward. This prevents the inherited positive-rudder command from overwriting a left-turn input. No injected positions, headings or velocities are used.
- Camera preserves its existing focus and orbit direction, then fits the actual visible mesh AABB corners and stern/aft endpoints inside90% of the perspective frustum. For camera basis coordinates `(x,y,z)` relative to focus, minimum distance obeys `d >= z + max(abs(x)/(tanX*.9), abs(y)/(tanY*.9))`; near-plane clearance and1% slack are also enforced. The aft span is twice the larger of measured waterline length and the previous nominal inspection length. Requested zoom remains recorded; `camera_framing` reports actual minimum/effective distance. Baseline and field selection use exactly the same ship-only calculation.
- GPU driver additionally verifies each capture's actual mesh corners and two measured waterline lengths are inside an8px inset. This verifies scene projection, not shader-deformed pixel silhouettes; raw GPU images still require inspection.
- New CLI `--turn-direction=left` or `right` is stored in controls. Optional repeated `--window=start:end` captures short consecutive observation-tick stages in addition to the existing sparse `--every` schedule; at most3 windows, each spanning at most64 ticks. Example: `--ticks=256 --every=4 --window=120:144 --window=240:256`. Every4 by itself remains valid and still yields65 frames at256 ticks.

Verification retained:

- `t3-wake-framing-turn-red-2.json`: valid RED11/3, specifically missing explicit right default, cropped real vessel at8s/high/zoom.65, and unsupported left direction. The first attempt `...-red.json` had a test type-inference error and is not counted as valid RED.
- `t3-wake-framing-final-regression.json`: original lab41/0 plus new framing/turn suite16/0. The latter checks actual opposite rudder/physics trajectories, identical pre-turn native state, full fuchuan AABBs and aft span at8s, and identical source/field camera transforms.
- `t3-wake-framing-field-regression.json`: field lifecycle/input suite30/0.
- `t3-wake-windows-red-2.json` → `t3-wake-windows-green-1.json`: valid missing-window RED15/1 →17/0. The first window attempt called an unavailable third argument and timed out after a script error; it remains retained and is not counted as valid RED.

Follow-up source freeze supersedes the earlier T3 hashes: `wake_flow_experiment.gd` SHA256 `aea132767415b6283f2f861c8873c0c498435199702e6deae4b8078b09d2b3e4`; `verify-interactive-wake-lab-gpu.gd` SHA256 `589a217143914a22cebe5c33994767ce208a03a4cb7a96bd01196b66cbf5da90`. This worker again ran no GPU; root owns paired cruise/source, left/right, stop, reentry and small-vessel visual acceptance.

## Follow-up: duplicate queue ownership and production projected carrier

Two independent defects were investigated and tested separately. The accepted art direction and the numerical field/shader were not changed in this follow-up.

### Same-time observer redraw

Controls' preserved reproduction `Temp/research/t2-wake-duplicate-queue-review-cruise.json` showed a real2.0s accepted packet containing5 emitters and1 wake becoming0/0 after a camera redraw at the same time. Its nonzero force proxy was2.88995098917544 before loss. The producer correctly rejected duplicate sampling; the lab incorrectly submitted that empty duplicate result into the field facade's latest-request queue and also replaced its diagnostic input receipt.

`test_laboratory_wake_queue.gd` reproduces both in-flight and awaiting-ACK boundaries using the actual Demo, producer and main-thread facade queue. Only the asynchronous scheduling boundary is held; no GPU device is created and no simulation state, force, pixels or successful field state is fabricated. RED `t3-wake-duplicate-queue-red.json` had12 assertions/8 failures. GREEN `t3-wake-duplicate-queue-green.json` had12/0.

The lab now submits only when the producer reports `diagnostics.accepted`. A duplicate changes only `interaction_duplicate_skips`; it preserves the queued accepted packet, queue coalescence count, requested time and last accepted `interaction` receipt. The next accepted pose still replaces the queue normally. Camera-only redraw continues the existing source-camera update and field bind/ACK polling, without injecting empty forces.

### Actual production carrier

The raw side-view image `docs/research/evidence/wake-flow/interactive-lab-2/side/t0384.png` was inspected: the384m PlaneMesh exposed its distant polygon boundary as a ridge. The parent hull-contact experiment intentionally owns that finite plane. It remains unchanged.

Only the derived wake experiment now defaults to `carrier_mode=projected`. After the inherited real scene is built, it calls the existing public `Ocean.configure` with the actual camera and normal texture, restoring the production `_projected_mesh`; pose changes, camera-only redraws and field binding call the production `update_projection`. Existing shader, wave descriptors, optics/reflection and field binding stay with that same owner. No replacement projection algorithm was introduced.

The final default is `projected_resolution=80`, matching normal production, with6561 vertices and38400 indices. The early implementation used160 (25921 vertices) but there was no GPU evidence that160 was necessary; it was changed to80 before freeze. Explicit96 and160 remain bounded experiment factors. A160 result must not be presented as proof of production80 detail quality. Projected grid cell size depends on view/depth and is not the field's0.375m cell size. Inspection records actual mesh class, segments, vertex/index counts, maximum distance, AABB and production projection diagnostics.

`carrier_mode=plane` retains the old384m/1200m planes as explicit comparison. Carrier selection does not alter native initial state or the full-vessel framing camera. The lab also delegates tail suppression/restoration to `SourceRenderer.set_external_water_coverage`; it no longer bypasses submission eligibility by directly overriding SceneStrip visibility.

`test_laboratory_wake_carrier.gd` RED had7 assertions/5 failures (`t3-wake-projected-carrier-red.json`). The actual production mesh identity, Camera3D center-ray intersection, finite vertices beyond the384m comparison edge, paused reprojection, five-wave material, explicit plane, resolution control and identical baseline/candidate cameras now pass29/0. The production80 default change has its own29/1 RED in `t3-wake-production-grid-resolution-red.json`.

Final receipts, all headless and all successful:

- `t3-wake-production-grid-final-green.json`: carrier29/0, original lab41/0, full-vessel framing/left-right16/0, duplicate queue12/0.
- `t3-wake-production-grid-field-regression.json`: capture guard17/0, shared source fallback39/0, field38/0, ocean20/0, shared system62/0, interactive lab30/0. These shared-module counts are current regression observations, not work authored by T3.

The GPU driver now explicitly defaults to projected80, supports `--carrier-mode=projected|plane` and `--projected-resolution=80|96|160`, and records carrier diagnostics and duplicate skips per capture. Its source freeze additionally includes `source_surface.gd` and `projected_grid_coverage.gd`. For the new source/field pair, hold camera, scenario, quality and carrier identical:

```powershell
rtk proxy $env:GODOT_EXE --path . --script res://tools/verify-interactive-wake-lab-gpu.gd -- --mode=source --carrier-mode=projected --projected-resolution=80 --camera=side --zoom=0.65 --ticks=384 --every=4 --no-contact --output=res://docs/research/evidence/wake-flow/NEW-RUN/projected-source
rtk proxy $env:GODOT_EXE --path . --script res://tools/verify-interactive-wake-lab-gpu.gd -- --mode=field --carrier-mode=projected --projected-resolution=80 --camera=side --zoom=0.65 --ticks=384 --every=4 --no-contact --output=res://docs/research/evidence/wake-flow/NEW-RUN/projected-field
```

Final T3 source freeze supersedes prior hashes: Demo `080ca47b0bf94ee798d8f42a2c2e633c06197800ed51c642ffc227761e6558d5`; driver `2acd60238a78256a2495e4bfd734ced8fa1f34eaef27039f3e266040ff25d31b`. No GPU was run by this worker. The normal production field remains default-off; projected80 visual quality, the former plane-edge symptom in real pixels and production rollout still require root's serial paired GPU acceptance.
