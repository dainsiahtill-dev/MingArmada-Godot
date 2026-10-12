# Fleet return control ownership audit

Read-only audit of `C:/Users/dains/Documents/Git/ming-armada`. Production source, tests, frozen voyage evidence, and the ongoing full-suite outputs were not modified. No new builds, simulation ticks, browser sessions, or voyages were run by this audit. CodeGraph was already established unavailable/unindexed by Root. Used systematic-debugging/source tracing; reused the sibling command-contract auditor's zero-step native probes instead of duplicating them.

Evidence identity:

- Frozen second journey: `docs/migration/evidence/opening-story/second-voyage-aftermath/journey-second.json`, SHA256 `191170ccf22ab26dfd00521c3ea2ff6933e30c2c24b98d575e7ea856b2a3c037`, 82 checks / 1 failure. The failed check is `normal confirmed full-fleet final checkpoint exists`.
- Encounter: `modules/naval_simulation/encounter.gd`, SHA256 `0910d581c7a5f4642edc9d3ddcb826a9b42f5936655be441f1527458526c9df9`.
- Peer probes: `build/second-aftermath-work/fleet-return-audit/command-probe.json` and `timeline.json`. Probe is explicitly zero accepted seconds, recorded scalar reconstruction, no campaign return claim.
- This audit's source hashes and extracted completion proof: `build/second-aftermath-work/fleet-return-architecture/source-audit.json`.

## Findings

**B has a real terminal-control lifecycle defect.** Rally completion leaves the old autonomous rudder active after relinquishing the navigation/order owner. The actual exact rudder persists across the recorded return aftermath. This is independent of checkpoint validation; loosening save rules would conceal it.

**Fast has an earlier ordinary-autopilot arrival defect, followed by an ownership restriction and geometry failure.** While protecting an actually anchored target, it continues full rudder inside its already-reached final goal with sails furled. That is distinct from B's terminal order cleanup. Fix the earlier controller output lifecycle first; do not widen Approach/Egress ownership as the current repair. Removing the Rally restriction at the late recorded position still does not produce a safe connector.

**Do not change generic cancellation into an unconditional control reset.** Explicit queued controls are applied before the encounter tick and cancellation currently occurs after writing those controls. A global reset in `_cancel_order` would overwrite fresh player input.

The current native implementation names the relevant routine `_tactical_tick`, not `_orders_and_ai`.

## Exact B call path

1. `tactics/order_controller.gd:23`: Rally declares a participant complete when distance to its fixed point is `<25m` and planar speed is `<1m/s`.
2. `Encounter._fixed_tick:487-491`: increments native time and invokes `_tactical_tick` before autopilot and physics.
3. `_tactical_tick:599-603`: obtains the decision, counts completed participants, writes the decision point to `state.navigation`.
4. `:604-606`: when every remaining participant is complete, marks `rally-arrived`; clears decisions/navigation and sets `sailDeployment=0`. It does **not** neutralize rudder. It also leaves route/tack/low-speed-turn/sail-recovery scratch state behind.
5. `_fixed_tick:503` skips autopilot once navigation has been erased. The completed order is no longer active, and a controlled friendly does not enter hostile AI (`:494-495`).
6. `:523-527` applies `state.rudder * 30` and ordinary native forces to the physics core. There is no later completion cleanup. Hence the prior autonomous helm remains physically commanded.

Recorded evidence supplied by the independent timeline audit:

| Accepted simulation time | B Rally | Distance to Xiamen goal | Speed | Rudder |
|---|---|---:|---:|---:|
| 2141.6 | active | 30.6417m | 0.63035m/s | 0.1442985 |
| 2156.6 | first recorded completed | 21.8809m | 0.54747m/s | 0.1448271765552296 |
| 2517.8 | completed; flagship docks | 66.1449m | 0.14677m/s | same exact value |
| 2981.6 | completed | 103.7856m | 0.0872069m/s | same exact value |

