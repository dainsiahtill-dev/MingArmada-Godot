# Legacy runtime and encounter authority

Implemented in the native product at `C:/Users/dains/Documents/Git/ming-armada`. Frozen web source remains read-only at HEAD `9ad6a44daecd4ec36a8172d83ff27493feffe5dd`.

## Authority boundary

`game/runtime/legacy_runtime.gd` owns one `AdventureSession`, one native `NavalEncounter` through the existing `SailingSimulation`, presentation events, accepted sea time, UI intent revision, replacement generation, independent pause reasons, surrender transaction and disk checkpoints. Existing shared/domain/physics modules are reused unchanged.

Every business mutation first runs on an isolated v1 Session clone. All owned, quest and ambient ship setups are validated before live native reconciliation. A failed business command or a failed native batch retains domain finances, fleet identities and native state. Source officer, cargo, morale and injury modifiers reach native stats. Sold vessels leave native state; settled/captured hostiles cannot reappear. Departures and result/import replacements invalidate old generations.

Sea selection follows actual frozen `AdventureRuntime`: initial hostile radius 350 m, ongoing radius 450 m, retaining live hostiles while projectiles or recent firing require them. The 600 m threat boundary belongs to naval policy rather than legacy source selection. Background routes, fleet formation, escort and rescue waypoints refresh at source 0.5 s intervals. Source 60 Hz sailing step and 0.1 s frame acceptance are retained. Domain clock advances only by actual native accepted time; domain sync precedes daily costs. Native event settlement is once-only, and new career settlement or day changes invalidate old UI revisions.

`game/runtime/legacy_encounter_coordinator.gd` owns the actual Duel, LandBattle, Treasure and Banquet models. UI may send actions, retreat, pause, settle or close; it cannot submit a result, score, success or reward. Settlement uses the owned model's terminal result and original context. Duel victory requires capture/plunder/release disposition. Banquet uses source 14-cue perfect-score normalization, source fee and three-day cooldown. Loser/retreat injuries come from native results. Practice uses the same models and changes no career state. Retry exists only for terminal practice games and generates a new request identity.

Sea pauses `panel` and `encounter` are independent from minigame time. A launching page remains open while its career model advances and accepts actions. External player/menu/tactical/blur/hidden/loading/error/result/surrender pauses still stop minigame time and action callbacks. Duel and banquet report actual accepted model seconds; turn-based land/treasure models have no time step and report zero accepted seconds. No global frame time enters the saved voyage during encounters.

`panel` suspends sea progression, held helm, sail/trim controls and native fire. Directed `navigate` and settings `begin-surrender` ignore only this page suspension; every other pause, real voyage state, battle context and token fence remains authoritative. This lets chart/quest waypoint commands install their native route before the scene closes the panel, and lets the settings surrender button start a real quote without unpausing the sea.

## Public packet and intents

`configure(height_sampler: Callable, options: Dictionary = {})` returns `{ok, reason?}`. Options support source `name` and `seed`, `initialDock` (defaults true), and runtime-owned `storage`. The Session receives no disk adapter: domain autosave cannot bypass runtime checkpoint gates or call the incompatible `write/read` interface on a `SaveCoordinator`.

Publicly readable `voyage`, `session` alias and `simulation` remain native authorities. Presentation uses `snapshot()`, a detached packet:

```text
{
  adventure: AdventureSession.snapshot(),
  naval: SailingSimulation.snapshot(),
  runtime: {
    generation, revision, paused, pauseReasons,
    handlingMode, handlingStatus, notice,
    canSave, saveReason, surrenderQuote, surrenderEligibility,
    pendingSurrenderReceipt, encounter, lastSaveReceipt
  }
}
```

An active `runtime.encounter` contains `id`, `generation`, `kind`, `targetId`, `practice`, `seed`, native difficulty `normal`, `context`, `state`, `model` alias, `identity`, owned terminal `result`, `settled`, `acceptedSeconds`, `paused` and settlement `receipt`. After actual settlement it also contains `settlement{mode,rawScore,score,paid,before,after}`. Banquet score is normalized from the real rhythm result; paid fee comes from the real business receipt. Before/after social state reads canonical silver, morale, fame, relations and the port faction relation, so UI does not invent rewards. Practice explicitly identifies its mode and reports identical career before/after. Kind values: `duel`, `landBattle`, `treasure`, `banquet`. Inactive encounter is null.

`command(intent)` validates optional `generation` and `expectedRevision`. Business intents retain source names. Runtime intents remain separate:

