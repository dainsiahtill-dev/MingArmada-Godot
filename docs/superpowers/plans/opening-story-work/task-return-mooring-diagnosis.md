# Return mooring: read-only diagnosis and berthing review

Date: 2026-10-12. Repository: `C:/Users/dains/Documents/Git/ming-armada`.

This task changed no production source or tests. It created a temporary, headless, static probe in `build/diagnostics/return-mooring-probe.gd`, its JSON output, and this report. No physics time was advanced, no game save was produced, and no long journey or GPU window was started. CodeGraph has no project index; discovery used the already authorized RTK fallback.

## Actual failure and causal chain

The root's actual formal journey capture is `docs/migration/evidence/opening-story/journey-formal-manual-fire-return.json`: 29 assertions, one failure. The shipment, combat and clerk conversation succeeded; the remaining failure was the ordinary full-fleet checkpoint.

- Grain-b genuinely unloaded 20 grain at **327.4166666666667 accepted seconds**. Its canonical receipt is `mingqi-1650:mingqi-1650-grain-b-voyage:arrival`, with the correct vessel, voyage and Kinmen destination. Both grain vessels eventually delivered 40, with no cargo loss.
- At the 330s recorded native frame grain-b was at `(258.49006683496486, 105.02588515825647)`, close to the unloading point.
- At 2400s it was at `(268.09109648690276, 178.27201194631013)`, heading `-1.6065130771306857`, horizontal speed `0.011928176701670196`, hull/sail 100, crew 20/30, empty cargo and draft 1.2. Its displacement from the recorded 330s frame is **73.87269m**. Its distance from Kinmen is approximately **72.17m**, outside the existing 55m dock range.
- The captain issued actual `journey-9`, a rally for grain-b to Kinmen `(282.1499288930165,107.48568719733964)`, at 1682s. It remained active at 2400s. Native navigation still contained that exact target, but rudder and sail deployment were zero. `canSave=false`, reason `save-fleet-not-anchored:mingqi-1650-grain-b`.

The underlying lifecycle gap precedes the failed rally. `Campaign._arrive` (campaign.gd:484–493) empties the cargo, records real arrival, marks the voyage arrived, sets the business speed to zero and orders the sails down. It does **not** request a native anchor. `NearFieldBridge._apply` (near_field_bridge.gd:50–63) removes business navigation when the voyage is no longer underway. Native physics consequently continues with no persistent mooring operation; the captured boat drifted while waiting for the flagship. The original report did not instrument force terms, so the precise individual contribution of wave pressure versus residual motion is not claimed here.

The later rally fails for a separate, directly demonstrated reason: its drifted **starting point** fails the wet planner's conservative turning-circle check. This is not a missing rally command or a loss of authorization.

## Static native isolation

The probe loaded the actual final capture and the same formal geography/options, reconstructed the actual horizontal ship poses and velocities, and called the unchanged planner and `_autopilot` once. It did not restore unrecorded route/tack internals or advance accepted time; this is an isolation of the current geometry/control branch, not a replacement full voyage.

