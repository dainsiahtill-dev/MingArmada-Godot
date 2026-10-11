# Native entry router and v2 recovery

Task10 ownership: `game/runtime/game_router.gd`, `game/scenes/main/main_scene.gd/.tscn`, `game/ui/menu/save_recovery.gd`, `tests/test_game_router.gd`.

## Responsibilities and API

`GameRouter` is a detached `RefCounted` orchestration layer. Defaults use the actual `SaveCoordinator` at `user://saves/mingqi-v2.json` and `user://saves/legacy-v1.json`; the latter uses `LegacyRuntime.validate_save`. Settings use the actual `UserSettings` at its independent settings path.

- `_init(dependencies)` accepts `mingqi_storage`, `legacy_storage`, `settings_storage`, `entry_factory`, `dev`, and `qa` for integration and focused verification.
- `view_model()` returns detached settings, legacy save availability, v2 slot state, and developer gates to the presentation menu.
- `prepare_entry(request)` accepts the menu's generation/nonce intent, recognizes original modes and non-start retry targets, rejects duplicate/late tokens, and returns a token-stamped prepared record or recovery/error receipt.
- `prepare_recovery(intent)` handles retry, validated backup continuation, JSON import, and a filesystem JSON import. File import checks the 16 MiB bound before allocating the text.
- `is_current(prepared)` checks generation, nonce, and operation sequence. `cancel(next_generation)` invalidates pending scene and recovery work.
- `create_scene(prepared)` constructs the actual Mingqi/Legacy, duel/fleet/sail naval practice, ship book, and four-encounter practice scenes. It injects staged startup options, original continuation JSON, independent settings, and appropriate storage. An optional extra mode factory returns a `Node` or `{ok,scene,reason}`. A created scene must expose a final `startup_receipt` with `ok`; it may expose `main_menu_requested` and `activate_entry()`.
- `commit_import(prepared)` writes only an explicit import and only for a current operation. Repeated committed operations cannot rotate the slot again.
- `export_recovery()` returns originally read recovery text tagged `raw-recovery`. `export_backup()` validates the backup's v2 schema and native projection before identifying it as a verified checkpoint.

`MainScene` owns live nodes, deferred loading stages, menu/recovery/settings controls, and lifecycle fences. Stages describe actual work (entry preparation, resource/scene creation, startup confirmation). They do not claim measured byte-loading progress. Candidate scene processing and canvas visibility remain disabled until readiness confirmation; startup options specify `staged=true`, and the owner calls `activate_entry()` after commit. Career/native adapters use this boundary to defer audio, window title, and shared engine/viewport settings. Failed candidates are detached/freed; the previous camera is restored when applicable. Return signals are tied to the current scene, and disposal after a return signal is deferred past that scene's command stack.

`SaveRecovery` is presentation only. It emits retry/read-backup/import/export/back intents and never validates or writes a checkpoint. It exposes JSON paste, filesystem selection, separate raw and verified backup copy actions, raw export to a separate file, and a Back control which remains available during readiness. Each file-dialog opening captures recovery session and dialog sequence; closing/reopening invalidates prior callbacks, and the owner checks emitted session IDs. Shared `SettingsPanel` sends patches to actual transactional `UserSettings`, then receives its confirmed receipt/snapshot.

## Continuation and import boundary

Ordinary continue adopts the original save text and never calls `write_checkpoint`, including validated backup continuation. It does not rewrite settings or rotate backups. Missing, unreadable, and invalid v2 slots all retain an available recovery entry. Invalid/readable slot text remains available for raw export; failed JSON/file/backup attempts preserve the original recovery evidence.

V2 preparation uses `SaveCodec` plus an isolated actual `MingqiRuntime` adoption to validate source rules and native projection. `MainScene` then constructs the actual native scene with its real terrain, waits for final startup receipt, commits through `SaveCoordinator`, and only then swaps visibility and active processing. Schema/native failure and transaction failure retain the original slot and recovery page. Imported career state never overwrites independent player settings.

New source `start` entries normalize the menu captain name and persist that name through `UserSettings` after scene startup succeeds. Ship-book and practice intents do not persist names. Native1650 receives decoded Unicode scalars: literal private-use characters are preserved and lone surrogates/control units become U+FFFD; reversible source text remains unchanged in settings and the legacy boundary. Both presentation and owner enforce QA/practice gates. The original QA scenario suite remains an explicit unavailable-entry failure pending migration; the router does not present a substitute as that suite.

## Focused evidence

RED: the focused test first returned exit 1 with `native router exists with fenced continuation and recovery`. A second RED, after core preparation was implemented, required the missing native lifecycle owner.

GREEN command:

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_game_router.gd --quit-after 200
```

Result: exit 0, exactly one `GAME_ROUTER_TESTS complete assertions=48 failures=0`, no Godot script/error/warning diagnostics. Tests cover actual v2 native validation and an actual filesystem continuation without backup rotation, duplicate intents, generation cancellation, raw invalid export, failed-retry evidence retention, invalid import, backup reads, write failure, QA gates, native name conversion (including DEL accepted by the source menu but rejected by native1650 without adaptation), actual extra-scene construction/options, trusted owner dev/qa flag propagation to the ship book despite spoofed request fields, native menu/recovery/settings controls and physical-Esc closing, scene return/disposal/activation, startup rejection, stale file-dialog callbacks, and commit-before-swap through the main owner. Injected entry scenes isolate lifecycle from GPU rendering while actual runtime/save validation remains exercised.

A dedicated cancellation-after-tree-entry case initially exposed a Godot typed-argument diagnostic for a previously freed candidate; disposal now validates the object before accessing it, and the same case passes without diagnostics.

Limits: this focused run does not certify GPU rendering, actual career scene entry through the router, platform file-dialog interaction, clipboard delivery, every extra-mode implementation, exported Windows builds, or the full migration inventory. Root integration owns those checks and the project entrypoint setting.
