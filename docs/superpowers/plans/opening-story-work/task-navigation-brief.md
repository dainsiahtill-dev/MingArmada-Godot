# Gameplay task: transport waypoint handoff

Repository C:/Users/dains/Documents/Git/ming-armada. Every shell command rtk. No subagents, git mutations, GPU, sea/island/particle/physics changes or performance work. Preserve Story/Campaign/SaveCodec source freeze and original locate_route math/oracles.

## Real symptom and evidence

Root tools/play-opening-story-journey.gd --flat uses real Runtime inputs and no pose/cargo/health/victory injections. In docs/migration/evidence/opening-story/journey-flat.json, grain-a waits about90seconds at149–150,79–83 while its catalog waypoint is164.4685,78.3321, voyage leg1/progress.963 and native navigation keeps targeting the same intermediate waypoint. Ship stays afloat/healthy. Flagship later sank under enemy fire; do not weaken enemy, guarantee captain victory or treat a naive driving script as combat proof.

Source root cause candidate: Campaign.locate_route only promotes leg when projection progress>=1, while Encounter._autopilot deliberately lowers sail to0 at distance<=18m for a final navigation target. Bridge passes each intermediate catalog point as a final single target, so a ship can stop inside native reach but never satisfy exact business projection.

## Ownership / expected repair

Own `game/runtime/near_field_bridge.gd`, optional small generic `modules/contracts/navigation_contract.gd`, `modules/naval_simulation/encounter.gd` only to name the unchanged18m native reach constant. Add `tests/test_voyage_waypoint_handoff.gd`. Do not edit Campaign.locate_route, stock/unload/arrival thresholds, physics speed, enemy gunnery, or other worker files.

Bridge chooses the next catalog waypoint once an actual near vessel is inside native reach of an intermediate waypoint. It must never skip a final port target or synthesize arrival/delivery; final port remains actual25m/low-speed business check. Preserve existing wet route planning from actual current position to new target, permissions, controls, ownership, pose and cargo. fresh_startup keeps navigation null; when outside reach target remains old point. Shared navigation reach must remain18m (unchanged ship controls).

First prove the contract mismatch with a meaningful failing test using actual Campaign/NearFieldBridge/Encounter projection at a deterministic ship position14m before an intermediate waypoint. Unit starting position is a test fixture, not acceptance teleport or invented delivery. Assert the actual native navigation chooses following waypoint, final point never skips, outside radius never skips, current pose/cargo/permissions unchanged, and actual subsequent native ticks move along next leg. Cover fresh_startup. If your investigation disproves the candidate, report evidence before any changes.

Run scoped bridge/nav/readiness/save regressions and preserve full outputs. Full journey through combat may be lost honestly; focus tests prove reliable transport continuity independently. Report `task-navigation-report.md` and a scoped baseline/diff here, with source hashes, RED/GREEN and limitations. Root owns full actual journey/capture/playability follow-up.
