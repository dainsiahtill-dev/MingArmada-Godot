# Wet Route Egress Implementation Plan

> **For agentic workers:** execute this isolated fix natively; parent owns independent review and full journey verification. Existing user authorization permits reversible implementation without another approval gate.

**Goal:** Recover a physically wet, low-speed authorized navigation start outside the unchanged Planner circle domain.

**Architecture:** A dedicated directed connector proves the complete shortest turn and translation with braking, measured yaw, continuous hull sampling and moving peer envelopes. Encounter owns its execution separately from ordinary waypoints, rechecks each tick, and only returns to Planner after the real current position is circle safe.

**Tech Stack:** Godot GDScript, native Encounter/Manual, formal height field.

**Spec:** Parent assignment; immutable `journey-second-corrected.json`, 1049.8/2999.8 starts and 1064.8 dry-turn counterexample.

## Global Constraints
- Do not change Planner endpoint checks, arrival, draft, campaign, cargo, rewards, poses, terrain or existing 25–55m approach recovery.
- Authorized planned/reference navigation only; manual, tactical, service, combat, disabled/captured/sunk or insufficient crew must not acquire/retain connector control.
- Every shell command starts with RTK. No commit. Root owns GPU/full journey verification.

## Review Focus
- Actual connector must not be popped by ordinary 45m waypoint threshold.
- Wet final orientation with a dry intermediate turn must stay blocked.
- Moving peer and residual yaw/velocity invalidate clearance.
- Changed controls/goal/draft/authority revoke ownership without opening sails.
- Fresh numeric fixture is not actual full-voyage evidence.

### Task 1: Directed connector and scoped Encounter owner
**Files:** Create `modules/naval_simulation/navigation/wet_route_egress.gd`; modify `modules/naval_simulation/encounter.gd`; test `tests/test_wet_route_egress.gd`.
**Interfaces:** Module `plan(own, target, peers, terrain, sea_level)` and `assess(own, node, peers, terrain, sea_level)` return dictionaries, no domain mutation. Encounter supplies measured state, conservative real Manual braking budget and authority.
- [x] RED: real 2999.8 start remains blocked before connector exists.
- [x] Implement bounded turn/travel envelope plus circle-safe original Planner continuation.
- [x] Add independent per-tick owner with capped sailing speed, brake/turn/hold phases and current-position Planner handback.
- [x] GREEN: exact starts, dry turn, moving peer, dry target, revoked authority, and actual continuous short-turn steps; candidate long handback labeled separately.
- [x] Run old approach regressions; save preedit baseline, cumulative patch, report with explicit evidence limits.
- [ ] Parent full suite/final frozen-source voyage evidence. Late window exceeds1799.8 deadline; parent requested upstream cause investigation before another full run.
