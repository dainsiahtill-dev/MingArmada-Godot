# Safe arrival berthing — implementation report

Status: final source frozen after the residual-rudder review correction described below. The initial-stage record is retained; use the final patch and hashes in the appended review section. No commits or staging performed.

## Result and authority boundary

`game/runtime/near_field_bridge.gd` now selects eligible original leased `grain-a` / `grain-b` vessels in the synchronized campaign candidate and passes their identities through the existing `_apply(vessels, candidate, anchors)` / `Encounter.reconcileShips` transaction. No direct stop, pose correction, campaign write, new persistence schema, or native bypass occurs in production.

Eligibility requires the campaign's `genuine_lease`, original `grain` profile, surviving business/native hulls, both business/native able crew at or above the original minimum, and control permission in both candidate and current native policy. Captured, disabled-motion and locked identities are excluded in both policies. The candidate must retain the matching authoritative `arrived` voyage, zero cargo, and a real destination port. Range and horizontal speed use the **current native observation**, with inclusive limits of 55m and 0.75m/s.

Pending native attacks, actual navigation, an active native order, nonzero actual rudder or sail deployment, active boarding, active port work, and a live uncaptured hostile at or within 600m prevent arrival anchoring. Reconciliation and synchronization use the same predicate and same atomic handoff. Existing service work still retains its own ordinary native lock and stop behavior.

The initial arrival observation retains normal unloading and normal clearing of the voyage's old terminal navigation; eligibility only occurs on a later safe observation. Already-arrived voyages retain any later explicit native navigation. Active rally commands remain native authority; arrival anchoring never cancels them.

## Rulings supplied by the controller

- Preserve already-arrived manual navigation: `_apply` clears the voyage navigation when the voyage transitions into `arrived`, or during existing fresh startup; later `arrived` synchronization omits a navigation replacement. Reason: the original unconditional null projection erased new user navigation. Cost if wrong: a stale destination could remain after an imported inconsistent arrival; the unchanged fresh-startup path clears navigation, and actual navigation still blocks arrival anchoring.
- Treat nonzero native rudder/sails as actual control intent and exclude that ship. Reason: protecting only navigation/orders would allow automatic berthing to erase direct helm commands. Cost if wrong: residual autopilot control can delay automatic berthing; actual captain voyage verification must establish the game's normal terminal controls settle appropriately. Global held input does not block another merchant's berth.

## TDD evidence

Native command used for both observed phases:

```powershell
rtk proxy "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_arrival_berthing.gd
```

The RTK-prefixed Python orchestration captured stdout/stderr from that same RTK child invocation and saved the log without changing game state or QA tools.

RED, before production edits, against the preserved baseline:

```text
ARRIVAL_BERTHING_TESTS assertions=607 failures=12
FAIL: sync actually berths original arrived leased transport
FAIL: repeated sync retains stable native berth through 10s wind
FAIL: reconcile actually berths original arrived leased transport
FAIL: repeated reconcile retains stable native berth through 10s wind
FAIL: sync preserves the player's real explicit navigation
FAIL: 55m inclusive gate uses actual native location
FAIL: 0.75 inclusive gate uses horizontal native speed
FAIL: live uncaptured hostile inside inclusive 600m prevents automatic berth
EXIT 1
```

Repeated lines for the second original transport account for all 12 failures. This was an expected behavior failure, with no script/resource errors; full output is `arrival-berthing-red.log`. Fixture mistakes from an earlier exploratory run were corrected before this clean RED and before any production implementation.

The minimal implementation immediately produced 607 assertions / 0 failures. Additional native guard, casualty and export assertions were added while keeping that behavior green. Final frozen test:

```text
ARRIVAL_BERTHING_TESTS assertions=723 failures=0
EXIT 0
```

Full output is `arrival-berthing-green.log`. Both `sync` and `reconcile` are exercised against actual Campaign/Bridge/Encounter objects. The tests assert real `isAnchored`, unchanged actual position, and 600 real native ticks / 10 seconds with 12m/s wind. Stock, settlements, crew, hull/sails, ownership, profile, named people, silver, debt, reputation, contracts, prizes and casualty ordinals retain their appropriate state; repeated handoffs create no duplicate business effects. Real native sinking keeps the original vessel, crew and steward dead. Native and business snapshots both remain unchanged when a companion's incompatible hull causes the handoff to reject.

