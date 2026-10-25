# Blender maritime kit implementation plan

> Execution: superpowers:executing-plans, inline. User explicitly requests Blender production, game integration and actual gameplay acceptance. Preserve the existing uncommitted workspace; no commits, resets or cleanup of others' files.

**Goal:** Deliver original Blender assets visible through normal Godot gameplay, with editable source, exported meshes, regression evidence and observed native play.

**Architecture:** Reuse CoastalDetailLibrary's grounded Y-up single-surface ArrayMesh contract and existing harbor placement/MultiMesh batching. Add an original cannon barrel through the existing cannon node, preserving recoil transforms, muzzle sockets and gameplay state. Keep original geometry available as baseline/fallback.

**Tech Stack:** Installed Blender 5.4.0 Alpha fbe82a461016, Python bpy, GLB, Godot 4.7.2, GDScript, native Windows Computer Use.

**Spec:** This document includes the bounded asset brief below. The broader Zheng campaign proposal remains separate from this asset-production task.

## Asset brief and scope

Create eight independent editable assets: wooden cargo crate, staved water barrel, coiled hemp rope, netted grain sacks, woven basket, timber mooring bollard, planked landing skiff with oar, and muzzle-loading cannon barrel. The grain-sack cargo assembly counts as one production asset. The skiff is a harbor prop, not a new playable ship. The cannon is a visual replacement, not a new weapon statistic.

Each asset: meters, grounded origin except cannon's axial origin, consistent export orientation, bevelled readable silhouette, restrained wood/hemp/iron palette, UVs and vertex color, one material/surface for batching, no external texture/mesh dependencies. Preserve individual source components in .blend. Export runtime GLBs separately. These are historically informed game interpretations, not certified reconstructions of specific surviving objects.

Alternatives considered: (1) full new sailing ship requires sail/deck/waterline/crew contracts and would dilute this delivery; (2) port-only props would omit battle relevance; (3) coherent harbor cargo/skiff kit plus cannon barrel supports both requested experiences with existing gameplay. Adopt (3) as implementation judgment.

## Global constraints

- All shell calls use RTK. CodeGraph returned unindexed earlier this session; use targeted RTK reads, do not index.
- Keep all user work. Back up exact touched existing files and hashes before edits. Work in current checkout so the user's current paper UI and world are retained.
- No changes to inventories, damage amounts, saves, storyline, sail/crew physics or authoritative time.
- Model assets and rendering integration do not prove improved gameplay or frame rate.
- Baseline and candidate must retain counts, positions, collision clearance and event sockets. Independent viewer precedes production wiring.
- Real native interaction is required; scripted captures are supplementary and labelled.

## Review focus

1. GLB color/UV/orientation survives Godot import; one material remains suitable for MultiMesh override.
2. Imported meshes are cached without retaining scene nodes; instances and resources release normally.
3. Harbor footprints remain compatible with the existing placement clearance and grounded origin.
4. Cannon replacement preserves muzzle, recoil nodes, source transforms and owner-isolated mutable state.
5. Ordinary entry, pause/resume, movement and firing remain usable; native screenshots are distinct from diagnostic renders.

## Tasks

- [ ] 1. Record baseline hashes and scoped tests. Create Blender authoring script and retained .blend, eight runtime exports, manifest and actual Blender preview render. Validate topology, bounds, UV/color and material count.
- [ ] 2. Add independent asset reader and focused import/cache/bounds tests, observe RED then GREEN. Register a bounded laboratory comparison with baseline/candidate. Inspect real GPU appearance before wiring.
- [ ] 3. Wire harbor kinds and cannon geometry through existing seams. Test placements, batches, cannon sockets/recoil and source ownership; retain rollback through original paths.
- [ ] 4. Run relevant regression plus repository runner. Launch isolated-save ordinary game, use native controls to inspect harbor, sail and fire. Fix observed task-related issues and rerun affected checks.
- [ ] 5. Independent final review, asset manifest/hashes and candid delivery report with exact measured and unmeasured scope.

## Execution ledger

- Initial audit: existing workspace has many unrelated edits. The two target asset-provider files were clean against HEAD. Blender found at C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe; version executed successfully.
- Ruling: current checkout used rather than creating a HEAD-only worktree, because gameplay acceptance must include the user's uncommitted current assets/UI. Exact target files will be backed up before change.
- Ruling: user's direct production-and-play instruction supplies execution authorization; proceed through reversible modelling and integration without repeated permission prompts.
