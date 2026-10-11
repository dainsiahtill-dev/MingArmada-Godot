# Native island and working-harbor detail

`modules/scene_engine/world/island_details.gd` owns deterministic native 3D
dressing. `coastal_detail_library.gd` owns reusable procedural ArrayMesh assets.
Both consume plain geography/read-only ground authority, importing no game,
naval simulation or physics rules. Root owns WorldView integration and actual
D3D12 screenshot acceptance. Terrain, ocean, original trees and original houses
remain where they were.

## API and lifecycle

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

Configure rejects invalid sampler, missing/nonfinite port coordinates or radius,
nonpositive radius and catalogs above64 islands. Identity is port id, falling
back to island coordinates. Sorted identities and per-island seeds preserve
geometry when catalog order changes. Attach under an identity-transform world
root: anchors/transforms use world x/z and Y-up.

Snapshot focus accepts Vector2 or {x,z}. Whole island groups cull beyond selected
distance plus island radius. Focus never rebuilds geometry. Finite authoritative
time includes zero/rewind. Art has no wall clock, process loop or wind; accepted
zero time and reduced motion remain frozen. Dispose immediately frees only owned
MultiMesh nodes and clears private resources/placement/support records. Repeated
disposal preserves caller-owned children. Reconfiguration starts with disposal.

## Screenshot-led composition, phase2

Root's actual island-shore.png and harbor-details.png confirmed better colors
but still showed a large smooth green island, tiny sparse understory and little
visible port life. Three concrete composition changes:

1. Three broad asymmetrical inland groves combine medium coastal broadleaf
   canopies, larger grass/shrub undergrowth and low weathered rock shoulders.
   Grove breadth24–37m before island-size scaling; elongated scatter and rotating
   offsets leave large empty breaks. Trees exceed7m world height with branched
   trunks and overlapping crowns. Understory scales3.5–6.2; rock shoulders are
   8–13m across and1.8–3.8m tall. A compact central copse supports smaller islands
   when clearance removes outer grove candidates. Original shoreline palms stay.
2. Two working yards flank the preserved pier approach. Native small houses
   with raised plinths, upturned eaves, windows and front steps mix with open
   lean-tos and market stalls. Setbacks/spacing/orientation vary; yard bundles
   reuse crates, barrels, nets and baskets. Buildings require sampled support
   and avoid the original house ring. Stylized late-Ming coastal volumes;
   no historical reconstruction claim.
3. Warm path/yard dressing uses small volumetric gravel fragments with broken
   outlines and native stone faces. They follow ground slope, reserving original
   house footprints and loading/approach corridors. No giant plane, projected
   poster, altered height field or submerged rectangular marker.

Earlier coast layers remain: broken weathered outcrop sectors, pebbles, beach
grass, small shrubs and genuinely local shallow reefs. Pier-edge barrels, crates,
rope coils, domed nets, fish baskets, bollards and lanterns retain taller readable
cargo dimensions and an open center lane.

## Material boundary

Meshes use one triangle surface. Fourteen cached rough palette materials supply
wood brown, hemp yellow, grey-brown stone, restrained greens and weathered
architecture/ground colors. HTML source colors convert to linear luminance for
neutral vertex shading; StandardMaterial3D.albedo_color supplies hue and receives
engine conversion. Instance tint only varies brightness. MultiMesh explicitly
binds the authored surface material_override. Clockwise faces/outward normals
supply native lighting.

Original GPU white appearance was not attributed conclusively to one cause:
independent CPU probes found vertex colors/material flags intact. Corrected
color-space handling and nonwhite material boundary were confirmed by Root's
subsequent first-batch screenshots. Phase2 aesthetics still require recapture;
headless results cannot prove final pixels or GPU frame time.

## Placement, support and exclusion

Fourteen contour bisection steps locate targets only when finite inner/outer
ground samples bracket them. Land anchors exactly sample ground. Coastal rocks
target0.35–1.75m, pebbles0.12–4m, dune understory2.2–4.8m. Inland groves require
height above6m. Reefs accept-2.6..-0.18m and remain below mean water; water shader
and wave phase determine visibility.

Nondock clearance considers actual reusable-mesh footprint. Exclusion reserves
pier local x within13m plus footprint, local z-110..65m plus footprint, 24m
inter-port lanes plus footprint, original house centers within9m plus footprint.
New structures reserve adjacent ground for yards/nearby dressing; tree sites
enforce minimum5.5m spacing. Architecture precedes less important decoration
when global budget is small.

Building plinth/post bottoms embed in sampled ground. Corner tests reject slopes
which expose bottoms or penetrate usable floor/counter/roof clearance. Tests
independently inspect actual lowest mesh vertices against ground. Raised floors
and steps accommodate slope without relocating terrain.

Gravel normal derives from +/-0.3m ground samples. Local-axis scale follows slope
orientation; global row scale would flatten tilt. Every bottom-edge vertex must
meet sampled ground within0.18m or placement rejects. Each piece is a small solid
stone; tangent fits do not replace terrain authority or claim exact conformance
over a large flat surface.

Pier cargo uses deck top4.45m (center4.2 + half-thickness0.25), x edges2.35–2.75m,
z3–40.6m. Decoration adds no collider or simulation rule.

## Bounded cost and diagnostics

Default global budget2200, hard clamp0–4096; quality low0.55/balanced1/high1.4.
Catalog limit64; cache ceiling23 meshes/14 materials. One nonempty
island/kind/variant MultiMesh group; groups bounded by instances and64×23.
Sorted identity makes budget truncation deterministic. Architecture attempts,
grove sectors and path candidates are bounded. Each path caps balanced steps72,
quality-scaled, so huge finite radii cannot cause unbounded sampling work.

Balanced real three-island fixture on2026-10-11:1040 instances,65 groups,
23 meshes,17946 shared vertices;42 trees (supply8/Kinmen13/Xiamen21),17 structures
(5/6/6),264 path fragments (83/84/97),25 reefs and56 shore/interior outcrops.
These are reusable geometry/instance counts, not measured GPU performance.
Diagnostics exposes counts, visibility/resources/ownership/budget/accepted time
and a deep-copied CPU placement/transform list. Dummy headless GPU buffer reads
are not used as actual rendered transformation/color evidence.

## Focused verification

Phase2 runs Godot directly via RTK with --headless --path <project> --script
res://tests/test_island_details.gd. No sharedverification.json, GPU capture,
full-suite or Git operations. Root owns broader integration evidence.

Fresh: ISLAND_DETAILS_TESTS assertions=3039 failures=0. Covers native geometry
and bound palette, analytical/real grounding, pier/route/original-house exclusion,
embedded structure footing, slope-following gravel, readable inland scale,
per-island composition, seed/order reproducibility, focus/reconfigure bounds,
zero time, ownership-safe cleanup,64-island hard cap and radius1e9 bounded work.
Initial phase2 test failed for missing medium composition. Contact checks then
exposed/corrected nonuniform global scale flattening gravel tilt.

Independent review then caught inward gable caps on opposite roof halves and
the negative-side underside facing up. Actual house/stall ArrayMesh tests failed
16 checks before repair. Cap order now follows x*side and underside order follows
side. Tests inspect all four cap triangles and four underside triangles per roof,
checking stored outward/downward normals and actual Godot clockwise winding.
Counts and all placement transforms remain unchanged; latest3039 checks pass.
