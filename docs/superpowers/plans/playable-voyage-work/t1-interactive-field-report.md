# T1 Interactive Wake Field — implementation evidence

Status: first field numerical/publication checks passed, but real-ship visual candidate was rejected as two thin, nearly parallel grey streaks. The persistent outward-foam-drift candidate is now source-frozen, CPU-green and GPU-readback-green; its new real-ship appearance verdict remains pending. This report is not full-game performance acceptance.

## Scope and ownership

Implemented only the new `interactive_wake_field.gd`, `interactive_wake_field_rd.gd`, `interactive_wake_height.glsl`, `interactive_wake_foam.glsl`, independent CPU reference, focused tests and numerical GPU QA driver. No ocean material, old wake-flow, producer, lab demo or production caller changed by this worker. No commit/reset/cleanup.

Sources: [research report](../../../../docs/research/wake-flow-online-research-2026-10-14.md), especially its fixed Crest source URLs, distinction between Crest 4/5, and Atlas prototype boundary. Equations are an independent implementation of damped wave propagation, semi-Lagrangian scalar transport, diffusion and exponential decay. The signed Gaussian interaction kernel is independently authored rather than a copy of Crest's SDF/nested-sphere falloff. No Crest substantial code or commercial assets copied; original `wake3unique` DDS bytes use the existing project resource route.

## Implemented numerical model

- Defaults: 256² cells across 96 m; dx=0.375 m; 60 Hz fixed step; c=1.2 m/s; |h|≤0.25 m; |v|≤2 m/s. Courant capped at0.7; scalar diffusion capped at0.24*dx²/dt.
- Height state: RG32F h and vertical velocity. Four-neighbor Laplacian, exponential damping0.35/s, signed force into velocity, absorbing12-cell boundary with4/s edge damping. Two state textures ping-pong.
- Force: radius-normalized Gaussian dipole, horizontal factor0.30/s and vertical factor0.45/s, weighted by producer wetness and emitter weight. Vertical kernel has positive core/negative outer ring; horizontal kernel pushes/pulls opposite sides. These coefficients are declared artistic choices, not full hull hydrodynamics.
- Foam state, current candidate: RGBA32F `(density,localVX,localVZ,0)`. Semi-Lagrangian history advection uses uniform ambient flow plus the persistent local world-XZ drift. Density diffusion0.04m²/s, decay0.214/s, clamped0..1. Low activity source `0.08*abs(vertical_velocity)*length(slope)` remains a proxy, not a Jacobian calculation.
- Fresh foam: original DDS alpha with U across water and V behind stern. Keeps both native U peaks and empty center. Source span1.8beam; lateral half-width0.75beam+0.18aft; source disappears outside this short footprint. `foam_source_rate=2.5` multiplies the former source to target more readable density under root's grain shading. No central propeller plume.
- Persistent drift: `foam_drift_speed=0.5m/s` points outward on each birth side in world space; `foam_drift_decay=0.18/s`; drift smoothing0.08m²/s. At birth the velocity support is wider than the narrow alpha ridges so transport can leave the source pixels. Existing density mixes with new birth direction by fresh-density fraction; only nearly empty source-support water gets broader velocity seeding. Once the source leaves, stored vectors do not reference current ship heading. Positive divergence dilutes density; compression alone does not create foam. Drift is finite-clamped and bounded before dispatch.
- Output RGBA32F: h,dh/dx,dh/dz,foam. Output slopes derive from the same updated height field. Two output textures separate simulation writes from the currently published surface.
- Static optional mask: `{resolution:int,bounds:Vector4(xmin,zmin,xmax,zmax),data:PackedByteArray R8}`. Nearest sampling, >127 wet, outside mask domain wet. Dry cells and dry neighbor reads are zero for height/velocity/foam; output normal slopes in dry cells also zero. Without a mask, `land_masked=false` explicitly.

