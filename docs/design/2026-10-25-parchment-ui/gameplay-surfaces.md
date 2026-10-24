# Gameplay parchment UI surface inventory

Read-only source inventory, 2026-10-25. Product code not changed by this pass. Root agent already confirmed no CodeGraph index; discovery uses RTK source reads. Only repository-root `AGENTS.md` exists in indexed file inventory. This document is design/discovery evidence, not a GPU or input-validation report.

## Integration seams

| Surface | Actual runtime attachment | Styling seam / local override |
| --- | --- | --- |
| Current 1650 career | `game/scenes/mingqi/mingqi_scene.gd:65` creates `game/ui/mingqi/mingqi_interface.gd`; interface is CanvasLayer 20 | `_make_theme()` at 1237; `_box()`, `_text()`, `_heading()`, `_local_button()` at 1103–1144. Separate local theme means parent/global theme does not replace it. |
| Naval practice / free sailing | `game/scenes/naval_practice/naval_practice.gd:37` creates `game/ui/naval_practice.gd` | `_ready()` builds custom font-only theme plus local dark panel at 22–25, duplicated for pause/surrender/result modal at 46. `button()` centralizes every action. |
| Sailing trial | `game/scenes/sailing_trial/sailing_trial.gd:108` creates `game/ui/sailing_hud.gd` | `_ready()` local dark panel at 12–17; pale title/status/hint colors at 25/29/40; `_button()` at 43. No shared theme assigned. |
| Legacy challenges | Legacy scene creates `encounter_interface.gd` in layer 35 at 55–57 | Inherits `legacy_theme.gd` through `ThemeFactory.create()`. `_label()` and `_button()` already central. 9×7 cells copy inherited styles then reduce margins to 2px. Selected/enemy `modulate` colors at 103 remain a local override. |
| Both career charts, practice chart, compact map, trial chart | Base `game/ui/charts/nautical_chart.gd`; `mingqi_chart.gd` only adapts data; `legacy_chart.gd` is another wrapper | Custom `_draw()` entirely bypasses inherited theme. Already uses parchment chart/background textures and sepia ink. Purely stylistic substitutions belong in draw palette/background/frame, never terrain, projection, or input code. |
| Common compact map | `game/scenes/common/sea_chart_overlay.gd`, CanvasLayer 22 | Base chart owns visuals. Wrapper only places/hides it; no wrapper restyle needed. |
| Common settings overlay | `sea_services.gd:28–29`, CanvasLayer 50; also entry layer 100 in main scene | `game/ui/settings/settings_panel.gd:22–30`: dark screen shade, dark panel, pale text overrides. Shared integration belongs to settings/menu owner. |
| Recovery overlay | `main_scene.gd:30–33`, entry layer 100 | `save_recovery.gd` obtains main-menu theme but overrides full-screen deep-green shade and pale panel at 25–28. Menu owner should remove conflicting local palette. |
| Trial expanded chart chrome | `sailing_trial.gd:165–188`, CanvasLayer 28 | Dark-green backdrop at 167, gold caption at 177, unthemed close button. This is UI embedded in a scene script; restrict edits to these presentation lines. |

## Current 1650 career details

Six operations panels: flagship/handling, fleet/chart, port/trade, boarding/prizes, tactics, voyage log. All are scrollable children of right-hand `operation` panel. Story scene cards and voyage settlement card also use `_box()`; theme hierarchy can style outer folios and inset paper differently using a role/type variation without touching callbacks.

HUD contains identity/calendar, money/debt, navigation, cannon readiness, time state, current objective, progress, pause/speed/menu buttons, six navigation actions, camera actions and keys. It has a duplicate theme with 14px default size and special 12px panel margins. Preserve this compact budget. Current tests require HUD ≤430×390 at wide sizes, right panel independent, and collapsed operation leaving sea view unobstructed.

Hardcoded colors defeating theme: `_text()` defaults to `eee6d4`, headings/objectives/bill highlights use `e3c88d`, muted information uses `a9c3bd`, warnings use `ffd99a`. Replace by shared ink / sepia / muted blue / vermilion tokens. Change all explicit call-site colors as well as `_make_theme()`. `_heading()` and `_text()` are the central font-size seams; keep existing size overrides unless actual rendered evidence warrants adjustment.

Critical type assumption: `_build():202` declares `var hud_style: StyleBoxFlat = _theme.get_stylebox("panel", "PanelContainer").duplicate()`. If shared panels become `StyleBoxTexture`, widen this to `StyleBox`. `set_content_margin_all()` belongs to the base style API; there is no need to require flat style.

Existing portrait and harbor art are decorative `TextureRect`s added by `_art()` at 1204, with `MOUSE_FILTER_IGNORE`. Existing paths are `assets/art/characters/zheng-captain-v1.png` and `assets/art/ports/xiamen-harbor-v1.png`. New paper/brush/folio decoration should follow that ignore-input convention. Avoid inserting illustration banners that consume more HUD height.

