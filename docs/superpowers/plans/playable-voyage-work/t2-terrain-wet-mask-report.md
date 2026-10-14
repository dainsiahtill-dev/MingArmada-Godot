# T2 — cached world terrain wet mask

2026-10-14. Prepares an opt-in production seam; does not enable the interactive field or modify `NavalWorldView`, the field solver, ocean, original wake history, physics, crew or sailing controls.

[Frozen evidence manifest](../../../research/evidence/wake-flow/2026-10-14-world-wet-mask/manifest.json) preserves the pre-edit source, final source snapshots, RED/GREEN and four regression receipts.

`WorldView.get_interactive_water_mask_revision() -> int` is a lightweight polling getter. A consumer should fetch `get_interactive_water_mask() -> Dictionary` only when revision changes. A successful packet contains `valid:true`, R8 `resolution`, `bounds:Vector4`, copied `data:PackedByteArray`, `revision`, `cell_m:Vector2` and content `digest`. Rectangular world domains need separate X/Z cell spacing.

An explicitly disabled/no-shore route returns `{}` as the agreed all-wet contract. Unconfigured, disposed, unavailable or failed generations return `{valid:false,error,revision}` with no data. A failed build keeps the last complete bytes internally but does not offer those stale bytes as a valid current domain. Dispose clears cached bytes. Revision is monotonic for the lifetime of a `WorldView` object, including configure, invalidation and disposal, so an owner notices invalid transitions without fetching a large byte array. Identical rebuilt content can retain the same SHA256 digest while receiving a new revision.

`terrain_wet_mask.gd` takes an already sampled `PackedFloat32Array`, vertex side and world `Rect2`. It validates all heights/domain before building `(side-1)²` cells. A cell is255 only if all four corner heights are strictly below0; touching sea level is dry. Mask bounds remain the vertex lattice's full bounds. Nearest-sampled `floor(uv*(side-1))` then identifies the correct source cell without an added half-cell offset. Resolution need not be a multiple of8; side4 creates mask resolution3, accepted by T1. The mask contract allows up to4096 cells per axis.

The existing `_configure_static_shore_field` and `_update_near_shore_field` pass their completed CPU heights directly to this builder. No height callback is added, no texture is downloaded, and no secondary grid is queried. Cache publication assigns a completed dictionary once. The getter copies the byte array so caller edits cannot mutate cached state. Static quality rebuild and dynamic chunk-domain movement both recompute bytes/digest and revision; same-window calls keep the cached version.

**Scope of conservatism:** four-corner maximum is conservative for the sampled lattice's interpolation. A coarse static shore grid can miss a small dry peak wholly inside one sampled cell; this is not a guarantee against all higher-resolution terrain triangles. Mixed shoreline cells become entirely dry, which can narrow channels; consumers can report `cell_m`. The dynamic grid matches the existing rendered near-terrain lattice. Mask domain changes must be uploaded with matching bounds as one generation and reset/reinitialize the field before new propagation; T1 currently treats world coordinates outside an explicitly bounded mask as wet.

Static side512 creates511²=261121 R8 bytes; maximum current dynamic side1153 creates1152²=1327104 bytes. The revision getter avoids copying those payloads every snapshot. This does not claim a measured frame-time improvement or GPU result.

## Verification

- Initial RED:2 assertions/2 failures, exposing missing builder and world getters before implementation.
- New CPU contract passes30 assertions/0 failures, covering literal four-corner values, exact sea-level gate, nonfinite/invalid atomic rejection, odd resolution accepted by T1, digest/domain changes, caller copy isolation, lightweight revision, static/dynamic cache publication, failure invalidation, same-window retention, dispose and actual open-water reconfigure.
- Exact static query counts remained9 and16 for3×3/4×4 source lattices; dynamic remained25 per5×5 lattice. Repeated getter/window calls made no new queries.
- Existing `test_world_lifecycle.gd`, `test_static_water_land_mask.gd`, `test_natural_game_world.gd` and `test_shore_field.gd` passed through the strict headless runner. No GPU execution or visual effect enablement.

Receipts use `Temp/research/t2-terrain-wet-mask-{red,green-initial}.json` and `Temp/research/t2-terrain-mask-{world-lifecycle,static-water,natural-world,shore-field}.json`. The pre-edit world source and SHA256 were saved before RED at `Temp/research/t2-world-wet-mask-baseline/`.
