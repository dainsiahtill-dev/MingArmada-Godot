# Native 1650 checkpoint UI verification

Scope: Task 9/10 scene composition only. Changes in `game/scenes/mingqi/mingqi_scene.gd`; new `tests/test_mingqi_scene_checkpoint.gd`. Runtime/domain/coordinator/interface/router unchanged by this work. Source webpage remains read-only. CodeGraph target was confirmed unindexed by root; discovery used RTK fallback, without indexing.

## Source contract

Frozen source `apps/game-client/src/components/adventure/MingqiScene.svelte` owns scene lifetime; storage menu/save orchestration is in `MingqiShell.svelte`. `MingqiStorage.ts` exposes `exportLastVerifiedCheckpoint()` from caller-validated bytes, with exact readback. First successful save establishes recovery. Continue establishes recovery only after exact read equality with validated original bytes, without writes. Raw recovery input is separate from a verified checkpoint. Failed save/import retains prior verified bytes. `MingqiShell.svelte` renders explicit persistent save/import/export results and permits retry.

Native scene previously omitted `runtime.hasCheckpoint` and `runtime.saveStatus` from the UI packet. Export backup directly read arbitrary `.backup` bytes; first successful save and ordinary continue did not establish the source recovery action. Successful export also left the interface pending command marker unchanged, causing the next actual export click to be swallowed.

## Change

Scene keeps only the latest checkpoint confirmed by the actual coordinator. Continue requires validated storage read equality to the original accepted save before establishing recovery. Mismatched/absent/corrupt disk never fabricates a recovery checkpoint; startup itself can still adopt the validated supplied save, as instructed by root. Save/import confirms the real committed disk result. Raw `.backup` bytes do not enable/export verified recovery. Failed writes/restores preserve the prior confirmed bytes. Runtime packet fields project this scene-owned storage fact and persistent user-readable result. Successful export notifies the runtime to settle the actual UI command marker.

No time or authority is advanced by export/continue; import still uses the existing transactional runtime/coordinator path. Main-menu navigation remains contingent on real save success.

## Evidence

All commands below use installed Godot `4.7.2.stable.official.ed1daf0bf`, `--headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/<file>` and begin with `rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`.

- Initial RED: `test_mingqi_scene_checkpoint.gd`, 16 assertions / 12 failures, exit 1. Missing recovery/status fields and latest verified recovery were observed before production edits. The first draft whole-campaign equality overasserted export synchronization; final tests assert actual captain/time/generation and exact checkpoint bytes instead.
- Real-control RED: actual recovery export button emitted only one intent for two clicks after successful export; 20 assertions / 1 failure, exit 1. Added success notification to release UI pending gate.
- Final GREEN: `test_mingqi_scene_checkpoint.gd`, 25 assertions / 0 failures, exit 0. Clean final output, no resource leak warnings.
- `test_save_coordinator.gd`: 12 assertions / 0 failures, exit 0.
- `test_save_compatibility.gd`: `save compatibility v2: PASS (0)`, exit 0.
- `test_mingqi_ui.gd`: 195 assertions / 0 failures, exit 0.
- `test_mingqi_chart.gd`: 25 assertions / 0 failures, exit 0.

The scene test uses real scene/runtime/coordinator/UI, real invalid JSON, real disk corruption, valid mismatched disk bytes, a regular file blocking the intended storage directory (actual Godot result `save-write-failed`), failed import commit, successful retry/import, first-save recovery and paused continue. Recovery checks exact latest confirmed bytes rather than a mock counter. Actual Save button drives first save and retry; repeated backup export clicks verify command settlement. Save-and-menu failure verifies no leave signal.

All scene settings/checkpoints are process-isolated under `user://tests/checkpoint-ui-<pid>/`; cleanup removes only owned fixture files. No default career/settings slot is touched. Existing `test_mingqi_scene.gd` uses default settings and was deliberately not run here; root owns safe full-suite integration. This report makes no visible/GPU/clipboard-platform/export-package claim. Headless tests verify the exact receipt handed to clipboard and real UI intent/status, while root owns actual rendered/player acceptance.
