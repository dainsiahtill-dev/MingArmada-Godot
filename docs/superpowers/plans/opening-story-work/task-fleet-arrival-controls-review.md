# Fleet arrival controls: independent Spec / Quality review

2026-10-12. Reviewed Encounter `5cceb84d487858d5374edf7cb909e519e1b0b8b27b48a082efdc49868ec57290` and final regression test `4d00a6c67a893ca9f76933cd7321279c2adc30477e5991ff812ceeb6a49c66bf`. Review writes are restricted to this report and `build/second-aftermath-work/fleet-arrival-review/`. No production, tests, QA, original voyage evidence or Git mutations. CodeGraph independently confirmed no project index; RTK fallback used.

## Blocking finding and action

**[P1] `Encounter._tactical_tick:604-611`: terminal neutral cleanup releases Rally ownership before the real recorded B has physically settled.** Neutral output repairs the old helm lifecycle, but is insufficient to retain the returning carrier at Xiamen while the flagship finishes. Independent native simulation from the genuine 2156.6 recorded B fixture starts at distance 21.88093m, speed 0.547474m/s, yaw 0.000832635rad/s. With new terminal rudder/sail output zero, B is **69.202872m from the same port goal after 360 accepted native seconds**, speed 0.177337m/s, yaw 0; at 400 seconds it is **75.920593m**, speed 0.159333m/s. Both exceed the existing 55m port eligibility radius, and `is_anchored` remains false. Actual historical flagship docking occurred approximately 361 seconds after this B fixture. Do not freeze this candidate as a sufficient return repair or spend a fresh full voyage assuming cleanup alone resolves it.

Action: keep physical settling under an explicit current owner, or another narrowly authorized native stop transition, and prove its stopping distance with the existing bounded controls before releasing the owner. Root must decide/test the precise lifecycle; do not write velocity/pose/yaw, expand braking budgets, loosen Save/port gates, reset every idle ship, or alter QA captain intent to conceal the result. Same-goal supersession and fresh queued helm/sail input must still revoke the old owner before further stop output.

Evidence: `build/second-aftermath-work/fleet-arrival-review/b-neutral-coast.gd`, `b-neutral-coast.json`, `b-neutral-coast.native.log`. The probe has 7 fixture/control assertions, zero failures and exit 0; that status proves a valid executed counterexample, **not** a successful berth. All three recorded peers remain present. Their active orders `continued-voyage-5` and `continued-voyage-7` are restored from actual accepted order commands/statuses. No peer is removed, and the probe never directly corrects physical state after initialization. Native shore/contact routines continue for all 24,000 accepted ticks. All B sampled/tick hull footprints remain wet, rudder/sails remain neutral, and hull/sail/crew remain 100/100/20. Native contact routines do not emit contact events, so the empty event buffer is not a claim of zero contacts. This is a four-recorded-ship scalar reconstruction, with explicitly linearized unrecorded previous heading and no restored unrecorded tack; it is not an exact historical tick replay or campaign voyage acceptance.

| Native seconds after fixture | Distance to original goal, m | Speed, m/s | Yaw rate, rad/s | Rudder / sails | Anchored |
|---:|---:|---:|---:|---|---|
| 0 | 21.880933 | 0.547474 | 0.000832635 | 0 / 0 | false |
| 1 | 21.338836 | 0.542708 | 0.000482460 | 0 / 0 | false |
| 10 | 16.664177 | 0.503510 | 0.000003610 | 0 / 0 | false |
| 60 | 5.059582 | 0.359381 | approximately 0 | 0 / 0 | false |
| 120 | 23.253931 | 0.267497 | approximately 0 | 0 / 0 | false |
| 240 | 49.131922 | 0.176994 | 0 | 0 / 0 | false |
| 360 | 69.202872 | 0.177337 | 0 | 0 / 0 | false |
| 400 | 75.920593 | 0.159333 | 0 | 0 / 0 | false |

The input stage's narrative simulation time is 2156.6; the preserved native core/Encounter epoch starts at 1575.0. The table uses accepted elapsed native seconds, not a fabricated narrative clock.

