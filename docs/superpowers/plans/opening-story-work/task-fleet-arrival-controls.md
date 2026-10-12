# Fleet arrival controls: scoped implementation report

The bounded-stop follow-up below supersedes the neutral-only candidate as the current implementation. Earlier candidate identities and RED/GREEN results are retained as history; they do not constitute current long-term stopping or voyage acceptance.

2026-10-12. Writable repository: `C:/Users/dains/Documents/Git/ming-armada`. This worker changed only `modules/naval_simulation/encounter.gd`, the new `tests/test_fleet_arrival_controls.gd`, this report, and scratch artifacts under `build/second-aftermath-work/fleet-arrival-controls/`. No Git staging/commit/reset, production save manipulation, QA changes, full voyage, full suite, or GPU session was performed. CodeGraph was unavailable/unindexed as established by Root; source discovery used RTK fallback. Applied systematic debugging, TDD, and verification-before-completion.

## Repair and scope rulings

The genuine second journey remains the immutable 82/1 failure. Its scalar fixture SHA256 is `191170ccf22ab26dfd00521c3ea2ff6933e30c2c24b98d575e7ea856b2a3c037`. Read the approved fleet-arrival plan and the latest independent command/control-architecture reports, including `docs/task-fleet-return-command-audit.md` and `docs/task-fleet-return-control-architecture.md`.

1. Normal Rally completion relinquishes that current order's rudder/sails and obsolete route/tack/turn/recovery output state. Native core identity, position, velocity, yaw, clock and ordinary physics remain untouched. Generic `_cancel_order` remains unchanged because new manual controls are written before cancellation.
2. A stateless final-point hold runs after route validity and existing Egress handling, before tack/shore/heading-error steering. Existing Approach owners continue their physical hold/handback path. The hold clears rudder/sail/turn output, keeps navigation and active tactical ownership, and adds no brake or recovery authority.
3. Ruling approved by Root: ordinary unordered final navigation uses the existing planned18m/unplanned30m reach boundary. Ordered protect can hold only with the current participant/order and exact current decision point, no fire decision, existing route-planning/reference-handling flags, a truly anchored target under `is_anchored`, and current control/operational/manual gates. A moving or departing target, threat/fire decision, other tactical intent, intermediate waypoint, new command, or unavailable authority keeps the existing path. The predicate is re-evaluated each tick; no cached stationary-target authority is introduced.
4. Additional refinement requested by Root: a completed participant in a multi-ship Rally holds neutral while its current shared Rally remains active for other ships. This uses the existing current `Orders.decision.completed` condition (25m/1mps), exact decision goal, and final-route check. Other participants continue normal steering. It does not widen Approach/Egress authorization or change Rally completion thresholds.
5. Neutral-only coast passed the recorded ten-second native probe, so no new `Manual.build` braking request was introduced. This is a short control/slowing result, not proof of a full stationary checkpoint or safe return over hundreds of seconds.

## Source identities and exact delta

- Pre-edit Encounter: `0910d581c7a5f4642edc9d3ddcb826a9b42f5936655be441f1527458526c9df9`.
- Candidate Encounter: `5cceb84d487858d5374edf7cb909e519e1b0b8b27b48a082efdc49868ec57290`.
- Final pinned-fixture test: `4d00a6c67a893ca9f76933cd7321279c2adc30477e5991ff812ceeb6a49c66bf`. The preceding87-assertion version was `21ce1d9f8ba294199bffab3e98cb3387806b1ec8540a6eb22cf67eb68593628d`.
- Exact bounded production diff: `build/second-aftermath-work/fleet-arrival-controls/production.patch`, from the0910 pre-edit body to the5cce candidate only; this is not the inherited dirty-tree diff against HEAD.
- Scratch baseline/candidate: `encounter-before.gd` / `encounter-after.gd` in the same directory. The baseline was recovered by reversing only this worker's known patch in scratch, then verified byte-for-byte by the previously captured SHA256. `capture_delta.py` preserves the recovery/verification method. Production source was never reverted or swapped to produce RED.

## Actual RED/GREEN commands and results

All commands ran from the writable repository with Godot `4.7.2.stable.official.ed1daf0bf`. All log/result paths below are worker-owned scratch. The first test attempt incorrectly called nonexistent `Sailing.command`; it emitted eleven assertion failures plus `Invalid call. Nonexistent function 'command' in base 'RefCounted (sailing_simulation.gd)'`. That attempt is retained in `red.log` / `red.json` but was not treated as a valid TDD RED. The test was corrected to the real `Sailing.action` queue before any production edit.

Confirmed pre-production RED:

