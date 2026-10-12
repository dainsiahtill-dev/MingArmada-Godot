# Tack route replan scoped report

Same-goal, same-draft, same-effective-leg successful refresh now keeps an unfinished safe tack. The old no-progress30s replan unconditionally erased it, making nearest-heading selection reverse an unfinished southwest turn.

## Proven mechanism and limits

Recorded989.8 horizontal pose/velocity/yaw and an explicitly hypothetical in-progress side+1 were held constant. Only `route.checked` changed from fresh to expired. Baseline erased+1 and chose−1, changing helm from+1 to−.5703206. Historical tack and previous-controller state are absent, so this is a mechanism counterexample, not an exact replay of the original historical side.

`_keep_tack_after_replan` requires successful nonempty plan, equal goal/draft/effective first point, current controlled ownership without manual/tactical takeover, and the retained side's actual150m wet-hull corridor. Changed identity, failure, empty route and unsafe side clear as before. `_tack_course` retains existing wind and leg-completion rules. The actual45m waypoint pop still clears tack; an old multi-point route whose first point is already within45m also cannot preserve tack even if the new Planner simplifies that point away. No route generation, speed, wind threshold, deadline, Egress, Approach, old units or QAtools changed.

## Verification

- Baseline Encounter is `build/port-approach-work/tack-route-replan/encounter.preedit.gd`, expected SHA256 `c3a87bed5f145cf7041e1240a2db065233ca629a343d8814db25502406d844e0`.
- TDD RED:6 assertions,2 expected failures, exit1: `same safe goal/leg/draft replan keeps unfinished tack side` and `only checked expiry cannot reverse helm on equivalent leg`. Original RED was observed in session tool output, not separately saved to a log.
- Independent review exposed an expired replan swallowing the old near waypoint. Added test was RED35 assertions /1 failure (`expired replan cannot hide an old45m waypoint advancement`), exit1; one explicit old-near-first guard made it green.
- Final GREEN:35 assertions /0 failures. `tests/test_tack_route_replan.gd` checks the one-variable expiry case, goal/leg/draft/failure/empty/manual/tactical replacement, current unsafe side, original wind/45m pop behavior including expired simplification, retained leg counter and normal settling reset, and actual60-tick sailing advancement.
- Fresh log/hash evidence: `build/port-approach-work/tack-route-replan/unit.log`, `unit.json`.
- Scoped two-file patch: `build/port-approach-work/tack-route-replan/task.patch`; reverse-check recorded after creation.
- Existing approach candidate regressions: `test_autopilot_port_approach.gd`24/0; `test_port_approach_recovery.gd`132/0, actual46s arrival/40s timeout retained. Both loaded before the final one-line old-near-waypoint guard, so final frozen-source broad verification belongs to parent.
- Final Encounter SHA256 `5a86e578f41846b90ccd21c74f89518c6994441ce9beb2018bcfefc5fe7698e9`; final unit artifact matches. Patch reverse-check exit0. Parent owns full suite and actual first-to-second on-time delivery; no campaign/GPU outcome claimed here.

Independent review and actual voyage remain parent acceptance gates. No Git commit made.