Guard coverage includes missing lease, wrong owner/profile, missing/mismatched/loading/underway voyage, remaining cargo, missing native authorization, actual crew loss below eight, boarding, port work, current captured/disabled/locked policy, real rudder/sail commands, actual explicit navigation, active campaign-issued rally, inclusive range/speed/hostile boundaries, pending actual volley, non-merchant helm commands, normal captain dock rejection, and real `Runtime.export_save` full-fleet rejection.

## Scoped regression evidence

All 17 selected scripts passed with exit 0 and no script/compile/resource errors. Exact RTK command arguments, completion lines, exits and full stdout/stderr are recorded in `arrival-berthing-scoped-results.json`. Each run used the same engine/path command above with the corresponding `res://tests/test_<name>.gd` script:

| Script | Observed completion |
| --- | --- |
| near_field_bridge | 13 assertions, 0 failures |
| voyage_waypoint_handoff | 64 assertions, 0 failures |
| autopilot_port_approach | 24 assertions, 0 failures |
| manual_sailing_assist | 11 assertions, 0 failures |
| naval_invariants | PASS, 72 assertions |
| naval_simulation | PASS, 51559 assertions, 72 cases |
| native_readiness | 16 assertions, 0 failures |
| sailing_runtime | 13 assertions, 0 failures |
| mingqi_runtime | 12 assertions, 0 failures |
| mingqi_rules | mingqi source golden: PASS (0) |
| mingqi_live_projection | 9 assertions, 0 failures |
| save_compatibility | save compatibility v2: PASS (0) |
| save_coordinator | 12 assertions, 0 failures |
| opening_story_runtime | 45 assertions, 0 failures |
| opening_story_save | 122 assertions, 0 failures |
| career_startup | 53 assertions, 0 failures |
| convoy_recovery | 124 assertions, 0 failures |

The controller identified `mingqi_rules` and `save_compatibility` as the two original oracle/golden scripts. Both passed once in this scoped run.

## Scope, exact patch and frozen hashes

Only these source/test files changed:

- `game/runtime/near_field_bridge.gd`
- `tests/test_arrival_berthing.gd` (new)

The actual pre-edit bridge is preserved as `near_field_bridge.gd.arrival-before`. `arrival-berthing.patch` contains only its exact bridge delta and the new test, excluding unrelated existing branch changes. `arrival-berthing-hashes.json` records SHA256:

```text
baseline bridge  b1802c077abb19855422fec274522f88fa21ce7fdebe2363989723a48239726d
frozen bridge    8621c85da31d14de50ee9c27137268866ab29b80dfe3d9a02333fe6771e86617
frozen test      b24b89cc28f13b0ab2685aeea2e4accdc4b0b4bc536cae51a7725e8574242928
scoped patch     55205caa615bd154d5ab7a56db2697ffcc2f26d015c9e29b225d5a3a17aa0daf
```

## Limits and self-review

Unit fixtures establish deterministic campaign/native starting scenarios and exercise real transactions. They are never evidence of the player's voyage. Native pose/policy fault cases are test-only, and no production test hook was added. Stability evidence here uses flat deep water and an empty native wave descriptor list, plus real wind; actual geographic/wave sailing remains the controller's next acceptance gate.

The full discovered suite and real captain journey are deliberately delegated to the controller after this source freeze, as instructed, to avoid duplicate heavy runs and shared-source races. Existing full-fleet save, docking, wet-route planning and physics implementations were untouched. The old `MingArmada` directory and editor PID 8384 were untouched; no player saves, QA tools, graphics, performance resources or Git state were modified. CodeGraph reported no index, so scoped source discovery used RTK fallback and no indexed review is claimed.

Self-review found no remaining scoped implementation issue. Independent spec/code review and actual voyage acceptance remain controller-owned.