The command audit found no manual B controls and B was not the selected helm. More directly, its zero-step probe reconstructed the recorded 2156.6 B pose/control state, submitted an actual fresh same-point Rally, then called `_tactical_tick`. The accepted order became `completed/rally-arrived`, navigation became null, sails became zero, and rudder remained exactly `0.1448271765552296`; physical motion was unchanged. This proof is extracted into `source-audit.json`.

**Minimal corrective seam, after Root unfreezes implementation:** release the *current completing Rally's* autonomous outputs inside the normal completion path: neutral rudder and furled sails, clear owned navigation/decision and obsolete route/tack/recovery latches. Preserve core identity, pose, velocity, yaw rate, HP, cargo, reward and native clock. Do not call `_stop_service` or `anchor_fleet` to make the assertion pass: those methods explicitly stop horizontal physical motion (`encounter.gd:948-968`). No teleport or instantaneous anchoring is justified.

This cleanup alone cannot prove safe anchoring. `is_anchored:942-946` requires speed `<=0.05m/s`, yaw rate `<=0.01`, neutral rudder, zero sails, no navigation and no active order. Rally currently completes at almost 1m/s. If the product contract requires Rally to finish in a stationary hold, a bounded settling phase using the existing physical braking request must remain owned until its separate safe-stop condition is reached. That is an explicit behavior decision/test, not an implicit velocity reset. Port eligibility remains a separate predicate.

## Manual takeover and interruption ordering

- `game/runtime/sailing_simulation.gd:81-87` queues a detached validated control intent; player input may cancel navigation immediately. Other-ship controls are queued without cancelling the player's waypoint.
- `:121-122`: queued native commands are consumed before `Encounter.step`.
- `Encounter.command:315-317`: computes whether controls changed; `_ship_command` validates and writes controls first; only then `_cancel_order(id, "manual-control")` executes.
- `_ship_command:329-339`: invalid controls return before mutation; changed controls revoke owned recovery and record manual override; real controls sequence increments.
- `_cancel_order:235-243`: removes only that participant from active orders, clears its navigation/tack/decision. It deliberately does not erase the newly supplied rudder/sails.
- On the subsequent `_tactical_tick`, that participant is no longer eligible for the old order's completion cleanup. Thus putting neutralization in the current terminal Rally branch preserves queued-manual precedence; putting it in every cancel path does not.

Terminal outcomes need explicit policy. `:579-583` already neutralizes an unavailable participant's autonomous outputs. `:585-589` clears navigation/tack on target loss/capture but not all controls; `:604-606` handles normal Rally completion and unsafe decision blocking together. Avoid silently changing every tactical outcome while fixing B. First isolate normal Rally completion and prove takeover/supersession behavior; broaden only with separate evidence and tests.

## Comparison with working arrival/stop contracts

Ordinary `_autopilot` lowers deployment near the goal (`:731-739`); it does not itself declare campaign arrival or remove navigation. The business arrival flow is a separate trusted transaction:

- `near_field_bridge.gd:133-150` recognizes autonomous arrival controls only for genuine leased grain ships with an active voyage, matching native battle/control projection sequence, no active tactical order, and an exact recorded destination point. Newer explicit controls take a distinct path.
- `:152-178` permits arrival anchoring only for genuine lease, live eligible crew/hull, aligned policy, no navigation/order/rudder/sails, arrived and empty voyage, actual destination distance `<=55m`, speed `<=0.75`, no conflicting boarding/work or nearby live hostile. It does not authorize arbitrary returning fleet members merely because a Rally status says completed.
- `tests/test_arrival_berthing.gd:79-110` deliberately obtains a real nonzero residual autopilot rudder through native ticks, then checks automatic completion neutralizes it while actual newer helm/sail input survives. This is the closest existing *ownership* example to follow.

B's return Rally is not a new outbound grain voyage to Xiamen, so it cannot inherit old destination-arrival authority. Do not extend that campaign-specific bridge rule to every ship/port to hide a native tactical cleanup bug.

## Fast: restriction versus safety refusal

`_approach_authorized:843-848` requires route planning + reference handling + live navigation, excludes manual handling/manual override and **every active order**, and preserves operational, control-policy, combat and terminal-status gates. `_egress_authorized:759-760` adds minimum crew fraction `0.25` and a revoked-goal fence. Thus the active fixed-point Rally cannot acquire either recovery even though it legitimately owns navigation.

