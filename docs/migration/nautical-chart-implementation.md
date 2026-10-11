# Ming nautical chart implementation

The shared native `game/ui/charts/nautical_chart.gd` Control presents the actual
Scene geography and Naval fleet as an aged Ming chart. `LegacyChart` retains its
old `apply_snapshot(adventure)` API for annotations, while native snapshots own
ship positions and headings. Scene placement now covers the default trial and
both career scenes; campaign adapters retain their original command semantics.

## Authority and geography

- `configure(ports: Array, height_sampler: Callable, options: Dictionary = {}) -> bool`
  detaches canonical port records and receives the existing read-only Scene height
  sampler. No port radii are converted to painted islands.
- Options: `bounds: Rect2`, `compact: bool`, `span: float`, `title: String`.
  Expanded bounds default to `Rect2(-1000, -800, 2400, 1750)`. Bounds must be
  finite, positive and at most 3840 metres along each axis. Compact spans clamp
  to 300–2400 metres, default 1100 metres, and follow the actual native player.
- World points use `{x, z}`. The projection is north-up, increasing `x` right,
  increasing `z` down. Heading zero points east; `PI / 2` points south, matching
  Naval's `cos(heading), sin(heading)` contract. World aspect ratio is preserved.
- Coastlines use marching squares on a fixed 30-metre world lattice with actual
  interpolated zero-elevation edge intersections. Ambiguous diagonal cells use
  the four sampled corner heights' average. Land polygons use elevation >= 0;
  shoal polygons use elevation >= -4 metres, with land painted over them.
  Mountain ink hatching uses sampled positive terrain, independent of ship time.
- Sampling is cached across frames and compact movements. Only a changed lattice
  window rebuilds terrain polygons; drawing/resize never calls the sampler. The
  cache retains at most 20,480 samples, evicting oldest inserted points. A full
  1100-metre compact window needs no more than 1,521 grid samples; adjacent
  movement normally adds only a row/column. Default expanded bounds need about
  4,900 samples. Extreme accepted 3840-metre bounds remain below 17,000 samples.
- Land/shoal fills are clipped, triangulated and batched into two cached 2D
  meshes. Stationary frames reuse these meshes. Compact movement or resize
  rebuilds their pixel geometry without re-reading already cached elevations.
  Each build caches its bounds/rectangle/scale once; contained polygons bypass
  intersection, while crossing/outside polygons retain exact clipping.

## Snapshot and overlay contract

`apply_naval_snapshot(native: Dictionary, overlays: Dictionary = {})` deep-copies
both dictionaries. It neither advances a clock nor writes any domain state.

```gdscript
native = {
    "time": 42.0,
    "playerId": "player",
    "ships": [{
        "id": "player", "team": "player",
        "visual": {"position": {"x": 25.0, "y": 1.0, "z": -10.0}, "heading": 0.0}
    }]
}
overlays = {
    "waypoint": {"x": 400.0, "z": 200.0},
    "activeObjectives": [{"position": {"x": 80.0, "z": 40.0}, "label": "航程目标"}],
    "routes": [{"points": [{"x": 10.0, "z": 20.0}, {"x": 100.0, "z": 200.0}]}],
    "landSites": [{"x": 40.0, "z": 50.0, "name": "古迹"}]
}
```

Native `visual.position`/`visual.heading` take precedence; top-level
`position`/`heading` are fallback fields. Flagship identity comes from
`native.playerId`. Other `player`, `ally` and `friendly` teams appear cyan;
`hostile` appears vermilion; other teams appear amber. Off-map contacts disappear,
without being moved to a misleading edge position.

Null/inactive `waypoint` becomes `{}`; null objective/route/site collections become
`[]`. Route entries contain a `points` array of canonical dictionaries. These
annotations do not invent contacts or substitute adventure fleet positions.

