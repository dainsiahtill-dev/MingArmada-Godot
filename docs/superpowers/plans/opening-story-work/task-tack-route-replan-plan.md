# Tack Route Replan Implementation Plan

> **For agentic workers:** execute this scoped fix natively; root owns independent review and full suite/voyage. Existing reversible implementation authorization applies; no additional approval or commit.

**Goal:** Successful refresh of the same safe navigation leg must not reverse an unfinished tack merely because the no-progress timer expires.

**Architecture:** Compare old/new goal, draft and effective first route point before installing the refreshed route. Preserve existing tack only for equivalent authorized navigation with a still-wet side. Keep failure, waypoint pop and existing wind/settling gates intact.

**Tech Stack:** GDScript, native Encounter, formal terrain and recorded scalar fixtures.

**Spec:** Parent task and `build/port-approach-work/second-voyage-audit/upstream.json`; observed mechanism is proven in a one-variable counterexample, historical tack state is unknown.

## Global Constraints
- Product edit only Encounter; do not change frozen Egress/Approach, old units, QAtools, route generation, speed, wind thresholds or deadline.
- No unsafe side or stale manual/tactical tack persistence; ordinary45m waypoint pop continues clearing tack.
- No claims of historical replay or actual campaign completion from scalar fixtures.

## Review Focus
- Same goal/leg/draft succeeds without reversing unfinished side.
- Changed target, effective waypoint or draft clears stale leg state.
- Failed replan and newly shallow current tack side cannot retain state.
- Existing wind gate still invalidates changed wind.
- Manual/tactical replacement and ordinary waypoint advancement keep original ownership semantics.

### Task 1: Preserve equivalent safe tack
**Files:** modify `modules/naval_simulation/encounter.gd`; create `tests/test_tack_route_replan.gd`; scoped artifacts only.
- [x] RED:989.8 same scalar pose/yaw, fixed in-progress+1 hypothesis, only checked fresh/expired differs; require same tack and helm.
- [x] Implement equivalent goal/draft/effective-leg success predicate with wet-side/authority checks.
- [x] GREEN: target/leg/draft/failure/wind/unsafe side/manual/tactical/pop counterexamples and short actual steps; reviewed near-waypoint expired case also RED/GREEN.
- [x] Save c3a87 baseline, patch and report.
- [ ] Root executes full suite/final actual voyage.