`_autopilot:671-694` retries ordinary wet-route planning. For an empty `unsafe-endpoint` route it tries Egress only if authorized and within the existing speed/retry gates. Otherwise it writes zero rudder and sails. The actual Fast therefore remains active Rally + empty route + stopped controls near Supply.

Peer command probes distinguish the layers:

- Actual `Encounter.navigate` accepted the recorded ship/goal and cancelled the old Rally without moving the ship. Authorization changed from false to true.
- At 1691.2 and final 2981.6, fresh Egress planning still reported `no-safe-egress`: three wind rejections and five swept-depth rejections from the actual current turning pose. Native oriented hull wetness alone does not certify the swept turn.
- Earlier Fast evidence: at 1511.6 the route planner's start circle was wet; at 1526.6 it was not, while native current hull was wet. Cancelling the then-active protect order and testing the actual static return goal produced a safe connector at the 1526.6 pose; by 1541.6 that connector was no longer available. This is a zero-step feasible-window result, not a simulated return. Do not broaden recovery to moving protect/intercept/focus targets on that basis.

Therefore an owner extension must be evaluated from a legitimate timely return order, not advertised as a late guaranteed rescue. The geometry/trajectory work remains with the command-contract auditor and Root. The system should expose a truthful blocked/unsafe navigation reason through ordinary UI if it cannot act, rather than require a debug console command or claim completion.

## Fast's earlier protect arrival defect and minimal current seam

After the initial report, Root requested a narrower preventative fix, explicitly without broadening Approach/Egress ownership. Additional direct frozen-record inspection and the peer's `protect-arrival-timeline.json` establish the following:

- Active order is `continued-voyage-3`, `protect` on `mingqi-1650-grain-a`.
- Grain A remains at `(-70.45767504892005, 296.9786219264525)`, heading `1.3002418505288293`, speed/yaw/rudder/sails zero, no navigation, arrived voyage.
- `Orders.decision:30-35` therefore repeatedly generates the same guard point `(-128.2750461670996, 313.0145689512683)`.
- At 1451.6 Fast is 6.0457m from that point with sails 0, rudder 0.1191. At 1466.6 distance is 2.4111m. At 1481.6 distance is 1.26394m, but rudder is now 1.0, speed 0.21845m/s and yaw 0.01199rad/s.
- At 1496.6 / 1511.6 / 1526.6 it remains within the 18m planned reach radius (4.4242 / 7.5690 / 10.7244m), with sails 0, rudder 1.0, speed approximately 0.213m/s and yaw approximately 0.0166rad/s. By 1541.6 the route is `unsafe-endpoint` and only then the blocked branch writes rudder 0.

Source mechanism:

1. `_tactical_tick` intentionally keeps `protect` active; protect has no `completed` result.
2. `_autopilot:730` computes and writes heading-error rudder. At `:733` the reached-final-point condition only zeroes deployment; low-speed turning keeps the sails furled at `:738`.
3. `_navigation_steerage:849-852` declines additional assistance when already within target reach. It returns an empty dictionary **after** the nonzero rudder was written, so it does not supply an arrival stop.
4. `ship_dynamics.gd:388-401` calculates low-speed crew steering lift from rudder. That force adds lateral velocity even with zero sail force. The control output is actively recomputed by the still-live protect owner; this is not an old completed-order value as in B.

**Small current repair seam:** an ordinary final-goal *arrival hold* in the existing `_autopilot`, before it computes a fresh turn toward a point already reached. Keep this initially specific to the proven stationary-protect situation: current active protect order and membership; current decision and navigation equal that order's generated final goal; valid non-intermediate route; target truly anchored under the existing `is_anchored` predicate; own ship operational and controlled, no manual owner, no current fire/threat decision; existing routePlanning/referenceHandling feature flags. Re-evaluate those facts every accepted tick. A stateless predicate avoids introducing another persistent authority cache.

