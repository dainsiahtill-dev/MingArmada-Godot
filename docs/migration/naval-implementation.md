# Native naval simulation

Source: read-only `C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada`, HEAD `9ad6a44daecd4ec36a8172d83ff27493feffe5dd`. Source package is `packages/naval-core`. Implementation lives in `modules/naval_simulation`; it depends only on contracts and the numeric physics engine. It creates no Nodes and imports no scene, game, runtime or UI modules.

`encounter.gd` ports the current `NavalEncounter` authority: six hull specifications; command permission and operational checks; manual controls and assisted handling; auto trim; wind updates; live statistics; six tactical orders and their lifecycle; nearest threat AI and unarmed evasion; navigation, tack hysteresis, lookahead hull checks, traffic avoidance, bounded routes and retry; swept shore contact, rotated SAT vessel contacts; cannon positions, firing arc, target lead and low trajectory solve; staggered cannon volleys, five grape pellets, reload/crew/equipment budgets; moving/rotating hull and mast sweeps with nearest time of impact; water contact, splash, damage, sinking and neutral aggression; pending combat/attack guards; terminal outcomes, continuous battle episodes and stale-request-safe surrender; atomic batch validation, service anchoring, work locks, captured/disabled vessels and preserved inertia.

Public construction is `Encounter.new(config)`. `reset(config)` returns a native boolean; rejected configuration records `last_error`. Valid source configuration and ship fields retain canonical camelCase. Snapshot shape is the source `{time,tick,status,playerId,battleId,wind,oceanWaves,ships,projectiles,surrender?}`; ship `visual` remains scalar `{position,heading,velocity,heel,pitch}`. All public snapshots, events and order telemetry are detached. `controlsSequence` advances for accepted same-tick vessel mutations without advancing physics time.

Every source public method is present, with native aliases:

| Source API | Native alias |
| --- | --- |
| `drainEvents()` | `drain_events()` |
| `reconcileShips(setups,policy?)` | `reconcile_ships(...)`, `reconcile(...)` |
| `setPlayerId(id)` | `set_player_id(id)` |
| `updateShipStats(id,update)` | `update_ship_stats(...)` |
| `isAnchored(id)` | `is_anchored(id)` |
| `hasPendingAttacks()` | `has_pending_attacks()` |
| `hasPendingCombat()` | `has_pending_combat()` |
| `hasActiveOrder(id)` | `has_active_order(id)` |
| `issueOrder(order)` | `issue_order(order)` |
| `orderStatus()` | `order_status()` |
| `navigationStatus(id)` | `navigation_status(id)` |
| `anchorFleet(ids)` | `anchor_fleet(ids)` |
| `previewSurrender(captorId?)` | `preview_surrender(captorId?)` |
| `setWind(wind)` | `set_wind(wind)` |
| `setManualHandling(id,request?)` | `set_manual_handling(id,request)` |
| `findManualRecoveryHeading(id)` | `find_manual_recovery_heading(id)` |

`command`, `step`, `snapshot`, `navigate` and `reset` use their source names. Optional arguments represented as JavaScript undefined use native `null`; telemetry with no route also returns `null`. Commands and reconciliation return detached `{ok,reason?}` results.

Clock correction: frozen `NavalEncounter.fixedTick` calls `NormPhysicsEngine.step({deltaSeconds:1/60})` once per naval tick. It has no internal 120 Hz subdivision. This native encounter preserves that integration order for source trajectory equality. The standalone sailing physics lab uses 120 Hz separately. Encounter callers may run at 30, 60 or 120 Hz: accepted elapsed time is accumulated into 60 Hz naval ticks, each caller delta is capped at 0.1 seconds, at most six ticks are accepted per call, and surrender consumes no further time. Physics and ballistics use the same accepted encounter tick time.

Trusted native extension: `config.waveSampler: RefCounted` optionally injects a sampler with `sample(x,z,time)`; default source generic/described waves remain unchanged. The adapter gives every injected physics/water sample the accepted encounter time. Existing `CoastalWaveField` is supported. Native descriptor `direction.z` is accepted at this boundary and normalized to source canonical `direction.y` in snapshots. The root runtime owns injection, renderer and crew clock coordination. Source oracles use the untouched source wave profiles; coastal attenuation is an intentional native profile and is tested separately, without claiming source offshore trajectory equality near shore.

