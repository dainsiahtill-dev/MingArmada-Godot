# Cloud billboard reuse implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox syntax for tracking.

**Goal:** Reduce repeated pure billboard calculations without changing the ship, sea, islands, atmosphere output or source history.
**Architecture:** Freeze the current compiler as the independent baseline. A research subclass memoizes exact rotation bytes only within a single static minimum-state invocation; each published result owns its rotation array. Measure before integration.
**Tech Stack:** Godot 4.7.2, GDScript, Forward+, Windows/Intel Arc130T.
**Spec:** `docs/research/frame-budget-2026-10-26.md`, existing topic `architecture-convergence-2026-10-21`.

## Global constraints

- Continue in the existing `codex/godot-migration` working checkout, preserving its three prior diagnostic changes and local art resources. This is the user's authorized continuation after checkpoint 94003ac; no new commit/push is part of this plan.
- All shell commands use RTK. CodeGraph has no index; use focused source reads.
- Keep every cloud, vertex, minimum-Z calculation, controller, seed and time; no actor/quality reduction. No cross-frame memo, approximate equality, matrix reassociation or shared published arrays.
- The existing architecture topic/demo remains the home laboratory entry. Preserve its default physics workload and tests; add an optional cloud comparison only if the isolated candidate is worthwhile.
- Raw output/logs use fresh directories; failures remain. CPU timings do not prove full-game FPS. GPU and normal-entry evidence are separate gates.

## Review focus

- Same numeric rotation with different signed-zero bytes must not share a key.
- One result's writable rotation must not mutate another leaf or later call.
- Camera changes and alternating owners cannot reuse a previous call's value.
- Animated fog/weather must retain original controller call order and output.
- A candidate that reduces calls but costs more overall is rejected.

## Task 1: Independent candidate and CPU decision

**Files:** `game/research/fixtures/cloud_billboard_baseline.gd`, `game/research/demos/architecture_billboard_candidate.gd`, `tests/test_cloud_billboard_reuse.gd`, `tools/measure-cloud-billboard-reuse.gd`.
**Interfaces:** The existing `compile_asset`, `render_minimum_states`, `render_states`, `_billboard_mode0`, `_transform_transpose` and `controller_snapshot` signatures remain unchanged. Baseline is a byte-for-byte frozen compiler; candidate initially inherits unchanged so a real work-count test fails.

- [ ] Freeze baseline with source hash, create inheriting candidate stub, write tests comparing complete bytes for five assets/30 actual ring clones, varied cameras/rotations and ownership/lifecycle boundaries.
- [ ] Run RED: identical outputs but no work reduction; preserve process receipt.
- [ ] Implement invocation-scoped exact-byte memo in the research subclass. Match full key bytes, return detached arrays, clear scope on return. Run GREEN.
- [ ] Alternate 2 warmup pairs and 12 measured pairs of identical 30-clone input batches; preserve every sample, nearest-rank quantiles, hashes, work counts and full-state equivalence. Reject if candidate mean is not lower or outputs differ.

## Task 2: Visual proof and conditional integration

**Files:** existing architecture demo plus a small cloud-pair helper; existing topic paper; production compiler only after independent gates.
**Interfaces:** Preserve existing demo options by default. An optional cloud factor adds paired baseline/candidate atmosphere renderers consuming the same accepted source packet and camera; only selected branch is visible. Host remains sole clock owner.

- [ ] If Task 1 passes, add cloud factor to the registered architecture demo, test pause/camera/reset/rebuild/dispose and production state equality.
- [ ] Capture a real GPU continuous fixed-step baseline/candidate comparison, main and reflection views, with raw frames and state/time/hash receipts; inspect actual images.
- [ ] If CPU/state/GPU gates pass, integrate the exact candidate at production `render_minimum_states` only, then run related regression and normal game entry/frame intervals with unchanged actors and quality.
- [ ] Fresh independent review of final diff and evidence. Record actual results, failed attempts and limits; leave full game goal active.

No automatic commit or branch cleanup. If the candidate fails the cost gate, retain experiment and documented rejection, leaving production unchanged.
