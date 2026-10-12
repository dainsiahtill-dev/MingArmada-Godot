# Safe final-navigation recovery: Task 1

Status: three independent-review P2 fixes implemented and focused checks passed; re-review/full suite/authoritative voyages remain root-owned. The first implementation was rejected and is preserved separately.

Authoritative inputs: [implementation plan](../2026-10-12-port-approach-and-voyage-clarity.md), [450s/750s audit](task-port-approach-pacing-audit.md), immutable [actual 29/0 first voyage](../../../migration/evidence/opening-story/journey-formal-manual-fire-return.json).

The new `tests/test_port_approach_recovery.gd` builds real Encounter/ship physics using recorded positions, headings, lateral velocities, native hull dimensions and loaded draft 1.6m, with the formal HeightField. This is an isolated regression fixture, not restoration of historical controller state or evidence of a new campaign voyage. Historical yaw, sails, tack, route cache and controls were not captured. Initial fixture velocity correction is confined to test setup.

RED command (from the writable `C:/Users/dains/Documents/Git/ming-armada`):

```text
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_port_approach_recovery.gd
```

Result: exit 1; `PORT_APPROACH_RECOVERY_TESTS assertions=66 failures=2`. Named expected failures:

- `750s safe final destination acquires bounded turn recovery instead of permanent stop`
- `real physics rotates recovering hull over ten seconds without pose correction`

The second assertion advances real physics 600 ticks. Other tests retain rejection for the 450s overlap, future crossing peer, wind restriction, dry/shallow sweep, old opt-outs, fast/remote/intermediate navigation and ownership/operational gates. Initial shell quoting caused a parse error before meaningful RED; it was corrected, and the reported RED has no script errors.

CodeGraph had already returned no index to root; discovery used scoped RTK reads. No full suite, GPU window, editor PID8384, historical evidence, save or Git state was modified. Root owns combined suite, actual voyage and native UI verification.

## Root ruling and final behavior

Root approved existing `Manual.build(... braking=true ...)` with furled sails; no new acceleration, thrust or yaw budget. Root fixed the acquisition zone at `25 < distance <= 55` and speed `<= .75m/s`, with both planning/reference flags, exactly one planned point matching current navigation, operational crew/hull/sails, no capture/lock/disable/manual/tactical ownership and no combat shortcut. Failed clearance retains old alternatives/stop behavior. The transient owner must stay bound to the goal and be revalidated each tick until within five degrees.

The old blocked branch still evaluates its original +/-60-degree alternatives. If those fail, the actual final course is considered through `approach_clearance.gd`. An accepted turn furls sails and submits the existing bounded steering/braking request. The transient owner prevents the old ahead cone becoming clear mid-turn from immediately restoring sail. At five degrees it releases to existing navigation. Actual integration, shore sweeps, ship contacts, arrival range/speed, cargo and save authority remain unchanged.

Effective changed controls while navigation exists revoke recovery for that goal. Idle/no-op controls do not create a fence; an authorized new goal via either navigation or policy reconciliation clears the obsolete fence, while routine same-goal reconciliation preserves a deliberate override. Navigation cancellation and service/operational authority changes clear the transient owner. A second RED run originally added revocation cases: 77 assertions, three failures for explicit controls, cancelled navigation and service lock. Independent review then found the broader idle-command bug; the revision below fixes it. `controlsSequence` cannot serve as this fence because `_apply_update` increments it during ordinary reconciliation. No new field enters serialized ship state.

## Prediction and limits

The module accepts detached numeric footprints/motion/bounds and terrain callback; it neither imports game/domain nor mutates vessels. Its decision is a finite prediction, not a guarantee about later peer decisions or future ocean behavior.