## Review correction: real autopilot residual rudder and explicit first-arrival controls

The independent review identified a real missing case in the initial green fixture: arrival was observed before a native autopilot tick. The original `_arrive` cleared sails but retained the autopilot's nonzero rudder; clearing native navigation then removed the component that would update that rudder. The strict actual-rudder berth gate consequently rejected the transport forever. The initial 723/0 result and 17/17 scoped run are retained above as historical evidence, rather than final acceptance evidence.

The controller also reported a completed 103/103 full-suite run on the initial implementation and saved it as the before-rudder-review run. That historical run is not acceptance of the corrected source. A new full suite and actual captain voyage remain controller-owned after the final freeze.

### Additional controller rulings and bounded ownership context

- Ruling: expand production scope only to `Campaign.reconcile_near` and its internal `_sync` / `_inspect` / `_arrive` call chain, in addition to the already-owned Bridge. Supply optional, nonpersistent arrival-control identities instead of blindly clearing every arrived rudder. Reason: only the runtime has actual native navigation and active-order authority; Campaign must retain ownership of business controls. Cost if wrong: an incorrectly classified automatic identity could erase a real helm command. Both layers therefore check original lease/profile, authorized near membership, voyage identity/status, surviving hull/crew, epoch, tick and control projection. Actual active-order and current native policy checks stay in Bridge; Campaign independently rechecks the identity, campaign policy and observation fields available to it.
- Ruling: protect an actually observed new explicit command, including a sail-only command, at the first genuine arrival. Reason: the original unconditional unloading sail reduction erased that new command and permitted a subsequent automatic berth. Cost if wrong: treating an unrelated changed native control sequence as explicit can conservatively delay berthing until a new neutral helm command. This prioritizes preserving native control authority. Duplicate, unauthorized, stale-epoch and unobserved identities must reject before either authority commits.

`reconcile_near` now accepts two optional identity arrays, both defaulting to `[]`. One marks completion of the existing automatic voyage controls; the other marks newly observed explicit native controls. They are local transaction arguments, never campaign state, save fields, commands, receipts or actor identities.

An automatic identity must have the current native final-port navigation, no active native order, and the same native controls sequence as its last business projection. On its one genuine `_arrive`, Campaign lowers sails and neutralizes rudder, then the normal native projection applies the same business controls. The current-observation berth gates remain unchanged; the next safe observation can anchor the real vessel.

An explicit identity instead requires a strictly newer actual native controls sequence, matching epoch, current business controls revision, valid observation tick, and the same original leased grain/underway/authorization/hull/crew boundaries. `_sync` observes those real controls; that one `_arrive` preserves their rudder and sails while keeping the original cargo, stock, arrival receipt, pose-speed and revision semantics. Later explicit controls and navigation retain the existing protection. A new different navigation target is also preserved at the first arrival; only the old destination-port target is cleared.

The default-empty legacy call path retains the original unloading sail behavior. A real native test exercises that default explicitly, and both original oracle/golden scripts pass on the final source. Active-order truth necessarily comes from the live Bridge/Encounter; it cannot be fabricated from Campaign's historical order list. The bounded context delegates that live query while Campaign rechecks all supplied identity/observation proofs it possesses.

### Additional observed RED/GREEN evidence

All phases use the same RTK-prefixed native test command recorded above:

| Stage | Observed result | Evidence |
| --- | --- | --- |
| Real automatic voyage projected at 25.01m; actual native ticks enter arrival range with nonzero rudder | RED 747 assertions / 4 failures, exit 1 | `arrival-berthing-rudder-red.log` |
| Added first-arrival different-target navigation and real controls/order protection | RED 779 assertions / 5 failures, exit 1 | `arrival-berthing-rudder-red-expanded.log` |
| Initial ownership correction plus malformed proof and atomic rejection coverage | GREEN 852 assertions / 0 failures, exit 0 | `arrival-berthing-rudder-green.log` |
| Actual first-arrival sail-only command, rudder 0 / deployment 0.4 | RED 863 assertions / 2 failures, exit 1 | `arrival-berthing-first-sails-red.log` |
| Final ownership correction, explicit proof checks, legacy default and newly arriving handoff rollback | GREEN 911 assertions / 0 failures, exit 0 | `arrival-berthing-first-sails-green.log` |