```text
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_fleet_arrival_controls.gd --log-file C:/Users/dains/Documents/Git/ming-armada/build/second-aftermath-work/fleet-arrival-controls/red-confirmed.log -- --report=red-confirmed.json
```

Exit1, 78 assertions / 13 expected failures, no script errors, loaded Encounter0910. Failures demonstrated terminal old helm/route/recovery leakage; stationary protect old helm/turn state; old ten-second native rudder/slowing behavior; planned/unplanned final helm; stationary-to-departing target hold; and partial multi-Rally hold. All takeover/intermediate/moving/threat/recovery-priority controls passed on the old body.

Initial candidate GREEN used the same command with `green.log` / `green.json`: exit0, 78/0. Additional player/non-player queued-control and unchanged-control preservation cases were then added without further production changes.

Final candidate GREEN:

```text
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_fleet_arrival_controls.gd --log-file C:/Users/dains/Documents/Git/ming-armada/build/second-aftermath-work/fleet-arrival-controls/green-pinned-final.log -- --report=green-pinned-final.json
```

Exit0, 88 assertions / 0 failures, no script errors, candidate5cce. The preceding `green-final.log/json` recorded87/0. Root review then requested a provenance-only check pinning the exact immutable fixture SHA, with early exit for a missing/unreadable record. No further production change was made. The test covers recorded B completion and Fast near-station decisions, all-ship native snapshot immutability, subsequent B native coasting, ten-second Fast native slowing, planned/unplanned final reach, intermediate progression, moving/departing/threat protect behavior, real Sailing queued helm/sail-only input for selected and non-selected ships, invalid/unchanged controls, superseding order, partial multi-Rally, owned Approach/Egress holds and invalid wet route rejection.

The expanded87-assertion test also ran against the exact0910 scratch body, with only its Encounter preload and loaded-source hash reference redirected to that scratch source:

```text
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://build/second-aftermath-work/fleet-arrival-controls/final-baseline-red.gd --log-file C:/Users/dains/Documents/Git/ming-armada/build/second-aftermath-work/fleet-arrival-controls/final-baseline-red.log -- --report=final-baseline-red.json
```

Exit1, 87/13, same expected failures, no script errors. Its JSON accurately records the loaded0910 source hash. This proves the expanded behavioral regression still catches the original body without modifying the production file. The final provenance-only assertion did not require a new behavior RED.

The missing-record preflight was verified with a scratch copy whose INPUT points to a nonexistent worker-owned fixture, keeping production/test/evidence unchanged:

```text
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://build/second-aftermath-work/fleet-arrival-controls/missing-fixture-preflight.gd --log-file C:/Users/dains/Documents/Git/ming-armada/build/second-aftermath-work/fleet-arrival-controls/missing-fixture-preflight.log
```

Exit1, only the expected pinned/readable-fixture failure; no SCRIPT ERROR or nil access. It exited before terrain setup, control decisions, native ticks, or result-file writes.

## Ten-second physical evidence

Both valid RED and GREEN fixtures retain all recorded1496.6 ships and formal terrain/wind/crew/cargo/draft. At setup only, real cores receive the recorded initial position/velocity/yaw and other available motion scalars. Historical previous-heading/tack were absent; previous heading is explicitly linearized from measured yaw, and no historical tack is invented. Decisions compare the whole real native snapshots before/after and do not change them. Ten-second native integration is then observed without corrections.

- Initial Fast velocity `(0.0579060,0.2046023)`m/s, yaw `0.01658123`rad/s, position `(-127.7459745,317.4069852)`.
- Old0910 after10s: velocity `(0.0825775,0.1973340)`, yaw `0.01659803`, position `(-127.0253377,319.4150730)`; neutral controls did not hold.
- Candidate5cce after10s: velocity `(-0.0320301,0.0938500)`, yaw `0.0001012023`, position `(-127.7485731,318.7572065)`; every tick retained rudder0/sails0 and a wet native hull. Residual position/velocity remain nonzero and change through real integration. No instantaneous anchor, native force constants, or speed/yaw reset was added.

## Remaining acceptance

Independent Spec/Quality review and Root's consolidated fresh full suite and actual first/second journeys remain required. Existing safety/ownership regression suites, long-term station/port drift, deadline/reward, full-fleet Xiamen checkpoint, normal Save/Continue, and personally reviewed native captures are not claimed by this worker's88/0 focused result. Rally still completes at its original speed<1 condition; neutralization alone does not prove anchored speed<=.05 or eventual checkpoint eligibility. No old evidence record was upgraded or rewritten.

## Bounded-stop follow-up: current candidate