- Own turn: sample every <=2 degrees and expand by `hullCircumradius * 1 degree`, plus .15m clearance. Extend the angular range by measured `abs(yawRate)/yawDamp` to cover stopping yaw. Native nine-point wet-hull samples use the expanded footprint; native shore handling remains authoritative.
- Braking: available acceleration is `.2 * Manual.powerFraction * dryMass/loadedMass`, minus bounded crew lateral acceleration and hydraulic rudder acceleration at 1.2m/s. No beneficial drag credit. Residual drift radius is `v²/(2*availableBrake) + v/60`. Nonpositive available brake rejects.
- Enforced finite interval: fixed **60 seconds = 40 seconds maximum owned turning + 19 seconds stop reserve + 1 second outgoing travel**. Native tick counts enforce the forty-second limit; no assumption that full-rudder rate lower-bounds the actual proportional turn remains. Available translational stopping time and passive measured-yaw decay to .005rad/s must each fit 19 seconds. Neutral Manual damping adds no credit to this reserve. Timeout enters zero-rudder, furled, existing Manual braking. A holding vessel may reacquire only after speed<=.05m/s and |yaw|<=.005rad/s, with a fresh complete clearance decision.
- Outgoing interval: one second, using the existing .25/s sail-recovery ramp after the furled turn. Integrate the maximum sail force coefficient `1.4*pressureScale + CL + .08 + .08*CL² + .5`, where `CL=4.2*28deg`, actual sail area, actual speed multiplier and loaded mass. Crew/rudder bounds also enlarge travel. Predicted speed above 1.2m/s rejects. The travel footprint includes subsequent stopping distance and five-degree course error, ending at the actual target plus stopping envelope rather than assuming 45m beyond the port.
- Peer motion: continuous moving SAT intersects overlap-time intervals on all four rectangle axes using measured full vx/vz. Measured yaw is enclosed about the horizon midpoint by `peerCircumradius * abs(yawRate) * horizon/2`. This catches crossings between time samples. It conservatively compares each own turn orientation against the entire peer interval. New peer acceleration/commands can invalidate the prediction; every-tick revalidation and native collision handling are retained.

The first implementation overestimated outgoing motion as two seconds of full sail, rejecting the 750s scene as `swept-depth`; this was a real conservative rejection, not weakened terrain. The corrected one-second formula uses the actual existing sail ramp. The final 750s prediction reports horizon 60.0s, initial drift .00306855m, outgoing travel .103237m, stopping distance .357442m. A prediction/depth rejection during an owned maneuver retains a goal-bound neutral-braking hold even after the old forward cone clears. It does not resume sail through ordinary navigation. Actual manual/tactical/operational ownership changes still yield normally.

## Focused verification

All commands used the same exact prefix below, followed by the listed `res://tests/...` path; no command ran the full suite or overwrote central verification evidence.

```text
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script
```

| Script argument | Result |
|---|---|
| `res://tests/test_port_approach_recovery.gd` | 132 assertions, 0 failures |
| `res://tests/test_autopilot_port_approach.gd` | 24 assertions, 0 failures |
| `res://tests/test_reference_handling.gd` | 33 assertions, 0 failures |
| `res://tests/test_manual_sailing_assist.gd` | 11 assertions, 0 failures |
| `res://tests/test_naval_invariants.gd` | 72 assertions, PASS |
| `res://tests/test_arrival_berthing.gd` | 980 assertions, 0 failures |
| `res://tests/test_voyage_waypoint_handoff.gd` | 64 assertions, 0 failures |
| `res://tests/test_encounter_rules.gd` | source golden PASS (0) |
| `res://tests/test_ship_physics.gd` | 16557 assertions, 0 failures; oracle max error 1.455e-11 |
| `res://tests/test_naval_simulation.gd` | 51559 assertions, 72 cases, PASS |
| `res://tests/test_sailing_runtime.gd` | 13 assertions, 0 failures |
| `res://tests/test_sailing_input.gd` | 49 assertions, 0 failures |

All twelve focused commands were rerun after the three review fixes and exited 0 without script/parse errors. Aggregate counted assertions: 69494, plus the encounter golden comparison. No named remaining focused failure.

The real 750s fixture advances 600 physics ticks: heading .08184272 to .67573843 radians, speed .0000007619m/s. Continuing this isolated fixture reaches the unchanged 25m/.75m/s threshold at 46.0 simulated seconds with hull100/crew20 unchanged. The 450s turn remains rejected, as do moving-peer crossing, dry/insufficient draft, no-go wind, opt-outs, distant/intermediate/fast motion, exact unloading boundary, outside55m, combat and authority failures. This is not the historical voyage replay or an actual new campaign delivery: root must still verify voyage receipts, real cargo, saved continuation and user-facing pacing.

