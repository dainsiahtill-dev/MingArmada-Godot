# Fleet-arrival and aftermath freeze/evidence tooling

Owner files only: `build/second-aftermath-work/freeze-fleet-phase.py`,
`build/second-aftermath-work/verify-fleet-phase.py`, and this record. Writable
repository: `C:/Users/dains/Documents/Git/ming-armada`. Old tooling, production,
tests, QA, source freezes, user saves and evidence stay outside this lane.

Preparation only. Neither freezer nor acceptance verifier is run. No voyage,
GPU capture, browser or full test suite starts. New phase selection and final
acceptance are not created. Root runs normal commands only after the reviewed
Encounter/new-test correction is complete and the appropriate evidence is ready.

```powershell
rtk proxy python build/second-aftermath-work/freeze-fleet-phase.py
rtk proxy python build/second-aftermath-work/verify-fleet-phase.py
```

The first command creates source/QA freezes; the second exclusively creates the
final judgment after all actual evidence and root personal visual inspection.
Do not treat either command's preparation or guard tests as gameplay acceptance.

## Exact new contracts

New phase: `docs/migration/evidence/opening-story/fleet-arrival-and-aftermath`.
Base source freeze is259 supported product/test/formal-data/runner files. Actual
unfiltered discovery/runs are113 distinct `test_*.gd`. QA inventory is14 paths,
all unchanged. No optional final/test freeze is supported in this new phase.

Previous immutable baseline is old phase `source-freeze-final.json` (258 paths,
the already reviewed wet-egress test correction) plus `qa-source-freeze-final.json`.
Pinned previous raw SHA identities:

- Source final: `b710efd0cfea7927d93c0f112961610786991926afa6bc4eae8061edff669246`.
- QA final: `a060fecc62782512d3828cd028519ced94e84d5f79b5dabbddc6875bbc44615e`.

Freezer accepts exactly one changed existing path:
`modules/naval_simulation/encounter.gd`; exactly one added path:
`tests/test_fleet_arrival_controls.gd`; zero removed paths. Every other previous
source hash is identical. All14 QA mappings/hashes remain identical. Counts,
delta, supported source inventory and distinct test discovery are checked before
writing; sources and old references are rechecked immediately before write.
Both new freeze records bind pinned previous paths/SHA in
`previousFrozenReferences`. Existing freeze or acceptance record refuses freeze;
both outputs use exclusive creation. No selection/acceptance is created by freezer.

Verifier requires current259 source hashes and exact inventory; current14 QA
hashes and immutable previous-reference/delta proof; newly completed unfiltered
113/113 strict native runs after the new freeze timestamp. Every run needs its
actual source-derived completion marker, exit0, false timeout, no process/reason
failure and no Script/Parse/Compile/resource errors. Historical successful112 or
failed voyage82/1 cannot substitute. Every new native runtime source inventory
still has22 exact current source identities, including the changed Encounter.

`artifact-selection.json`: same seven distinct repo-relative paths confined to
this new phase: `first`, `second`, `opening`, `return`, `afterShare`, `afterDebt`,
`afterKeep`; `journeyRuns.first/second` bind actual zero exit, false timeout and
final literal native journey completion. Native folders:
`native-opening`, `native-return-complete`, `native-after-share`,
`native-after-debt`, `native-after-keep`. Optional `sourceFreeze` may name only
this phase's base `source-freeze.json`.

Fresh gameplay: first40/0/0, base400+bonus100, actual Kinmen full-fleet normal
checkpoint; second20/0/0, base200+bonus50, actual Xiamen full-fleet normal
checkpoint. Each confirmed raw checkpoint equals actual final campaign exactly.
Second consumes byte-exact selected new first artifact/checkpoint, retains exact
preaccept material,1200-second deadline, zero second lease and dead enemy. Real
fire/hit, formal delivery/deadline and first pacing checks remain strict.

Fresh current-source GPU evidence is **45 actual PNGs**: opening11, complete
return17, share5, debt7, keep5. Actual PNG dimensions/SHA, metadata source hashes,
identified GPU, actual controls/full-fleet safety and root personal-view hash
manifest cover every selected image at1280x720/1600x900. Each native folder's
`root-visual-inspection.json` needs all current unique `personallyViewed` names,
exact `imageHashes`, exit0, false timeout, and actual final literal completion.
Opening marker: `OPENING_STORY_GPU_CAPTURE_COMPLETE`; return/aftermath marker:
`OPENING_RETURN_CAPTURE_COMPLETE ... preflightOnly=false`. Final post-write
assertion offsets remain opening0, return/aftermath2, first journey1, second0.

All aftermath branches consume the same exact new genuine second artifact SHA
and raw checkpoint through native Continue. Actual fixed receipt binds scene/key/
choice, safe observed Xiamen and revenue250. Share pays50/support+4, actual
surviving carrier beneficiaries, unchanged debt. Keep/debt choices cost0/support0.
Debt separately pays100/principal400 to300 with exact cash and no early credit.
Raw UI save SHA equals actual disk slot SHA; strict native Codec/material Save/
Continue gates and independent raw-to-raw final material/prior receipt/history
checks remain. Existing absent uncaptured sunk-enemy normal-export ownership
exception stays narrow. No invented pose, health, cargo, casualty or receipt.