While that predicate holds, request neutral rudder/furled sails and clear the obsolete low-speed turn/tack/sail-recovery output. Keep the protect order and navigation goal intact; it is station keeping, not order completion, campaign arrival, or service anchoring. If the protected vessel starts moving, a threat changes the generated objective, the point leaves final reach, permissions change, a new order supersedes it, or the captain takes over, the predicate no longer holds and the existing controller/input path resumes. No new manual `_cancel_order` reset is needed.

Deceleration must remain physical. Existing `Manual.build` already supplies a crew/hull/sail-scaled neutral-yaw and bounded braking request (`manual_handling.gd:11-23`); the native solver applies ordinary air/water drag plus at most the existing dry-hull braking budget without reversing velocity (`ship_dynamics.gd:310-324`). If an owned arrival hold uses that existing request, it changes controller intent, not solver constants or acceleration budgets. It must not call `stop_horizontal_motion`, force an anchor, edit position/yaw or set velocity directly. Neutral-only coast versus the existing bounded brake should be decided by a short isolated physical-stop regression, not a full-voyage guess.

Required focused checks for this seam: reconstruct the early recorded Fast/anchored-A fixture; show final goal is within reach and outputs become neutral without changing motion at command time; advance short real native ticks and verify speed/yaw reduce while depth/collision checks stay active; target departure/motion resumes following; changing goal/order/manual controls wins; an intermediate route, moving protected target, threat/fire decision, blocked wet route, or missing capability cannot be silently treated as arrived. Then validate B's independent completion cleanup. Only a fresh full return can establish the combined product result.

This preventative hold avoids losing the early safe configuration. It is not a claim that a hold at the already-unsafe late Fast pose creates a route.

## Deferred alternative: narrow static-Rally recovery interface

The following is an architecture option only. **Root's current chosen scope does not widen Approach/Egress ownership**; do not implement it as part of the two lifecycle fixes above.

Retain one native navigation controller. Its recovery seam should resolve an *owned static navigation goal*, not answer merely `not hasActiveOrder`:

1. Unordered navigation retains existing authorization behavior.
2. An ordered candidate is eligible only when the active record is exactly `rally`, the ship is a current participant, the fixed `intent.point` exactly equals current navigation, the order is still the latest owner, and all current operational/control/combat/manual gates pass.
3. Every held approach/Egress/tack-continuity state records and revalidates owner identity (at least native incarnation/battle, ship, authority kind, Rally order ID, exact goal; retain draft and physical checks). A same-coordinate replacement order is a new owner. Goal equality alone is insufficient.
4. A manual takeover, explicit cancellation, order supersession, participant removal, goal change, crew/hull/sail loss, permission change, service lock, capture, disabled motion, pending combat or terminal state revokes old ownership before any further output. New manual values must survive. No recovery may reopen sails merely because a revoked owner used the same coordinates.
5. New eligible ownership may acquire a fresh recovery only after a new complete clearance check. It must not inherit the old recovery's connector or stale progress. Preserve a clear transition/revocation observation so incoming tactical commands do not silently reuse the old navigation recovery.
6. Moving-target orders remain excluded. `_keep_tack_after_replan:747-754` also currently excludes every active order; any static-Rally continuity allowance must use the same owner/goal checks, unchanged effective leg, draft and wetness, rather than changing each gate independently.

This is a small ownership module/internal seam, not a new steering engine. Keep Egress horizon, speed/sail caps, padded sweep, peer prediction, depth, wind, native physics and checkpoint guards unchanged.

Existing tests explicitly encode revocation on incoming Rally: `test_port_approach_recovery.gd:184-187`, `test_wet_route_egress.gd:104-118`, `test_tack_route_replan.gd:29`. Simply deleting the active-order guard would invalidate their purpose, especially equal-goal supersession. Preserve those takeover assertions; add separate fresh-static-Rally acquisition tests. Some old “all tactical orders forbidden” expectation may need an explicit contract refinement, but never weaken clearance tests to accommodate the actual late unsafe Fast pose.

## Focused tests required before claiming a repair

No test files were changed or executed here. Suggested implementation order:

