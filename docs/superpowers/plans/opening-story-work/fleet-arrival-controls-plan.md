# Fleet arrival controls: scoped gameplay reliability repair

User-approved direction: improve story and playable sailing/fleet loop; graphics wait for REA. This repair closes the genuine second-voyage return failure before native aftermath acceptance. No production or QA fixture is allowed to fabricate a return.

## Evidence and intended behavior

Current second actual run delivered20/20 grain and earned250 silver; flagship returned toXiamen, but no full-fleet checkpoint. CarrierB completed Rally at2156.6 with rudder0.144827 unchanged until2981.6, drifting21.88m to103.79m fromport. Fast already approached its protect station at1511.6 with sail0 and rudder1; by1541.6 its future turn envelope was unsafe. Egress owner widening or changing QA to navigate alone cannot recover the final native pose.

The current autopilot computes a turn toward a reached final station while deploying no sail. Completion must relinquish its old helm, and a reached final navigation point should hold a neutral helm while preserving the active navigation/order so a moving station can be followed again. Native position, velocity, yaw and normal slowing remain untouched. The ordinary manual-control command must retain its newly requested helm when canceling the old order.

## Work and acceptance

1. Preserve the current112/112 unfiltered passing record alongside the immutable initial111/112 and genuine second82/1 failure. Independent investigators finish control-owner and actual-timeline reports.
2. Add focused regression tests before production changes: staleRally completion controls; reached final autopilot station neutral controls; intermediate waypoint still steers; moving target can resume normal navigation; manual takeover preserves newcontrols; no pose/velocity/yaw edit; existing permission, wind, hull, terrain, peer, Approach and Egress gates unchanged.
3. Make the minimum Encounter-owned cleanup. No generalized_cancel_order neutralization, no staticRally recovery-owner extension, no physics force change, no Save gate relaxation. Independent Spec/Quality review, with actual native short simulation from failed-pose evidence if practical.
4. Run targeted regressions and then fresh full suite. Freeze a new distinct evidence phase because production source changed. Fresh actual first and second journeys consume current sources and unchanged captain intents.
5. Only a real full-fleet Xiamen checkpoint authorizes native aftermath choice/Save/Continue captures and personally reviewed screenshots. Keep all prior failures and phases immutable. If the repair is insufficient, diagnose the actual new run before any further change.

This is a reliability subtask of the broader active game goal; it is not final completion or graphics acceptance.

## Arrival-hold scope ruling

The preventative early final-point hold is restricted to ordinary navigation without an active tactical order, or the current protect owner whose protected target is actually anchored, current decision exactly matches the navigation goal, and no fire/threat decision or manual ownership applies. Moving-target protect and other tactical intents continue their existing steering; departure or changed objective is re-evaluated eachtick. Existing Approach/Egress state has precedence and must not be bypassed. Rally terminal cleanup is separate. Operational/control/crew/capture/service gates remain applicable. Start with neutral coast in real short native ticks; only use an existing bounded neutral brake if evidence requires it. No new owner authorization, brake budget or physical state edit.

## Physical stopping evidence requires a second repair

Candidate5cceb84d fixed stalehelm and passed88focused checks. Independently reconstructed B completion at2156.6 remained wet/neutral but physically coasted: initial21.88093m at0.5474735m/s,120s23.253931m,240s49.131922m,360s69.202872m,400s75.920593m and0.1593327m/s, anchored=false. Hence neutralization alone fails the fleet-return objective. Root interrupted only owned fresh-first PID24180/session17385 at150simseconds; arrival-and-aftermath freeze/interruption record remain immutable diagnostic evidence, never a successful voyage.

The next TDD seam may apply only the existing bounded Manual neutral-braking budget under a fresh, explicit current Rally terminal-stop owner, with native physical integration. It must retire on actual stop or bounded timeout and revoke on manual/newnavigation/neworder, participant/permission/service/capture/crew/hull/sail/combat/terminal-state changes. Unchanged idle controls cannot revoke solely by controlsSequence increments. No new force/clearance/arrival/Save budget, no teleport/instant anchor, no changed completion threshold. Active stop must prevent Save until neutral output is fully released; no ephemeral stop state may leak silently into a save. Architecture and independent Spec/Quality review precede a distinct fleet-stop-and-aftermath source freeze and fresh actual voyages.

## Terminal settling navigation and input synchronization

While its wrapper-only terminalStop is active, the ship retains the exact original Rally goal in state.navigation as the actual pending settling navigation. Marker processing takes precedence over ordinary autopilot; completed order threshold stays25m/1mps. Successful physical retirement, timeout or explicit revocation clears only that still-owned navigation, never a newly requested goal or manual values.

SailingSimulation already refreshes native autonomous controls after every fixed STEP inside its advance loop. Keeping the goal through at least one published fixed-step snapshot synchronizes its formerly cached helm to the new neutral outputs. Physical stop retirement requires tick>startedTick in addition to existing speed/yaw thresholds; total60second deadline is unchanged. This covers the near-already-stopped .04mps Rally completion case as well as multi-step advance calls. No SailingSimulation API/source change or special interpretation of autoTrim angle echoes is required unless a real failing regression proves otherwise.