This is **height + vertical velocity + foam with an artistic persistent drift**, not Navier–Stokes or a horizontal momentum/pressure solver. The initial scalar-only candidate had just uniform ambient transport and diffusion; it failed the real-ship view because old lobes did not visibly continue separating. The current extra vectors belong to visual foam transport and do not drive hull physics or the height solver. Their adequacy for turns, long trails and multiple ships remains a GPU visual question.

## Clock, resources and QA

- Accepted time belongs to the caller. First timestamp initializes; duplicate timestamp does not inject/age. No-step/no-remap requests reuse the exact output bytes. A shifted window at the same time remaps history only.
- Window origin is texel-aligned; history samples world positions from the prior window. Rewind or >half-extent window teleport clears history.
- Maximum8 catchup steps per submission. `dropped_steps` records missing simulation steps; `queue_coalesced` separately records replaced pending requests. Controlled numerical GPU runs require zero dropped steps.
- `time` is the accepted timestamp of the published receipt; `tick` is simulation steps since last reset; `total_steps` is cumulative executed steps over the backend lifetime.
- At most16 nearest emitters and4 nearest fresh-wake sources. Inputs copied and validated atomically before render-thread dispatch. At most one dispatch plus one latest pending request.
- Sorting uses strict squared distance, with id only for exactly equal distance. Pairwise approximate-equality comparison was rejected because it is non-transitive and changed the selected16th emitter with input permutation.
- Supported clock range is |seconds|≤1e12, step is1/240..1/15s. Both facade validation and backend planner reject values beyond that envelope without mutating state, before a floating count can overflow int64.
- All GPU allocation, compute encoding and freeing use the global RenderingDevice on the render thread. No local device, submit(), sync(), synchronous production texture download, or main-thread texture get_image(). Original DDS is decoded from CPU source bytes.
- Explicit QA readback uses `texture_get_data_async`, at most one active readback. Callback thread is not assumed: resource lifetime completion is requeued to the render thread. Dispose defers freeing while a readback is outstanding and returns a stale-data error; queued init/dispose is handled.
- Raw shader source is compiled through RDShaderSource, so a missing `.glsl` importer cache does not silently prevent the field compiling.

### Surface publication contract after review

The original single mutable Texture2DRD wrapper was insufficient: changing its RID could reach a consumer before the corresponding bounds update. That implementation is superseded.

Each of the two output slots now owns a fixed Texture2DRD wrapper whose RID does not change during its resource lifetime. `acquire_surface()` returns one `{texture,bounds,generation,time}` receipt, or `{}` before readiness/after disposal. Consumer calls its ocean binder with that pair and, **only after successful binding**, calls `acknowledge_surface(generation)`. The backend cannot reuse the former displayed slot or dispatch its next queued request before that acknowledgement. Stale/duplicate ACK is a no-op. Initialization's flat zero surface also requires acquire/bind/ACK.

`pending` describes render work in flight. `awaiting_ack` describes a ready receipt held for a consumer; `queued` describes the one latest replacement request. Waiting for all forms of pending to clear before acquiring would deadlock, so the numerical driver explicitly acquires/ACKs whenever a receipt is ready. A missing/failed consumer keeps source fallback and bounds GPU work. `time` belongs to the available surface receipt; it does not assert that an arbitrary consumer has drawn that receipt. Consumers retain their bound generation separately.

Dispose clears outstanding leases/queues and both wrapper bindings, invalidates stale owner callbacks, schedules render-thread freeing, and receives a cleanup acknowledgement with resource_count=0. `cleanup_pending` distinguishes requested cleanup from confirmed cleanup.

## RED / GREEN and GPU evidence

