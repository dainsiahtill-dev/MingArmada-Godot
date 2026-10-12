# Safe arrival berthing

The actual opening voyage delivered 40 grain and reached the Kinmen clerk, but grain-b drifted from its genuine low-speed unloading point at 327.42s to 71m outside the harbor while waiting for the flagship. A later rally failed because the wet-route planner's conservative turning disk was unsafe at that drifted starting position. Do not weaken the route planner, physics, SaveCodec, dock/export gates, or counterfeit a checkpoint.

Ruling: berth the original leased grain transports after genuine arrival under the existing native transaction boundary. This removes unnecessary harbor micromanagement; an incorrect gate could stop a commanded or threatened transport, so explicit navigation, active orders and combat must prevent automatic berthing.

Implement only in `game/runtime/near_field_bridge.gd` with a meaningful new `tests/test_arrival_berthing.gd`; preserve the pre-edit file for an exact scoped diff. No other production files, graphics, performance, git mutation, saves, or QA tools.

Use TDD: real Campaign/Bridge/Encounter transactions and native snapshots, observe an expected failing behavior before implementation. Fixtures may configure test-only legitimate campaign scenarios; never treat a fixture as actual voyage evidence. Tests must verify actual berthing and retained cargo/ship/person state, not merely a helper return value.

Requirements:

- Only the two original leased grain ships of this campaign, authorized in the current native policy, alive, operational with enough able crew, original grain profile and house-lin ownership.
- Their authoritative voyage exists, matches the vessel, has status `arrived`, and cargo is empty. A loading/underway voyage or unleased ship must not qualify.
- The actual native ship is within 55m of that voyage's real destination port and has horizontal speed <=0.75. Do not move its position or revive anyone.
- Pending attacks, a live uncaptured hostile within 600m, active boarding, active port work, captured/disabled/locked policy, actual navigation or an active order prevent automatic berthing. Preserve user commands; don't cancel a rally to an explicit new point.
- Apply via the existing `_apply(..., anchors)` / `reconcileShips` transaction in both `reconcile` and `sync`, respecting existing error/atomicity behavior. Repeated reconciliation must keep an already berthed ship stable and must not duplicate business rewards, payments, losses or personnel changes.
- Do not berth the flagship, fast escort, inherited ship or random NPC boats; the captain still docks normally and `export_save` still requires the normal full fleet safety gate.
- Do not add a new persistence schema, runtime bypass, test-only production hook, or universal ship anchoring shortcut.

Run new test red/green, scoped bridge/navigation/native/continuous/campaign/save tests plus the two existing oracle scenarios if appropriate; root will run the full suite once and actual captain journey after source freezes. Record commands, red/green output and limitations in `task-arrival-berthing-report.md`; provide exact scoped patch + hashes. All shell commands start with RTK. Godot 4.7.2 exe is in `C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`. Repo `C:/Users/dains/Documents/Git/ming-armada`, old ambient `MingArmada` is read-only. CodeGraph has no index and instructed not to call again this session. No commit/stage/reset/push/clean, no touching editor PID8384. User authorized autonomous gameplay implementation.

Ruling: preserve explicit native navigation once a voyage is already arrived; clear its old automatic destination only on the normal underway-to-arrived handoff (and fresh startup). Existing reconciliation erased later user navigation every sync, which could make auto-berthing disregard a captain order. Cover both cases through real native commands; no loading/underway routing change.
