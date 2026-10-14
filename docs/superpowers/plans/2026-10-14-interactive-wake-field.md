# Interactive Wake Field Implementation Plan

> Use superpowers:subagent-driven-development for independent components, then root performs shared integration and serial GPU validation. Existing uncommitted work is retained; no commit, reset, cleanup or new checkout is authorized by this plan.

**Goal:** 在已有实验室实现并验证双侧船波、真实升沉交水、持久泡沫，再通过同一接口接入正常试航。
**Architecture:** 原五波海面保留，新增有界世界空间局部高度/竖直速度/泡沫场。真实船体点向场注入力；显示读取 delta-height、slope-X/Z 与 foam。先单向船→水，不改变操控或浮力采样。
**Tech Stack:** Godot 4.7.2 Forward+、RenderingDevice compute、GDScript、GLSL、现有原素材。
**Spec:** `docs/research/wake-flow-online-research-2026-10-14.md`，尤其 §8；用户已批准研究结论及独立实验→正式场景的步骤。

## Global Constraints

- 正确工程 `C:/Users/dains/Documents/Git/ming-armada`；RTK shell；CodeGraph 本session已回报未索引，继续精确RTK读取，不自行索引。
- 保留双侧主形、现有五组海浪、3D船员、0.6/0.55水岸羽化；中央单带 v1/v2 留作未采用历史，不能默认为新效果。
- 既有 source history/math/oracle 保留。实验、正式运行均只接受已有权威时间；暂停不推进，重复时间不累积；GPU全由root串行运行。
- 新代码独立进入现有 wake-flow 课题；不创建新首页示例，不改旅程，不读写用户存档。
- 数值测试/GPU画面/完整游戏性能分别报告。独立高度场不是精确全波长Kelvin求解；不直接把第三方GPU耗时当本机性能。
- 使用标准波动/平流公式的独立实现并引用来源；若直接移植Crest实质代码，附固定MIT版权许可。

## Shared Contract

`modules/scene_engine/water/interactive_wake_field.gd` is a RefCounted owner:

- `configure(options: Dictionary = {}) -> Dictionary`: default resolution=256, extent_m=96.0, fixed_step=1/60, wave_speed=1.2 m/s, height_limit=.25m. First tuning values are declared artistic/numerical choices. `configure` creates GPU resources asynchronously; expose pending/ready/error accurately.
- `advance(seconds: float, center: Vector2, emitters: Array, wakes: Array = []) -> Dictionary`: accepted seconds, world XZ center. Internally texel-align window, fixed-step accumulator, at most8 catchup steps per submission with explicit dropped-time diagnostic. Same time may remap a shifted window but must not age state or inject forces. Time rewind/teleport resets. Inputs are copied before render-thread dispatch; queue/ownership bounded.
- emitter dictionary: `position:Vector3` full world point, `velocity:Vector3` world m/s relative horizontal ambient flow, `radius:float` m, `wetness:float` [0,1], `weight:float`, `id:String`. At most16 near-view emitters initially; selection deterministic with explicit diagnostics.
- wake dictionary: `stern:Vector3` actual world waterline end, `forward:Vector2`, `beam:float` world metres, `speed:float` m/s, `wetness:float`, `id:String`. Used only for short dual-sided fresh-foam source/art direction, not a permanently attached full trail. At most4 sources initially; far ships retain legacy route.
- `surface_texture() -> Texture2D`: stable Texture2DRD, RGBA = delta height(m), dh/dx, dh/dz, foam [0,1]. Flat/zero outside field; sampling must gate bounds explicitly.
- `surface_bounds() -> Vector4`: world xmin,zmin,xmax,zmax matching the texture actually published, not a future enqueued origin.
- `diagnostics() -> Dictionary`: ready,pending,error,time,tick,resolution,extent_m,window_origin,steps,remaps,resets,emitter_count,texture/resource counts, dropped_steps. Main-thread snapshots must never race mutable backend dictionaries.
- `request_readback(callback: Callable) -> void`: explicit QA-only async raw data; no per-frame production GPU readback.
- `dispose() -> void`: idempotent, scheduled render-thread cleanup safe against stale queued calls.

Input producer `modules/scene_engine/water/ship_water_interaction.gd`:

