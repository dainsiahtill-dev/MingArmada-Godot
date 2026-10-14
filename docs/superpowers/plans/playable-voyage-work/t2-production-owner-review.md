# T2 read-only production wake-owner review

2026-10-14. Reviewed `NavalWorldView` → `InteractiveWakeSystem` → Field publication/ACK and `Wakes` → `SourceWakeRenderer` coverage. No production code changed and no GPU process launched by this reviewer. Root has now changed `interactive_wake` to default **false** pending production acceptance.

## Confirmed blocker

**P1 — empty current geometry can resurrect stale source tails.** `SourceSurface.submit` sets `node.visible=false` and returns when the current index array is empty; it intentionally retains the preceding `ArrayMesh`. `SourceWakeRenderer.set_external_water_coverage` tests that retained mesh's index count, then sets visibility true for an uncovered actor. A sea-clipped current submission can therefore show its previous geometry, including across dry terrain. This also affects an empty coverage list while the new field is unavailable.

Actual headless reproduction using the production SourceRenderer and battle path:

1. Wet source submission: 21 visible `BattleDraw_*` layers.
2. Next submission with `sea=false`: 0 visible layers.
3. `set_external_water_coverage([])`: **21 layers wrongly reappear**.

Follow-up: the scoped [source eligibility fix](t2-fallback-eligibility-report.md) now passes39/0 after the preserved39/13 RED, with18 related regression files passing. This resolves the reproduced CPU visibility contract; it does not complete formal GPU acceptance.

Driver: `Temp/research/probe-fallback-stale-geometry-review.gd`. Receipt: `Temp/research/t2-fallback-stale-geometry-review.json`. Root acknowledged the finding; fix and formal regression remain with root. Preserve current-submission eligibility separately, then combine it with external coverage. Cached GPU geometry is not a current-frame eligibility receipt. Include SceneStrip in the review because its surface uses the same empty-index early return.

## Checked integration

- Root only asks World for the integer mask revision on ordinary snapshots. Complete copied mask data is acquired on initial configuration or revision/ocean identity changes. No new terrain query or GPU readback was introduced by this caller.
- System strips revision/cell metadata before field configuration, hashes normalized bytes/bounds, and preserves the field on a quality rebuild with the same actual mask. Changed or explicitly invalid mask unbinds/disposes prior field and releases coverage. Empty mask remains explicit all-wet input from World.
- Selection keeps at most three complete five-probe actors: at most15 emitters, at most3 short-wake sources. This stays below Field's16/4 individual budgets. The safe interior includes each probe radius plus edge margin; actors outside it retain fallback.
- Time0 initialization does not cover actors just because the initial zero texture has published. Coverage requires a processed request whose accepted time maps to selected IDs, successful texture/bounds binding, and current actor fit. The consumer ACK occurs after binding. Skipped queued records remain bounded.
- Same-time snapshots do not replace queued forces with empty producer duplicates. Removal is handled before the duplicate-time return. An empty live fleet at an advancing time continues field aging without inventing emitters. Epoch change, rewind and sampled warp clear history.
- Quality rebind preserves the bound generation's actor record. Dispose unbinds before disposing Field, clears selection/history, and is idempotent.

Independent strict runner: `Temp/research/t2-owner-review-green.json` — **38 assertions / 0 failures**, one selected test, clean strict runner.

Additional actual integration probe: `Temp/research/probe-production-water-owner-review.gd`; receipt `Temp/research/t2-production-water-owner-review.json` — **9 / 0**. Uses actual MingqiRuntime, HeightField, NavalWorldView, World, ShipView, interaction producer, ProjectedOcean and SourceRenderer, with only the GPU Field replaced by the existing test double and a valid4×4 ImageTexture. Explicitly enables the otherwise-off candidate. Covers first submission, binding/coverage, paused duplicate, quality revision and same-mask rebind, paused removal, same-time environment epoch, and repeated disposal. It does **not** prove GPU scheduling or visual output.

Reviewed hashes: `Temp/research/t2-production-owner-reviewed-hashes.json`. System SHA256 at review: `03c2ee03e376eb338353a9bd5ae39a3ec0ec9690f731d5c5c3fd1d25125735b4`.

## Remaining limits

The independent review found one additional narrow defensive gap and sent it to T1: `apply_snapshot` checks `_field==null` before epoch/warp reset, but a synchronous configuration failure during the reset can clear `_field` before the later unconditional `advance`. Initial configuration failure is tested; reset failure needs its own guard/test. No production GPU failure was observed and this is separate from the reproduced fallback blocker.

Root still owns formal GPU visual, coastal-mask, multi-ship, delayed publication, performance and shutdown acceptance. T3's duplicate-input/projected-carrier fixes remain a separate frozen-source review. No statement here marks formal integration complete.