| Evidence | Result and scope |
| --- | --- |
| `Temp/research/interactive-field-red-owner.json` | Meaningful RED: missing new owner;1 assertion/1 failure |
| `Temp/research/interactive-field-red-numerics.json` | Meaningful RED: no numerical update; hand-derived impulse/diffusion expectations fail;5 assertions/5 failures |
| `Temp/research/interactive-field-green-1.json` | Failed compile due inferred Variant types. Test stdout alone said pass, but strict runner correctly rejected parse errors. Retained; not GREEN |
| `Temp/research/interactive-field-green-2.json` | Focused initial owner/reference tests pass |
| `Temp/research/interactive-field-headless-clock-green.json` | Input copying/selection, finite validation, clock/remap/rewind/catchup, DDS CPU decode tests pass |
| `Temp/research/interactive-field-mask-red.json` | Meaningful RED: malformed static mask was ignored;24 assertions/1 failure |
| `Temp/research/interactive-field-mask-green.json` |24 assertions/0 failures, strict runner passes |
| `docs/research/evidence/wake-flow/interactive-field-gpu-1/GPU_VERIFY.json` | Root real GPU run;7 receipts. Duplicate-time byte mismatch is the only failure. Float comparison found all four channels exactly equal, but +/-zero bit changes remained. Retained failed baseline |
| `docs/research/evidence/wake-flow/interactive-field-gpu-2/GPU_VERIFY.json` | Root real GPU run;8 receipts, valid=true, failures=[]; raw process log `Temp/interactive-field-gpu-2-run.json` |
| `Temp/research/interactive-field-publication-red.json` | Missing consumer lease API and huge finite timestamp accepted;26 assertions/2 failures |
| `Temp/research/interactive-field-publication-green-2.json` |29 assertions/0 failures, including epoch, supported clock envelope and lease API boundary |
| `docs/research/evidence/wake-flow/interactive-field-gpu-3/GPU_VERIFY.json` | Root real GPU, Intel Arc130T16GB / Forward+;8 receipts plus publication_checks, valid=true, failures=[]; raw process log `Temp/interactive-field-gpu-3-run.json` |
| `Temp/research/interactive-field-selection-red.json` | Review reproduction:6 near-distance input permutations;35 assertions/4 failures |
| `Temp/research/interactive-field-selection-green.json` | Strict-distance comparator repair;35 assertions/0 failures; this is the final worker source freeze |
| `docs/research/evidence/wake-flow/interactive-lab-1/cruise/t0256.png` | Root actual ship GPU capture, personally inspected: correct twin structure but thin, faint and almost parallel; max|height|.0595m and max foam.2327 reported by root. Rejected for production despite valid capture metadata |
| `Temp/research/interactive-field-drift-red.json` | CPU reference cannot move stored twin density after sources stop;38 assertions/1 failure |
| `Temp/research/interactive-field-drift-green-2.json` |38 assertions/0 failures after persistent world drift, outward centroid movement and continued decay; latest numerical-driver parse check exit0 |
| `docs/research/evidence/wake-flow/interactive-field-gpu-4/GPU_VERIFY.json` | Root real GPU;9 receipts, valid=true, failures=[]; raw process log `Temp/interactive-field-gpu-4-run.json`; includes measured persistent drift centroids |

GPU QA explicitly checks the source-center impulse `h=0.000125m` from a hand calculation; signed outer ring; exact duplicate bytes; one-cell origin remap without world drift; continued unforced propagation; rewind reset; both original-mask foam lobes with subordinate center; stopped foam decay; dry-mask zeroes and wet domain exterior; pending readback disposal and queued initialization disposal. Raw RGBA32F, EXR and exact source hashes are saved. Those are numerical and lifetime checks, not proof of normal sea appearance.

GPU3 additionally holds the initial receipt unacknowledged while submitting24 requests: the field remains at time0/generation1, no render job runs, only the latest request is queued (`queue_coalesced=23`). Stale ACK does not release it; current ACK publishes the next slot; the old wrapper RID remains unchanged. Repeated ACK and render-thread cleanup also pass. The probe uses64²/24m, matching the default0.375m cell size; it is not the default256² coverage/performance measurement. GPU3 hashes precede the final CPU-only strict comparator repair; subsequent live-scene evidence must record the final source hashes.

