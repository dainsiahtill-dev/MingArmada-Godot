# Port Approach and Voyage Clarity Implementation Plan

> For agentic workers: Use superpowers:subagent-driven-development. Parallel tasks own disjoint files. Do not commit, stage, push, reset or clean this inherited dirty checkout.

**Goal:** Remove verified low-speed arrival deadlock and make preparation/deadline/repayment information understandable, then revalidate actual voyages and native UI.

**Architecture:** Navigation chooses safe courses; existing physics integrates motion and resolves contacts. Campaign remains the sole arrival, cargo, reward and save authority. UI derives relative times from current campaign time without changing state or deadlines.

**Tech Stack:** Existing Godot 4.7.2 GDScript and strict headless runner.

**Spec:** [Verified approach audit](opening-story-work/task-port-approach-pacing-audit.md) and [current acceptance](../../migration/opening-story-gameplay-acceptance.md).

## Global Constraints

- Writable project: C:/Users/dains/Documents/Git/ming-armada. Old MingArmada and all reference/game folders remain read-only. All shell commands begin with RTK.
- Retain actual arrival within 25m and speed <=0.75m/s, original cargo/people/receipt accounting and full-fleet save gates. No position correction, invented arrival, healed crew, restored wreck or rewritten voyage evidence.
- Recovery is limited to planned/reference handling, low-speed final navigation near the destination. No new thrust or yaw budget; use existing bounded handling. Manual input, tactical orders, capture/disable/lock/crew/hull and wet-hull gates remain effective. Old opt-out paths remain identical.
- A feasible final heading is insufficient: evaluate the turning footprint, braking/travel envelope, peer relative motion and a bounded future interval. 450s overlap counterexample must remain rejected. Keep existing physical contact handling.
- No water/island/particle changes or performance tuning in these two implementation tasks. REA handoff is a parallel read-only study.
- One controller owns the final full suite, real voyages and visible GPU capture. Workers run covering tests only and report named failures. Never overwrite prior evidence or operate editor PID8384.

## Review Focus

- A heading clear at the current instant may collide during rotation or with a moving peer.
- Loading, manual helm, tactical orders and opted-out simulation must retain previous behavior.
- Arrived/sunk/interrupted voyages and offered/active/settled contracts must not show a false ETA or deadline.
- Kinmen/sea repayment requires Xiamen; unsafe Xiamen must still show its genuine safety reason.
- Test fixtures diagnose geometry only; full real sail/arrival and normal saved/continued cargo require separate verification.

## Task 1: Safe final-navigation recovery

**Files:** modules/naval_simulation/encounter.gd; optional focused modules/naval_simulation/navigation/approach_clearance.gd; tests/test_port_approach_recovery.gd. Do not edit UI, Campaign, Bridge, SaveCodec or physics budgets.

**Interface:** Existing Encounter navigation/physics APIs stay compatible. Any clearance module consumes numeric actual own/peer footprints and motion plus terrain callback, returning an acceptance/rejection decision. It does not import game/domain or mutate vessels.

- [ ] Revalidate the 450s rejection and 750s missed-heading case against current actual evidence and source.
- [ ] Write and run a meaningful failing actual Encounter recovery test before changing production. Include turning overlap, future crossing peer, dry/insufficient depth, wind restriction, fast/remote/intermediate navigation and manual/order/disabled paths.
- [ ] Present the bounded motion/clearance design and ownership gate to root; root records any necessary ruling before implementation.
- [ ] Implement safe consideration of the actual destination course when old alternatives block. Failed clearance preserves old avoidance/stop behavior.
- [ ] Run covering navigation/handling/contact tests, report exact commands and failures; provide baseline files and a scoped patch for independent review.

## Task 2: Relative voyage information and Xiamen repayment copy

**Files:** game/ui/mingqi/mingqi_interface.gd; existing tests/test_opening_story_ui.gd or one focused UI test. Do not edit domain/runtime/navigation or shared existing tests owned by Task1.

**Interface:** Read existing campaign simulationSeconds, contract status/deadlineAt, voyage status/eta/cargo and runtime readiness. Dispatch and financial gates stay unchanged.

- [ ] Confirm current debt/contract/voyage presenters and add meaningful black-box UI assertions for wrong-port debt and advancing clock where needed.
- [ ] Offered contracts with an existing positive deadline show actual remaining/overdue duration and explain that time already counts before acceptance. Only an unset/zero deadline shows timing begins on acceptance. Active contracts show remaining duration or genuine overdue duration. Completed contracts show their actual outcome.
- [ ] Underway voyages show remaining ETA; loading/arrived/lost/interrupted statuses explain actual preparation or result instead of absolute estimated seconds. Do not promise readiness without actual runtime conditions.
- [ ] Debt-only wrong-port text explicitly directs the player to Xiamen. Keep generic port messages and all actual safety/financial guards unchanged.
- [ ] Run covering UI/runtime tests; supply a scoped patch and baseline for independent review.

## Task 3: Integration and authoritative verification (root)

- [ ] Independently review both scoped changes, resolve important findings with their original implementers, then freeze production.
- [ ] Run one fresh unfiltered full suite after the combined final source is frozen.
- [ ] Re-run actual formal first voyage in a new evidence path. Record last-approach navigation and motion to verify reduced waiting without manufactured delivery.
- [ ] Continue the real saved campaign into the second twenty-grain voyage, actual arrival/claim and safe save; do not substitute a fixture for voyage evidence.
- [ ] Generate and personally inspect current native UI screenshots with real normal save/Continue. Preserve user slots and prior runs.
- [ ] Update acceptance with actual scope, unresolved issues and current source identities. Broad game/effects goal stays active.

## Execution rulings

- Reuse codex/godot-migration with its existing uncommitted migration: moving to a clean checkout would omit the implemented game. Preserve scoped pre-edit baselines and patches for review; no Git mutation. Cost if wrong: unrelated inherited changes complicate review, mitigated by separate file ownership and hashes.
- Proceed under the user's full autonomy and explicit multi-expert authorization; no additional design/approval question. Cost if a reversible design choice is wrong: local rework after evidence/review.
- First convoy has a fixed world-time deadline of 1800, while the offered second convoy has an unset deadline until acceptance. Preserve both original business rules and correct the earlier blanket copy assumption. Cost if wrong: misleading preparation advice; explicit delayed-acceptance UI checks cover it.
- Recovery can use the existing bounded Manual braking request with fully furled sails. Maintain transient goal-bound ownership until alignment, freshly revalidate each tick, and use conservative numeric motion envelopes rather than a second shadow physics authority. Limit recovery to 25<distance<=55m and <=0.75m/s; prediction does not guarantee unknown future peer actions. Cost if wrong: blocked or unsafe maneuver, addressed by geometry/gate regressions, native physical steps and a genuine full voyage.

## Task conflict scan

| Pair/task | Shared interface or file | Decision |
|---|---|---|
| 1 / 2 | Existing runtime snapshot only; no shared edited file | Parallel implementation allowed; freeze together before root suite. |
| 1 / 3 | Encounter and real voyage motion | Root verifies final worker source; static probe alone cannot complete task. |
| 2 / 3 | UI copy and captured viewport | Root captures only final source; existing PNGs remain historical. |
| Task1 | Tests specify safe recovery plus unsafe rejection | No conflict; bounded prediction design must be reviewed before code. |
| Task2 | Copy-only debt fix and relative time math | No financial/domain change; first fixed deadline differs from the second unset deadline, now explicitly covered. |