The independent real400s counterexample `build/second-aftermath-work/fleet-arrival-review/b-neutral-coast.json` demonstrated the neutral-only candidate was insufficient: B remained neutral/wet but was75.920593m from the goal at400s, speed.1593327m/s and not anchored. Root explicitly stopped the new voyage attempt and retained its diagnostic phase; this worker did not run that voyage or upgrade any acceptance. Read the subsequent control-architecture appendix and Root's binding60-second stop ruling before implementation.

Initial bounded-stop identities, superseded by the capability review below:

- Saved pre-stop Encounter: `5cceb84d487858d5374edf7cb909e519e1b0b8b27b48a082efdc49868ec57290`, exact bytes copied **before** the stop edits to `build/second-aftermath-work/fleet-arrival-controls/stop-encounter-before.gd`.
- First bounded-stop Encounter: `763d7608ffde4719e8d45ac87a17e18ff3298d33fadfadcd2db0d405289de23a`.
- First bounded-stop test: `79ce5b7601b04f3d413e5f1daf9faf968360931db9fa60f76f00f1e894715330`.
- Exact bounded diff: `stop-production.patch`; captured candidate bytes: `stop-encounter-after.gd`, in the same scratch directory. The old0910-to5cce patch,88/0 result and pre-stop test copy `stop-test-before.gd` remain intact. No production back-and-forth, Git staging, runtime/Sailing edit, new module, codec/schema change or save/evidence overwrite occurred.

The current hold returns existing `Manual.build(kind,0,actualSpeed,crew/maxCrew,hull/maxHull,sail/maxSail,true,0,true)`, with the existing reference-handling/combat exclusions. It changes controller intent only: bounded0.2 brake, existing crew/health scaling and neutral yaw; no new force, acceleration, torque, reach, port or anchor threshold.

A genuine current Rally terminal transition can create a ship-wrapper `terminalStop` containing battle/ship/order/goal/draft/start/deadline. It retains the exact Rally point as **still-active stopping navigation**, while the tactical receipt remains completed at the unchanged25m/1mps condition. Stop requests take priority over normal autopilot in `_fixed_tick`; native shoreline and contacts continue normally. Current identity, completed record/participant, exact goal/draft, healthy controlled continuous planned/reference capability, neutral controls, no manual/capture/service/disabled/combat/terminal state and current wet footprint are rechecked. Losing a guard removes the owner/request and only its still-matching navigation.

Root refinement: retain the marker through its arming tick (`tick > startedTick` required for retirement), so at least one returned native substep carries neutral controls plus owned navigation. Existing `SailingSimulation.advance` then refreshes its cached helm through its existing navigation condition. This prevents both ordinary selected-player stale-helm resurrection and the already-slow .04m/s case whose marker could otherwise retire in its first completion step. No runtime API, `hasActiveOrder` meaning or automatic trim exception was added.

Retirement happens after real physics/contact observation at the existing speed<=.05/yaw<=.01 gates. It erases only wrapper authority and its exact owned navigation; it never writes pose, velocity or yaw. While owned, `isAnchored` is stricter and rejects the marker. Normal Runtime Save already queries that predicate and remains blocked. A60-accepted-second deadline uses `Approach.MAX_HORIZON`; timeout removes assistance, records `terminalStopResult.reason=timeout` internally and cannot rearm from a historical completed order or pretend to anchor. Valid changed controls, explicit navigation/cancellation, new orders, service/anchor, committed control/draft/permission/capture changes and replacement of the orders collection revoke; failed commands/projections preserve atomicity, and unchanged controls/projection sequence increments preserve the original start/deadline.

### Actual follow-up TDD and focused results

Initial stop tests against5cce ran260/51, exit1, no script errors after correcting test assertions to distinguish physical kinematics from legitimate rig-control projection. The retained `stop-red.log/json` first attempt recorded256/51; that version also incorrectly expected unchanged rig snapshot on a projection that legitimately applied pending neutral sails. Corrected `stop-red-confirmed.log/json` records the valid260/51 RED before any stop production edits, including the actual400s scalar counterexample and exact pre-completion/early-retirement Sailing cases.

```text
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_fleet_arrival_controls.gd --log-file C:/Users/dains/Documents/Git/ming-armada/build/second-aftermath-work/fleet-arrival-controls/stop-red-confirmed.log -- --report=stop-red-confirmed.json
```

First stop implementation GREEN attempt was260/1: surrendered `step` returned before metadata revocation. Added committed permission/capture projection checks then ran270/3 (`stop-policy-red.log/json`): those two new checks exposed the use of old policy while prepared ships were applied. Fixed the actual successful policy commit seam and terminal/surrender entry metadata cleanup, without changing physical state or invalid-request atomicity.