## Spec review of the bounded control change

Within the two output-lifecycle seams, no additional P1/P2 implementation defect found. The physical-stop insufficiency above is a blocking requirement gap for the intended actual fleet-return repair.

- Completed Rally neutralization is inside the normal current completion branch. It clears navigation/decision and obsolete route/tack/low-speed/sail-recovery/recovery fences without invoking service anchoring or changing physical state. Unsafe/target-loss outcomes retain existing semantics.
- Generic `_cancel_order` is unchanged. Native controls validate/write the new request before cancellation, and removed participants cannot receive old completion cleanup. Queued player and non-player controls, sail-only change, invalid controls, unchanged controls and superseding orders are covered by the new real `Sailing`/Encounter regression.
- A reached participant of a shared Rally uses the current completed decision's unchanged `<25m` and `<1m/s` condition to hold neutral while the team record and navigation remain active. The unreached participant continues. A later tick recomputes the decision, so there is no permanent completed-participant cache or old-owner authority inheritance.
- Ordinary final navigation preserves its goal at the existing planned 18m / unplanned 30m radius. An intermediate route is not treated as final. Protect hold requires current active membership, exact current decision/navigation equality, no fire decision, an actually anchored target, and both route-planning/reference-handling capability flags. Moving protected targets, departure and threats resume existing tactical behavior on re-evaluation. Other tactical intents are excluded.
- `_controlled`, live hull/crew/sail, capture, manual-handling/manual-fence and terminal-status checks constrain the new hold. Existing recovery owners have precedence: Egress is handled before the new branch, empty/blocked routes return earlier, and existing Approach state explicitly excludes the new hold. Existing Approach/Egress authorization, clearance, wind/depth/peer predicates and budgets are unchanged.
- The new normal hold requests neutral coast and returns no assist. No native brake or physics constant is added. `Manual.build`, solver yaw/brake budgets, native shore/contact paths, business arrivals, rewards and Save predicates remain outside the delta.

## Quality and provenance

The delta stays inside Encounter's existing navigation/tactical ownership. Two small helpers share neutral output cleanup and express the current hold policy; no new persistent owner cache, unrelated feature or cross-layer authority is introduced. No documented-standard breach or actionable new design smell found.

Independently reconstructed `production-independent.patch` from the supplied before snapshot and current live source; it matches `fleet-arrival-controls/production.patch` after newline normalization. The exact recovered-before bytes hash to the already audited frozen source `0910d581c7a5f4642edc9d3ddcb826a9b42f5936655be441f1527458526c9df9`, and live bytes equal supplied after bytes. This verifies the recovered baseline; no production revert was performed. `source-audit.json` records both hashes and the patch identity.

Final regression preflight pins the genuine 82/1 fixture SHA256 `191170ccf22ab26dfd00521c3ea2ff6933e30c2c24b98d575e7ea856b2a3c037`, validates a readable Dictionary and exits 1 before constructing fixtures if it is missing, unreadable, changed or invalid. It cannot silently substitute a different same-count pose. The original failed record remains unchanged.

## Executed independent targeted verification

Eleven unique scripts executed with official Godot 4.7.2 headless; all exit 0, no script/parse/error diagnostic, **52,129 assertions**, zero failures. Every accepted batch independently hashes Encounter, OrderController, Manual/physics solver and frozen fixture before/after, confirming stable source/fixture during its run. Test copies preserve all assertions and inputs; only output destinations move into the review run folder for scripts that otherwise overwrite old `unit.json` artifacts.

| Script | Assertions | Actual result |
|---|---:|---|
| `test_fleet_arrival_controls.gd` final pinned version | 88 | exit 0, failures 0 |
| `test_manual_sailing_assist.gd` | 11 | exit 0, failures 0 |
| `test_reference_handling.gd` | 33 | exit 0, failures 0 |
| `test_autopilot_port_approach.gd` | 24 | exit 0, failures 0 |
| `test_port_approach_recovery.gd` | 136 | exit 0, failures 0 |
| `test_sailing_input.gd` | 49 | exit 0, failures 0 |
| `test_wet_route_egress.gd` | 68 | exit 0, failures 0 |
| `test_tack_route_replan.gd` | 35 | exit 0, failures 0 |
| `test_navigation_course_safety.gd` | 54 | exit 0, failures 0 |
| `test_naval_simulation.gd` | 51,559; 72 reference cases | exit 0, pass |
| `test_naval_invariants.gd` | 72 | exit 0, pass |

