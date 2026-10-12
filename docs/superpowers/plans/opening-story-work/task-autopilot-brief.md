# Gameplay investigation: low-speed port approach

Writable root C:/Users/dains/Documents/Git/ming-armada. Every shell command rtk. No subagents, git mutations, GPU, sea/island/particle or performance work. Keep previous Story/Campaign/SaveCodec/UI frozen. Do not guarantee combat victory, weaken enemy fire, teleport, fabricate cargo or modify core physical constants.

## Actual evidence

`docs/migration/evidence/opening-story/journey-flat-outer.json` is a real Runtime captain-driver run after18m handoff repair, outer flagship route plus actual fast-vessel protect order. Grain-a genuinely delivered20 at439.93s, background delivered10 at448.3s. Grain-b remained underway past750s despite progress1. At750s position347.597/126.349, target282.150/107.486, velocity .186/.049; by780s it drifted353.170/127.858. At791.5s flagship was killed; this is a naive combat driver, not a demonstrated balancing defect.

Wind(-1,0)12m/s. Final grain-b hull68/sail96/crew16, target same, heading-1.4386, rudder-1, sails.1987. Flagship also struggled approaching from east: at750s309.68/129.93, velocity.155/-.216, target282.15/107.49. No terrain obstruction in this flat control, but other boats can affect avoidance.

Candidate seam: `_autopilot` lowSpeedTurn reduces sails to0 while needing>60°turn. `_tick_ship` provides existing `Manual.build(...)` steering recovery only to manualHandling actors, never autopilot. Low speed, tacking and avoidance may leave the AI unable to turn back into the wind/finish approach. This is a candidate, not a proven cause; diagnose and falsify first.

## Task and ownership

Read actual navigation/tack/control path and the record. Build deterministic real Encounter tests starting one healthy merchant at the observed approach position/heading/low speed under west wind, no enemies/other boats, flat sampler. Test actual accepted native ticks for recoverable approach into25m and≤.75m/s. Add an independent two-vessel collision case only if necessary to distinguish berth avoidance. A test starting pose is a unit fixture, not acceptance teleport.

Own `modules/naval_simulation/encounter.gd` controller logic only, optional small generic navigation helper under modules/naval_simulation/navigation, plus `tests/test_autopilot_port_approach.gd`. Physics implementation in modules/physics_engine stays unchanged; reuse existing bounded manual/steerage assist through controls if justified for referenceHandling=true, preserve default=false original oracle behavior. Existing `_wet_hull`/wet planner/avoidance must remain active. Arrival rule25m/low speed and business receipts remain authoritative. If evidence shows driver misuse rather than AI defect, report it and do not change production.

Report actual isolated RED, cause, smallest fix, GREEN, scoped old navigation/physics/gunnery/bridge/story-save regressions. Capture before files/diff/hash and write `task-autopilot-report.md` here. Root runs whole gameplay and final evidence. Initial diagnosis can precede implementation; let Root know exact hypothesis results.