Final command:

```text
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_fleet_arrival_controls.gd --log-file C:/Users/dains/Documents/Git/ming-armada/build/second-aftermath-work/fleet-arrival-controls/stop-green-final.log -- --report=stop-green-final.json
```

Exit0, **270/0**, no script errors, wall5.06235s. Canonical recorded full-peer B probe now uses ten actual native seconds; `terminal_physics(400)` remains available to the independent review scratch. Root directed the long continuation out of the canonical unit path so the unchanged60s whole-test runner timeout needs no expansion. No simulation timestep, native clock jump or source-runner change was used.

Focused tests now include: command-time whole-native snapshot immutability; exact existing Manual request; true B stop plus unchanged peer control outputs at acquisition; live protect/partial-Rally brakes; pre-completion selected Sailing and .04m/s completion with multiple fixed substeps inside `advance(.1)`; unchanged sequence/projection ownership; invalid control/projection atomicity; changed helm/sails/trim/manual, null/same/new navigation, same/new Rally, changed projected controls/navigation/orders/permission/capture and explicit anchoring; crew/hull/sail/capture/service/disabled/permission/combat/terminal/config/draft/terrain/incarnation/record/participant revocation; insufficient positive-crew60s timeout/no rearm; and real Campaign/Runtime/Bridge Save rejection before retirement followed by normal export and unchanged codec restore.

Observed B under the current candidate: initial speed.5474735m/s; first physically anchored observation **3.68333 accepted seconds**, maximum measured goal distance21.86290m over ten seconds, all sampled hulls wet. After retirement, ten-second velocity `(0.0115475,-0.0483095)`m/s remains legitimate residual motion under the unchanged.05m/s anchor gate; no direct zeroing occurs. Recorded Fast reaches native velocity0 and negligible yaw by ten seconds through the existing braking solver. The legacy JSON case name `recorded1496-station-coast` is retained from the original test; its current requests are physical brakes, as asserted separately.

Current independent Spec/Quality, long400s native continuation, consolidated full suite and fresh full first/second journeys remain Root/review work. This270/0 result is focused controller evidence only; it does not establish a full-fleet campaign return, normal final checkpoint, new aftermath acceptance or reviewed graphics.

### Capability review and final candidate

Independent review of763 proved a real additional owner-lifetime gap: valid positive changes in crew/hull/sail/cargo/speed/steering remained healthy and therefore inherited the old stop owner with a changed budget. Root ruled that successful authoritative health/physical capability changes revoke the old owner. The smallest repair remains in the already-atomic `_apply_update` commit seam: compare normalized old/new controls, crew/hull/sail/maxes/dimensions/stats, then remove the old wrapper owner and only its matching navigation after the successful physical/state commit. No fields are added to the marker, schema or snapshots; no second module/field comparison seam is introduced. Failed preparation remains untouched, and exact ordinary projection retains the original deadline.

Root's separate initial suspicion about locked/disabled gates was disproved: `_terminal_stop_authorized` already calls central `_controlled`, which rejects both in continuous mode. Direct-request tests returned no assistance and revoked the owner before the existing service/disabled tick; no redundant gate was added. Clearing absent manual handling with null also preserves the stop, as required. Independent review's actual public-update RED was46/6 with the same positive-capability defect, no parse/script errors (`fleet-arrival-review/stop-transition-red.json/log`).

Worker capability RED:

```text
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_fleet_arrival_controls.gd --log-file C:/Users/dains/Documents/Git/ming-armada/build/second-aftermath-work/fleet-arrival-controls/stop-capability-red.log -- --report=stop-capability-red.json
```

Exit1,335/8, no script errors, loaded763. Exact expected failures: accepted crew10, hull99, sail99, maxCrew40, maxHull120, cargoMass1000, speedMultiplier.9 and steeringMultiplier.9 retained old ownership. Accepted draft1.5 already revoked correctly. The new direct locked/disabled request, null manual, no-op projection, rejected update and real Runtime/Bridge cases passed before the fix.

Final verification:

```text
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_fleet_arrival_controls.gd --log-file C:/Users/dains/Documents/Git/ming-armada/build/second-aftermath-work/fleet-arrival-controls/stop-capability-green-final.log -- --report=stop-capability-green-final.json
```

Exit0, **335/0**, no script errors, wall5.06530s. Final source identities:

