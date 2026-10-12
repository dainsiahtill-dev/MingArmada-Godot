# Wet route egress scoped report

Status: low-speed connector implemented and scoped regressions green; this late recovery alone does not satisfy the playable second-voyage goal. First recorded full-envelope window2489.8 is later than the actual deadline1799.8. Complete campaign voyage, on-time twenty-unit delivery and GPU acceptance are not claimed; parent has paused full-voyage rerun pending the upstream steering/tack cause.

## Root cause and bounds

The original WetRoutePlanner requires a circle of radius 26.68154m for the grain vessel. Recorded late-state actual 36×10m hull is wet while its planning circle is unsafe; empty route returned before navigation steerage. The implementation retains Planner's endpoint, terrain, draft, sample-budget and smoothing contracts.

`wet_route_egress.gd` separately proves a directed 32m neighbor connection (diagonals ≤46m), current native nine-point hull, complete shortest yaw sweep, residual yaw/braking drift, half-meter translation footprints, heading error and stopping reserve. Each actual nine-point footprint is retained and each point has a 3×3 uncertainty neighborhood, plus the expanded nine-point footprint. This is a conservative discrete terrain sampling contract, not a mathematical guarantee for every possible arbitrarily thin terrain feature. A thin patch exactly at the original corner and nonzero-yaw current corner are regression tests.

Continuous moving SAT encloses every live peer over a bounded 259-second turn/travel/stop horizon. Peer controls/environment changes remain modeled only by fresh measured velocity/yaw; Encounter rechecks every owned tick and native shore/contacts stay active.

Only planned/reference navigation with trusted existing control, live hull/sails, no combat/tactical/manual/service/disabled/captured state and crew ≥25% can acquire. Speed cap is .35m/s, travel sails ≤.1, turn/overspeed hold uses existing furled Manual braking. Failed acquisition retries after two seconds; owned clearance failure/time limit latches neutral furled hold. Ownership is separate from ordinary route points, so the 45m pop cannot discard it. Actual-position original Planner success is required for handback.

Changed goal/draft/control authority retires ownership. Cancel/reconciliation removes old rudder/sail output; explicit manual controls preserve the new user's rudder/sails. Removed hazard does not automatically reopen sails.

## Evidence

- Preedit baseline: `build/port-approach-work/wet-route-egress/encounter.preedit.gd`, SHA256 `51f6ba1eca84b5c925000c5db7d8a33b2718f9d770613263f9548e28c7d68faf`.
- TDD RED: original code exact2999.8 fixture, 5 assertions, one expected missing-owner failure. Original Planner rejects; actual hull wet.
- Final scoped unit: `tests/test_wet_route_egress.gd`, 61 assertions / 0 failures. Fresh log and exact source/fixture hashes in `build/port-approach-work/wet-route-egress/unit.log` and `unit.json`. Includes exact high-speed1049.8 rejection, dry-turn1064.8 rejection, full moving peer crossing, dry target, yaw reserve, thin shallow corner, nine authority changes, actual five-second native continuous turn, travel cancel/manual/reconciliation, and held-hazard behavior.
- Existing `tests/test_port_approach_recovery.gd`: 132 assertions / 0 failures, actual46s arrival, actual40s timeout and existing authority/peer/turn behavior preserved.
- Pre-final-current-depth-guard candidate diagnostic: exact2999.8 actual continuous7731 ticks =128.85s handback, all actual hull samples wet, max speed .35014474. True handback position `(17.272283,426.154485)`. The runtime was loaded before the final explicit current-depth guard; this is candidate diagnostic evidence, not final frozen-source evidence.
- Final-source isolated recorded snapshots: first southern32m full new envelope pass at2489.8, position `(13.396430,431.351864)`, padding1.860298. `recorded-windows.json`,96 rows. No continuous-voyage claim.
- 1049.8 scalar-fixture natural full Encounter step probe includes existing shore/contact and starts from recorded peer poses/velocities/yaw/controls/draft/cargo/permissions. The fixture retained recorded sail/rudder controls before this natural probe started, unlike the earlier2999 diagnostic which furled all initial sails. Old tack, prior solver/controller state and Bridge/campaign reconciliation are unavailable, so this is not a replay of the original runtime environment. At600.0167 accepted seconds still blocked, position `(11.667475,431.308462)`; at800.0167 still blocked, `(12.133987,431.397064)`. Parent explicitly stopped the probe after this last observed stage because the known safe window already exceeded the real deadline. `natural-partial.json` records termination and missing final aggregate. This runtime loaded before the final explicit current-depth guard and remains candidate diagnostic, not final frozen-source handback evidence.

## Rejected unsafe extension

1049.8 recorded speed1.000673m/s exceeds egress admission. A proposed neutral stopping extension was removed. In a separate exact native-core diagnostic without shore projection, neutral brake reached a dry actual hull at96ticks; south turn+brake at74ticks, north/east at118ticks, west at85ticks. The rejected analytic straight-line stop also omitted keel-induced lateral path changes. No unproved high-speed stop remains in production.

## Scope and verification limits

Product edits are only `encounter.gd` and new `navigation/wet_route_egress.gd`; new scoped test and plan/report/probes/patch accompany them. Existing Approach module unchanged. No arrival, deadline, draft, campaign, cargo, vessel pose correction, reward, sea/particle/performance configuration, Git commit or deployment change.

Final frozen-source full suite and actual first-to-second voyage must still establish whether the safe recovery window permits on-time delivery. The late recorded window is not evidence of that outcome. Parent owns final full suite, source inventory freeze, actual voyage and GPU evidence.

Independent scope safety review closed the identified current-pose, original-corner sampling and cancellation/manual/reconciliation issues, with no remaining P1 within this low-speed scope. Reviewer did not approve complete voyage recovery. Scoped cumulative patch includes only the three source/test files; `git apply --reverse --check` passed against current working files. No commit made.