The real-autopilot RED failures were the missing business/native neutral rudder and failed next-observation berth, in both `sync` and `reconcile`. The sail-only RED failures were erasure of the actual new sails and subsequent automatic anchoring. All decisive RED/GREEN runs above completed without script/compile/resource errors.

The final test also demonstrates: actual first-arrival rudder and sail-only commands survive; native rally ownership is retained; newly requested different navigation survives first and later synchronization; malformed/unauthorized/duplicate ownership, a wrong epoch and unobserved explicit ownership reject atomically; a changed native sequence cannot be claimed as automatic; and native batch rejection rolls back the newly arriving cargo and neutral-rudder transaction.

### Covering regressions on corrected source

The first rudder-only correction passed 19 scoped scripts, with full command/output evidence in `arrival-berthing-rudder-scoped-results.json`. That intermediate run is retained.

After the final sail-only correction, all 14 covering scripts passed with exit 0 and no script/resource errors. Exact RTK arguments and full output are in `arrival-berthing-final-scoped-results.json`:

| Script | Final observed completion |
| --- | --- |
| near_field_bridge | 13 assertions, 0 failures |
| voyage_waypoint_handoff | 64 assertions, 0 failures |
| native_readiness | 16 assertions, 0 failures |
| mingqi_runtime | 12 assertions, 0 failures |
| mingqi_rules | mingqi source golden: PASS (0) |
| mingqi_live_projection | 9 assertions, 0 failures |
| mingqi_ui | 195 assertions, 0 failures |
| save_compatibility | save compatibility v2: PASS (0) |
| save_coordinator | 12 assertions, 0 failures |
| opening_story_runtime | 45 assertions, 0 failures |
| opening_story_save | 122 assertions, 0 failures |
| opening_story_ui_runtime | 39 assertions, 0 failures |
| career_startup | 53 assertions, 0 failures |
| convoy_recovery | 124 assertions, 0 failures |

### Final frozen review package

Final production/test scope is exactly:

- `game/runtime/near_field_bridge.gd`
- `game/domain/mingqi/campaign.gd`, limited to the approved transaction/arrival call chain
- `tests/test_arrival_berthing.gd`

`arrival-berthing-rudder-delta.patch` is the exact incremental review correction against the initial frozen bridge/test and the pre-correction Campaign. Those baselines are preserved as `near_field_bridge.gd.arrival-review-before`, `test_arrival_berthing.gd.review-before`, and `campaign.gd.arrival-review-before`.

`arrival-berthing-final.patch` is the cumulative scoped implementation: original pre-edit Bridge delta, approved Campaign delta and complete new test. It excludes unrelated branch work. `arrival-berthing-final-hashes.json` records the current SHA256 values:

```text
final bridge     19cea28a36f55766126f066a5941f21477688a96f35e1815709629dcbabfbb9f
final campaign   f36ca92c29a9061ede634b414c5fd76a719ecdfd2b90cc9994a35b2b7becad1f
final test       ad7b0ea88b9b757fb7d8d91de60427260b7cc571f39362b6968d0bab76f98142
review delta     b4ac665a4880188181f1b2ce616718071ae57ee4486b89a6e242e9a07a0b58fc
cumulative patch 5496daf73da11b0f023bfbdccbd94aa20403b489755ce89778dca2c5eb7b3868
```

Source and test are frozen. No commits or staging were created. The prior limits still apply: deterministic real native fixtures are not evidence of the player's voyage, actual geography/waves remain an end-to-end acceptance gate, and the controller owns the final full-suite and actual captain journey runs. No further source edit is planned unless independent review or those real acceptance runs identify a blocking issue.

## Review fix round 2: malformed ship rows before ownership lookup

The remaining P2 finding was specific to the new nonempty ownership context: `reconcile_near` looked up `_ship(before, id)` before the existing `_sync` snapshot/row validation. A malformed `before.ships` value of `7`, `[null]` or `[{}]` therefore reached an unchecked `ship.id` access. Default-empty callers already reached the original normal atomic rejection path.

