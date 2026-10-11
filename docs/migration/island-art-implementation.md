# Native coastal and harbor detail

`modules/scene_engine/world/island_details.gd` receives plain island/port geography
and a read-only ground sampler. It generates coastal dressing without importing
game rules, naval simulation, physics, a business catalog, or external assets.
`coastal_detail_library.gd` supplies native `ArrayMesh` geometry. Root integration
is through `WorldView`; this module does not alter terrain or water authority.

## Presentation API

```gdscript
var details = preload("res://modules/scene_engine/world/island_details.gd").new()
add_child(details)
details.configure(height_sampler, ports, {
    "quality": "balanced", # low / balanced / high
    "seed": 0,
    "max_instances": 2200,
    "focus_distance": 1000.0,
})
details.apply_snapshot({"time": 0.0, "focus": Vector2(player_x, player_z)}, 0.0)
var audit = details.diagnostics()
details.dispose()
```

`configure()` returns false after cleanup for an invalid sampler, missing or
nonfinite port x/z/islandX/islandZ/radius, nonpositive radius, or more than 64
islands. Port identity uses `id`, falling back to island center coordinates.
Ports are sorted by identity. Per-port random seeds do not depend on input order.
All placement anchors and MultiMesh transforms use world-space x/z and Y-up.
Attach the detail renderer under an identity-transform world root.

`apply_snapshot()` accepts finite authority `time`, including zero and rewind.
`focus` accepts `Vector2` or `{x, z}`. It toggles visibility of whole island groups
outside the selected distance plus island radius. Changing focus does not create
or replace geometry. Static art does not use wall time, `_process`, wind or a
shader clock. Reduced motion and accepted zero time therefore remain frozen.

`dispose()` immediately frees only owned MultiMesh nodes and clears the private
mesh cache, batches and placements. It can be called repeatedly and preserves
caller-owned children. Reconfiguration starts with disposal.

## Art layers

- Asymmetric, faceted outcrops with three silhouette variants, lighter weathered
  tops, muted warm stone faces and instance tint variation. Rock clusters follow
  broken angular sectors rather than forming a uniform ring. Sizes are roughly
  3–9m across and 1.7–4.7m tall, intended to survive an overview camera.
- Pebbles concentrate around those sectors; broad sections of beach stay open.
  Small sand-colored beach grass clumps and compact shrubs enrich existing palm,
  broadleaf and grass vegetation without adding another tree canopy.
- Three irregular interior patches per island reuse grass, shrubs and low
  weathered rocks. Patch centers vary over 28–53% of island radius; scatter is
  elongated and rotated, with 12–21m nominal breadth scaled for island size.
  Understory scales 2.5–4.4 so it reads in overview. Most interior stays open;
  house and pier/route exclusion still apply to every accepted anchor.
- Reef stones use muted green-grey materials and three variants. Their centers
  sit on actual shallow seabed; vertical scale keeps their tops below mean water.
- Pier-edge cargo includes bulging stave barrels with hoops, timber crates with
  battens and diagonal braces, round rope coils with loose ends, domed cargo nets
  made of crossing rope geometry, woven fishing baskets with a small fish load,
  rope-wrapped bollards and wood-framed lanterns. These are volumetric composite
  meshes, with narrow footprints and most barrel/crate heights around 1.4–2m
  so they remain readable from the ship camera.

Each composite prop has one triangle surface. Nine cached rough palette
materials provide warm wood brown, hemp yellow, grey-brown stone, greens and
dark timber. HTML author colors are converted to linear luminance to derive
neutral vertex shade; material albedo supplies hue and receives normal engine
color conversion. Vertex and instance brightness do not multiply a second
colored RGB palette. Each MultiMesh explicitly binds its mesh's palette material
as `material_override`. Rope tubes and weathered faces are geometry, requiring
no texture download or product dependency. Geometry winding follows Godot's
clockwise front-face convention; outward normals supply native lighting.

## Ground authority and navigation clearance

