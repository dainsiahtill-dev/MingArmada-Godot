# Navigation Course Safety Implementation Plan and Report

> **For agentic workers:** native scoped implementation, root owns independent review/replay. Existing reversible authorization applies; no commit or additional approval.

**Goal:** Select a wet tack first and never replace a blocked shore course with an unchecked no-go heading.

**Architecture:** Correct the wet-first tack comparison, then use the existing wind/hull/peer feasibility predicate to validate a shore fallback. If no checked choice exists, hold neutral/furled. Leave native forces, contacts, navigation/tactical authority and Egress ownership intact.

**Tech Stack:** GDScript Encounter/native ship physics, formal height field, real return scalar fixtures.

**Spec:** `build/port-approach-work/second-voyage-audit/return.gd` and `return.json`; auditor confirmed21 zero-step rows, unknown historical tack/previous explicitly labeled.

## Constraints and review focus
- Product edit only Encounter; new scoped test/artifacts. No force, wind threshold, terrain/planner/arrival/save/QA/Egress/FX changes.
- Both one-wet-side permutations must prioritize wet side; both-wet retains heading tie-break.
- Nearshore fallback must remain outside existing no-go and pass actual hull/peer checks; no safe choice yields neutral hold.
- Legitimate active Rally remains navigation owner without acquiring Egress; explicit manual takeover retains controls.
- Existing tack wind/settling/completion gates remain intact.

## Task
- [x] RED: final real flagship/direct-nav and grainB/activeRally scalar fixtures pick dry120 and near-zero helm; native210 sail force0 versus safe240 positive force. Observed21 assertions/6 failures, exit1.
- [x] Correct wet priority and checked fallback/hold.
- [x] GREEN: real return fixtures, wet-side permutations/ties, nearshore/no-go/peer/all-blocked, Rally/manual and original tack gates; native20 seconds only. Final54 assertions/0 failures, exit0.
- [x] Save baseline/hash/patch/log/report.
- [ ] Root owns full voyage and independent review.

## Scoped result

Baseline `build/port-approach-work/navigation-course-safety/encounter.preedit.gd` SHA256 `5a86e578f41846b90ccd21c74f89518c6994441ce9beb2018bcfefc5fe7698e9`.

Final Encounter SHA256 `0910d581c7a5f4642edc9d3ddcb826a9b42f5936655be441f1527458526c9df9`. Product delta corrects wet-first comparator from wet(b) to wet(a), validates the outgoing shore course using original wind/no-go/fade and actual hull0/15/30/45 samples, tests quarter-turn and tack alternatives with unchanged `_feasible` wind/hull/peer gates, and returns neutral/furled when no checked choice is available. Existing peer avoidance, Approach and Egress gates remain. No physical force or native configuration changed.

RED21/6 captured the two real return vessels' wrong side and helm, existing dry tack's unchecked+90 fallthrough, and failure to hold neutral when every outgoing course is blocked. `red.log` records observed completion/exit context; failure labels printed to stderr were observed in the session. Baseline native210 force0 and240 force>40kN passed before the fix, pinning controller behavior rather than adding sail force.

Final `green.log` and `unit.json` record54/0 with exact source/fixture hashes. Tests cover both one-wet-side permutations regardless of nearest-heading side, both-wet tie-break, original valid/finished/changed-wind tack gates, checked no-go/peer alternatives, neutral all-blocked hold, legitimate activeRally, and real API transfer to manual controls. Actual20-second native segment kept the flagship and grainB hulls wet, moved their headings from the old210 no-go direction toward235–236 degrees, and produced positive unchanged native sail force. GrainB retained activeRally without acquiring Egress.

Recorded scalar fixture comes from `journey-second.json` SHA256 `92b76d0daa85d64cf0ff5c2cecdd4f80e3accd3feecf8843ddbe34fd58a310e4`. Historical tack/controller/previous solver internals are unavailable; no-tack and local previous linearization are explicit reconstructions, not an exact historical campaign replay.

Additional final-source regressions: tack-replan35/0; autopilot-port-approach24/0. Approach recovery regression is **NOT PASS**: parallel domain implementation temporarily introduced a missing `second_voyage_aftermath.gd` preload, producing actual compilation errors before the partial test continued. It also printed a real `wind no-go cannot be bypassed` failure,97 assertions/1 failure, exit1; this is not hidden behind the transient compile issue.

The precise old unit fixture/wind mutation was reconstructed old/new without physics advancement in `approach-assist-kind.gd/json`. Destination bearing79.164534°, windFrom90°, destination wind angle10.835466° remains forbidden. Baseline5a86 picked dry side−1/course30°; wet side+1/course150° exists. Candidate0910 selects that lawful150° course,60° from wind, and returns ordinary `_navigation_steerage` with targetYaw−4°/s, brake0, sails0. Explicit `_final_approach_clear` is false; neither `approachRecovery` nor `wetRouteEgress` exists. Therefore the old broad `request(e).is_empty()` expectation conflates a lawful ordinary tack steering request with forbidden final approach ownership.

After reviewing that numeric distinction, parent explicitly authorized narrowing only the old wind assertion197 and necessary local reads/assertions, subject to independent review. Old fixture/wind mutation and every no-go/Approach guard are unchanged. New assertions pin unchanged destination angle/no-go, rejected explicit final-approach clearance, absent Approach/Egress owners, wet150° tack outside no-go/fade, and ordinary assist equality to the existing hull/crew/sail-scaled `Manual.build` budget. This ruling does not authorize new force or broader recovery authority. The old-test assertion baseline accompanying the patch is reconstructed by reversing this exact authorized local hunk, rather than claimed as a pre-edit capture.

Exactly one authorized scoped rerun after domain dependencies were complete passed `test_port_approach_recovery.gd`:136 assertions/0 failures, exit0, no compilation errors. Log `approach-green.log`; actual arrival47.766667 seconds and40-second timeout remained verified. The earlier97/1+compile run remains recorded above as NOT PASS. Final three-file patch reverse-check exit0.

Three-file scoped patch (Encounter, new course test, authorized old wind assertion) and baseline/log/hash evidence reside under `build/port-approach-work/navigation-course-safety/`. Root owns independent review and actual full return/safe-save replay. No complete voyage, arrival/save, full suite, GPU or performance outcome is claimed. No commit/stage/push; only writable ming-armada paths changed.