- `sample(id:String, attachment:Dictionary, seconds:float, water:Callable, hull_alive:bool=true) -> Dictionary` returns `{emitters:Array,wake:Dictionary,diagnostics:Dictionary}`.
- Builds 3–5 actual hull-local waterline probes per actor, full `hullToWorld` positions; finite differences use accepted dt. No vertical rate from yaw-only history. Repeated seconds do not mutate previous positions; invalid packet atomic; rewind/large teleport zero derivative.
- Actual world beam and waterline length from profile/transform, no nominal 32×9 substitution. Submerged strength decreases to zero when probe sphere fully leaves water; scale/radius documented. Preserve gentle stationary heave response; speed0 suppresses long wake foam, not all local interaction.
- `forget(id)` and `clear()` bound actor lifetime.

GPU algorithm responsibilities:

1. Height/velocity fixed-grid ping-pong with four-neighbor Laplacian, dt-aware damping, conservative finite clamps/Courant bound, world remap and absorbing edges.
2. Force is signed horizontal/vertical interaction, not opacity. Foam has persistent transport, dt-aware decay and small separately documented diffusion. Fresh dual-lobe foam source uses original `wake3unique` as a shape mask; no middle propeller plume.
3. Main ocean samples the same field for vertex displacement, macro normal and foam; independent overlay mesh alone is insufficient. Dry-terrain visual gate remains; field-land propagation mask must be addressed before production coastal use.

## Review Focus

1. Render-thread lifecycle: destroy/reset while updates queued; no stale writes into freed RID or data races.
2. Translating world window: no history following camera/ship, no wrapping bright seam at bounds, repeated-time remap only.
3. Different ship model scales: physical probes and dual-arm spacing follow actual waterline, not nominal actor dimensions.
4. Stop and heave: no long wake at rest, old foam dissipates, stationary bobbing may still generate weak local rings.
5. Runtime acceptance: material rebuild/quality change, pause, removal, current original fallback, overlapping close ships and shore mask.

## Tasks

### T1 GPU field — voyage_visual
Files: new `interactive_wake_field.gd`, `interactive_wake_field_rd.gd`, `interactive_wake_height.glsl`, `interactive_wake_foam.glsl`, numerical CPU reference/test helpers scoped to this topic.
- [x] Write tests/probes for impulse propagation, bounded density decay, coordinate remap, pause/duplicate/rewind, resource ownership. Preserve RED.
- [x] Implement the shared interface and compile/parse checks; independent CPU numerical reference explains the compute math.
- [x] Deliver GPU validation driver using explicit readback and exact source hashes; root executes GPU. Do not touch ocean shader, lab host, producer, production callers or old trail code.

### T2 Real hull input — voyage_controls
Files: new `ship_water_interaction.gd`, `test_ship_water_interaction.gd`, fixtures/tools if necessary. Shadow candidate remains parked until its own GPU acceptance.
- [x] RED: unchanged XY with rising Y must emit finite vertical velocity; fully dry must have0wetness; zero speed but bobbing can remain active; 4 actual ship models world units.
- [x] Implement actual probes and short double-arm source metadata via shared contract; no own clock and no GPU.
- [x] GREEN + packet lifecycle/teleport/repeated-time tests; document exact coefficients and inputs, no visual success claims.

### T3 Existing laboratory — voyage_story
Files: `wake_flow_experiment.gd`, its tests and new GPU harness; avoid root's shared ocean/catal​og edits.
- [x] Keep current original source baseline and archived v2 distinguished. Add a new explicit `field_enabled` experimental factor; default source baseline until GPU accepted.
- [x] Wrap/reuse existing real Ship/Crew/Ocean/SailingRuntime; invoke producer then field after accepted poses; disable original tail only when valid field candidate is actually ready. Local contact froth remains a separate visible factor.
- [x] Add field/force/foam diagnostic views, clear field reset, pause+single-step, straight/turn/stop/reentry/small-vessel; failure cannot silently look like success.
- [x] GPU harness saves consecutive frame/time/field receipt, controls/ship/camera hashes; independent water quality/performance labels. No GPU run by workers.