Coastal candidates are sampled along elliptical island rays. Fourteen bisection
steps locate a target height only if authoritative inner and outer samples bracket
it. Invalid samples reject the candidate. Outcrop targets are 0.35–1.75m above
mean water; pebbles require at least 0.12m and stay below 4m. Understory targets
are 2.2–4.8m. Every land anchor exactly uses the sampler's final height.

Reefs target -2.4 to -0.55m and are accepted only between -2.6 and -0.18m. Their
height is capped at 74% of sampled depth and 1.8m. A near-shore underwater shelf
does not automatically receive reefs; placements remain local to island rays.
Ocean transparency and wave phase determine how visible those submerged stones
are in the integrated image.

For all nondock detail, clearance considers geometry size:

- Every pier and its outward approach reserve local x within 13m plus footprint
  clearance, local z from -110 to 65m plus clearance.
- Each inter-port segment reserves a 24m corridor plus footprint clearance.
- Existing settlement house centers reserve 9m plus footprint clearance.

Pier props occupy local x 2.35–2.75m on alternating sides, z 3–40.6m, at actual
deck top y=4.45m (4.2m center + 0.25m half thickness). Their dimensions fit the
8m pier width. The central loading/walking lane remains empty. Decorative
meshes introduce no new colliders or navigational rules.

Interior patches accept ground above 6m; cliff-edge/dune jitter samples above
6m also use the larger readable understory scale. Low interior rocks use a
3–6m width and 0.55–1.1m height to break the smooth lawn.

Grounding uses center anchors, not a new sampler or relocated terrain. Very
rough contacts under wide boulders need visual review; terrain/water geometry
and original wave amplitude remain authoritative and unchanged.

## Allocation limits and diagnostics

Default global budget is 2,200 instances. Requests clamp to 0–4,096. Quality
controls candidate density (low 0.55, balanced 1.0, high 1.4); the same hard cap
applies to all qualities. A catalog cannot exceed 64 islands. At most 18 shared
mesh variants and nine palette materials are cached. Each nonempty island/kind/variant
uses one MultiMesh; group count is also bounded by accepted instances and
64 × 18. Sorted identities make budget truncation deterministic.

The balanced real three-island fixture after first screenshot review produced
570 instances, 54 groups, 18 meshes, 15,753 shared vertices (5,251 triangles),
26 reefs and 63 outcrops in
the scoped headless verification on 2026-10-11. These are mesh-cache counts;
instances reuse them. They do not claim a measured GPU frame-time budget.

`diagnostics()` exposes instance/group/visible-group counts, mesh count and
vertices, material count, owned node count, budget/hard limit, accepted time,
and a deep-copied placement list including port identity, kind, zone, anchor,
scale and pier-local coordinates. Inspecting diagnostics cannot mutate the
renderer's placement list.

## Verification

`rtk proxy node tools/verify-godot.mjs --filter island_details` exercises native
geometry, analytical ground vs shallow anchors, pier/inter-port exclusion,
bound palette material, neutral vertex modulation, cargo height, overview
interior scale, per-port reproducibility and input order, different seeds, focus changes,
repeated reconfiguration, accepted zero time, caller-owned cleanup, real
three-island geography, and a maximum 64-island catalog with an oversized budget.
Fresh run after screenshot corrections: `ISLAND_DETAILS_TESTS assertions=1744 failures=0`.

Root's first native screenshots showed pale cargo/rocks and empty island
interiors. Reviewer probes confirmed original CPU vertex colors and material
flags existed; the old HTML vertex colors were nevertheless treated as linear
RGB. The material boundary now supplies a proper kind palette, while vertex
data is neutral linear shading. This resolves the authored color-space and
white fallback issues; it does not prove a unique cause for the original GPU
white appearance. Native screenshot recapture remains necessary. Headless
RenderingServer instance color readback returned black in the probe, so tests
do not mistake that dummy-renderer result for a live GPU measurement.

Headless evidence verifies the placement/resource contract. Root owns native
D3D12 screenshots, integrated rendering review and full-suite evidence.