1. **Rally terminal cleanup red/green:** use recorded B arrival scalar setup plus real issued Rally. Completion neutralizes old rudder/sails and obsolete internal navigation state without changing physical motion at cleanup. Subsequent real ticks must not apply the stale helm. Also cover multiple participants and a participant interrupted before the completion tick.
2. **Manual precedence:** queue changed rudder and sail-only controls before the same completion tick for player and non-player ship; verify latest values survive, old order does not complete for the removed participant, invalid controls do not cancel, unchanged controls retain existing ownership, and fresh superseding order survives.
3. **Static owner lifecycle:** real Rally issuance → own goal → fresh valid clearance; same/different-point supersession, cancel, manual takeover, service/capture/disabled/crew/combat gates; target-based orders still excluded. Test old-owner revocation and new-owner acquisition as distinct observations.
4. **Safety negatives:** exact late Fast recorded pose remains refused; earlier eligible fixture can only acquire the connector after the complete unchanged safety test. Passing acquisition is not arrival evidence.
5. **Game integration:** ordinary UI exposes the intended fleet return command/cancellation and truthful block state. Exercise real business/native envelopes and final all-fleet checkpoint guards. No console-only workaround is an accepted user flow.
6. After Root's source freeze and targeted tests, Root performs the consolidated suite and one actual fresh voyage/return acceptance. Keep the current 82/1 frozen record unchanged as the failing baseline.

The current migration oracle (`tools/migration/export-naval-reference.mjs:89-92`, `tests/test_naval_simulation.gd:27`) exercises all six order types with short step sequences and manual cancellation. It is useful for compatibility and atomicity, but its remote Rally target does not cover B's terminal-arrival cleanup. New explicit gameplay regression coverage is required; existing reference parity alone cannot certify a usable fleet return.

## Follow-up ruling: neutral controls alone do not physically stop B

This section supersedes any interpretation that the neutral-only fix is sufficient. Inspected subsequent Encounter SHA256 `5cceb84d487858d5374edf7cb909e519e1b0b8b27b48a082efdc49868ec57290`. Root reports the candidate's focused tests at 88/0 but an independent real 400-second native coast probe leaves B 75.920593m from its Rally goal, speed 0.15933m/s, yaw 0, all samples wet and not anchored. At 360 seconds distance was already 69.20m. Root stopped only its fresh acceptance attempt and preserved the interrupted evidence; there is no newly accepted voyage result. This audit did not rerun the probe or change production code.

The new code fixes output neutrality (`:605-611`) and near-goal hold (`:704-706`), but both paths still return no physical braking request. With quadratic drag, a nonzero initial speed may coast for a long distance. Keeping thresholds, terrain and save rules intact therefore requires a **bounded native settling request**, not more waiting or a new checkpoint exception.

### Exact minimal implementation seam

