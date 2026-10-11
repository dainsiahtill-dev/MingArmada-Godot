# Legacy career and encounter native UI

The native presentation lives in `game/ui/legacy/legacy_interface.gd` (CanvasLayer), `legacy_chart.gd` (Control), `legacy_theme.gd`, and `game/ui/encounters/encounter_interface.gd` (Control). It reads detached snapshots and emits intent dictionaries. It never imports or constructs game models, advances time, writes saves, generates rewards, or changes fleet resources.

The source is the read-only web worktree at HEAD `9ad6a44daecd4ec36a8172d83ff27493feffe5dd`: AdventurePanel, AdventureShell, DialoguePanel, EncounterPanel, SurrenderPresentation, and the authored legacy catalog. CodeGraph reported the target unindexed; discovery used RTK fallback without creating an index. The original web project was not changed.

## Scene contract

```gdscript
var ui = preload("res://game/ui/legacy/legacy_interface.gd").new()
add_child(ui)
ui.set_readiness_provider(runtime.preview_command)
ui.command_requested.connect(route_intent)
ui.view_requested.connect(set_tactical_view)
ui.apply_snapshot(runtime.snapshot())

var mini = preload("res://game/ui/encounters/encounter_interface.gd").new()
add_child(mini)
mini.command_requested.connect(route_intent)
var packet = runtime.snapshot()
if packet.runtime.encounter != null:
    mini.apply_snapshot(packet.runtime.encounter, packet.runtime.revision)
else:
    mini.apply_snapshot({})
```

Legacy packet: `adventure` is canonical AdventureSession state, `naval` is the actual native encounter snapshot, and `runtime` supplies generation, revision, paused state, handling mode, notice, canSave/saveReason, surrenderQuote, pendingSurrenderReceipt, encounter, and lastSaveReceipt. All copies are detached.

`set_readiness_provider(Callable)` receives the original partial command with original field names and returns `{ok,reason,cost?,reward?}`. The actual Runtime `preview_command` is the preferred seam. Alternatively, `runtime.previews[LegacyUI.command_signature(command)]` holds detached receipts. The signature sorts top-level command keys and serializes without dictionary key sorting; callers should use the static helper rather than recreate the algorithm. Missing receipts disable business actions and display a reason. UI resource arithmetic does not authorize trade, service, docking, departure, land visits, retirement, or encounter launch. Gates query only currently visible controls, cache duplicates within a refresh, and revalidate before emitting a business command.

Every emitted intent includes the current `generation`, `expectedRevision`, and unique `uiRequestId`. The last field is UI transport metadata, never persisted business data. Native actions retain `{type:'native-action', action:{type:'fire'|'select-ammo',shipId,side?|ammo?}}`. `set-sails{value}`, `trim`, `navigate{point:{x,z}}`, and `set-handling-mode{mode}` remain Runtime intents. Rename passes editable native text; Runtime owns `Text.encode_native` at its boundary. All source display strings use `Text.display_text`.

After every routed command finishes, Scene calls `ui.acknowledge_command(intent, receipt)` before presenting the next snapshot. Pass the original emitted intent and actual completion receipt containing `ok`, including refusals and disk/file/export failures. Cover early return routes such as main-menu/save-and-menu. Matching completion releases that request's pending entry without changing business revision; old nonce/generation/mount acknowledgments cannot release a newer request. Synchronous signal reentry and the 250ms wall-clock duplicate window remain blocked. A changed revision also invalidates old pending entries. Readiness refusals before dispatch never create a pending request.

Scene routes UI-only actions explicitly: `panel{value:id|false}` controls Runtime `set_pause('panel',value!=false)`; `menu{value:bool}` controls `set_pause('menu',value)`. The independent pause reasons prevent closing one surface from resuming another. `save`, `export-save{kind:current|backup}`, and pasted `import-save{json}` go to Runtime. `import-save{path}` comes from the actual FileDialog; Scene reads the file before calling adopt/save validation. `save-and-menu` requires a successful verified save before leaving. `main-menu` requests normal exit; `main-menu{discardUnsaved:true}` is the explicit failed-save recovery choice. `settings{value}` is routed to the native settings owner. Root owns app navigation and persistence of settings.

Public presentation methods: `open_panel(id)`, `close_panel()`, `get_selected_panel()`, `is_panel_open()`, `open_menu()`, `close_menu()`, `is_menu_open()`, `captures_keyboard()`, `request_shortcut(code)`. Aliases crew/missions/settings-career map to recruit/quests/settings. I opens quests, M chart, F nearest actual port docking or current-port market, B fleet with actual boarding targets, Esc cancels a current surrender quote, closes menu/panel, or opens menu. Scene may forward keyboard shortcuts; editable LineEdit/TextEdit focus protects typing, while buttons/selectors/sliders permit held sailing input.

## Source feature coverage

