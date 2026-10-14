# T2 generic target shadow boundary repair

2026-10-14. Frozen implementation; root's same-scene production GPU acceptance has now passed. Files changed: new `game/presentation/world/target_shadow_boundary.gd`, target adapter constructor/diagnostics, new `tests/test_target_shadow_boundary.gd`, one target-output assertion in `tests/test_rigid_shadow_preparation.gd`, and shadow paper/evidence. No wake/Ocean/NavalView edits. All GPU execution was performed by root.

## Evidence and minimal seam

Root's prior isolated GPU comparison is [158→0 far-line pixels,29→22 near-shadow pixels](../../../research/evidence/shadow-edges/DIRECTED_BOUNDARY_GPU_COMPARE.json). Its active backend receipt showed8 target/altered calls,0 rejected calls, exactly2 appended side triangles with original vertex/index prefixes and direction preserved. Root then ran the ordinary diagnostic without candidate injection: [production DIAGNOSIS.json](../../../research/evidence/shadow-edges/directed-boundary-production-20261014-r1/DIAGNOSIS.json) is valid with4 captures at24s,44 active casters,4 total added side triangles and no adapter errors. The same fixed far ROI has0 dark pixels and near ROI22, matching the isolated candidate. This is the actual generic production path, not the caster-filtered diagnostic backend.

`TargetShadowBoundary` subclasses the unchanged `PreparedRigidShadow`. TargetRigidCaster creates this subclass for every eligible target rigid caster, with no name, ship class or mesh-ID selection. The existing SourceShadowRenderer `prepared is Prepared`/`matches` checks and PreparedShadowFrame ownership certificate therefore remain in use. Generic/mutable input still uses original source Math. Original Math, RD shaders and Prepared source hashes are unchanged.

For each new immutable source topology, the subclass sums directed cap-edge multiplicities and subtracts original side edges. Nonzero signed residuals append the missing side triangles. All original positions/indices form an exact prefix, and current direction stays exact. If original side triangles exist, their original f32 apex is reused. For zero original sides with nonempty caps, a new apex is appended **after** all original vertices; source index0 is not repurposed. Its direction/addition follows the same f32 source arithmetic.

The correction cache is keyed by the original immutable index array identity, which changes when Prepared rebuilds the face-sign topology. A changing light that keeps the same face-sign pattern does not scan all caps/edges again. Corrected indices and fixed vertex references are reused; a changed apex is published in a fresh frozen outer array. Only the current source/corrected volume pair is retained. Every published nested position array is read-only. Exact repeated light returns the existing corrected volume.

The65535 vertex bound is checked before expanding side multiplicities. An oversized repair keeps the complete original bounded geometry and exposes `boundaryError`; it does not truncate or drop the caster. This limitation can leave an unresolved defect on oversized input and is explicitly visible in diagnostics.

## Public diagnostics

Existing public wrapper:

```gdscript
var status: Dictionary = scene.sea.source_shadow_status()
var adapter: Dictionary = status.casterAdapter
# adapter.boundaryBuilds : cumulative boundary computations for active casters
# adapter.addedSides     : sum of currently appended side triangles
# adapter.errors         : includes explicit over-bound repair limitations
# adapter.activeCasters, topologyBuilds, classifications remain available
```

Read after the actual render/presentation submission. `boundaryBuilds` is a topology work counter, not a frame counter; repeated light and light changes within the same face-sign region do not increase it. Removal/reconfiguration naturally replaces that actor's accumulated counters. Per-caster prepared-owner diagnostics also expose `boundaryBuilds`, `addedSides`, and `boundaryError`.

## Verification and preserved failures

[Complete baseline/candidate snapshots, hashes and receipts](../../../research/evidence/shadow-edges/target-directed-boundary-20261014/manifest.json).

- New behavioral RED:51 assertions/14 failures against original target behavior. The earlier script parse failure was corrected and preserved separately; it is not the behavioral RED.
- GREEN:57/0. The same test executes six additional checks once appended geometry exists. Cases cover two/three/four same-direction multiplicities, zero-side caps, opposite cancellation, closed oriented mesh identity, exact source prefixes/apex, unchanged-topology cache reuse, reconfiguration, immutable historical publications, bounded fallback, the actual imported defect, arbitrary actor names, and existing renderer/frozen-frame integration.
- Complete shadow regression:10 files passed,0 failed. Existing target edge oracle covers450 actual/large casters and83,339 original volume vertices; new target repair is a distinct output layer.
- First regression showed36 expected old target full-Math equality failures. The revised assertion requires complete equality for unchanged target volumes and an exact original vertex/index/direction prefix when the target repair appends sides. Generic Prepared/full Math oracle, mutable-holder fallback and deep-copy isolation checks remain unchanged. The failed first regression is archived.

Commands:

```powershell
rtk proxy node tools/verify-godot.mjs --filter test_target_shadow_boundary.gd --output Temp/research/target-shadow-boundary-green-1.json
rtk proxy node tools/verify-godot.mjs --filter shadow --output Temp/research/target-shadow-boundary-regression-2.json
```

Frozen SHA256:

- Helper:`9f5474d9883a1cd9ca15912b39157dc906f2d8454fa5456bf1c11448890fc65f`
- Adapter:`d3dd2092d514dc4ebc31b6c3a513a0f50f680f3ee6eeb92d082050b0e776e757`
- New test:`d6c260b407cca96ee839333cf3c952ce6afa141061d1a9a646ce09991fac7e86`

Root ran ordinary `diagnose-voyage-ship-line.gd` with no injected candidate as documented above. The subsequent [ordinary free-sailing GPU receipt](../../../research/evidence/wake-flow/interactive-production-1/final/GPU_VERIFY.json) is also valid with no failures and six captures at accepted seconds0,4,12,20,30,30. All retain81 active casters/volumes; addedSides are30,30,34,26,30,30, and adapter/renderer/GPU errors are empty. Root personally inspected cruise, turn and stop images: the long line is absent and the two wake arms remain. The final paused quality capture keeps the same classification and boundary-build counters as the preceding30s capture. This run uses the normal production shadow path without an injected candidate backend.

CPU cache counters establish the absence of repeated correction scans; they are not a GPU or full-frame performance measurement. Cap winding, source classifier policy and all caster-selection rules remain unchanged. Root's separate native-UI interaction evidence is outside this shadow implementation handoff.

[Independent voyage_visual review](shadow-directed-boundary-review.md) completed with no blocker. Reviewer reran57/0 boundary and546/0 preparation checks, verified frozen helper/adapter and unchanged Prepared/Math/RD hashes, and inspected the original GPU images. Production all-retained/stencil-off image hashes match the isolated candidate's corresponding images. The rigging-hidden diagnostic matched0 nodes and therefore is not an effective rigging ablation. Overflow fallback is explicitly unresolved input, and the fixed-scene GPU result is neither native pixel equivalence nor a complete performance claim.
