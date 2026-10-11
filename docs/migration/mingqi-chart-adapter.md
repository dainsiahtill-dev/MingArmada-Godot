# Current-1650 nautical chart adapter

`game/ui/mingqi/mingqi_chart.gd` now inherits the shared antique nautical chart. The original `fleet_chart` Control name, `apply_data(vessels, ports, routes, selected)`, and `point_requested(point)` interface remain available. Route selection, convoy accounting, trade, and canonical command construction retain their existing implementation.

The Root scene injects its immutable Scene height authority after mounting the interface:

```gdscript
interface.configure_chart(heights.sample_height) # bool, false rejects invalid sampler
interface.apply_snapshot(packet)
```

The interface retains this Callable across campaign/generation rebuilds. Every new chart reads `game/data/mingqi_geography.json` for the three canonical native port positions. Its stable world bounds encompass the island extents with a 90 metre margin: `Rect2(-755, -335, 1425, 905)`. Port radii determine coverage only; the shared renderer derives coastlines, land, and shoals by sampling the actual injected terrain.

Campaign route points are copied into `routes:Array[{points:Array[{x,z}],minimumDepth}]` overlays. Native `packet.naval.ships[*].visual.position` supplies chart contact positions. The campaign's flagship ID fills a missing native `playerId` identity without supplying a position. Campaign vessel poses never create contacts or stretch the chart, including when native contacts are absent. All snapshots and overlays are detached at the chart boundary.

Expanded chart clicks emit canonical world X/Z, round them into the existing tactical form, and update its real SpinBox controls. The click emits no navigation or tactical command. The existing `navigate` Button remains the authority for `{type:"navigate",shipId,point:{x,z}}`, with the existing operational, pause, controllability, native presence, pending-command, generation, and mount fences. Non-navigable frame clicks are ignored by the shared chart. Retired charts cannot edit a rebuilt interface.

Root can query `interface.is_panel_open()` and `interface.is_menu_open()` when setting compact-chart visibility. A compact chart click belongs to Root and opens `interface.open_panel("convoy")`; this adapter does not issue orders from that click.

Verification on Godot 4.7.2, headless:

- TDD red: missing injection API produced `MINGQI_CHART_TESTS assertions=1 failures=1`, exit 1.
- Focused adapter regression: `MINGQI_CHART_TESTS assertions=25 failures=0`, exit 0.
- Existing real five-panel interface regression: `MINGQI_UI_TESTS assertions=195 failures=0`, exit 0.
- Both passing runs had no script/resource diagnostics. The focused test uses saved source campaign/native fixtures, production geography and height field, an actual Control mouse event, real form controls, and the existing Navigate button.

Root owns combined Scene/runtime/GPU and full-suite verification. These focused headless runs do not claim those results or visual acceptance.