Forms include SpinBox, OptionButton/PopupMenu, HSlider, TextEdit, and FileDialog. Shared styling must include embedded LineEdit, popup background/text/selection, focus indication, separators, scrollbar, disabled states and tooltips; merely styling Button and PanelContainer will leave mixed default chrome.

## Chart treatment

Base chart currently uses `ming-nautical-chart-v2.png`, fallback v1, and `ming-nautical-land-paper-v2.png`, loaded once in `_ready()`. It draws geographical terrain and live ships over that material. Keep the generated replacement texture free of invented coastlines, ports or navigation labels; map truth comes from native terrain and snapshots.

Safe restyle boundaries: background path or drawing material; ink `423b29`, frame `b3944f`, land/sea muted palette, header cartouche, label ground, seal. Current neutral ship palette includes vivid ally cyan `68d5cf`; a muted ink-blue ally color fits new direction, but player/ally/hostile contrast and legend must remain recognizable. Hostile vermilion `b94732` is already compatible.

Do not cover draw content with a new full-rectangle TextureRect. A frame texture can be drawn under the geographic content, or an input-ignored overlay restricted to outer gutters. Keep `map_rect()`, projection/inverse projection, coastal meshes, labels/collision avoidance, cache budgets and compact-map span intact.

## Input, layout and visibility boundaries

- Mingqi and practice fullscreen root Controls are `MOUSE_FILTER_IGNORE`. Never replace with input-stopping paper backdrop during active sailing. Panels should intercept only within their existing rectangles.
- Mingqi `_local_button()` captures mount/generation token and WeakRef; `_button()` adds authority/enable gates. Keep these callbacks, names and dictionary payloads unchanged.
- Mingqi text editors capture sailing keys; buttons/dropdowns/sliders do not. Preserve `_capture_editor()`, `_restore_editor()`, `captures_keyboard()`, open/close-panel focus behavior.
- Mingqi mouse sailing and camera observation currently require operations/menu/settings panels closed (`mingqi_scene.gd:271–276`). Restyle should not change that contract or disguise panel visibility.
- Base chart is `MOUSE_FILTER_STOP`; compact chart click opens full chart, expanded click emits canonical waypoint only inside `map_rect()`. Trial overrides expanded chart to IGNORE because trial has no Navigator. Preserve all three behaviors.
- Common minimap appears only when unblocked and viewport ≥820×480. Size stays 230–290 wide, height width+33, at top right. Career operations/menu/settings and practice chart/surrender/terminal states hide it. Do not add competing ornamental panels there.
- Practice HUD is max 390×460 at (18,18); terminal/menu modal max width 360, centered. Keep HFlow wrapping and scroll behavior so cannon/ammunition controls remain available.
- Encounter panel max 780 wide; grid cells 42px high with 2px margins and 13px text. Heavy textures/borders must not steal glyph width or make selected/enemy states ambiguous.

## Suggested ownership

1. Root: shared parchment theme/assets, main menu, generated paper/button variants, root background. Expose reusable theme/panel helpers and palette constants.
2. Gameplay implementer: `mingqi_interface.gd`, `naval_practice.gd`, `sailing_hud.gd`, `encounter_interface.gd`; consume shared theme only, remove local dark/pale conflicts, preserve all command/state logic.
3. Chart/chrome implementer: base `nautical_chart.gd` style-only edits and trial chart chrome at `sailing_trial.gd:165–188`. No changes to adapters or common minimap placement needed.
4. Menu/settings implementer: `settings_panel.gd`, `save_recovery.gd`, legacy theme/interface, research/ship-book/other entry UI surfaces coordinated by root. Avoid concurrent edits to shared theme.

## Existing regression coverage to run after implementation

- `tests/test_mingqi_ui.gd`: callback fencing, duplicate command guard, editor capture, narrow/wide actual layout, first-packet settling, menu/file dialog, nineteen campaign intent paths.
- `tests/test_encounter_ui.gd`: detached-model actions and callback fencing, localized action width, 9-column Chinese glyph fit.
- `tests/test_nautical_chart.gd`, `test_mingqi_chart.gd`, `test_sea_chart_overlay.gd`: actual Control clicks, projection/layout/aspect, label fitting and map wrapper visibility.
- `tests/test_naval_practice_scene.gd`, `test_mouse_course_control.gd`, `test_camera_scene_input.gd`: scene/input integration after any scene chrome changes.
- Story/flow visual text coverage: `test_voyage_ui_clarity.gd`, `test_voyage_flow_ui.gd`, `test_second_voyage_aftermath_ui.gd`.

Follow with real GPU views of current career log/trade/menu, practice active HUD/result/chart, legacy challenge grid and sailing trial expanded chart at wide and narrow windows. Test actual buttons, dropdowns, scrollbars and click-through sea behavior. No tests or GPU runs were executed during this discovery-only pass.