## Scoped review identities

Review patch: `task-port-approach-recovery.patch` alongside this report, generated against the preserved baseline, not inherited repository HEAD. Full patch is 439 lines; `task-port-approach-recovery-review-fixes.patch` is the 246-line delta from the first reviewed sources. Those sources are preserved under `build/port-approach-work/review-1/` with the original three SHA256 values from the independent review.

| File | SHA256 |
|---|---|
| `build/port-approach-work/encounter.gd.before` | `efa4a5e072b6b542eb872bd1cc3f6cf56e84290cc8bd7a1be01f7637dc9cfc5d` |
| `modules/naval_simulation/encounter.gd` | `51f6ba1eca84b5c925000c5db7d8a33b2718f9d770613263f9548e28c7d68faf` |
| `modules/naval_simulation/navigation/approach_clearance.gd` | `6a303f0ff243d446a4200fa06215959991ac1584250f03928764d905eac25df3` |
| `tests/test_port_approach_recovery.gd` | `94dee71d27ff2b5b0a23005e28e7b518ebfe693dff2ff6d76f32e33e87a387a0` |

## Independent-review repair evidence

The [independent review](task-port-approach-recovery-review.md) rejected the first implementation for three P2s. Actual native regressions verified all three before repair. The first expanded run reported 119 assertions / 10 failures, including two incorrectly placed hazard-fixture preconditions. Correcting only those fixture placements produced the meaningful **119 / 8 RED**:

1. `P2 idle Sailing controls followed by actual reconcile can acquire recovery`
2. `P2 no-op controls do not cancel navigation ownership`
3. `P2 authorized new goal clears only obsolete manual fence`
4. `P2 idle selected runtime vessel does not carry poisoned manual fence after departure`
5. `P2 predicted horizon covers actual native PD ten-to-five degree turn`
6. `P2 late crossing within true turn interval rejects and brakes owned turn`
7. `P2 owned peer clearance rejection stays furled with neutral bounded braking`
8. `P2 owned depth clearance rejection stays furled with neutral bounded braking`

The controls fix made the first four green, leaving 119 / 4. Timeout/reduced-power/opposing-yaw checks were then added before changing the horizon/holding policy: **130 / 7 RED**. The extra named failures were reduced-power loaded acquisition, forced braking after forty actual seconds, and full prediction for opposing native yaw. The fixed bound and holding policy produced 130 / 0, then the final real manual-handoff assertion/log produced **132 / 0**.

Root explicitly approved the revised 40+19+1=60 design before implementation. The twenty-second stop proposal was corrected by root so outgoing travel was not double-counted beyond the cap. No solver clone, new physical budget or user permission question was introduced.

Concrete final native evidence:

- Full-power merchant starts with ten degrees of error: real native proportional steering needs **8.25s** to reach five degrees. Old prediction was **6.3333s**, final prediction is **60s**. A peer crossing after the old interval is now rejected with neutral braking.
- Reduced crew10 and cargo100000kg: after **2401 actual native ticks / 40.0167s**, owner retains `startedTick=0`, enters `holding=true`, yaw remains **.00711962845rad/s**. Repeated requests cannot restart the clock while yaw exceeds .005.
- Opposing yaw comes from sixty actual solver steps with an existing negative Manual steering request; its prediction remains sixty seconds.
- Real `SailingSimulation.advance` emits idle controls, followed by real `Encounter.reconcileShips`; recovery succeeds. A separate real Runtime is configured, flagship selected, idled, actually departed and reconciled through Bridge; no poisoned fence remains. Deliberate same-goal override persists through reconciliation; a changed authorized goal clears it.
- Mid-turn peer/depth fixtures first acquire and advance native physics, then place the old blocker away to isolate a newly measured hazard outside the old cone. The remaining error is between five and forty degrees. Both refusals keep sail0, neutral target yaw and existing braking; real manual controls can supersede that holding state. These controlled fixtures are not campaign replay evidence.
