# Wake visual regression repair

> Worker workflow: systematic-debugging, test-driven-development, parallel independent ownership, verification-before-completion.

**Goal:** Repair the hard white bow/side polygons and replace the obsolete scene wake geometry adapter with the latest recovered finite geometry.

**Spec:** User requests latest completed reverse research and actual Godot inspection. Source: `C:/Games/Pirates-REA-Reference-20261011/weather-cloud-shadow-wake-native-continuation-20261013/AGENT_HANDOFF.md`. Preserve ocean, islands, steering, camera and 3D deck crew.

**Architecture:** Keep the existing production Wakes seam. Restore authored NIF vertex color semantics in the compiler/froth consumer. Retain independent 30-point sailing, 90-point battle and local froth chains. Original finite fixture math is separate from Godot water fitting, clipping and GPU safety.

**Constraints:** Work in actual `ming-armada` checkout; preserve dirty changes. No stage/commit. No original withdrawn play reports as truth. Latest CPU research does not prove GPU equivalence. Do not submit NaN geometry. Root exclusively owns native UI/GPU.

## Tasks and ownership

- [x] Froth worker: reproduce lost source alpha through real assets and actual surface colors; restore vertex-mode/material/controller semantics; focused RED/GREEN.
- [x] Geometry worker: real normal finite source fixture RED; latest tangents/head/inactive UV/persistent buffer and literal repair contract; focused GREEN within stated numeric tolerance.
- [x] Integration auditor: packet/model/clock/visibility audit; target birth gate RED/GREEN while preserving original default particle replay.
- [x] Root: controlled production scene before/after captures at startup, developed straight wake, turning, stop and restart; all 7 final PNGs inspected. Native menu/free-sail play is additional evidence, not original game truth.
- [x] Root: inspect diffs, 26 impacted regressions, independent review, fixed P2 inactive terminal selection and report verified scope.

## Additional findings closed during GPU inspection

- Actual split-layer capture proved the remaining fan/cap came from SceneStrip. Original DDS bytes, UV and attribute packing were correct.
- Actual low-speed trace proved 6DOF heave caused 5 false samples. Target scene30 producer now uses yaw-only planar travel from the same authored marker; raw battle/froth poses and ship display remain intact. Real production packet test RED74/79 then GREEN83/83.
- Original coarse mip alpha and nonzero final row exposed terminal boundaries. Target scene shader preserves the body and source data, feathering only lateral borders and last three valid segments. Actual SourceSurface GPU readback RED3 then GREEN0.
- Independent review found inactive retained UV must not choose the terminal. Original finite inactive fixture RED2/8 then GREEN8/8; original buffers unchanged.

## Native window follow-up (acceptance reopened)

Normal free-sail mouse turning at 1069x600 exposed repeated teeth on SceneStrip edges. The earlier seven production captures and headless checks establish the repairs above, but do not close this newly reproduced rendering issue.

- [x] Compare original, depth-test bypass, constant-alpha texture and base mip sampling in frozen production frames; balanced cases did not reproduce. Reproduce saved low quality, virtual viewport mouse click and natural cadence.
- [x] Actual ocean uses REFERENCE_GAME_SHADER (transparent depth_draw_always), not the old body include. Bypass that surface depth only for SceneStrip and explicitly test opaque-pass depth; original finite buffers/attachments preserved. Actual GPU RED1 then GREEN3/3, front hull/behind object checks.
- [x] Natural low-quality production loop 8 captures, frozen same-time/pose counterfactual and restored-material proof, all inspected. Strict impacted headless10/10, feather GPU passed, independent review no findings. Computer Use normal menu -> free sail -> mouse-course at168deg/6.2kn has no repeated teeth; screenshot saved.

Delivery: `docs/migration/wake-regression-repair-2026-10-14.md`; paired inputs/headless/GPU evidence: `docs/migration/evidence/wake-regression-2026-10-14/DELIVERY_VERIFY.json`. No original DX9 parity, complete475550 lifecycle or sustained-FPS claim.

## Findings and acceptance

Current native play and prior production screenshot reproduce hard opaque bow/side polygons. Two independent audits confirm source meshes with alpha-zero vertices lose their authored colors. Old scene strip uses centered tangents, invented crossings and zeroed inactive UV, unlike latest research. Shared authored-wave count is an alias, not duplicate rendering.

Acceptance requires actual source alpha surviving upload; finite fixture topology/UV matching within documented tolerance; no hard opaque source polygon footprint in actual production capture; visibly curved historical trail, no non-finite vertices, stopped/restarted effects inspected. Other visual shortcomings discovered during inspection must be diagnosed, not hidden with global alpha tuning.
