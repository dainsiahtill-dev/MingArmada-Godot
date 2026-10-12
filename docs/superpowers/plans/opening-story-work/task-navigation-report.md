# Transport intermediate waypoint handoff

Status: minimal navigation fix and directed verification frozen. Root owns the full real journey and GPU/playability acceptance. This task did not edit Campaign, Story, SaveCodec, physics, stock/unload thresholds, water/islands/particles, or enemy gunnery; it did not spawn agents, open GPU windows, export, or mutate Git.

## Root cause confirmed

The existing `journey-flat.json` shows the healthy grain-a transport remaining near (149–150,79–83), about 14–16m before catalog waypoint (164.4685239455,78.3321223618). Its business leg remains 1, projection progress about .963, while native navigation retains that same waypoint.

The directed test reproduces the mismatch using real Campaign/Runtime/NearFieldBridge/Encounter projection. A deterministic unit-fixture position (150.4685239455,78.3321223618) is 14m before the intermediate point. Campaign's unchanged exact projection returns leg 1 / progress .9626378842. The old bridge targets that intermediate point as a final single native destination, so native route-planning autopilot's existing 18m braking rule lowers sails before the exact projection can reach 1.

`navigation-red.json` records a meaningful **47 assertions / 3 failures**, with no parse or constructor error: the actual native target is wrong, the ship does not sail through the stalled point during 1200 subsequent ticks, and the 18m handoff boundary is missed.

## Repair and ownership

- `modules/contracts/navigation_contract.gd` names `PLANNED_TARGET_REACH_METERS = 18.0`.
- `modules/naval_simulation/encounter.gd` substitutes that shared constant for the existing literal 18 in planned-target braking. The value and all autopilot/physics/control behavior remain unchanged; the non-route-planning 30m branch is unchanged.
- `game/runtime/near_field_bridge.gd` retains exact `Campaign.locate_route`, then advances **only the native target index** by one when the target is intermediate and the actual synchronized vessel position is inside the same inclusive 18m reach. The final port target is never skipped.

The existing native wet planner still plans from the actual ship position to the newly selected point. The fix changes no pose, ownership, cargo, escorts, permission, current controls, voyage status or arrival receipt. `fresh_startup` still assigns navigation null before any route selection. Outside the reach radius, the old target is retained.

The actual business arrival rule remains distance≤25m and speed≤.75. The tests verify that final approach at 14m and 2m/s cannot unload; low speed at 26m also cannot unload; low speed at 14m still produces the normal arrival receipt and conserved +20 grain port stock. Those initial positions are explicitly unit fixtures, not acceptance teleports or fabricated journey delivery.

## Verification

Godot `4.7.2.stable.official.ed1daf0bf`; each exact test was launched headless with:

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_voyage_waypoint_handoff.gd
```

The same command prefix ran the seven regression script paths below. Complete stdout/stderr and exit codes are in `navigation-green.json`, leaving Root's final `verification.json` untouched.

| Exact test | Final result |
| --- | --- |
| test_voyage_waypoint_handoff.gd | 64 assertions, 0 failures |
| test_near_field_bridge.gd | 13 assertions, 0 failures |
| test_naval_simulation.gd | 51,559 assertions / 72 source cases, PASS |
| test_native_readiness.gd | 16 assertions, 0 failures |
| test_mingqi_live_projection.gd | 9 assertions, 0 failures |
| test_mingqi_rules.gd | original full state/business/navigation golden PASS (0) |
| test_save_compatibility.gd | original web-v2 and forged save cases PASS (0) |
| test_opening_story_save.gd | 122 assertions, 0 failures |

Eight selected scripts all exit 0 with no Godot error diagnostics. Counted tests total **51,783 assertions, 0 failures**, plus two original fixture/oracle suites PASS (0).

The 14m case now supplies the following target (282.1499288930,107.4856871973) immediately. Over 1200 actual native ticks and about20 accepted seconds, the transport sails more than14m along the following leg and through the formerly stalled point, while hull remains100 and its actual20 grain remain aboard. The existing native wet route planner remains active. Exact18m and outside19m cases, final target boundaries, preserved controls/permission/pose/cargo/escorts and fresh startup are covered.

## Reproducible diff and limits

- `near_field_bridge.gd.navigation-before` and `encounter.gd.navigation-before`: pre-edit owned source snapshots.
- `navigation-scoped.patch`: only this task's source changes plus complete new contract/test.
- `navigation-source-hashes.json`: final changed-source hashes and a true unchanged-SHA check for every previously frozen Campaign/Story/SaveCodec source and domain test.
- `navigation-green-initial.json`: first GREEN 47/0; final test adds explicit controls and real final-arrival boundary checks, reaching64/0.

This is a focused continuation/arrival-contract fix, not a claim that the flagship will survive combat or that a naive automated driving script demonstrates good tactics. No enemy, cannon damage, health, speed, victory or delivery was weakened/injected in production. The earlier full journey's enemy-fire sinking remains an honest gameplay outcome. Root should rerun the full actual journey to assess continuity amid terrain, escorts and combat separately.