GPU4 directly measures the added **foam drift**, independently of any assertion about height-wave shape. In its controlled source fixture, left/right density centroids start at(-2.250333,+2.352811)m;1s after removing sources they reach(-2.671090,+2.772517)m, about0.420m outward each. After another1s with a distant source turned90°, the old region reaches(-3.024210,+3.124898)m, another0.353m outward each. Old-region density sums decrease63.36692→50.39129→40.27647. These values prove retained world drift and dissipating old foam in this numerical fixture; they do not prove the real ship's wake is visually accepted.

Run driver on an actual renderer, root serially:

```text
rtk proxy <Godot> --path C:/Users/dains/Documents/Git/ming-armada --script res://tools/verify-interactive-wake-field-gpu.gd -- --output=<new-directory>
```

Current drift-candidate driver completion marker expects `INTERACTIVE_WAKE_GPU receipts=9 failures=0`. It additionally measures left/right density centroids: after1s with no sources each must move outward>.15m; after a distant orthogonal new wake source the old world-region centroids must continue outward>.10m and old density mass must decrease. The driver first acquires/ACKs a ready receipt, then waits for `ready && !pending && receipt time==accepted time`, not merely successful submission. It refuses an existing output directory.

## Open integration review

1. **Publication pairing:** fixed-slot receipt + consumer ACK supersedes the identified mutable-wrapper race; numerical publication probe passes. Every actual consumer still must use the receipt and ACK only after its own texture/bounds bind succeeds. Merely polling legacy surface_texture()/surface_bounds() separately does not acknowledge consumption.
2. GPU field is not yet measured with all real ship inputs in normal sea rendering. Proper dual-sided long-wake appearance, temporal motion, multiple hull scales, turn/stop/heave and shoreline use remain root acceptance work.
3. Producer and ocean integration must provide the mask, update bounds consistently and keep original fallback while unavailable. A visual depth gate is not a replacement for propagation masking.
4. Full-project suite and actual-game performance belong to root integration. This worker has not run a whole-game benchmark or claimed60FPS.

## Production-reusable system owner (subsequent authorized task)

Added `modules/scene_engine/water/interactive_wake_system.gd` and `tests/test_interactive_wake_system.gd`. This prepares the reusable owner without changing NavalWorldView, world_view, the ocean shader, crew, buoyancy, source history or any production caller.

- API: `configure(ocean,water,wet_mask,options={})`, `apply_snapshot(seconds,focus_id,actors,epoch)`, `poll()`, `covered_actor_ids()`, `set_ocean(new_ocean,wet_mask)`, `diagnostics()`, idempotent `dispose()`.
- Options accept direct field options or a `field_options` dictionary. `field_factory:Callable` provides the explicit dependency seam used by headless tests. The producer is the real `ship_water_interaction` in those tests; only field completion and ocean binding are controlled doubles.
- Selection prioritizes focus, then strict distance from the focus's actual world hull origin (or last field center if focus is missing), then id. Maximum3 complete actors gives15 probes; no individual probe truncation. Producer-derived real length/beam/probe positions determine coverage.
- Center is `stern - forward*(extent/2 - actual_length - 8m)`; with the96m field a20m hull fixture centers at stern minus20m, and a70m hull moves the center forward. Every one of five actual probes must remain inside the field after subtracting absorption width and its sphere radius. A120m fixture that cannot fit remains entirely on source fallback.
- `covered_actor_ids()` requires selection, matching completed input receipt, successful ocean texture/bounds bind and current-pose containment. Requested work is insufficient. The initial flat texture cannot consume the time0 actor record. A failed bind does not ACK or claim coverage.
- Repeated timestamps still process removal/dead hulls, current-pose coverage and ocean polling, but never resample forces or queue empty replacement inputs. Empty fleets and valid-but-uncovered inputs continue advancing old foam decay. Invalid input creates no invented force.
- Same-mask quality rebuild detaches the old ocean and binds the current lease to the new ocean without clearing field/producer history, including during pause. The already-bound generation's actor record is retained for this case. Mask identity includes actual resolution/bounds/R8 bytes; revision/cell_m metadata is stripped before field configuration. Explicit `valid:false` clears/disables the field and leaves source fallback.
- Epoch, rewind or selected producer warp/profile/time-gap reset clears the field and producer before a fresh first sample. Removal forgets producer history. Configuration failure disposes the failed field and prevents further submissions to it.
- Review found a second failure path: initial configuration could succeed, but epoch/rewind/warp recreation could fail synchronously and leave `_field=null`. Both reset sites now return safe `poll()` immediately after failed recreation, before any new producer sample/record or `advance()` call. The already-safe mask-rebuild path is included in the same regression matrix.