Valid run manifests, terminal/native logs and redirected unit reports:

- `batch-1-20261012-075752-920/manifest.json`: manual/handling; earlier new-test 87/0 kept as historical targeted run only.
- `batch-2-20261012-075853-832/manifest.json`: autopilot/Approach/input.
- `batch-3-20261012-080022-092/manifest.json`: Egress/tack/course.
- `batch-4-20261012-080208-861/manifest.json`: fresh reference oracle/invariants.
- `batch-5-20261012-075951-514/manifest.json`: final pinned new-test 88/0.

Commands are recorded verbatim per manifest. Runner invocation: `rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File build/second-aftermath-work/fleet-arrival-review/run-targeted.ps1 -Batch <number>`. Native coast command: `rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://build/second-aftermath-work/fleet-arrival-review/b-neutral-coast.gd --log-file C:/Users/dains/Documents/Git/ming-armada/build/second-aftermath-work/fleet-arrival-review/b-neutral-coast.native.log`.

An initial oracle harness run `batch-4-20261012-075655-223` executed the scripts successfully but its child PowerShell lacked `Get-FileHash`, leaving invalid empty provenance fields. It is retained, discarded from evidence totals, and replaced by the fresh valid oracle run using .NET SHA256. No failed or superseded result was overwritten.

Reference oracle compatibility is proven for its existing six order types, native/navigation snapshots and command atomicity. Its remote Rally does not cover terminal stopping distance; those 72 cases cannot invalidate the independent B coast counterexample. No full suite, first/second voyage, checkpoint, native aftermath UI, Save/Continue or GPU acceptance is claimed by this review.

## Follow-up final review: bounded native stop, candidate 62e0aa00

**No outstanding P1/P2 Spec/Quality finding remains in the bounded repair.** This appended conclusion applies to Encounter `62e0aa00ef732b59571e1782db83b4cc9531df7a3ecf6d1c5daf7acd2cf1a2c0` and test `68598d4926b2dc4df36b12ddb66bfc61d13b1bdd14276c2d0767c6f041940077`. The earlier neutral-only finding and every failed/intermediate artifact above remain historical evidence. Root may freeze this source for its fresh full suite and actual voyages; this review does not accept the full game or fleet return.

Three demonstrated gaps are now closed:

| Finding | Actual failing evidence | Final independent closure |
|---|---|---|
| P1: neutral-only B stopping distance | 5cce native400s: 75.920593m, speed0.159333, not anchored | 62e0 native400s: 8.905612m, speed0.0278071, anchored; owner retired at3.683333s |
| P2: valid health/physical changes retain old stop | 763d public-update probe46/6: positive crew/hull/sail/cargo/speed/steering changes accepted but owner retained | 62e0 exact probe46/0; successful normalized capability changes revoke, no-op/invalid inputs preserve |
| P2: route-planning opt-out still receives new brake | 0de5 old autopilot24/1 and Approach136/1, both real exit1 with stable source | 62e0 same unchanged old tests24/0 and136/0, both fresh exit0; unplanned final hold coasts neutrally with no new assist |

Direct locked/disabled request checks pass through the existing `_controlled` policy. The earlier suspicion of a missing service gate was corrected; it was not a source defect and no duplicate permission rule was added.

The final scope is Encounter plus focused regression coverage. A genuinely completing current Rally keeps its completed receipt and unchanged25m/<1m/s decision, then hands its exact original navigation goal to a wrapper `terminalStop` containing battle/ship/order/goal/draft/start/deadline. Eligible controlled, healthy, planned/reference, wet, noncombat ships consume the existing neutral `Manual.build` brake before ordinary autopilot. Its deadline is exactly3600 accepted ticks/60 seconds; paused time cannot reset or consume it. It first publishes the neutral owned navigation across a native tick, then retires after native physics/shore/contacts only when speed<=0.05 and abs(yaw)<=0.01. Retirement/timeout/revocation removes only still-owned matching navigation and metadata. Timeout cannot rearm the old completed order or force anchoring.

