# Player flagship Blender production and integration

> Inline execution using executing-plans. This supersedes the eight-prop maritime-kit plan after the user clarified that the main deliverable is the ship the protagonist drives, including rudder, sails and many components.

**Goal:** An original modular, controllable fuchuan flagship authored in Blender, integrated with the actual game, accepted through native gameplay and directed regression.

**Architecture:** Author three GLB LODs in a new namespace; a dedicated provider supplies model metadata and animation roles. Preserve the original reference provider for baseline and reference tests. ShipView uses the new fuchuan for normal gameplay after independent validation. Retain physics specs and all other ship kinds.

**Tech Stack:** Installed Blender 5.4.0 Alpha, bpy, GLB, Godot 4.7.2, native Computer Use.

**Spec:** This document, current ship-fuchuan concept v2 and production research (concept scale/lines are approximations, not historical certification).

## Scope and constraints

- Primary deliverable: one complete player flagship, not harbor dressing. Nominal physical envelope 32 m long, 9 m beam, 2 m draft; existing four guns per side. The concept's three openings per side is explicitly adapted to the authoritative four-gun battery, not a silent physics change.
- Separate hull, decks, stern cabin, railings, hull trim, rudder blade, rudder stock/tiller, three masts, battened cloth, yards, standing/running rig, flags, eight cannon assemblies, anchors, capstan, hatch and cargo fittings.
- Original textures/geometry generated in Blender; editable .blend and authoring script retained. Three LODs, export manifest, consistent meters/Y-up/+Z bow, texture packing and actual bounds.
- Existing accepted snapshots drive rudder, sail trim, furl/inflation, recoil, damage, water attachments and crew. No new wall-clock animation. Pausing does not move rig components; rewinding resets accepted state.
- New rig/appearance integration follows an independent laboratory topic before normal game wiring; record fixed inputs and true GPU images separately from native player observations.
- Protect all existing changes and user saves. Exact source backups retained. No commits, resets, pushes or deletion of prior work.

## Approach

Use a dedicated authored provider with the existing ShipView roles. Extending the original extracted-asset manifest would blur provenance. Replacing the entire renderer/physics would risk working gameplay. A new provider plus narrow model choice keeps both original baseline and new ship independently usable.

## Review focus

1. Hull waterline, +Z bow, muzzle positions and crew deck support match gameplay coordinates.
2. Three LODs keep independently mutable meshes/shape keys, identical rig role names and instance-owned nodes.
3. Furl includes battens, trim rotates sail assemblies; rudder and tiller visibly move from actual input.
4. Smoke origins and recoil agree with authoritative cannon directions; no material/shader color loss.
5. Ordinary new-game/practice entrance shows the new ship; pause/restart/dispose and save behaviour remain valid.

## Tasks

- [x] 1. Author detailed modular flagship in Blender, create source/GLBs/manifest and inspect Blender render.
- [x] 2. Implement dedicated provider and independent laboratory rig test. RED/GREEN import, bounds, sails, steering, deck support, guns, isolation, lifecycle. Inspect true GPU continuous frames.
- [ ] 3. Integrate through ShipView; update provenance expectations where intentionally changed, retaining original provider regression. Run affected tests and repository suite.
- [ ] 4. Launch ordinary game with separate save directory, use native controls to sail, turn, trim/furl and fire; inspect model at normal/close camera, preserve evidence and fix defects.
- [ ] 5. Fresh final review and delivery with actual verified scope and remaining limitations.

## Ledger

- User steering: prioritize the protagonist's multi-component ship. No harbor model was produced or integrated before this correction.
- Current fuchuan simulation: 32x9 m, draft2 m, four guns each side. Existing visual maps to barque; new art will retain the game dimensions and replace only appearance.
- Concept v2 inspected. Three masts/battened sails/deep keel/raised stern adopted as art direction. Exact underwater lines, stern proportions and historical hardware remain design interpretations.
- The first multi-test runner filter used a pipe expression but runner accepts a substring; no tests selected. Replaced with individual substring runs, preserving the failed command as a tooling error, not test evidence.