Original12 user save/settings/transaction slots must match root baseline, each
capture before/after and live hashes; native cleanup only removes newly owned
isolated slots. Verifier writes only a new final judgment, refuses overwrite,
collects failed/malformed evidence and returns1 on any failed check. No numerical
weakening: raw/raw material exact; explicitly captured Godot15-digit serialization
comparison only, and existing native speed roundoff `<1e-8`. No general pose or
heading tolerance. No original-game GPU equivalence, performance, whole historical
chapter coverage or human-fun claim.

## Preparation verification

Fresh commands and observed results:

```powershell
rtk proxy python -m py_compile build/second-aftermath-work/freeze-fleet-phase.py build/second-aftermath-work/verify-fleet-phase.py
rtk proxy python build/second-aftermath-work/freeze-fleet-phase.py --self-test
```

Both exit0. The pure delta-guard check reports6 assertions /0 failures and labels
its invented inventories explicitly as no source/gameplay acceptance. Cases
cover the allowed delta, unexpected extra production drift, missing Encounter
change, missing required new test, extra new test, and removal of an old member.
These guards perform no source inventory freeze and write no files.

Read-only post-check confirmed both pinned previous freeze SHA identities remain
unchanged and new phase directory does not exist. Neither normal freezer nor
acceptance verifier has run. No selection/freeze/final judgment was created;
fresh113 suite, journeys and45 GPU captures remain root's future acceptance work.

## Independent fleet-stop phase preparation

Owner addition: `build/second-aftermath-work/freeze-stop-phase.py` and
`build/second-aftermath-work/verify-stop-phase.py`; existing fleet tools and this
record's earlier entries remain unchanged. New phase:
`docs/migration/evidence/opening-story/fleet-stop-and-aftermath`.

```powershell
rtk proxy python build/second-aftermath-work/freeze-stop-phase.py
rtk proxy python build/second-aftermath-work/verify-stop-phase.py
```

Commands are for root's later reviewed-source freeze and completed-evidence
acceptance respectively. Neither normal command runs during this preparation;
no selection, freeze or final judgment is created. The new phase must remain
absent until final source review passes.

Root reports neutral candidate `5cce` was frozen in the previous fleet-arrival
phase, then the actual first voyage was deliberately interrupted with exit1
after150 simulation seconds because the independent400-second carrier coast
probe remained75.92m away, speed0.159, unanchored. Those are failure/diagnostic
history; root's original editor PID8384 remains outside tooling ownership.
This lane does not evaluate that interrupted run as successful evidence.

The fleet-stop tools retain the same pinned original story-final baseline:
258 source identities at source SHA `b710efd0cfea7927d93c0f112961610786991926afa6bc4eae8061edff669246`,
14 QA at raw SHA `a060fecc62782512d3828cd028519ced94e84d5f79b5dabbddc6875bbc44615e`.
Only `modules/naval_simulation/encounter.gd` may change; only
`tests/test_fleet_arrival_controls.gd` may be added; removed0. Counts remain259
sources,113 actual tests,14 unchanged QA. Existing bounded manual arrival-brake
ownership is the new candidate's reviewed product scope; no QA change or other
production exemption is introduced.

Optional `historicalDiagnosticReferences` binds exact raw abandoned identities,
with role `abandoned-diagnostic-only-not-current-acceptance`:

- Previous fleet phase `source-freeze.json` SHA:
  `dee54f432aef99b6bc44e1dffbc03075d304215a13e7d667b2d7bdfef6a93ed3`.
- Previous fleet phase `first-run-interrupted.json` SHA:
  `e895044c82910084026e9db7091165141da3cde9ce01cd0fa6b779e841384a7d`.

Freezer includes existing pinned diagnostics as read-only links, rechecks them
before writing, and never adopts their source mapping/campaign/checkpoint or
success claims. Verifier accepts the optional reference field only with exact
pinned paths/SHA/role and identical references in source/QA freeze. Diagnostic
records never participate in current journey/UI/test selection or acceptance.

Current selected first/second/opening/return/share/debt/keep paths must belong
exclusively to the new fleet-stop phase. Every22-path runtime inventory and all
45 PNGs must record current changed Encounter SHA. Original strict40/20 claims,
400+100/200+50 rewards, actual Kinmen/Xiamen dock/full-fleet canSave, raw checkpoint
equality, byte-exact new first adoption, actual deadline/no-lease/no-rebirth,
normal raw UI Save/Continue, root personal-view hashes, original12-slot protection
and new113/113 suite remain unchanged. No optional test/final freeze, numerical
relaxation, human-fun, original-game GPU-equivalence or performance claim.

Stop-phase preparation verification pending syntax compilation and pure guard
checks. Normal freeze/acceptance and all real gameplay/GPU/tests remain unrun by
this lane.

Completed preparation post-check: both new stop scripts pass `py_compile`, exit0.
`freeze-stop-phase.py --self-test` passes6 pure invented-inventory guards, exit0;
this is expressly no source/gameplay acceptance. Read-only AST comparison of16
core verifier functions (numeric equality, source/material/checkpoint/process,
slots/captures/journey/suite/raw Save/branch checks) against unchanged fleet
verifier shows exact equality,0 mismatches. Only phase selection/marker labels
and optional diagnostic-reference provenance differ; no numerical or acceptance
predicate is weakened. Both abandoned diagnostic SHA identities still match;
new fleet-stop phase remains absent. Neither normal freezer nor acceptance
verifier ran; no real voyage, GPU, browser, full suite, save or editor operation.