Accepted changed controls/navigation/orders/service/policy/health/dimensions/stats revoke the old owner without overwriting the newer request. `_apply_update` compares normalized before/after capabilities only on successful commit; invalid projection remains atomic. Unchanged projection, idle controls, benign nullable manual clear and controls-sequence increments retain the exact start/deadline. Existing Approach/Egress owners, intermediate/blocked routes and their clearance predicates retain priority; both planning/reference capabilities now gate the shared new physical brake. No physics budget, force formula, anchor/port/Save threshold or Codec field changed.

Fresh final-source evidence is under `build/second-aftermath-work/fleet-arrival-review/`:

- `b-bounded-stop-62e0.json` and matching native log: actual400-second all-recorded-peer native continuation,13/0, exit0. Before/after creation motion is identical. All tick samples are wet/neutral/inside55m, health remains100/100/20, old owner never rearms. At400s distance8.905612m, speed0.0278071, yaw approximately zero and actual `is_anchored=true`. No anchor API or post-step fixture correction is used. Normal native contact resolution remains active; the fixture does not claim zero contacts.
- `stop-transition-62e0-green.json`:46/0, exit0, with the original `stop-transition-red.json`46/6 preserved. It exercises real successful public updates, current permission direct requests, unchanged/invalid updates and nullable handling.
- `stop-lifecycle-extra-62e0-green.json`:20/0, exit0. Selected Sailing starts before completion with cached rudder0.7/sails0.4 and native speed0.04; six substeps in one `advance(0.1)` retire safely without old-control resurrection. Calling `advance(120.0)` while paused consumes no native ticks and retains deadline. Real Runtime/Bridge rejects export during settling; after physical retirement, real export, Runtime re-adoption and re-export succeed without reconstructing or encoding stop metadata. No Storage write occurs.
- `stop-test_fleet_arrival_controls-20261012-083712-086/manifest.json`: fresh final canonical337/0; `stop-test_autopilot_port_approach-20261012-083712-451/manifest.json`:24/0; `stop-test_port_approach_recovery-20261012-083712-729/manifest.json`:136/0. Each exits0 with stable final Encounter/test/common-source/fixture hashes and no script/parse/error diagnostic.

The ten unaffected targeted PASS records from the immediately preceding0de5 source remain accepted after independently reviewing the exact one-line opt-out guard delta; they were not rerun wholesale. They cover manual11, reference handling33, naval invariants72, reference oracle51559/72cases, Bridge13, berthing980, sailing input49, Egress68, tack35 and course54. Combined with the three fresh final-source scripts, this is **13 accepted targeted scripts,53,371 assertions,0 failures**, plus **79 fresh final-source probe assertions**, totaling53,450 accepted assertions. Both0de5 failed opt-out manifests and all earlier candidates remain preserved and excluded from PASS totals. Root owns the upcoming new113-script full suite.

`stop-62e0aa00-source-audit.json` and its independently rebuilt patch prove live bytes match the supplied final snapshot and the complete5cce→62e0 delta. OrderController, Manual/physics solver, Sailing, Bridge, Runtime, Codec and the immutable191170cc…a3c037 fixture are byte-identical to the reviewed prior source. `results-62e0aa00.json` records per-script source version, exact commands, logs, fresh probes and aggregate counts; it explicitly distinguishes retained unaffected0de5 evidence from freshly executed62e0 evidence.

Limits remain: recorded scalar/previous-heading reconstruction is not an exact historical tick replay; only the recorded peers are present. These checks establish bounded controller stop and owner/Save closure. They do not replace a fresh full suite, actual first/second voyages, real full-fleet checkpoint, native aftermath choice/Save/Continue captures or GPU/graphics acceptance.
