# Actual continued-voyage command envelope correction

Scope: only the continued QA driver, one focused real zero-advance acceptance regression, report/delta and a supplemental freeze for the corrected driver itself. No production/Campaign/Codec changes, first-driver edits, complete voyage, Storage, GPU, full suite, or prior evidence writes.

The actual first journey remains immutable (`journey-first.json`, SHA `c07a1ccd6dafa04d6030b1ad1de70529ce8231e18ff46dfa3f0f65130cb1f21e`). The failed actual second attempt remains immutable (`journey-second.json`, SHA `91f9e47e3e4f7abf352bad33418e27837b5f88e3fb6f38d1413bdbc872c247f7`): 30/1 before any accepted advancement, actual `accept-convoy` returned `invalid-command` at restored revision 36600.0.

## Root cause and correction

The focused regression invokes the actual current `captain.command` using a separate detached Runtime and the raw confirmed checkpoint from the new successful first journey. It does not run `captain.run`, call `runtime.advance`, or use Storage.

Initial RED reproduced `invalid-command`. Casting `expectedRevision` to `int` gave TYPE_INT but still failed. Boundary instrumentation showed `type` and `contractId` keys were String, while the dot-inserted `commandId` and `expectedRevision` keys were StringName. `SaveCodec.command_data` requires String keys, explaining the real rejection. Campaign's `_count` already accepts finite integral floats; no numeric/schema widening is necessary.

The driver now merges a literal dictionary with String keys for the two business envelope fields, and explicitly casts revision to int, matching the product UI's command shape. After this correction all four actual input keys are String, and normal Runtime/Campaign authority accepts the twenty-grain shipment.

## Immutable first source identity

Only `tools/play-continued-voyage.gd` is classified as an **unexecuted upstream QA reference** in the first journey's inventory. The driver records the first recorded self hash, current executing self hash, drift boolean and role in `upstreamQaContext`. It still requires the current self source to exist, verifies every other first recorded source hash strictly, and retains exact immutable raw-checkpoint equality with the first final campaign plus the reviewed post-adopt material audit. There is no prefix/path-category whitelist, source rewriting or material repair.

The current second result's `sourceHashes` includes the actual corrected executing driver. Root's original QA freeze remains historical; the new supplemental freeze lists only this corrected driver and records before/after identity plus the strict unchanged-source check count.

## Focused observed verification

- Actual command regression GREEN: `CONTINUED_ACCEPT_REGRESSION assertions=16 failures=0 acceptedSeconds=0.0`.
- Final immutable GREEN fixture: `build/port-approach-work/qa-continued-accept-regression-23524.json`; body is 14/0 before the two final flush/readback assertions, completion is 16/0. Readback confirmed its driver SHA equals the supplemental current freeze.
- Actual twenty grain loaded, leasePaid zero, real Kinmen stock reduced by twenty, silver unchanged, original `simulationSeconds+1200` deadline retained. Raw first checkpoint equals actual first final exactly; adoption material violations empty; no simulation time advanced.
- First and failed-second SHA identities remained exact throughout the real regression. Fresh RED/intermediate/GREEN build-only diagnostic records are retained, including the StringName boundary evidence; no failed record was replaced.
- The final compiled driver path preflight accepts the immutable first input and fresh unused output without configuring or advancing a voyage.

No successful complete second voyage is claimed. Root must execute the corrected second driver into a new unused phase path; the existing failed `journey-second.json` stays unchanged. Disk/user saves and the successful first voyage need no replay solely because this formerly unexecuted QA reference changed.

Artifacts: `task-continued-voyage-accept-fix.patch`, `build/port-approach-work/qa-tooling-continued-accept-fix-freeze.json`, and fresh `build/port-approach-work/qa-continued-accept-regression-*.json` records. Original corrected-driver baseline retained at `build/port-approach-work/play-continued-voyage.gd.accept-before`.