The new tests supply otherwise legitimate automatic or explicitly sequenced arrival identities, corrupt only the detached input's ship container/row, and assert an ordinary rejection plus identical committed Campaign and native snapshots. The observed RED was:

```text
ARRIVAL_BERTHING_TESTS assertions=980 failures=6
SCRIPT ERROR: Invalid access to property or key 'id' on a base object of type 'int'.
SCRIPT ERROR: Invalid access to property or key 'id' on a base object of type 'Nil'.
SCRIPT ERROR: Invalid access to property or key 'id' on a base object of type 'Dictionary'.
EXIT 1
```

Those three diagnostics occurred once for each ownership mode, totaling six script errors. Full historical output is retained in `arrival-berthing-ownership-rows-red.log`. An earlier exploratory invocation printed a zero-failure marker while still emitting the six script errors; it was rejected as a failure, never accepted as a green run. The decisive RED above also asserts the existing normal snapshot-shape rejection codes.

Ruling approved by the controller: only the nonempty ownership branch validates `ships` as an Array and every row as a Dictionary with a valid identity before performing `_ship` lookup. Retain the default-empty path, reject bad rows rather than ignoring them, and change no additional API or source area. Cost if wrong: a shape check could reject a legitimate identity; the check uses the existing identity validator with a generous 4096-character shape bound, while the unchanged membership/authority validation determines whether that identity actually belongs to the campaign.

The production correction is exactly **four added lines** in `Campaign.reconcile_near`. The Bridge is unchanged from the prior freeze. Invalid container/row inputs now return the existing `invalid-near-snapshot` or `unknown-or-duplicate-near-vessel` reasons before any lookup, candidate mutation or native callback. The original empty-context path remains unchanged.

Observed GREEN on the final four-line guard:

```text
ARRIVAL_BERTHING_TESTS assertions=980 failures=0
EXIT 0
```

There were **zero script/compile/resource errors**. Full output is `arrival-berthing-ownership-rows-green.log`; exact RTK arguments, exits and output for the four covering runs are in `arrival-berthing-ownership-rows-scoped-results.json`:

- `test_arrival_berthing.gd`: 980 assertions / 0 failures, including all six malformed container/row cases and unchanged state/core snapshots.
- `test_near_field_bridge.gd`: 13 assertions / 0 failures.
- `test_mingqi_rules.gd`: Campaign source golden PASS (0).
- `test_save_compatibility.gd`: web-v2 save compatibility golden PASS (0).

The controller deliberately stopped its own in-progress Node runner before this source change. Completed scripts had passed; the interruption was preserved by the controller as an incomplete, intentionally stopped run, not reported as a functional test failure or a full-suite success. The controller owns the restarted final 103-script suite and actual captain voyage after this freeze.

P2-only review delta: `arrival-berthing-ownership-rows-delta.patch`. Its baselines are `campaign.gd.ownership-rows-before` and `test_arrival_berthing.gd.ownership-rows-before`; the latter was reconstructed from the preceding complete patch and verified against its frozen raw-file SHA256. The cumulative `arrival-berthing-final.patch` and `arrival-berthing-final-hashes.json` have been refreshed. These are now the final current hashes; prior values above remain historical:

```text
unchanged bridge 19cea28a36f55766126f066a5941f21477688a96f35e1815709629dcbabfbb9f
final campaign   beead54a168dc323eb0fe928fc436e9cf0d64d40e5d2b851fdcd477021b068c1
final test       72940022677c33925d8dc053f98c7d5af13c58abc756b46b438412340e66536d
P2-only delta    37fdfc958345aa74cf8bbde3d7d56965920cac1db606df33b7d9930b20ff9992
cumulative patch 279557688dc548851d1b4d94aeb82915f80b0fe9fb56bb8f3ede4854c9295259
```

Source/test are frozen. No production edits followed the freeze notification; only this report was appended. No commits or staging were created. Final independent re-review and full/live acceptance remain controller-owned.
