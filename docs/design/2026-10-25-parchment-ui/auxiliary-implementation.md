# Auxiliary scene UI implementation evidence

2026-10-25. Eight auxiliary presentation files now consume the shared parchment theme. Product files are frozen for runtime screenshot review.

## Implemented scope

| Surface | Presentation changes |
| --- | --- |
| `game/scenes/practice/practice.gd` | Shared theme and ledger-paper background replace full-screen green rectangle. Generated decoration ignores mouse input. |
| `game/scenes/visual_qa/visual_qa_inspector.gd` | Paper panel and shared control theme; retains 14px general diagnostic UI and 11px dense readout. Selected scenario text clips within narrow control, while popup item text and emitted scenario remain intact. |
| `game/scenes/reference_island_water/reference_island_water.gd` | Ledger background behind existing layout, paper controls panel, dark labels and serif headings. Existing 3D viewport, environment and materials unchanged. |
| `game/scenes/fidelity_island/combined_island.gd` | Shared theme, small paper toolbar and bottom status strip. No background is placed over the 3D viewport. |
| `game/scenes/fidelity_island/fidelity_island.gd` | Same local toolbar/status treatment, preserving original 3D world and input callbacks. |
| `game/scenes/natural_island/natural_island_prototype.gd` | Same local toolbar/status treatment, preserving seeds, terrain, forest and camera behavior. |
| `game/scenes/ship_book/ship_book.gd` | Already inherited shared paper through `legacy_theme`; no remaining hardcoded UI palette found. Title now uses `HeadingLabel`. Existing 3D environment/sea colors are not UI and remain unchanged. |
| `game/research/demos/voyage_flow_experiment.gd` | Independent read-only label sits on a bounded paper folio, with input ignored. Disposal owns the new paper container and its label. Fixture, projection, fixed timestep, reset determinism and state transitions are unchanged. |

Intentional exceptions: `architecture_convergence_experiment.gd:150` and `weather_shadow_experiment.gd:217–218` retain light text with dark shadows directly over 3D diagnostic scenes. This preserves scene readability without covering the scientific view with paper. These are explicit retained diagnostic treatments, not additional parchment coverage claims.

## Failures observed and repaired

1. Initial auxiliary environment directory used `aux`, a Windows reserved device name. Godot could not create its user-data directory. Subsequent runs use `Temp/parchment-ui-profiles/auxiliary/<suite>/{roaming,local}` through child-process environment only. Failed reports remain retained; no global environment was changed.
2. Voyage folio introduced a new parent for the existing label. Its original disposal attempted to remove the label directly from the Node3D, and the existing lifecycle test failed. Disposal now removes/frees the paper owner. The same 16-assertion lifecycle test passes, including repeated deterministic reset and zero remaining presentation children.
3. QA scene runs exceeded the standard runner's 60-second ceiling both during baseline and the first post-change run; startup and quality rebuilding alone took about 49 seconds. A dedicated run with a 180-second maximum exposed one actual narrow-layout failure. The long selected `impact-weak` item forced OptionButton minimum width to 286px, the panel to 314px, and its right edge to 326px in a 320px window. A lightweight real-Inspector regression reproduced this without constructing the world. Setting `clip_text=true` on only that OptionButton allows the panel to fit; popup text and its canonical action remain intact. Final complete QA scene passed in 45.1 seconds. The timeout reports are retained and are not presented as passing runs.

## Current verification

All headless runs use isolated APPDATA/LOCALAPPDATA under the task's `auxiliary` profile. Tests launch the actual Godot scripts; UI/state tests are not substitutes for GPU visual review.

| Test | Assertions | Evidence |
| --- | ---: | --- |
| `test_practice_entries.gd` | 88 | `evidence/aux-post-r1-test_practice_entries.json` |
| `test_practice_presentation_schedule.gd` | 56 | `evidence/aux-post-r1-test_practice_presentation_schedule.json` |
| `test_reference_demo_scene.gd` | 35 | `evidence/aux-post-r1-test_reference_demo_scene.json` |
| `test_natural_island_prototype.gd` | 10 | `evidence/aux-post-r1-test_natural_island_prototype.json` |
| `test_combined_island_scene.gd` | 12 | `evidence/aux-post-r1-test_combined_island_scene.json` |
| `test_fidelity_island_scene.gd` | 16 | `evidence/aux-post-r1-test_fidelity_island_scene.json` |
| `test_ship_book.gd` | 840 | `evidence/aux-post-r1-test_ship_book.json` |
| `test_laboratory_voyage_flow.gd` | 16 | `evidence/aux-post-r2-test_laboratory_voyage_flow.json` |
| `test_visual_qa_scene.gd` | 17 | `evidence/aux-post-r3-test_visual_qa_scene-extended.json` |
| `test_visual_qa_inspector_layout.gd` | 5 | `evidence/qa-inspector-layout-r4.json` |

Final: 10 suites / 1095 assertions / 0 failures. Complete QA run checks exactly one completion marker, zero script/resource diagnostics and exit 0. Eight changed scripts also passed `--headless --check-only`, recorded in `evidence/auxiliary-parse-r1.json`; the later one-line Inspector clipping change compiled and passed through both Inspector and full-scene runs. Scoped `git diff --check` passed.

No changes were made to shared theme, previously frozen gameplay UI files, experiment algorithms, save contracts, shader/environment settings or simulation clocks. Remaining verification is actual GPU layout/texture/contrast/pointer review, coordinated by the runtime owner for catalog and auxiliary scene captures.

## Final-review P2: voyage paper resize

Independent review identified that the new folio read its viewport width only during construction. `test_voyage_flow_paper_resize.gd` reproduced six failed assertions before the fix: the paper did not narrow/reflow and no demo-owned resize subscription existed. The fix subscribes to the owning viewport's `size_changed`, recomputes available width and compact content height, and responds to the label's changed minimum height after wrapping. Disposal disconnects the viewport subscription before freeing its presentation.

Final targeted run: 24 assertions pass for 960px startup, narrowing to 360px, restoring width, unchanged fixture/clock, and three repeated configure/dispose cycles with one live listener and none after disposal. The existing 16-assertion voyage lifecycle suite also passes. Evidence: `evidence/voyage-paper-resize-red-r2.json`, `evidence/p2-fixed-test_voyage_flow_paper_resize.json`, and `evidence/p2-fixed-test_laboratory_voyage_flow.json`. Scoped diff whitespace check passed. The product demo is frozen again pending the coordinated GPU capture; fixture contents and state clocks remain unchanged.
