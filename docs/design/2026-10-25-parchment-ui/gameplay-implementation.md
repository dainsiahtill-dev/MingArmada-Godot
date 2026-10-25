# Gameplay UI implementation evidence

Status: gameplay implementation complete and frozen for GPU capture. Shared theme and generated paper resources are connected. Twelve targeted headless suites passed; normal GPU visual review remains with the runtime verification owner.

## Changes

- `game/ui/mingqi/mingqi_interface.gd`: consumes `Parchment.create()`, uses base `StyleBox` for compact HUD panel and 8px HUD button margins, gives inset paper to story/settlement cards, replaces all pale-text overrides with shared ink/sepia/cinnabar tokens, and applies title font to headings. Existing form callbacks, authority checks, token/generation fencing, layout coordinates, and snapshot updates remain intact.
- `game/ui/naval_practice.gd`: shared theme for HUD controls, generated paper for HUD and result/pause folio, dark status/notice colors and title font. All actions and disabled-state rules unchanged.
- `game/ui/sailing_hud.gd`: shared theme and paper HUD, ink text and title font; direct pause/assist/camera signals unchanged.
- `game/ui/encounters/encounter_interface.gd`: shared theme, heading hierarchy, muted blue selected-unit tint and muted vermilion enemy tint, retaining neutral white tint and explicit friend/enemy text. Existing 2px grid padding preserved.
- `game/ui/charts/nautical_chart.gd`: shared body/title fonts and ink/frame/status palette. Chart retains original generated geographical-paper materials, native terrain, live ship markers, projection, label fitting, and click logic. No decorative chart image is placed over live geographic truth.
- `game/scenes/sailing_trial/sailing_trial.gd`: only expanded-chart shade, caption styling and close-button theme change. Trial world/physics/input behavior untouched.
- `mingqi_chart.gd` and `sea_chart_overlay.gd`: no edits required; inherit base chart visuals. Existing minimap size/visibility/input rules preserved.

## Before implementation

All four targeted baseline suites passed under Godot 4.7.2. Reports are stored under `evidence/`:

- `baseline-test_mingqi_ui.json`
- `baseline-test_encounter_ui.json`
- `baseline-test_nautical_chart.json`
- `baseline-test_naval_practice_scene.json`

Observed baseline Mingqi HUD in the saved-data UI fixture: 430×375 at 1600×900 and 1100×900, with that fixture's regression maximum of 430×390. The fixture omits native ships and the story projection, so this number is not the complete live opening HUD budget. See the live-data comparison below.

These initial headless baselines used the pre-existing verification runner environment. The four suite sources contain no user-slot/save writes. Subsequent runs use task-specific child-process APPDATA/LOCALAPPDATA isolation, as coordinated with runtime verification owner; no environment setting is persisted globally.

## Test-first integration check

`tests/test_parchment_gameplay_ui.gd` instantiates real gameplay UIs. It verifies generated paper resources reach actual panels, body/title/secondary/notice text uses opaque dark ink, fullscreen roots/decorations retain input boundaries, actual pause/trim buttons retain canonical intents, and encounter friendly/enemy/neutral states remain distinguishable by color and text.

Before implementation, its first run reported 18 assertions / 12 failures: the expected paper-resource and dark-ink assertions failed, while existing input/action checks passed. This is retained as `evidence/gameplay-paper-red.json`. Encounter checks were subsequently added as complementary semantic coverage.

## After implementation

All runs below use isolated child-process `APPDATA` and `LOCALAPPDATA` directories under `Temp/parchment-ui-profiles/gameplay/<test>/`. Evidence files follow `evidence/gameplay-r1-<test>.json`. The runner verifies completion markers, zero failures, process status and absence of script/resource diagnostics.

| Suite | Assertions | Result |
| --- | ---: | --- |
| `test_parchment_gameplay_ui.gd` | 29 | Pass |
| `test_mingqi_ui.gd` | 195 | Pass |
| `test_encounter_ui.gd` | 1085 | Pass |
| `test_nautical_chart.gd` | 507 | Pass |
| `test_mingqi_chart.gd` | 25 | Pass |
| `test_sea_chart_overlay.gd` | 11 | Pass |
| `test_naval_practice_scene.gd` | 16 | Pass |
| `test_mouse_course_control.gd` | 152 | Pass |
| `test_camera_scene_input.gd` | 79 | Pass |
| `test_voyage_ui_clarity.gd` | 37 | Pass |
| `test_voyage_flow_ui.gd` | 25 | Pass |
| `test_second_voyage_aftermath_ui.gd` | 110 | Pass |

Total: 12 suites / 2271 assertions / 0 failures. Scoped `git diff --check` also passed.

The themed saved-data fixture HUD measured 430×360 at 1600×900 and 1100×900; that fixture's initial packet also settled at 430×360. Existing narrow-window, editor-focus, menu/file-dialog, stale-token, command-payload, chart-click and sea-input regressions passed. This confirms those fixture layout and state contracts in headless Godot; it does not establish every live HUD's height, GPU contrast or image quality.

## Live opening HUD clarification

The actual MainScene GPU capture `evidence/gpu-mingqi-r1/mingqi-story-1600.json` records a 430×470 HUD. A follow-up read-only comparison instantiated the unmodified interface source from HEAD `68b0e1dbb868a0b584dd7fb7e3482a642eb411a9` (copied into `Temp`, without replacing product files) and the current interface against the same canonical initial `mingqi_runtime.snapshot()`. Both received five native ships and the story projection. Results in `evidence/live-hud-comparison.json`:

| Packet | Before paper theme | Current paper theme |
| --- | --- | --- |
| Saved UI fixture, no native ships/story projection | 430×375 | 430×360 |
| Canonical initial runtime with native ships/story | 430×486 | 430×470 |

The current live packet adds three visible rows absent from the saved fixture: broadside readiness 39px, objective 35px and voyage progress 18px, each with a 6px gap. Total: 110px, exactly explaining 360px versus 470px. The paper treatment reduced the comparable live HUD by 16px; it did not establish a universal 390px height limit.

The before/current comparison used native Controls in headless Godot with the same current runtime and a flat -12m sampler. It is controlled layout evidence, not an old-build GPU replay. Current 470px height additionally has the actual GPU capture. No Mingqi product code changed during this investigation.

## Outstanding validation

Real GPU captures, visual review and pointer checks are coordinated by the runtime verification owner: current career six pages/menu, practice HUD/result/chart, legacy encounter variants and sailing trial expanded chart, including wide/narrow views. Gameplay product files are frozen for this capture pass. No 3D world, shader, combat, physics, navigation or save logic changed in this group.