System RED/GREEN evidence:

| File under `Temp/research/` | Outcome |
| --- | --- |
| `interactive-system-red.json` | Missing reusable owner,1/1 failure |
| `interactive-system-red-lifecycle.json` |32 assertions,1 failure: paused quality rebind lost covered ids |
| `interactive-system-red-initial-publication.json` |34 assertions,2 failures: rebind plus initialization incorrectly consumed time0 input metadata |
| `interactive-system-uncovered-aging-red.json` | Test indentation parse error retained; not counted as behavioral RED |
| `interactive-system-uncovered-aging-red-2.json` |35 assertions,1 failure: valid but uncovered actor incorrectly froze old field time |
| `interactive-system-config-failure-red.json` |38 assertions,1 failure: failed field wasn't released before later input |
| `interactive-system-green-final.json` |38 assertions,0 failures |
| `interactive-system-component-regression.json` |6 scoped tests pass: capture guard, fallback, field, ocean, system, laboratory |
| `interactive-system-producer-regression.json` |Actual ship producer regression passes |
| `interactive-system-reset-failure-red.json` |Actual epoch/warp/rewind reconfiguration failures reproduce `Nil.advance`;56 assertions/6 failures, strict runner rejects the runtime errors |
| `interactive-system-reset-failure-green.json` |62 assertions/0 failures; successful-first/failed-rebuild cases cover epoch, warp, rewind and mask; old/rejected resources released, no coverage or new input records |
| `interactive-system-reset-component-green.json` |All6 scoped interactive-wake tests pass after the reset guards |

These tests verify coordinator phase/selection/lifecycle behavior with controlled GPU completion. They do not substitute for root's subsequent normal-scene GPU integration. The worker has not changed the production caller or independently run a GPU process.

### Independent read-only eligibility / coverage review

Reviewed T2's frozen `source_surface.gd` (SHA256 `a3425e3ce11268669a046189b65f7db924f44ef685790b478eed275e89e5bf9a`) and `source_wake_renderer.gd` (`5287d7c2f016e08ec8f8b71ff8721cdf8b31e6d4cde549832d887da8bcf93fb9`) against the retained baseline in `docs/research/evidence/wake-flow/2026-10-14-fallback-eligibility/`. Current files match the manifest hashes. No new blocker found in this scoped review.

Visibility now depends on current source submission eligibility AND absence of suppression. Empty indices and hide_unused remove eligibility, so retained mesh storage cannot revive itself when external coverage ends. The renderer combines external coverage with explicit flow suppression before duplicate-call return and again after fresh submissions. The gate addresses only SceneStrip/BattleDraw; local froth has its own Surface and retains its existing submit/hide_unused semantics. Transfer retains the actor/Surface eligibility state; route replacement creates fresh state. The battle oracle still emits21 draws, so no variable draw-count tail was introduced.

Read the root integration order: actual ship/crew poses update before source submission; world update precedes interactive-field polling/binding; covered ids are passed back after successful binding/ACK. Quality reconstruction calls set_ocean on the retained owner, with actual mask identity handled by the owner. No production files were edited by this review. Independent strict fallback test rerun: `Temp/research/visual-review-fallback-green.json`,39 assertions/0 failures. This is CPU/state review evidence, not GPU visual acceptance or an expansion of the deliberately unchanged payload/material validation policy.
