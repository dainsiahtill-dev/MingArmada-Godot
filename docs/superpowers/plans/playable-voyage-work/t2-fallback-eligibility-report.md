# T2 source fallback eligibility fix

2026-10-14. This fixes the stale-mesh P1 established in [the independent production-owner review](t2-production-owner-review.md). It changes only `source_surface.gd`, `source_wake_renderer.gd`, and `test_interactive_wake_fallback.gd`, plus this report/evidence. No GPU execution, source-history/math changes, or NavalWorldView/World/Field/System edits.

## Hypothesis and preserved baseline

An empty current submission hides a node while retaining its previous ArrayMesh for reuse. The former external coverage setter inferred current visibility from that retained mesh, so releasing coverage revived a tail already clipped from dry terrain. Real battle reproduction was21 visible wet layers →0 after dry submission →21 after empty coverage. SceneStrip used the same surface cache.

Hypothesis fixed before implementation: preserve the current source submission's eligibility independently from external suppression. `visible = eligible && !suppressed`. An overlay can suppress source drawing but cannot grant eligibility to retained geometry. Repeated source calls do not change eligibility; a new nonempty submission can restore it.

The [evidence manifest](../../../research/evidence/wake-flow/2026-10-14-fallback-eligibility/manifest.json) includes complete baseline and candidate source/test snapshots, SHA256 hashes, the failing test receipt and all successful receipts. The exact same final test hash exists in both baseline and candidate: `89c16cda3f7d081f96a09e2f7f6863deb4ae65fa91b6a8806ee84e1b6c109237`.

## Minimal implementation

- SourceSurface records eligibility using its existing submission rule: nonempty indices. Empty indices revoke eligibility before its existing early return, while retaining the mesh. `hide_unused` also revokes eligibility. Disposal clears both eligibility and suppression dictionaries.
- `set_visibility_suppressed(key, bool)` applies an independent visibility gate. A later source submission cannot accidentally release active suppression. The default gate is false, preserving other SourceSurface callers' ordinary behavior.
- SourceWakeRenderer stores external coverage per existing actor. Its common tail gate combines that coverage with the existing explicit target-flow gate for SceneStrip; battle layers use external coverage alone. The gate is applied before duplicate-call early return and after fresh geometry submissions. No cached mesh/index inspection decides current eligibility.
- Actor creation/release owns the coverage flag with the actor; in-memory owner transfer retains that same actor state. Local froth remains outside this tail-only selector. The public `set_external_water_coverage(ids)` interface is unchanged.

## RED / GREEN and regression

`rtk proxy node tools/verify-godot.mjs --filter test_interactive_wake_fallback.gd --output Temp/research/t2-fallback-eligibility-red.json`

**RED39 assertions /13 failures**, with no parse/runtime error. Both real scene30 and battle90 source routes demonstrate dry cached-geometry resurrection. Additional failing cases expose duplicate-call/fresh-submit suppression loss, hide_unused resurrection, and same-call flow disable releasing coverage.

The same command against the candidate, with output `Temp/research/t2-fallback-eligibility-green.json`, gives **GREEN39 /0**, strict runner passed. Wet recovery, original history advancement and local froth retention also pass.

Related strict-runner regressions:

| Filter | Test files | Result | Evidence suffix |
|---|---:|---|---|
| `source_wake` |5|5 passed|`t2-fallback-source-wake-regression.json`|
| `source_froth` |6|6 passed|`t2-fallback-source-froth-regression.json`|
| `hull_contact` |4|4 passed|`t2-fallback-hull-contact-regression.json`|
| `wake_flow` |3|3 passed|`t2-fallback-wake-flow-regression.json`|

All18 related files pass; together with the targeted regression,19 test files pass. The strict runner checks exit status, a unique completion marker, assertion failures and Godot error output. No entire-repository suite or GPU performance/visual claim is made.

## Deliberate scope and limits

Material fallback and malformed payload handling are unchanged. A separate exploratory test found that current SourceSurface does not comprehensively reject nonfinite vertices, short attribute arrays or missing material textures; the strict exploratory run produced59 assertions /26 failures and expected Godot array errors. That source/test observation remains in `Temp/research/t2-fallback-invalid-submission-observation.gd` and `t2-fallback-invalid-submission-red.json`. Root explicitly narrowed this task to the current P1, so that exploratory group is excluded from the final test and no new shared-FX validation policy was introduced.

This is a CPU contract fix for source visibility ownership. Actual production coast frames, field coverage transitions and GPU submission performance remain root's separate acceptance. The formal interactive wake feature remains off by default until that acceptance.

Frozen candidate SHA256:

- SourceSurface: `a3425e3ce11268669a046189b65f7db924f44ef685790b478eed275e89e5bf9a`
- SourceWakeRenderer: `5287d7c2f016e08ec8f8b71ff8721cdf8b31e6d4cde549832d887da8bcf93fb9`

Independent read-only review by voyage_visual completed against these frozen hashes, with no new blocker. Reviewer independently reran the strict fallback regression39/0 (`Temp/research/visual-review-fallback-green.json`) and checked hide_unused, shared froth's unsuppressed default, flow/coverage composition, duplicate/fresh submissions, all21 battle layers and owner-transfer state. Reviewer made no source changes.