1. **Arm only at normal Rally completion.** In the current `:604-611` branch, after proving the active record is a valid Rally and every current participant meets its existing completion decision, neutralize old outputs and create a per-ship ephemeral `terminalStop` marker on the ship wrapper (beside `route`/`manualHandling`, never inside `ship.state`). Record `{battleId, shipId, orderId, goal, startedTick, deadlineTick}`. Do not arm for blocked/cancelled/superseded/target-lost orders, merely reading an old completed status, arbitrary zero sails, or loading a checkpoint. Gate the new physical assistance by the existing opt-in reference-handling path so non-opted reference behavior is not accidentally expanded.
2. **Consume before the no-navigation skip.** `_fixed_tick` creates `navigation_assists` at `:497`; the current loop immediately skips navigation-less ships at `:503`. Evaluate the terminal-stop marker **before that skip**. An eligible marker contributes the existing `Manual.build(kind, 0, actualSpeed, crewFraction, hullFraction, sailFraction, true, 0, referenceHandling)` request to `navigation_assists`. The existing `:524-527` path then feeds it to `core.step(DT, controls)`. It must work when normal Rally completion has already erased navigation and the order is completed.
3. **Use existing physics only.** Reuse the existing neutral-yaw request and braking cap (0.2 times the current power fraction/dry-mass contribution). No new acceleration, torque, speed floor, hull dimensions, route reach, port radius, or anchor thresholds. Do not call `anchor_fleet`, `_stop_service`, `stop_horizontal_motion`, `correct_horizontal_motion`, or mutate core pose/velocity/yaw as the stop action. Existing shoreline/contact solvers continue on every tick.
4. **Bound lifetime by accepted native ticks.** Choose an explicit documented stop timeout long enough for the worst supported operational crew/mass case, verified numerically; do not derive it from wall time and do not reset it on every sync/frame. Complete when actual native speed is `<=0.05` and absolute yaw rate `<=0.01`, using the existing anchored thresholds. Prefer retiring the marker after the physics/contact pass, before the snapshot handed to the bridge. Retirement changes only ownership metadata, never motion. Timeout also removes the request and records a factual timeout/unfinished stop result; it cannot mark the ship anchored or pretend to have docked. No automatic re-arm from the old completed order.
5. **Revalidate current authority, never historical entitlement alone.** Require matching incarnation, ship, completed Rally identity/goal, current control permission, operational hull/crew/sail, neutral owned outputs, no newer navigation or active order, no manual owner, no capture/service/disabled state, no pending combat, and nonterminal encounter. Every accepted tick rechecks it. The `orderId` must still identify the record that actually completed; replacing the orders collection cannot silently retain the old marker.
6. **Revoke without overwriting new controls.** Successful explicit navigate (including null/cancel), accepted new order, real changed manual controls/trim, service/anchor takeover, replacement/reset/removal or permission/crew/hull/sail/combat/terminal changes revoke the marker. Failed inputs leave it intact. Revocation erases metadata/assistance only; it must not reapply neutral values over newly accepted input. Keep the generic manual `_cancel_order` control behavior unchanged.

**Do not use `controlsSequence` equality as the sole owner fence.** `SailingSimulation:113-122` emits valid unchanged idle player controls after navigation/order completion; `Encounter._ship_command:336` increments their sequence. In addition, ordinary bridge reconciliation calls `_apply_update:1062-1067`, which increments sequence and replaces the state dictionary even for a no-op projection. A sequence-only fence would revoke a legitimate stop on the next selected-player tick or every bridge sync. Use explicit accepted authority transitions and current neutral controls/owner identity; preserve a marker across unchanged projection and benign selection. Distinguish a validated changed control/explicit cancellation from a no-op idle control, matching the existing navigation contract.

The live `_arrival_hold_requested` path still owns navigation/order. If it also needs braking, return the same neutral braking request while its existing predicate holds, instead of `{}` at `:706`; it does not need the terminal marker. The terminal marker is specifically for the interval after a completed Rally has released navigation/order. Keep those lifetimes distinct and share only construction of the physical request. No Approach/Egress expansion follows from this design.

### Save, anchoring and codec closure

- While a terminal-stop marker exists, `Encounter.is_anchored:970-975` must return false even if a mid-tick value happens to cross the numeric threshold. The stop owner is still active until its final native observation retires it. Do not include the marker in `hasActiveOrder`: the Rally receipt remains completed and should not be rewritten as a fake active tactical order.
- `MingqiRuntime.check_safety:252-259` already queries the actual encounter's `isAnchored` for each required fleet vessel. That existing call can fail closed on the marker. `export_save:264-267` syncs then checks safety before serialization; do not bypass that native check with a source-only candidate path.
- `Encounter.snapshot:204-211` copies only `ship.state` plus current visual/cooldown data. Keep the marker on the wrapper so native snapshots, campaign state and v2 JSON do not acquire an unversioned controller field. Clearing/replacing the Encounter cannot restore an old marker from saved business data.
- `SaveCodec.encode:15-17` validates only the campaign save envelope. It cannot infer a hidden live native controller and must not be presented as the safety authority. Keep its schema unchanged. Test that normal runtime export refuses during settling; after physical completion, valid export/decode/re-adoption yields the same safe business state and no stop owner. Direct domain serialization being structurally valid does not mean the runtime checkpoint was authorized.
- Successful stop retirement makes the ship *eligible for the existing physical anchored predicate*; it does not establish the fleet's port proximity, voyage completion, cargo settlement or save readiness by itself. A timeout with too much residual speed still fails existing checks. The 55m checkpoint/port and 0.05m/s anchor constraints remain unchanged.

