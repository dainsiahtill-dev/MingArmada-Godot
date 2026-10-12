# Independent review: final-navigation recovery

**Spec: NEEDS FIX. Code quality: NEEDS FIX.** Three P2 findings block acceptance of this scoped change. No P1 found.

Reviewed the scoped patch against the preserved baseline, implementation plan, author report, and relevant native controller/physics/campaign call paths. All four SHA256 identities supplied in the author report match current files: baseline `efa4a5e072b6b542eb872bd1cc3f6cf56e84290cc8bd7a1be01f7637dc9cfc5d`; Encounter `619f09d841488f1e59e6071c9e0ce80542c71d24fbd0f0d23abdb51be89b829a`; clearance `e3cdc219209dd64738dc7df3702a32ce06840b9909e779027d8436cda591196b`; test `270b1d599a5613027d9aa4590cf07bdb2bd702a891f3d0b22e1460665fb6a650`.

## Findings

### P2 — Automatic controls permanently fence off subsequent campaign navigation

**Changed source:** `modules/naval_simulation/encounter.gd:329`, `:287`, `:730`.

The new fence treats every `controls` command as an explicit human override. However, `game/runtime/sailing_simulation.gd:113-116` emits this command on every physics tick with no navigation/order, including idle frames without held keys or an explicit user command. Campaign departure/navigation enters through `game/runtime/near_field_bridge.gd:53-62,69-71`, then `Encounter.reconcileShips` directly sets `state.navigation` at line 1003. This does not call `navigate` and does not clear `approachManualOverride`. The same ship dictionary survives reconciliation.

**Reproduction reasoning:** select a vessel while idle; advance one normal runtime physics tick; then start an authorized campaign voyage. The idle command sets the flag, Bridge assigns the voyage goal, and `_approach_authorized` rejects recovery for that vessel throughout the voyage. Later departures remain fenced until an explicit `navigate` call happens. The fixture begins with `Encounter.navigate`, so its current tests bypass this production path.

**Required fix:** distinguish genuine human control intent from automatic control restoration/idle updates. Define an authorized new voyage/goal transition that can establish navigation ownership without clearing a deliberate same-goal manual override during routine reconciliation. Add a runtime-level idle/select/depart/reconcile regression plus deliberate controls and same-goal reconciliation coverage.

### P2 — Full-rudder target is not a lower bound on actual turn rate

**Changed source:** `modules/naval_simulation/encounter.gd:719`; `modules/naval_simulation/navigation/approach_clearance.gd:11`.

The horizon divides course error by a full-rudder `Manual.build(..., 1.0, ...)` target multiplied by power, dry-mass ratio and 0.75. Actual recovery sends `ship.state.rudder` from `error * 1.8 - yaw * 6` at Encounter lines 677 and 691. That proportional controller intentionally slows near the five-degree release threshold. `Manual.torque` additionally applies bounded acceleration and yaw response; native dynamics applies yaw damping. Thus the assumed constant rate is not conservative, even with full crew and no cargo.

**Independent arithmetic check:** for a full-power merchant initially at rest with ten degrees of heading error, the predictor allows `10 / (4 * .75) + 3 = 6.3333 s`, including all three seconds of its extra interval. Iterating only the source yaw recurrence at 1/60 s, including the native bounded crew moment with 100 crew, responsive Manual torque, proportional rudder and default yaw damping, takes approximately **8.10 s just to reach five degrees**. This is a numeric source-equation check, not a Godot physics test or campaign replay. Its simplifying zero-speed assumption does not validate the full dynamics; it demonstrates that the supplied full-rudder value cannot be used as a proven lower rate.

This can accept peer motion that reaches the turning footprint after the predicted horizon but before alignment. Every-tick revalidation does not make the earlier claimed full-turn bound conservative.

**Required fix:** derive a conservative time bound for the actual proportional controller through the five-degree threshold, including acceleration/transient and opposing-yaw allowances, and reject when that bound cannot be established within the finite cap. A simpler safe alternative is to use a fixed conservative prediction interval plus a validated maximum ownership duration and safe abort reserve; merely changing the 0.75 factor is insufficient. Keep the existing physical budgets and solver authoritative. Cover small remaining errors, reduced power/cargo, opposing initial yaw and a peer arriving in the underestimated interval.

### P2 — Revalidation failure can resume sail before alignment

**Changed source:** `modules/naval_simulation/encounter.gd:667-673`; following control effects at `:683-691`.

On an owned turn, `_final_approach_clear` can reject a newly predicted crossing peer or shallow turning footprint after the original `_ship_ahead` cone has cleared. In that branch `blocked` remains false; rejection only erases `approachRecovery`. If remaining error is below forty degrees, normal logic clears `lowSpeedTurn` and increases `sailRecovery`/deployment. Because `recovery` is false, the existing Manual braking request is also removed. Clearance rejection therefore permits forward acceleration while the goal is still more than five degrees away.

**Reproduction reasoning:** acquire recovery; continue until the original ahead cone clears and remaining error is between five and forty degrees; introduce a measured moving peer whose future path intersects the turn but whose current position is outside that cone. The clearance module rejects `predicted-peer`, yet lines 673/683/686/688 select sail recovery instead of a stopped/braking fallback. This is a deterministic source-control-flow finding; no new runtime fixture was executed in this review.

**Required fix:** distinguish an owned maneuver's safety rejection from ordinary navigation without an owner. Preserve a stopped/furled, bounded braking fallback on geometry/prediction rejection, while yielding correctly to actual manual/tactical/operational ownership changes. Add a mid-turn rejection test that asserts both sail deployment and assist behavior after the old ahead cone clears.

## Scope and evidence limits