Verification: `tools/migration/export-naval-reference.mjs` imports and transpiles the actual frozen TypeScript in memory using the source-installed TypeScript compiler. It checks HEAD and tracked source cleanliness through RTK, writes only target artifacts, and records SHA256 for all 18 consumed source files. It does not use stale source `dist` output or write a source build directory. `tests/fixtures/naval-reference.json` contains 72 actual encounter replay cases, six source route results, five source collision sweeps and 1,444 host `localeCompare` pair oracles. `tests/test_naval_simulation.gd` checks exact dictionaries/arrays, canonical event order/identity and finite numeric values with relative tolerance `1e-7`. The first red run failed on absent implementations; subsequent expanded oracles caught stable route/hypotenuse arithmetic and the disengaged-versus-victory episode outcome when a hostile leaves while shots remain.

Current focused evidence on installed Godot 4.7.2:

- `test_naval_simulation.gd`: `NAVAL_SIMULATION_PASS assertions=51559 cases=72`.
- `test_naval_invariants.gd`: `NAVAL_INVARIANTS_PASS assertions=72`.
- No `SCRIPT ERROR` or runtime-error output in successful runs; process exit code zero.
- Replay covers all three ammo types on both broadsides; four world headings; all six source hulls with the original five-wave field and live cargo/draft/equipment changes; generic waves and live wind; 30/60/120 Hz caller clocks; all six orders; an 80 simulated second six-vessel battle; AI firing and unarmed evasion; route success/rejection, island routing and shore contact; same-tick controls and malformed updates; atomic batch/service/order rejection; captured targets, disappearing hostiles, pending attacks, disabled inertia, manual assist, sink/victory/defeat and surrender.
- Native canaries cover injected sampler use and clock, real `CoastalWaveField`, detached authority, event-buffer atomicity, preserved motion during equipment updates, invalid delta rejection and all public source/native API pairs.

Commands (each shell invocation starts with RTK):

```powershell
rtk proxy node --experimental-vm-modules tools/migration/export-naval-reference.mjs
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script tests/test_naval_simulation.gd
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script tests/test_naval_invariants.gd
```

This numeric authority evidence does not establish native UI, GLB cannon visuals, crew impacts, graphics performance or actual player navigation acceptance. Those integration checks belong to root runtime/presentation work. No full combined suite, GUI scene, packaged export or source repository commit was performed by this task. CodeGraph discovery was unavailable because both checkouts were unindexed; source discovery used RTK fallback.

## Independent review round 1

The four requested corrections are covered by fresh focused runs of the exact commands above:

- Source `localeCompare` tie/avoidance decisions now use `id_collator.gd` and source-derived `id-collation.json`; source lexical captor selection remains lexical. Stable source ordering is preserved when collation considers different IDs equivalent. Direct ICU oracles include mixed case, punctuation, accented Latin and canonical decomposition, Chinese, Greek/Cyrillic and selected symbols. Eighteen additional encounter oracles exercise target selection, protect threats and AI avoidance with those IDs.
- Combined `heaveExcursion + draft * 2` is checked before reset, update or batch commit; source envelope arithmetic order is preserved. Reset stages all newly configured bodies. Existing-body updates validate all physics setters on detached numeric clones, then commit scalar state into the original live core identity. Regression tests cover source rejected overflow, native configure/setter failure propagation, preserved event buffers and unchanged authority after rejection.
- Numeric comparison rejects nonfinite actual or expected values before tolerance arithmetic. Focused canaries reject NaN/Infinity on either side and retain finite tolerance behavior.
- Seed jitter uses floating remainder, preserving source fractional seeds. Actual source replays cover ±42.5, `1e100` and `1e308`; JSON numeric enemyCount values are accepted by value.

Collation scope and remaining limitation: source `String.localeCompare` depends on the source host ICU/default locale. The captured exporting host reports `zh-CN`; metadata records its ICU version and resolved options. Native collation is deterministic and matches all frozen product-generated ASCII IDs and audited oracles, without a new binary runtime dependency. This is not universal ICU equality for arbitrary external Unicode identifiers, unsupported characters or context-sensitive combinations. `supports(id)` reports table coverage; unsupported characters remain accepted with a deterministic scalar fallback. For such external IDs, an equal-distance target/order/avoidance tie may differ from another host's ICU. A trusted `config.idComparer: Callable(a,b)->int` seam can inject the chosen host collation later. No valid ID vocabulary was narrowed. This packaging-scope limitation was explicitly accepted by root and remains part of final review.
