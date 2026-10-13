# Terminal sinking and impact presentation implementation plan

> **For agentic workers:** Use Superpowers subagent-driven-development for the clock and scene tests; root owns scene integration and all Godot execution. Preserve the existing checkout; no staging, commits, worktrees or pushes.

**Goal:** Let existing sinking and crew impact effects finish after the native encounter settles, while all native/campaign authority stays frozen and user pauses remain effective.

**Architecture:** A shared scene-level bounded clock retimes a deep presentation snapshot only. It advances exclusively from accepted scene physics callbacks after result pause; it does not advance the runtime, alter native events, or create a wall-clock timer. Mingqi keeps full presentation once per render, with immediate anchor/fire/crew-hit flushes. Crew water-entry presentation events wait for the effect owner to reach their original birth time.

**Tech Stack:** Godot 4.7.2, GDScript, existing source ShipDamage, CombatEffects and Jolt ImpactPool.

**Spec:** `docs/migration/remaining-game-details-2026-10-13.md`, formal terminal defect and crew gaps; existing test contracts.

## Constraints

- Actual project `C:/Users/dains/Documents/Git/ming-armada`; old Three.js and reference workspaces read-only.
- Root alone executes Godot; preserve the user's editor and run one native game at a time.
- Result `victory`/`defeat` plus an actual sunk ship is required. No fabricated surrender death.
- First lethal callback anchors at native event time; no double-counted accepted native interval.
- Tail lasts at most 10 seconds, at most 0.25 seconds per physics callback. This covers the 7-second crew body lifetime plus a late 2.8-second water effect. Any extra pause or Mingqi rate 0 blocks it.
- Pause/completion retain the last presentation phase. Epoch/time/status changes and disposal/reset remove the old offset.
- UI, minimap, campaign and native data retain authoritative time and values. Audio sees the presentation phase only while allowed, including the final accepted tail callback.
- Existing source explosion/froth keys fire once; loaded already-dead actors do not replay historical keys.
- Preserve pre-step projectile observation, original event birth data, per-physics source poses and Jolt integration.
- Deferred crew water-entry must not weaken CombatEffects' general future-event rejection. Clear pending presentation events on epoch, rewind, fleet reset and disposal.
- Settled result stops drawing frozen projectile meshes. Native projectile data, ballistic state and hit events remain intact.

## Tasks

- [x] Revalidate current source and reproduce RED: `Temp/terminal-presentation-red-current-20261013.json` has the expected missing clock and real flagship sinking freeze.
- [x] Implement `game/scenes/common/terminal_presentation_clock.gd` and clock unit boundary tests. Agent owns these two files only.
- [x] Add inexpensive runtime pause-reason access and integrate the clock into actual Mingqi and Practice scenes. Root owns runtime/scene changes.
- [x] Expand actual scene regression tests: defeat, final-enemy victory, frozen authority, finite hiding, pause/resume, restart, event keys and a real 18-bone rig's per-physics age/request. Test Agent owns the scene test only. `Temp/terminal-presentation-green-20261013-v2.json`: three terminal scripts pass.
- [x] Reproduce and fix deferred crew water-entry loss with original event time/position/id preserved. Root owns Sea presentation changes and a focused regression. RED then GREEN recorded; late splash and frozen ball carrier RED then GREEN also pass.
- [x] Run focused terminal, damage, pause/runtime, deferred pose and crew schedule regressions. Root owns all test execution; independent reviewer audits the production diff. Seventeen related scripts pass; `Temp/terminal-detail-verification-20261013.json` indexes current evidence.
- [x] Run an actual native capture through the ordinary menu using a public validator lethal fixture; compare first-death/intermediate/ended frames and frozen authority. Six v2 frames viewed; `Temp/terminal-presentation-native-20261013-v2/capture-result.json` failures=0. Fixture and manual diagnostic callbacks are accurately labeled; no real-cannon or FPS claim.
- [x] Update the current detail inventory with verified fixes and remaining unimplemented systems. The full game-detail goal remains active. New control-study learning/gaps are documented separately; original integer motion kernels remain unintegrated.