- Encounter: `0de5a11c883d7ef93b798244ff1a116435c7c323eeeac5877b72e030fbe11030`.
- Test: `60908cce6fe83cb004724d60dea5662fc907ca6d2f8810d72139c13bd246ed1a`.
- Full exact5cce-to-final difference: `stop-production-final.patch`; exact final bytes: `stop-encounter-final.gd`.
- Scoped763-to-final capability difference: `stop-capability.patch`; saved pre-capability bytes: `stop-capability-before.gd` (SHA763 above). All reside under the worker's `fleet-arrival-controls` scratch. Earlier snapshots/diffs/logs were retained, not overwritten.

Authority boundary: this commit comparison covers real public/stat/projection changes. Direct ongoing native motion is still governed by the per-tick operational/control/wet/combat predicates; no pose/velocity/yaw/time/heave snapshot is frozen as an identity fence. The recorded wet/no-contact stop and guarded public update results do not claim every possible environmental casualty is a successful stop. Root reports the independent763400s continuation stayed wet/neutral, retired at3.6833s and ended8.9056m from goal/.0278mps/anchored; that independent evidence belongs to763, not a rerun of final0de5. The capability fence changes no force or native tick integration. Final re-review, consolidated suite and actual new voyages remain required before gameplay/checkpoint acceptance.

### Opt-out contract repair: latest candidate

Independent affected regressions on stable0de5 identified **two actual compatibility failures**, not stale assertions: `test_autopilot_port_approach.gd`24/1 (`non-planning native 30m braking range also suppresses recovery`) and `test_port_approach_recovery.gd`136/1 (`opted-out path retains blocked stop: routePlanning`). Their unchanged test hashes and identical before/after0de source identity were verified in the independent `stop-test_autopilot_port_approach-20261012-082919-649/manifest.json` and `stop-test_port_approach_recovery-20261012-082920-846/manifest.json` under `fleet-arrival-review`. Both real processes exited1 without diagnostic/script errors; their actual RED was reused rather than running the same long old tests again.

Shared `_arrival_brake` required reference handling/combat gates but omitted route planning. It therefore granted new physical assistance to non-planning ordinary final navigation. The one-line production repair also requires `config.routePlanning`. Non-planned final navigation keeps neutral rudder/sails and its goal but receives no physical assist; reference-handling opt-out also receives none. The old test files and their expectations remain unchanged.

Worker's new canonical opt-out RED, before this production gate change:

```text
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_fleet_arrival_controls.gd --log-file C:/Users/dains/Documents/Git/ming-armada/build/second-aftermath-work/fleet-arrival-controls/optout-red.log -- --report=optout-red.json
```

Exit1,337/1, no script errors, source0de5; sole failure `ordinary final reach uses planned physical brake or unplanned neutral coast false`. The new reference-off negative already passed. Current canonical assertion count is337; no module/test-file count or runtime fixture source was added.

Fresh GREEN commands:

```text
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_fleet_arrival_controls.gd --log-file C:/Users/dains/Documents/Git/ming-armada/build/second-aftermath-work/fleet-arrival-controls/optout-green-final.log -- --report=optout-green-final.json
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_autopilot_port_approach.gd --log-file C:/Users/dains/Documents/Git/ming-armada/build/second-aftermath-work/fleet-arrival-controls/optout-autopilot-green.log
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_port_approach_recovery.gd --log-file C:/Users/dains/Documents/Git/ming-armada/build/second-aftermath-work/fleet-arrival-controls/optout-approach-green.log
```

All three exited0: **337/0**, **24/0**, **136/0**, with no FAIL/SCRIPT ERROR/ERROR lines. `optout-validation.json` preserves current loaded Encounter, executed test hashes and parsed native-log summaries. Both old test hashes still match the independent RED manifests (`e4c853d5...216a`, `3a05ce5a...5a6f`). Canonical wall5.18345s; old affected tests ran as direct targeted native scripts, not a suite or campaign voyage.

Latest stable identities and exact deltas:

- Encounter: `62e0aa00ef732b59571e1782db83b4cc9531df7a3ecf6d1c5daf7acd2cf1a2c0`.
- Test: `68598d4926b2dc4df36b12ddb66bfc61d13b1bdd14276c2d0767c6f041940077`.
- Saved0de5 and its335-test bytes: `optout-encounter-before.gd` / `optout-test-before.gd`; saved latest Encounter: `optout-encounter-after.gd`.
- Exact0de5-to62 gate delta: `optout-production.patch`; exact original5cce-to62 complete stop delta: `stop-production-optout-final.patch`. All earlier diffs/results remain unchanged in scratch.

This final affected-regression verification supersedes earlier0de5 as the current candidate. Root has not frozen/started a new accepted actual first voyage yet. No full suite, complete voyage, GPU, old-test alteration, checkpoint exception or physical budget increase was performed. Independent closure and Root's fresh phase/suite/actual-return acceptance remain required.