- `set-sails{value}`, `trim`, `set-handling-mode{mode}`, `pause{reason,value}`.
- `native-action{action}` permits source `controls`, `fire`, `select-ammo` on owned fleet vessels only. Native surrender is fenced.
- `navigate{point}` uses actual wet-route refusal and native authority.
- `begin-surrender`, `cancel-surrender{token}`, `confirm-surrender{token}`, `acknowledge-result` / `resume-voyage`.
- `start-encounter{kind,targetId,practice?}`, `encounter-action{id,action}`, `encounter-retreat{id}`, `encounter-settle{id,disposition?}`, `encounter-close{id}`, `encounter-pause{id,value}`, `encounter-retry{id}`.
- `save`, `export-save{kind:current|backup}`, `import-save{json}` delegate to runtime APIs. App navigation, file selection, restart/main menu and save-and-menu orchestration remain scene-owned.

`preview_command(intent)` / `preview(intent)` returns detached `{ok, reason?}` without changing live state or writing disk. Business preview uses the same isolated Session/native validation as commands. Native preview invokes actual native validation on an isolated snapshot-based encounter. UI controls can gate their current exact quantities and ship selections through this seam. `notify(message)` sets public runtime notice without altering business revision.

Other APIs: `set_held`, `set_sails`, `toggle_trim`, `set_handling_mode`, `set_pause`, `advance` (returns accepted sea seconds), `drain_events`, `drain_results`, `native_snapshot`, `render_snapshot`, `sample_water_height(x,z,seconds?)`, `export_save`, `export_last_verified_checkpoint`, `save_checkpoint(storage?)`, `adopt_save(raw,storage?)`, `dispose`.

## Persistence and surrender

Surrender freezes source token/battle/tick/loss digest and pause epoch. Confirmation re-quotes the real latest native state, stages source losses, validates home reconstruction, then asks native authority to accept the precise captor/battle/tick request. Only after native acceptance does the domain commit. Pending receipt blocks normal business commands until result acknowledgment. Cancellation removes its own pause while retaining unrelated pauses. Duplicate/stale confirmation cannot apply losses twice.

Default checkpoint path is independent `user://saves/legacy-v1.json`. Existing SaveCoordinator stages, verifies and atomically rotates the exact source serialized v1 JSON with `LegacyRuntime.validate_save`. Import validates the source codec, all native ship setups and candidate construction; disk persistence precedes adoption. Failure retains live generation/state. Raw v1 exceptional UTF16 strings use existing Text/JsonNumbers/Surrender codecs; Godot's lossy JSON decoder is never used for save validation or adoption. Rename encodes native UI strings through `Text.encode_native`; display decoding belongs to UI.

Save/export/import refuse active combat, pending cannon attacks, dead native/domain flagship, runtime error, surrender prompt or an open encounter. A pending surrender receipt is a valid v1 checkpoint. This intentionally retains the stronger native transaction boundary described in the migration spec.

## Verification

Godot `4.7.2.stable.official.ed1daf0bf`, headless only. Strict runner rejects engine diagnostics, timeout, wrong exit code and missing/duplicate/failing completion marker.

- `tests/test_legacy_runtime.gd`: **123 assertions, failures=0**.
- `tests/test_legacy_encounter_integration.gd`: **146 assertions, failures=0**.
- Frozen source exporter: **1 runtime scenario, 9 source business steps, 38 loaded modules, sourceWrites=0**.

Source oracle compares business receipts and canonical financial/quest/market/fleet/native setup projection including names, IDs, ownership, ammo and modifiers. It excludes pose, ship saved controls and battle UUIDs; exact physics trajectories and visual rendering remain covered by earlier native physics/naval work and root integration. Five additional career checkpoints are generated through the real source Session from the previously audited source reference and its actual sync operation; no source files are written.

Coverage includes dock/trade/officer setup, source refusals, detached read-only preview, stale revision/generation, held helm and manual navigation cancellation, pause/accepted clocks, actual native reconciliation failure from exhausted control sequence, sold/captured exclusion, actual native sink/victory event settlement and duplicated events, surrender token/tick/pause-epoch/result fences, actual disk path failure/adopt rollback, real configured SaveCoordinator ownership, exceptional UTF16 import, true four-game results and once-only rewards, three boarding dispositions, retreat crew loss, four practice games, retry and disposed callbacks.

Runtime/UI/scene composition, GPU rendering, exported executables and a whole-product regression suite are root-owned and were not claimed by this implementation report.
