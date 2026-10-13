# Destruction visibility repair

**Goal:** Correct two observed production destruction overlay defects without changing damage settlement, the source event clock, or the full original-particle runtime.

**Design:** Preserve billboard mesh scale. Capture a separate smoke/flash anchor from the actual source hull support at the event's birth. Combine bounded accepted ship-pose history with an analytic model sink transform; never use a delayed render's current sinking model or move existing smoke after birth. Keep native/root event position and surface froth unchanged. The 0.35 m local lift is a named new-game presentation choice, not a recovered original dummy.

## Tasks

- [x] Reproduce actual ordinary career sinking with immutable native/campaign state.
- [x] Freeze a single native GPU frame and independently probe depth, height, size, and billboard scale.
- [x] RED/GREEN billboard regression: 91 assertions, 9 failures before the flag, zero afterward.
- [x] Preserve depth testing; recover the existing size/growth through `billboard_keep_scale`.
- [x] Compare actual source support placement; identify current-model sink placement as unsuitable for late smoke.
- [x] RED birth-anchor regression with real source boats, delayed delivery, finite history, and reset cases.
- [x] Add a pure analytic model transform query and a cached actual source support anchor.
- [x] Extend existing accepted pose history with the ship frame while preserving muzzle history semantics.
- [x] Use the captured presentation anchor only for destruction smoke/flash.
- [x] Run anchor, damage, event-time, source birth-pose, terminal, and source rendering regressions sequentially.
- [x] Capture and inspect the actual career GPU output; compare visible versus hidden puffs at identical accepted times.
- [x] Independent diff review and final evidence receipt; retain unresolved full 44-layer source and sinking froth work.

**Validation boundary:** Public lethal hull fixture and controlled production callbacks establish native presentation behavior, not a real cannon victory, performance benchmark, or pixel equivalence with the original game. Pixel difference counts measure visible overlay contribution; they do not certify artistic quality.

**Result:** Fourteen unique related Godot scripts and nine actual career GPU captures passed `Temp/destruction-visibility-verification-20261013.json`. Final anchor test: 258 assertions / 0 failures. Final smoke/flash visible contribution: 1,611 pixels at tail 0.4 s and 6,245 pixels at tail 1.6 s, using max RGB difference > 8 versus puffs hidden at the same accepted time. Native/campaign state stays at 0.15 s from death through the finite tail; the healthy frame is separately 0.1333333333 s. Remaining artistic and full-source-runtime work is not complete.