### Smallest necessary TDD matrix for the builder

1. **Recorded B physical stop:** real accepted Rally completion at recorded scalar pose/speed, same physics/terrain; motion identical immediately before/after marker creation; real ticks apply bounded braking and stop within the existing safe range. Verify every hull sample remains wet, no contact/depth checks were bypassed, speed/yaw reach existing thresholds, marker retires, and `isAnchored` becomes true without an anchor API. Include a 400-second post-completion continuation to catch renewed drift/output resurrection; this is an isolated numerical probe, not a campaign voyage.
2. **No-op stability:** selected-player idle controls, repeated unchanged bridge reconciliation, and benign selection do not discard settling. Test through `SailingSimulation.advance` and real bridge/native projection, not only direct Encounter calls.
3. **Latest command wins:** queued changed rudder, sail-only and trim controls; explicit `navigate(null)`; new same-point/different-point navigation; new same-point/different-point order. Old marker disappears, new values/owner survive the same tick. Invalid command leaves prior owner intact. Another ship's command does not clear this ship's marker.
4. **Revocation table:** operational crew/hull/sail loss, capture, lock/service, disabled motion, permission removal, combat/terminal, ship removal/replacement/reset. No further stop request and no new control/motion overwrite. Multi-participant completion arms only the actual eligible terminal participants; a removed participant is not resurrected.
5. **Bounded failure:** paused runtime does not consume timeout; accepted ticks do. A deliberately insufficient authorized stopping capability reaches timeout without forced velocity/position changes, no automatic re-arm, and unsafe checkpoint remains rejected.
6. **Save lifecycle:** refusal while marker active (including a numerical near-threshold observation), acceptance only after actual retirement plus all existing gates, unchanged codec schema, no marker in snapshots/JSON, successful decode/adopt does not reconstruct it. Existing protected-stop, manual precedence and physical safety negatives remain valid.

The builder can keep implementation local to Encounter plus focused tests unless the exact integration test proves an additional runtime guard is required. Root owns the next distinct `fleet-stop-and-aftermath` freeze and complete acceptance; the earlier arrival-only evidence and failed/interrupted voyage records remain immutable.

### Accepted Root ruling and projection detail

Root selected a **60 accepted-simulation-second bound** and a wrapper marker containing order/battle/ship/goal/**draft**/start/deadline. Scope is controlled healthy continuous-mode ships with reference handling and planned navigation, a current genuinely completed Rally owner, no navigation/active order/manual request, and the existing capture/service/disabled/combat/terminal exclusions. Use this concrete ruling rather than the earlier open timeout choice. The builder is implementing; this audit remains read-only.

`_apply_update:1062-1068` increments the controls sequence, copies prepared scalar physics into the same native core, replaces only `ship.state`, and preserves the existing navigation. A wrapper stop marker therefore survives ordinary projection naturally. Revoke only after a **successful** authoritative transition that invalidates its guard: changed draft/control output, new navigation/permission/service/capture state, or replacement of the orders set; keep invalid requests atomic. In particular, `reconcile_ships:1090` already rejects replacing an existing ship's kind before applying anything, so an invalid-kind attempt must leave its valid old stop owner intact. Do not revoke during speculative `_validated_update`/`_prepare_physics_update` preparation that may later fail.

The existing bridge does not continually assign null navigation for an already-arrived voyage: `near_field_bridge._apply:50-68` projects fresh-start/underway/arrival-transition navigation. B's already-arrived return Rally normally produces no new navigation entry. This makes unchanged bridge projection compatible with terminal settling. Nevertheless, `reconcile_ships:1154-1156` can explicitly replace the orders collection; that action must invalidate terminal ownership rather than merely finding a matching historical ID in newly supplied records.

Tests must prove both halves: ordinary projection increments sequence and retains the same stop start/deadline; a successful owner-changing projection revokes it; a rejected projection preserves the previous marker, controls, motion and clock. Changing hull/draft/control inputs must not reset the 60-second timer or manufacture an owner for a previously unowned ship.
