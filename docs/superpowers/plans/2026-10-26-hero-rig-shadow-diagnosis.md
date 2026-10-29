# Hero rig shadow diagnosis implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Distinguish native-map, stencil and small-caster causes before changing the ship's appearance.

**Architecture:** Research-only reversible factor controller, integrated into the existing registered HeroDemo; existing formal-light capture tool records actual state in an isolated World3D.

**Tech Stack:** Godot 4.7 GDScript, existing Python process wrapper, real Forward+ GPU.

**Spec:** `docs/production/hero-fuchuan-2026-10-26-art/R8-RIG-DIAGNOSTIC.md`

## Global Constraints

Use rtk; preserve dirty work and all failed evidence. Existing working tree/native execution authorized; no new commit/push. Production provider/assets/settings unchanged. No disabling shadows as final fix. Existing hero-fuchuan topic/demo only. Record independent/static/native/performance boundaries accurately.

## Review Focus

- Switching factors must restore baseline rather than combine changes.
- Stencil disabled must preserve initialized success and original native caster state.
- All original cast enumerations, not only ON, survive baseline/disposal.
- Invalid factor or absent compositor rejects without disturbing current factor.
- Reset/dispose must remove retained references and restore light/effect before freeing.

### Task 1: Reversible factor controller and lab access

**Files:** Create `game/research/fixtures/hero_rig_shadow_probe.gd`; create `tests/test_hero_rig_shadow_probe.gd`; modify `game/research/demos/hero_fuchuan_experiment.gd`.

**Interfaces:** `configure(actor:Node3D,sun:DirectionalLight3D,effect:CompositorEffect=null)->Dictionary`; `apply(mode:String)->Dictionary`; `inspection()->Dictionary`; `dispose()->void`. Modes baseline/native_off/stencil_off/rig_cast_off/sail_cast_off. Configure only after template handoff is initialized. The fixture owns no actor/time/storage.

- [ ] Write guard-first real-node tests: missing controller RED; then mutually exclusive factors, invalid no mutation, exact enum restoration, resource/pose preservation and disposal. Run `rtk proxy node tools/verify-godot.mjs --filter test_hero_rig_shadow_probe --output Temp/hero-fuchuan/rig-probe-red-01.json`; Expected intentional failed check, exit1.
- [ ] Implement controller and existing Demo `rig_probe` control, defaultbaseline; stencil-off rejects native mode. Run same test to fresh green report; Expected 0 failures/exit0. Add actual Demo integration/pause/reset checks to the same test if needed.

### Task 2: Fresh formal-light diagnostic captures

**Files:** Modify `tools/research/compare-hero-formal-light.gd`, `tools/research/run-hero-formal-light.py`; append existing paper and result record.

**Consumes:** Demo `set_parameter('rig_probe',mode)` and inspection receipt from Task1.

- [ ] Add exclusive `--rig-study`, same five factors in formal/reverse camera, expected11captures. Record actual sun/effect/caster/state, assert mode readback and complete actor/model/material invariant; no other light/AA factors.
- [ ] Run real GPU wrapper to fresh `docs/research/evidence/hero-fuchuan/rig-frequency-20261026/study-01`; Expected exit0/noERROR/unique marker/11captures and preserved sources/storage. If failure preserve it and repair only diagnosed harness defect.
- [ ] Inspect all five front/reverse pairs, classify each symptom independently, write findings/next smallest verified action. If no causal solution yet, leave production unchanged and goal active.
- [ ] One independent review of research changes and evidence claims. Appropriate targeted tests and source integrity checks; no full305-test run for this research-only reversible diagnostic. This proportional verification follows developer direction; known strict2timeouts remain open.

Pre-flight: Task2 consumes Task1's factor names/readback, fixed above. Ruling: user continuation preserves current checkout and opts out of repeated design/permission questions; choose inline execution. Research-only changes do not warrant worktree separation or production integration. No commit step until user asks again. Cost if wrong: diagnostic could mislead subsequent art work, controlled by actual-state assertions and review.

### Task 3: Evidence-driven filter and proxy followups

**Files:** same fixture/demo/capture tool and dedicated new evidence; existing topic paper.

- [x] H5 filter-only study, predeclared then real GPU59/0. All four candidates artist-rejected; no production integration. Mode readback limitation explicit.
- [x] Add proxy-input modes with failing behavior first: proxyRED30/4, firstGREEN exposed missing-meta ERROR, thenGREEN32/0; no original resources modified; repeated apply must reuse derived Mesh.
- [ ] H6 capture13frames with six independently declared factors, verify native states/caster count/actualproxyIDs/callbacks/AA, inspect raw pairs and record remaining ambiguity.
- [ ] One fresh final review covering all new research changes and claims; directed lab/hero regressions, preserve old strict full-suite timeouts. Leave production unchanged unless a separately validated actual fix exists.

Ruling: first CPU sampling suggested21mm hull difference, exact shared-triangle extrema found34.455mm beforeGPU; choose35mm diagnostic before run, retain checked CPUreport. Cost if wrong: displaced proxy could hide a silhouette issue; explicitly not an accepted geometric repair, only a path diagnostic.