| Native page or surface | Source behavior presented |
| --- | --- |
| Market | Six goods, local stock and flagship cargo, independent quantities, actual quoted buy/sell and refusals, copied goods art and harbor image |
| Shipyard | Actual hull/sail damage, repair, hull/cannons/sails/equipment upgrades, all six authored ship types and minimum crew/capacity/guns |
| Recruit | Crew counts and minimum departure crew, recruitment, solid/chain/grape ammunition quantities and stocks, divide-plunder |
| Officers | Three authored roles, descriptions, price and daily wage; real hire preview |
| Quests | Active/port/all filter, main and repeatable quest text/status/progress/issuer/deadline/rewards, original accept/complete IDs and port destination requests |
| People | Three source NPCs with copied portraits, welcome/trade/waters/commission topics, mission route and actual banquet gate |
| Fleet | Every owned ship, hull/sail/crew/mincrew/cargo, flagship selection/sale, original transfer-crew/transfer-cargo fields and actual hostile boarding targets |
| Factions | Four actual relations and trade/entry implications |
| Chart | Actual six ports/islands, five land sites, fleet and live objectives, geographic click waypoints, port/site waypoint buttons, docking, land visit, treasure/fort launch |
| Log | Actual entries in chronological order |
| Save | Save gating/refusal/failed receipt, current and verified-backup export, actual native file selection and paste import |
| Settings/career | Handling selection, native quality/music/sound/motion intent, volumes, rename, source key help, save/return, surrender request, explicit retirement confirmation |
| Compact HUD | Actual career resources/day/port, notice, pause/departure, actual ship hull/sail/crew/speed/guns/trim, sail slider, original ammo/fire actions and live reload/refusal |
| Result | Native victory/defeat acknowledgement, canonical career ending/score, actual surrender token confirmation/cancel, silver/cargo/ship/quest loss breakdown, save/export recovery |

The chart's click coordinate projection follows the source world bounds. Waypoints request real navigation and do not move ships or claim arrival. Quest destination buttons retain the canonical port destination; actual live objectives are plotted from state.

## Four encounters

Encounter packet fields: `id`, `generation`, `kind`, `targetId`, `difficulty`, `practice`, `context`, `state` (or model), `settled`, `paused`, and optional actual `settlement`. The interface emits `encounter-action{id,action}`, `encounter-pause{id,value}`, `encounter-retreat{id}`, `encounter-settle{id,disposition?}`, `encounter-retry{id}` (practice only), and `encounter-close{id}`. Generation and revision are attached to each request. No success, found, victory, injury, reward, or score is submitted by the UI.

- Duel presents live player/enemy HP, stamina, combo, cooldown, telegraph and action window. Original strings: high, low, thrust, guard-high, guard-low, parry, dodge. Career wins require the explicit capture/plunder/release button; generic settlement cannot silently capture.
- LandBattle renders all 63 cells, walls/cover and friendly/enemy health. Clicking friendly selects its original ID, empty terrain requests original move coordinates, enemy requests its original attack ID; end-turn is explicit. Actual model rejects blocked/unreachable/out-of-range actions.
- Treasure preserves fog, revealed terrain, guards, clue, player position/health/moves/digs. Four original directions and dig submit actions only; no treasure-found result is constructed.
- Banquet presents actual cue directions/timing/window, hits/misses, combo and raw model score. A settled career result displays Runtime's actual normalized score, paid fee, and before/after canonical silver/morale/fame/relation. Practice settlement states that career resources remain unchanged.

`request_key(code)` exposes J/K/L/U/I/O/Space and direction keys to Scene. UI does not own clocks or model reset. Coordinator owns practice retry identity and accepted encounter time independently from the paused sea.

## Lifecycle and sizing

Controls persist while generation and entity IDs remain stable. Snapshot refresh updates bound text and readiness; it preserves focused uncommitted text and quantities. Generation replacement rebuilds with a new mount token, clears drafts/debounce, and prevents stale callbacks from commanding a new voyage. Panel selection and closed/open state persist through structural rebuild. Repeated business/native-fire/save requests are suppressed for the same revision and a 250ms duplicate window; continuous sail/navigation changes remain responsive.

The settings page hydrates quality/music/sound/reducedMotion/volumes from confirmed `packet.settings`. Routine snapshots update untouched fields and preserve dirty fields plus focused uncommitted volume text. When the confirmed value matches a draft, that field becomes clean and can follow later confirmed changes. Generation replacement rehydrates every field even when the previous generation had a focused edit. Apply uses the full unchanged confirmed values and edited draft values, so rounding the volume display cannot overwrite untouched persisted precision. Volume fields display fractional percentages. Apply still emits intent to the existing verified settings persistence owner; failed persistence retains the draft.

The HUD uses a scroll container and sizes to actual content with a 380px/43%-viewport cap. The twelve page tabs use a real HFlowContainer and wrap inside the scrolling operation surface. Menus, results, and encounters also use actual ScrollContainer/layout controls. Below 1120px operation panels stack under the measured HUD rather than overlap. Every action button reserves width measured from its actual font and text; 9-column encounter cells use compact style margins so two Chinese unit glyphs fit at 400px. Actual resize/minimum-size changes schedule layout without frame polling. Source-derived teal, parchment text and brass borders use the existing copied assets and system Chinese font fallback.

## Verification

Focused commands (Godot 4.7.2):

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_legacy_ui.gd --quit-after 2000
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_encounter_ui.gd --quit-after 1000
```

First RED: missing legacy/encounter interface assertions, one failure each. Subsequent RED regressions covered actual 1100px overlap, hidden costly readiness queries, Escape surrender cancellation, absent sailing Controls, paused live HUD height at 1600/600/400px, failed-save exit recovery, nine implicit capture branches, and absent actual banquet settlement display. Root's real D3D12 opening-market/chart screenshots exposed collapsed narrow buttons; 36 actual font-width/tab-wrap assertions reproduced the defect before the fix. A separate 400px grid assertion caught clipped two-glyph Chinese unit text before compact cell margins fixed it. Their final outputs and counts are recorded in the implementation report.

Tests instantiate actual Controls, emit their signals, inspect actual focus/layout, use source fixtures for exact command fields and refusal branches, replay all four native models against original source states, and make actual Runtime sailing/banquet calls. No test supplies a gameplay success/reward as UI output. GPU appearance, Scene routing, app transitions, live audio settings, real file selection/import/export persistence, and full-suite acceptance remain Root integration work; focused headless UI results do not claim those outcomes.
