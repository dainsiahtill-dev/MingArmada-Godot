# Native world, original assets and ship presentation

Implemented in the separate Godot target on 2026-10-11. The web worktree at
`C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada` is read only.
Migration behavior baseline: `9ad6a44daecd4ec36a8172d83ff27493feffe5dd`.

## Assets and provenance

`tools/migration/import-assets.mjs` copies 59 original public files: 21 GLBs
(six ships × three LODs, three sailor LODs), 18 PNGs, one JPG, two MP3s, fourteen
art prompts and three original JSON manifests/validation reports. Thirty author
tool, source lock/patch and rendering-reference files are retained under
`assets/provenance/`. `assets/migration-manifest.json` records source root, source
commit, original relative path, target path, byte size and SHA256 for every copy.
Existing accepted water textures and fuchuan LOD0 are verified and never rewritten.

The tool evaluates the original pure height function read only to produce 143
goldens, including all three islands, elliptical edges/ridges, the 2.4m shelf and
both shelf transition boundaries. It exports the original palm, broadleaf, grass,
shell, starfish and pebble author geometry to native-readable vertex/normal/color
arrays. Randomized author geometry uses recorded seed 1650. Godot performs no
JavaScript execution at runtime.

The native `AssetLibrary` caches PackedScene resources and instantiates fresh
nodes/skeletons. Original GLB loading uses GLTFDocument; exported resource loading
also supports imported PackedScenes when raw GLB bytes are absent. Original
COLOR_0 is preserved by explicitly enabling `vertex_color_use_as_albedo` for
surfaces containing vertex colors, correcting Godot 4.7.2 runtime import behavior.
Disposed libraries reject further instantiation.

## Public APIs and boundaries

- `HeightField.configure_ports(Array) -> bool`, `sample_height(x,z) -> float`,
  `sample_data(x,z) -> Dictionary`. Data is copied on configuration; invalid
  configuration is rejected before replacing the active geography. The original
  scalar-double ridge and shelf formula is ported without business imports.
- `WorldView.configure(height_sampler, wave_descriptors=[], options={}) -> bool`.
  Options: `camera`, `normal_texture`, `ports`, `chunk_size` (default 250m),
  `resolution` (default 32), `chunk_radius` (default 2), `vegetation`, `collision`,
  `ocean_resolution`, `ocean_distance`, `visual_style` (default 1).
- `WorldView.apply_snapshot(snapshot,consumed)`: `snapshot.time` injects the sole
  simulation time; optional `snapshot.focus={x,z}` chooses the terrain window.
  Otherwise camera X/Z selects it. `get_ocean`, `get_chunks`, `get_chunk_count`,
  `get_chunk_build_count` provide observable state. `dispose` only frees owned nodes
  and supports repeated configure/dispose without touching caller-added children.
- `ShipView.configure(kind,asset_library=null) -> bool`,
  `apply_snapshot(ship,wind={},consumed=0)`, `apply_events(Array)`,
  `set_lod_distance(metres)`, `get_lod`, `get_model`, `dispose`. It consumes original
  camelCase naval snapshot fields and contains no steering, combat or damage rules.

WorldView keeps at most `(2*chunk_radius+1)^2` chunks (radius bounded to 0..4).
Stable windows retain meshes instead of repeating expensive terrain builds.
Collision is generated from the same sampled terrain mesh. Biome colors use the
original smoothstep interpolation in linear color space; beaches/grass are continuous
gradients. Original procedural vegetation meshes use bounded native MultiMeshes.
Ports preserve original pier/pile/house positions, dimensions, colors and roof slopes.

WorldView integrates the separately owned ocean module's bright style, fixed 512²
signed height/coast-distance textures covering configured islands plus 100m, and a
bounded 160-instance shore spray node. Ocean and spray receive the same snapshot
time. Fully underwater shelves receive depth tint without fake coast foam.

ShipView retains all three original GLBs and the original 220/650m LOD thresholds.
Godot Euler order YXZ uses `(-pitch, PI/2-heading, +heel)`. Original mast pivots,
furl/inflate morphs, wind-relative inflation sign and normalized rudder factor 0.42
are driven by snapshots. Actual fire events choose the nearest original smoke
socket/cannon, recoil its corresponding barrel across LODs by 0.6m, and use the
original `exp(-consumed*9)` recovery. Replayed event IDs are ignored; pause freezes
flags and recoil. Sailor allocation/animation/impacts, wake effects, sail damage
masks, sinking rules and full game orchestration remain separate subsequent work.

## Direct verification

Initial RED: asset test reported missing migration manifest; world test reported
missing native HeightField, WorldView and ShipView. Cannon RED reproduced missing
immediate 0.6m single-gun recoil and incorrect exponential recovery. GREEN uses
the actual `4.7.2.stable.official.ed1daf0bf` binary in headless mode:

```powershell
rtk proxy node tools/migration/import-assets.mjs
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_asset_manifest.gd
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_world_lifecycle.gd
```

Assertions cover source/target SHA256 and original author hashes, all 21 imported
models, actual sail morphs/COLOR_0, eighteen bones and six clips, separate active
skeletons, original height goldens at 1e-10 scalar tolerance, exact pose signs,
terrain/collision ownership, bounded/stable windows, smooth colors, pause/time,
LOD, per-gun recoil and repeated disposal. This document records native CPU/import
evidence only. GPU appearance, input feel and full playable scene acceptance require
Root's actual rendering/captures; these tests do not certify them.

Fresh focused results: `ASSET_MANIFEST_TESTS assertions=910 failures=0` and
`WORLD_LIFECYCLE_TESTS assertions=1707 failures=0`. The world run included the
current real-coast distance texture and shore-spray integration without warnings.
An attempted whole-suite run encountered the concurrently incomplete campaign
script (`save_codec.gd`, `_ordered`, `_prize_command`, `prize_state` absent at that
instant); it was stopped and is not recorded as a green suite. Root owns the final
integrated suite after all parallel implementation files are complete.