- Acquisition zone, planned/reference flags, final single-point goal, operational/control/combat checks, old candidate ordering and transient goal comparison match the intended scope by inspection.
- The patch does not change physical force budgets, shore/contact solver, arrival radius/speed, cargo accounting, save schema or Campaign authority.
- Continuous moving SAT uses measured peer translation and midpoint yaw expansion; its stated limitation concerning future peer commands is appropriate. The full-turn time bound still needs the correction above.
- Explicit `navigate`, cancellation, tactical ownership and operational changes have recognizable revocation paths. Routine reconciliation preserves the new fence, which causes the first finding.
- CodeGraph was unavailable for indexed review: root had established no project index and instructed no further queries. Review used targeted RTK reads.
- No production/test/Git mutation, author-test rerun, full suite or GPU execution. Only this report was written. Four SHA256 checks and independent Python yaw-equation calculations were performed; the latter are explicitly not actual runtime evidence. The final calculation uses the full 100-crew merchant budget; the initial 20-crew calculation was replaced.
- Author's 750-second geometry fixture and 46-second isolated arrival remain diagnostic evidence only. Root still owns fresh full-suite, real first/second voyage, cargo receipts, saved continuation and native UI acceptance.

## Resolution review — frozen three-finding correction

**Current scoped verdict: Spec PASS. Code quality PASS.** All three initial P2 findings are closed by the reviewed correction. The initial NEEDS FIX verdict and original identities above remain historical evidence. No new actionable P1/P2 found in this correction delta.

Reviewed `task-port-approach-recovery-review-fixes.patch` against the preserved first-review sources, the updated implementation report, the affected production call paths, and the added regression assertions. Independently verified current SHA256 identities:

| File | Reviewed SHA256 |
|---|---|
| `modules/naval_simulation/encounter.gd` | `51f6ba1eca84b5c925000c5db7d8a33b2718f9d770613263f9548e28c7d68faf` |
| `modules/naval_simulation/navigation/approach_clearance.gd` | `6a303f0ff243d446a4200fa06215959991ac1584250f03928764d905eac25df3` |
| `tests/test_port_approach_recovery.gd` | `94dee71d27ff2b5b0a23005e28e7b518ebfe693dff2ff6d76f32e33e87a387a0` |

### P2 closure: navigation ownership fence

Encounter now records a goal-valued fence only for effective changed controls while navigation exists (lines 328-330). Automatic no-navigation idle controls and unchanged controls no longer poison later navigation. Authorization compares the fence with the current goal (line 747). Explicit navigation clears it; authorized reconciliation clears it only when the goal changes (lines 1020-1023), preserving a deliberate override during same-goal updates. The Runtime idle/select/depart/Bridge test and direct same-goal/different-goal tests exercise the previously missing paths.

This follows root's clarified goal-identity rule. Navigation coordinates identify the fence; this is not a persisted voyage identifier and does not introduce save fields.

### P2 closure: proportional-turn horizon

The full-rudder rate division is removed. Numeric prediction uses the approved fixed 60-second interval: 40 seconds of owned turning, up to 19 seconds of stopping reserve, and one second of outgoing travel. Encounter enforces the 40-second limit through `tick - startedTick` (line 678), rather than estimating the proportional controller's completion time.

The clearance module rejects nonpositive braking/yaw damping, translational or measured passive-yaw stopping time above the reserve, and outgoing speed/stopping bounds outside that reserve. It takes no credit for neutral Manual yaw damping. The live budget still uses current crew/hull/sail power, current loaded mass, draft and steering configuration; the correction adds no physical force or solver.

A timeout produces neutral, furled, existing Manual braking. While speed exceeds .05 m/s or absolute yaw exceeds .005 rad/s, the owner cannot restart its clock (lines 675-678). Once settled, reacquisition requires another complete clearance decision. This is a finite maneuver deadline with safe stopping/retry behavior, not a claim that every proportional turn completes within forty seconds.

The new native ten-to-five-degree test directly targets the original underestimate; reduced-power/loaded timeout and opposing-yaw tests cover the new control boundary. Author reports actual native 8.25 seconds for the small turn, compared with the old 6.3333-second prediction and the new 60-second horizon. The review's earlier simplified arithmetic remains diagnostic history, not substituted native evidence.

### P2 closure: fail-open revalidation

An authorized owner's rejected revalidation returns `_hold_approach` (line 684), before normal sail recovery. The hold sets rudder, deployment and sail recovery to zero and returns neutral Manual braking (lines 706-710). Empty-route replanning also preserves that stop behavior for an existing authorized owner (lines 655-656). A settled hold whose fresh clearance still fails recreates/retains a hold, so the old clear ahead cone does not reopen sails.

Manual override, tactical orders, navigation changes and operational/combat restrictions remain authority boundaries: the native tick loop drops an unauthorized/mismatched owner before autopilot, and the existing normal authority handling continues. The correction's peer/depth rejection assertions inspect both zero sail deployment and the braking request; manual takeover explicitly checks release of the holding owner.

### Verification boundary

Author reports meaningful 119 assertions / 8 failures before repair, final recovery 132 / 0, and twelve covering commands totaling 69494 counted assertions plus the encounter golden check. This re-review inspected those tests and reported results but did not rerun them, as root requested. Only this report was changed; no production/tests/Git/GPU/full-suite activity occurred.

PASS applies to this frozen implementation and the three review repairs. It does not certify a fresh campaign arrival, cargo receipt, second-voyage continuation, safe save or native UI pacing. Those remain root-owned acceptance work. Prediction retains the documented measured-peer-motion and sampled-terrain limitations; native shore/contact handling remains authoritative.