Both probe executions exited 0 without Godot errors. Command:

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://build/diagnostics/return-mooring-probe.gd
```

The definitive output is `build/diagnostics/return-mooring-probe.json`.

| Check | Actual result |
|---|---|
| Original 36m × 10m grain-b hull, original heading | All nine production `_wet_hull` samples pass; highest terrain is **−13.0566964m**, comfortably below −1.2m draft clearance |
| Existing SAT ship overlap | None |
| `_ship_ahead` | False |
| Kinmen target planner disk | Zero unsafe samples |
| Current start planner disk | **2 unsafe samples / 138** |
| `Planner.plan(actualStart, Kinmen, actualDimensions, formalHeight)` | `{ok:false, reason:"unsafe-endpoint"}` |
| One unchanged `_autopilot` call | Empty route, reason `unsafe-endpoint`, rudder 0, sails 0, navigation target retained |

`wet_route_planner.gd:13` uses `hypot(length,width)/2 + 8`, a **26.68154m** radius independent of the boat's current orientation. Its disk covers two shallow/land samples beside a genuinely wet narrow hull:

| Sample x | Sample z | Height |
|---|---|---|
| 293.409555044032 | 171.590470503439 | +1.54476928710938 |
| 293.409555044032 | 175.590470503439 | −0.0112041406599523 |

The planner rejects `_wet(start)` before searching a route (`wet_route_planner.gd:18`). Encounter then sets rudder and sails to zero and returns before tack, collision avoidance or low-speed steering (`encounter.gd:649`). Changing the destination alone cannot cure this starting-point rejection.

The nearby fast ship is 25.639094m away, but its angle relative to grain-b's bow is 0.724388rad, outside `_ship_ahead`'s 0.6rad cone. The order is authorized; no captured, disabled or locked policy applies. The healthy grain-b failure is unrelated to the earlier hypothesis about a severely damaged hull's high-speed turning branch.

Bridge preserves active native orders: the settled voyage's normal navigation becomes null, but `Encounter.reconcileShips` applies that null only when `hasActiveOrder` is false (encounter.gd:945–948). Thus it does not discard journey-9. The retained actual target is consistent with that contract.

## Berth geometry and limits of a manual workaround

A 10m lattice produced **97** candidate positions inside the existing 55m port radius. **47** were wet, did not overlap the other recorded boats at the tested approach orientation, and had a safe planned route from a geometrically clear nearby escape point. Every route from the original grain-b point remained rejected at the start.

One tested geometric escape is a 10° left turn to heading `−1.781045...`, then 20m forward to `(263.917014812139,158.712435208241)` (54.37480m from the port). At 30m forward the point is `(261.829973974757,148.932646839207)` (46.16006m from the port). The sampled turn and one-metre hull trajectory are wet and do not overlap the other captured vessels. From the 20m escape point, berth `(262.149928893017,107.48568719734)` is a valid planner target 20m west of the port center.

**These are geometric candidates, not a verified ordinary UI workaround.** Grain-b is `neutral`; `setPlayerId` requires an alive `player` ship (encounter.gd:799–806). The earlier suggestion to mouse-select grain-b and drive it was incorrect and has been withdrawn. No selection/ownership restriction was changed. The static probe does not prove a normal player can perform that manoeuvre, nor does an endpoint overlap check guarantee an entire subsequent automatic route has no moving-ship conflicts.

The useful player-facing fix is consequently to avoid making an unloaded, correctly arrived leased merchant drift into this recovery situation. Requiring merchant micro-control would burden the trading loop, even if a future UI could expose that control.

## Independent review of the arrival-berthing brief

Reviewed `task-arrival-berthing-brief.md`. Its bounded Bridge approach is appropriate: the game has already established real arrival, unloading and native port position; Bridge can arrange the native port-service stop through the existing atomic `_apply(...,anchors)` transaction. The planner, physics, SaveCodec, dock rules, selected flagship and save gates should remain unchanged.

The brief permits berthing within 55m after an authoritative arrived voyage. That matches the existing dock range. Genuine initial arrival itself still requires 25m and speed ≤0.75 in `Campaign._inspect`; automatic berthing must not manufacture arrival from the larger 55m range.

Implementation and review recommendations:

1. Restrict identity to this campaign's original grain-a/grain-b, grain profile, house-lin ownership and actual current authorization. Reuse **`campaign.genuine_lease(id,candidate)`**, which checks the original paid lease receipt/roster; owner text alone is not lease evidence. Match the authoritative voyage to the vessel and real destination; require `arrived` and empty cargo.
2. Read speed and position from this transaction's **actual native snapshot**. `_arrive` already replaces `candidate.pose.speed` with zero, so that staged business value cannot establish the physical ≤0.75 gate. Reject missing native membership, dead/unoperational boats, captured/disabled/locked policy and invalid native facts.
3. Preserve actual navigation and active user orders. Immediately after true unloading the old arrival navigation may still exist in the pre-transaction snapshot; skip anchoring that pass. The normal arrived projection removes it. On the next safe sync/reconcile, with navigation absent, berth normally. Do not silently cancel a rally to an explicit new point or weaken the navigation guard.
4. Reject pending native attacks, live uncaptured hostility within 600m of the candidate boat, active boarding and active port work. The existing `reconcileShips` service-anchor checks independently reject pending attacks and local hostility; retain those last-line guards rather than bypassing them.
5. Merge eligible auto-anchor IDs into the **same** `_apply/reconcileShips` transaction. Do not invoke a separate early `anchorFleet`, alter core poses, call `_stop_service` before transactional validation, or mutate the committed Campaign outside its handoff. Existing atomic refusal must leave both sides unchanged.
6. Do not trigger only once on `underway → arrived`. Arrival may already be recorded by `_traffic` before the next Bridge callback; one transition check can miss it. Moreover the current native anchor operation stops motion rather than adding a persistent physical anchor constraint. Repeated safe reconciliation must retain an idle unloaded boat, while new loading/underway voyages and new commands naturally stop qualifying.
7. Do not use a blanket `simulation.has_pending_input()` gate merely to preserve grain-b commands: that method also includes the captain holding flagship helm keys. It could prevent merchant berthing throughout the captain's return. If pending control protection is needed, inspect **that boat's** `pending_controls(id)`; never override an explicit boat control request. Existing navigation/orders remain the primary brief guards.
8. Validate the immediate post-anchor projection and subsequent native tick: live rudder, sails and velocity must actually be zero and `isAnchored` true; business control ordering/fences must remain coherent. Arrival does not explicitly reset the business rudder, and candidate state is passed as a copy into the callback. Avoid assuming a mutation to that copy updates committed Campaign. A fresh ordinary export must pass the unchanged gate and decode, rather than merely checking a helper's returned IDs.

The flagship, fast escort, inherited boat and ambient NPCs remain excluded. Captain docking and global checkpoint safety remain normal actions. Cargo, money, people, historical losses, rewards and arrival receipt chronology must not change as a side effect of a native service stop.

## Expected verification impact

No tests were written or run by this diagnosis task. The arrival implementation is owned by the separate `arrival_berthing` agent.

- Direct Campaign and SaveCodec golden scenarios should retain their exact behavior: the proposed change is in Bridge, has no new schema, and cannot alter canonical loading, unloading or payments. This is an expectation to verify, not a fresh pass claim.
- Native Bridge scenarios will intentionally change only safe arrived original leased merchants. Cover both sync and reconcile; actual resulting native motion/order facts; unchanged cargo/person/receipt state; repeated calls without duplicate rewards; all excluded identities and unsafe gates.
- Use a meaningful real transaction failure case to prove refusal is atomic. Include native speed >0.75 even if the staged business speed has been set to zero, actual navigation and active rally preservation, pending attacks/hostility, loading/underway boats, nonempty cargo and insufficient crew.
- Existing bridge fence/replay tests, waypoint handoff, continuous simulation, native reconciliation/anchor rules, campaign oracle and save compatibility remain relevant. Root owns the subsequent full suite and a new complete real captain journey; the prior 29/1 checkpoint failure must be retained as RED evidence.

## Source and evidence integrity

At the end of this read-only inspection all **11 production hashes** listed in the actual 29/1 journey capture still matched current source, including Campaign, SaveCodec, Runtime, Bridge, Encounter, order controller, navigation contract and sailing simulation. The static JSON records a further ten local geometry/control source hashes. Changes by the separately authorized implementation agent after this inspection are outside this diagnosis.

The complete static probe/data are retained for independent inspection. This report does not claim a repaired production build, an actual successful berth, renewed whole-project tests, a new checkpoint, performance results or visual acceptance.