### T4 Root shared render + acceptance
- [x] Add optional field texture/bounds to projected ocean and shader, default off. Height/slope/foam must change the actual sea; keep old five waves and shore logic intact.
- [x] Run CPU tests and GPU numerical readback; inspect real field debug and normal modes. Test same input A/B, up/down, start/stop, both turn directions, zoom/orbit and multiple vessel scales.
- [x] If the local solver does not yield clear double arms, use a documented historical wave/shape source, not a central white trail; retain unsuccessful candidates.
- [x] Connect only validated candidate through normal rendering owner, with old route fallback and lifecycle/terrain gates. Independent review of a scoped diff before claiming integration.
- [x] Update bundled paper, sources, images/manifest and laboratory status. Actual game acceptance separate from isolated demo. No claim of 60FPS without a live measured run.

## Execution Ledger

- User approved the researched combination; no repeated approval for routine implementation choices. Existing checkout is kept because it contains the user's current work and live editor. All edits have explicit file owners.
- New local field 96m/256 gives0.375m cells as a compromise to cover roughly50m of recent trail plus the hull. This differs from the research note's64m first suggestion; coverage will be measured and tuned, not marketed as infinite or exact.
- Production tail remains source baseline until the independent new field passes visual and lifecycle checks.

### Checkpoint while explaining the research method

- Independent new-field GPU numerical runs3/4 passed, and 10 frozen real-ship lab scenarios in `docs/research/evidence/wake-flow/interactive-lab-2` passed capture/readback checks. Visual review accepted this as a better directional candidate, not final production acceptance.
- Reusable system and cached terrain mask are implemented; normal scene hooks exist but `interactive_wake` defaults false until production GPU and fallback review close. The production GPU driver is saved and check-only passed; it has not run.
- Independent review found a required fix: `SourceSurface.submit` can keep an old mesh when a later source submission has empty indices. `set_external_water_coverage([])` must not restore visibility from that cached mesh. Preserve current source eligibility before applying field coverage; reproduce with `Temp/research/probe-fallback-stale-geometry-review.gd` / `t2-fallback-stale-geometry-review.json`.
- T3 is fixing camera duplicate submissions and adopting the production projected ocean for the wake experiment. Wait for its freeze, rerun paired source/field GPU, then continue normal-scene acceptance. Old finite384m plane side-view evidence remains labeled as such.
- User now requests a detailed explanation of the scientific research attitude and step-by-step method for guiding other models. Do not claim the unfinished integration complete.


### Final integration after the method discussion — 2026-10-14

This supersedes the earlier checkpoint; its default-off and pending items describe the historical state only.

- SourceSurface fallback eligibility repaired (39/0; independent review), system reset failure guarded (62/0). Cached source geometry cannot become visible just because external coverage ends.
- The lab now uses the same projected ocean as production. `interactive-lab-3/PAIR_VERIFY.json` proves 97 source/field frames with identical ship, camera and accepted time; finite-plane horizon artifacts remain only in archived lab-2 evidence.
- Actual free-sail source, candidate and default paths each passed six GPU keyframes: initial, cruise, longer cruise, mouse turn, stopped decay, paused quality rebuild. The default path has no candidate opt-in; original five ocean waves and 3D crew remain.
- `NavalWorldView` now enables the new field by default. A maximum of three complete nearby ships receives the field; unsupported/far ships retain source history. Terrain masking is conservative at the existing sampled resolution, not a fine shoreline collision solver.
- The runtime does not synchronously read back GPU state. QA deliberately waits for accepted-time results and does not establish live game FPS.
- Source and unsuccessful candidates, formulas/units, reproducible checks, limits and current integration are recorded in `assets/research/papers/wake-flow.md`; the catalog status is integrated. Historical v1/v2 remain archived in `docs/research/wake-flow-history-v1-v2-2026-10-14.md`.
- Separate shadow defect: isolated directed-boundary repair removed the long line (ROI 158→0 dark pixels). The generic target adapter now also passed production GPU (far0, near22); no caster-ID filter or original Math/RD change. Evidence: `docs/research/evidence/shadow-edges/DIRECTED_BOUNDARY_GPU_COMPARE.json`. Final independent review and combined normal-game capture are tracked in their own report.

- Final combined default GPU run also passed: `interactive-production-1/final/GPU_VERIFY.json` has six frames, player bound, zero dropped steps, no caster errors, and same-mask quality preserves1800steps. Root inspected cruise/turn/stop original PNGs: two wake arms remain and the long black line is absent. Independent shadow review found no blocker; 57 boundary +546 prepared-shadow checks passed.