Legacy wrapper merges canonical catalog land sites and detached adventure
objectives/waypoint with any explicitly supplied native overlays. The caller
must configure real geography and feed the real Naval snapshot after adventure
UI refresh. `apply_snapshot` before configuration remains safe.

## Projection and interaction

- `projected(point: Dictionary) -> Vector2` and
  `unprojected(pixel: Vector2) -> Dictionary` share the same inset map rectangle.
  Header, legend, compass and ornamental margins do not issue waypoints.
- `map_rect() -> Rect2` describes that inset area; `view_bounds() -> Rect2`
  describes its current world coverage.
- Expanded left-button press emits `waypoint_requested(point: Dictionary)`.
  Compact left-button press emits `chart_requested` only. Release, right-button,
  frame and outside presses issue no intent.
- `ship_marks() -> Array` derives authoritative display records also consumed by
  the renderer. It does not alter the source snapshots.
- `dispose()` clears sampler, detached packets, geometry and mesh caches.

## Art, labels and provenance

The generated background is a material/ornament plate at
`res://assets/art/maps/ming-nautical-chart-v1.png`: aged blue-green parchment and
engraved golden cloud corners. It contains no replacement geography, title,
contacts or waypoints. Runtime ink coastlines, mountain hatching, labels, north
pointer, scale and navigation marks remain live data.

Expanded charts derive intrinsic height from allocated width, world aspect and
insets, bounded to300–500px. Actual VBox622px now uses about568px geographical
width; compact290×323px is retained. Expanded selection rings read
`selectedShipId` independently of native `playerId`; unknown IDs add no contact.

Generated source supplied by the root task:
`C:/Users/dains/.codex/generated_images/01a12087-2701-7d12-9091-fd4eb5b1d3be/exec-77234e50-c899-419c-9ebf-09d87b6cac65.png`.
Reference direction was the user's Ming chart clipboard image at
`C:/Users/dains/AppData/Local/Temp/codex-clipboard-c324d7d0-9cd4-4aff-8ad0-9e55e8dbde33.png`.

The background loads at construction if its resource exists. Missing artwork
uses native parchment and teal palette. Titles/footer/compass have pale
parchment backings; map labels have parchment outlines. Labels use runtime
SystemFont fallback (`KaiTi`, `Microsoft YaHei`, `Noto Sans CJK SC`) and original
UTF16 display normalization. Ports cap at three compact/eight expanded labels,
with rectangle collision checks. Generated text is never used.

## Focused evidence and remaining validation

Direct Godot 4.7.2 headless test: `res://tests/test_nautical_chart.gd`.
Latest focused result: `NAUTICAL_CHART_TESTS assertions=490 failures=0 samples=43964`.

Meaningful RED was first observed with the new chart missing. Later RED verified
oversized/nonfinite configuration acceptance and the real default runtime's
nullable inactive waypoint, before fixes. The focused test now covers actual
asymmetric analytic coastlines, production HeightField zero-elevation contours,
land/shoals, frame clipping of batched mesh vertices, metric round trips,
authority-derived flagship position/heading/team, detached overlays, actual
Control InputEvent handling, off-map focus/contacts, paused sampler and mesh
reuse, resize, long voyage eviction budgets and disposal. LegacyRuntime and
LegacyChart are exercised directly for nullable inactive navigation.

Headless tests establish authority, geometry, input and bounded sampling.
Root has imported the asset, captured and personally inspected all nine final
native1600×900 D3D12 screenshots under `evidence/charts/`. See
`native-nautical-chart-integration.md` for scene behavior and visual limits.
GPU frame-rate acceptance remains open. No browser,
full-suite runner, shared evidence file, frozen source checkout, domain module,
terrain mutation, independent clock or Git operation was used by this subtask.
Thirty-metre sampling approximates small coast details; compact pixel meshes
rebuild while the player moves. This chart exposes no terrain edits or simulation
commands; the scene's existing command path owns waypoint acceptance.
