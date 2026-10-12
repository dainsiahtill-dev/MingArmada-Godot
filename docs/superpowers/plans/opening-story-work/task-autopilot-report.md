# Opt-in low-speed navigation steering recovery

Status: controller source and selected regressions frozen. Root owns whole-game journey, independent review and formal-terrain/GPU acceptance. No journey tool, Campaign/Story/SaveCodec/UI, physics source, enemy weapon, cargo, arrival rule, sea/island/particle, export, performance setting, or Git state was changed by this task.

## Isolated diagnosis and falsification

The actual `journey-flat-outer.json` establishes healthy grain-a delivery20 and background delivery10 after the earlier waypoint repair, while grain-b overshoots the final port and spends a long interval approaching from the east. The flagship later dies under enemy fire. This is not treated as proof of a balancing defect or as a mandate to guarantee combat victory.

`test_autopilot_port_approach.gd` builds a real single merchant Encounter, no enemies or other ships, flat -24m sampler, no waves, west wind(-1,0)12m/s. Unit starting position(347.597,126.349) is based on the observed approach; headings are -1.4386, 0 and PI; starting speed .2m/s, normal20/30 crew, hull/sail100, actual merchant draft1.6m and cargo mass2000. Navigation targets the real Kinmen port position. It accepts native ticks at1/60s until the real distance≤25m and speed≤.75m/s arrival condition, or600s. This fixture is not an acceptance teleport or fabricated delivery.

The RED run disproves a claim that every starting orientation is permanently stuck: the observed -1.4386 orientation eventually reaches the boundary after557.05s. It also proves an isolated controller problem beyond enemy fire or berth avoidance: headings0 and PI fail to reach the same boundary within600s, with nearest distances68.11m and48.73m. `lowSpeedTurn` is active for282.9s,468.6s and310.97s respectively, repeatedly lowering sail deployment to0.

Source trace: `_autopilot` lowers sails for low-speed large turns; native ship controls pass `Manual.build` only for explicit `manualHandling`. Autopilot lacks the already-available bounded low-speed steering response and can spend minutes losing sail drive while trying to turn into a feasible tack. Single-boat reproduction establishes this without needing a speculative two-vessel collision fix.

`autopilot-red.json`: meaningful12 assertions /2 failures, with complete real native positions, velocity, heading, rudder, sail deployment and tack observations every10s.

## Minimal controller-only repair

Owned production file: `modules/naval_simulation/encounter.gd` only.

- `_autopilot` now returns an optional existing `Manual.build` steering request. Default `referenceHandling=false` returns no request and retains the original controls/oracle behavior.
- The request is limited to reference handling, speed<1.2m/s (existing low-speed seam), heading error>5°, operational uncaptured crew/hull, and an unblocked course. It uses the actual hull kind, current rudder, speed, crew fraction, hull fraction and sail fraction. Existing Manual.build yaw/acceleration/power budgets are unchanged; no drive/throttle is added and braking=false.
- `_wet_hull` checks all swept recovery hull orientations at≤10° steps plus15/30/45m of the outgoing course. The existing tack selection, wet route planner and ship avoidance continue to run; a blocked course or unsafe rotation cannot obtain recovery.
- `_fixed_tick` keeps requests in a local dictionary for the current tick and consumes them through the existing `controls.manualAssist` interface. There is no saved story/navigation field, lingering manual authority or persistent recovery state. Locked/disabled ships remain excluded by the existing native authority gates.
- Recovery does not act in the final stopping radius: original planned18m / non-planned30m. Intermediate wet-planner points may continue normally.

A follow-up boundary RED, `autopilot-red-braking-boundary.json` (24 assertions /1 failure), caught using18m for the non-planning30m case; a one-line controller guard now follows the same existing mode-dependent braking rule. This does not change the formal routePlanning=true timings below.

## Actual isolated outcomes

| Initial heading | Before | After | lowSpeedTurn time before→after |
| --- | --- | --- | --- |
| -1.4386 | arrival557.05s | arrival179.30s | 282.9s→23.33s |
| 0 | no arrival by600s | arrival226.73s | 468.6s→43.75s |
| PI | no arrival by600s | arrival206.27s | 310.97s→22.32s |

All three after cases end with unchanged hull100, sail100 and crew20. They reach the real arrival boundary at speed about.48m/s; no position, health, cargo, stock or victory is altered during the run. Exact native diagnostics are preserved in the JSON evidence; `autopilot-metrics.json` contains a compact before/after extraction.

## Final selected verification

Godot `4.7.2.stable.official.ed1daf0bf`; direct command pattern:

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_autopilot_port_approach.gd
```

The same prefix ran these exact selected regression scripts; `autopilot-green.json` preserves complete outputs and exit codes without touching Root's final `verification.json`.

| Test | Result |
| --- | --- |
| test_autopilot_port_approach.gd | 24 assertions,0 failures |
| test_naval_simulation.gd | 51,559 assertions /72 original cases,PASS |
| test_ship_physics.gd | 16,557 assertions,0 failures; max oracle error .00000000001455 |
| test_reference_handling.gd | 33 assertions,0 failures |
| test_reference_gunnery.gd | 42 assertions,0 failures |
| test_near_field_bridge.gd | 13 assertions,0 failures |
| test_voyage_waypoint_handoff.gd | 64 assertions,0 failures |
| test_opening_story_save.gd | 122 assertions,0 failures |
| test_save_compatibility.gd | original v2/forged-save cases PASS(0) |
| test_mingqi_rules.gd | original full Campaign/navigation/business golden PASS(0) |

All ten selected scripts exit0, no Godot error diagnostics. Counted tests total **68,414 assertions,0 failures**, plus two original fixture/oracle suites PASS(0). The new boundary tests exercise existing merchant numeric limits, default-false absence, blocked/dry recovery rejection, planned and non-planned stopping ranges, zero heading error, captured/locked/disabled authority and actual accepted-tick approaches.

## Source review artifacts and limits

- `encounter.gd.autopilot-before`: pre-edit controller source, including the previously frozen18m navigation repair.
- `autopilot-scoped.patch`: only this controller repair plus the complete new test.
- `autopilot-source-hashes.json`: final two-file hashes, unchanged previous Domain/Navigation sources/tests, and unchanged physics source hashes across verification.
- `autopilot-green-initial.json`, `autopilot-green-boundaries.json`: initial12/0 and boundary23/0 stages; the final run is24/0 after the non-planning braking guard.

The isolated fixture uses rounded observed position/heading and native constructor speed; it does not restore the exact recorded leeway velocity, wave state, damage or neighboring boats. It proves a control seam and bounded recovery for the tested conditions, not every berth or wind arrangement. Existing wet-planner/collision safety remains active, but multiple-vessel berth behavior is not newly certified here. No claim is made about flagship survival or enemy balance. Root must continue the real tactical journey and formal-terrain review with actual game inputs and receipts.
