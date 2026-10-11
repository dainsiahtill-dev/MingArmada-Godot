# Career startup scene boundary

`MingqiScene` accepts the same startup-facing properties as `LegacyScene`:

- `startup_options: Dictionary`: optional `seed`, `captainName`, `campaignId`, `staged` (boolean).
- `initial_save: String`: confirmed v2 save bytes for ordinary continue.
- `startup_receipt: Dictionary`: available after the scene's `ready` signal; `ok: true` means runtime, world, interface and both charts are ready. A rejected startup returns `ok: false` and a reason.
- Existing `storage` and `settings_storage` remain injectable before mounting.

New games create `Campaign.new(seed, captain_name, campaign_id)` and configure the actual runtime with the actual height sampler. Omitted options retain native campaign defaults: seed `1650`, captain `林船长`, identity `mingqi-1650`. Explicit seeds must be native integer uint32 values, including zero. Names must be native Strings, trim their edges, contain 1–24 Unicode scalar characters, and contain no ASCII controls or DEL. Invalid types, empty names, oversized names and campaign identities rejected by `Campaign` return `invalid-options` before creating sea or UI. Source UTF16 settings adaptation belongs to the router before this boundary.

Continue calls `runtime.adopt_save(initial_save, null, utc)`. It validates save structure and safe-port conditions, reconstructs the native simulation and its control policy, and retains the save's seed, captain, campaign identity and state. It does not write checkpoints or rotate backups. An injected storage write failure therefore cannot prevent ordinary continue. Explicit in-game import continues passing the injected storage to `adopt_save`; a failed write leaves active authority and disk bytes unchanged.

After a restore succeeds, the actual interface menu opens. Runtime retains `loading` and adds `menu` pause, so simulation remains frozen while the player reviews the restored game. Closing that actual menu removes `menu` and releases `loading`; independent reasons such as `player` remain. The successful receipt is published only after presentation is ready. Startup rejection never quits the application; the router can dispose the failed candidate and keep its current menu/game.

World, chart, minimap, capture, accepted-time physics, settings and water presentation retain their existing owners. Failed world or chart composition disposes partial presentation and publishes a failure reason.

Router candidates set `staged: true`. Once native startup succeeds, they hold a `loading` pause before their first presentation, including paused audio. Startup does not change the active Window title, global physics tick frequency or viewport MSAA. After its transactions commit, the owner calls `activate_entry()`, which applies the normal title, 60 Hz physics and 4× MSAA. Activation releases `loading` for a new game and retains `loading` plus the actual menu pause for restored games. Activation is idempotent and rejects unconfirmed/failed startup. Direct scene launches and source capture modes omit `staged` and activate automatically after successful startup.

## Focused verification

Godot `4.7.2.stable.official.ed1daf0bf`, headless, 2026-10-11:

- `tests/test_career_startup.gd`: `CAREER_STARTUP_TESTS assertions=53 failures=0`, exit 0. Covers invalid types/ranges/name/id, invalid save, real custom identity and seed, v2 checkpoint restore, unchanged checkpoint/backup bytes, storage write failure, transactional explicit import, real menu pause/release, native control policy after real convoy acceptance, staged zero-seed startup with unchanged globals and paused audio, new-game activation, and restore activation retaining menu/loading pause.
- `tests/test_mingqi_scene.gd`: `MINGQI_SCENE_TESTS assertions=17 failures=0`, exit 0. Retains actual model/crew, keyboard focus, minimap/full chart, pause, water/audio clock and settings checks.
- `tests/test_mingqi_runtime.gd`: `MINGQI_RUNTIME_TESTS assertions=12 failures=0`, exit 0.

All three runs had no Godot error/warning diagnostics. Test-first evidence: the startup suite failed against the original scene with `assertions=44 failures=35`, exit 1, including ignored startup identity, missing receipt, invalid options/save creating presentation, and restore missing menu/loading pause. The fixture subsequently added a real convoy acceptance before export to exercise leased native control authority. Staged activation tests then failed against the prior adapter with `assertions=53 failures=4`, exit 1: preparation changed global settings, new-game authority/audio was not paused, and activation was missing.

These checks do not establish GPU appearance, rendered capture quality or full-suite status.

## Legacy audit

The original `LegacyScene._ready()` passed `storage` into `runtime.adopt_save(initial_save, storage)` for ordinary continue. Root integration corrected this separately: `LegacyRuntime.adopt_save(raw, storage=null, persist=true)` retains the previous default for explicit import, while startup uses `adopt_save(initial_save, null, false)`. Passing only `null` would still fall back to the configured runtime storage, so the explicit read-only flag is necessary. `tests/test_legacy_startup.gd` exercises an actual rejecting storage adapter, zero startup writes, invalid-save rejection, menu/loading release and staged global settings: 11 assertions, zero failures. Legacy also defers shared settings until `activate_entry()`.
