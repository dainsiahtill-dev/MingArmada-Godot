# Gameplay QA tooling review

Final static review verdict: **Spec PASS. Code quality PASS. No outstanding actionable P1/P2 findings.** The initial source had one substantiated P1 and one substantiated P2; both are resolved by fresh source recheck. An initially reported fleet-aggregate P2 was incorrect and is explicitly withdrawn below. Root owns live gameplay/GPU validation. No voyage, GPU run, production test, Git operation, historical-evidence write, or user-slot write was performed by this reviewer.

CodeGraph was queried first for the writable Godot project and reported no index. Review used focused RTK reads. `qa-journey-material.gd` does not exist; the actual material helper is `tools/qa-journey-checkpoint.gd`.

## Findings

Initial findings retained below for correction history; final dispositions are recorded in the revision rechecks.

1. **P1 — GPU capture output can escape the project through a linked ancestor.** `tools/capture-opening-clarity.gd:14–15,33–36`: `output_allowed()` validates only a textual prefix, `..`, trailing slash and final-path existence. A fresh child beneath an existing evidence junction/symlink is accepted, then recursively created and used for PNG/JSON writes outside the intended project. Windows ambiguous components are also not handled consistently with the journey guard. Reuse the component/link checks in `qa-journey-paths.gd` for a synthetic child JSON before accepting the fresh directory, and include that helper in the capture source freeze. Root has acknowledged this finding and is preparing the fix; the reviewed initial guard's six selftests do not cover a linked ancestor.

2. **WITHDRAWN — initial fleet-aggregate P2 was a review error.** Fresh raw-string inspection confirms the `for member` at current line 187 and `if all_near` at line 191 both have three leading tabs; the member-loop body at lines 188–190 has four. Therefore the docking decision is already after the complete fleet loop. The preserved baseline has the same structure (`for` at line 160; `if all_near` at line 164). The initial rendered-output interpretation was wrong. No aggregate helper/refactor or gameplay change is required, and no premature-dock claim from this finding should be retained.

3. **P2 — first journey can exit successfully after an evidence write fails.** `tools/play-opening-story-journey.gd:217–223`: a non-null file handle is the only write assertion. `store_string()` is followed by `close()` without `flush()`, `get_error()` or readback, so a failure after opening (for example, an exhausted destination volume) leaves truncated evidence while the process emits its success marker and exits zero. Flush, check the write error and verify the exact serialized bytes; include write failure in the exit status. `play-continued-voyage.gd:220–224` already flushes and checks its write error. No failure injection was executed during this read-only review.

## Reviewed protections and behavior

- Journey output/input guards reject absent/duplicate explicit arguments, existing output, outside paths, traversal, backslashes, Windows forbidden/ambiguous components and device names. Ancestors and the selected final component are checked with `DirAccess.is_link`. Both drivers recheck the output path before writing. Windows junction behavior still needs live directed evidence; this review did not create a junction fixture.
- Continuation reads immutable first-run bytes, requires the first run's recorded success/formal terrain/safe return, verifies recorded source hashes, uses normal strict `Codec.decode`, and requires the decoded raw checkpoint to equal `record.final.campaign` exactly. The original raw checkpoint string/hash are retained; normal `Runtime.adopt_save(checkpoint, null)` uses no user Storage.
- The material audit preserves gameplay fields, positions/headings, existing epoch ticks and vessel membership; it permits recorded native revision/epoch/projection/observation changes and pose-speed roundoff below `1e-8`. It does not grant a representation/owner change exception or repair cargo, HP, pose, receipts or time. The report's historical 33 owner differences are historical diagnostic evidence, not a live voyage result.
- Continued `convoy-002` acceptance checks the actual 20-grain settlement, Kinmen stock deduction, unchanged silver, no second lease, native 1200-second deadline and actual catalog route. Departure, navigation/protect/rally, terminal claim, Xiamen docking and export all use runtime authority. There is no enemy spawn or HP/cargo/receipt patch, and a dead checkpoint enemy must remain dead.
- The continuation uses a bounded 0.2s native step, rejects missing/different accepted time, records an aggregate that must match campaign elapsed simulation time, and requires actual terminal `delivered=20/lost=0`, settled status, Xiamen return and normal decoded final checkpoint equality. A claimed loss can still be returned and exported for truthful failure evidence; the final 20/0 assertion makes that process fail.
- The continuation's per-step snapshot can precede a same-step claim/navigation/dock command. Those commands do not advance position or time, and its final checkpoint decision refreshes `runtime.snapshot().runtime.canSave`; no static path was found that turns stale facts into a successful unsafe export. Its full-fleet `all_near` loop ends before the repeat-moor decision.
- The new capture inherits the actual MainScene/menu/native `InputEventMouseButton` path. It intercepts the actual `contract_accept_convoy-001` action before acceptance, resizes to 1600×900 and 1280×720, reads the current `Label` named `contract_convoy-001`, checks the offered deadline text and saves actual GPU pixels through the inherited capture. Current interface source confirms that label name and the two deadline phrases. Static source cannot establish readability/clipping or actual GPU success.
- The capture snapshots the twelve real v2/v1/settings paths and transaction suffixes. It verifies all twelve prospective isolated files absent before setting `slot_owned`; dependency injection uses the same exact PID prefix as the inherited runner. Cleanup is file-only over those twelve exact isolated paths, after freeing MainScene; it never recursively removes the tests parent or the original slots. The ordinary failed-menu-entry branch calls the overridden finish routine and thus uses this cleanup. No supported additional slot-cleanup violation was found. Runtime/script crashes and externally terminated processes are not covered by an unconditional finalizer.

## Verification boundary

Fresh read-only SHA-256 comparison matched all eight entries in `build/port-approach-work/qa-tooling-source-hashes.json` at review time. The report and patch were inspected alongside current source; no author guard/adoption tests were repeated.

The author's guard/adoption/preflight counts establish only their stated path/codec/zero-advance boundaries. They do not establish a new first or second voyage, 20/0 delivery, full return, actual first-offered UI visibility, smooth approach or GPU/performance quality. Root must fix the findings, freeze the resulting source, run both actual voyages and native captures, inspect rendered images, and retain fresh final verification evidence before recording gameplay acceptance.

## P1 revision recheck

The revised `capture-opening-clarity.gd:15–18` now passes a synthetic `/capture-result.json` child through `Paths.output`, then requires the capture directory itself to be absent. This reaches the reviewed shared component, Windows alias and ancestor-link checks before directory creation. The helper is also present in the capture source freeze at line 49, and lines 101–103 add trailing-dot, ADS and device-path guard cases. **P1 resolved by fresh source inspection.** Root separately reports a 9/0 guard selftest; the reviewer did not repeat that process test and does not treat it as GPU or live junction validation.

The initial capture source remains preserved by root at `build/port-approach-work/capture-opening-clarity.gd.review-1`. At this intermediate revision, only the substantiated first-driver write-integrity P2 still required a source fix/recheck. The originally requested aggregate change was canceled after direct raw-indentation verification established that the existing guard already checks the complete fleet.

## Final write-integrity revision recheck

The revised first driver adds `write_verified()` at lines 25–36. It refuses an existing file/directory, checks directory creation and file open errors, stores the serialized full-precision bytes, flushes, captures `get_error()`, closes, and compares exact readback. The completion path at lines 224–232 retains the shared final output guard, checks `written.ok`, reports `writeOk`, and exits nonzero when the write check fails. **Write-integrity P2 resolved by fresh source inspection.** The author reports a focused 5/0 writer selftest; this reviewer did not repeat it or perform failure injection.

Raw-string recheck after this revision also confirms the fleet loop at line 199 and docking condition at line 203 both have three leading tabs. The withdrawn finding remains invalid; the write change did not alter that aggregate guard.

Fresh source hashes at final static recheck:

| Source | SHA-256 |
| --- | --- |
| `tools/capture-opening-clarity.gd` | `c4eb90f99a4dab9ce338372134ba8808252ca9549a657efdb298283cf11700cc` |
| `tools/play-opening-story-journey.gd` | `2391e92f4990da386dff8b60b1622864e7d6aad4f12c7b6aae042e803ad695cc` |
| `tools/qa-journey-paths.gd` | `e7ba67b3f07bf3cfedb84338e7a2a9eca617ff8d51507e761dd2360f353f4421` |

**Final scope: Spec PASS; Code quality PASS for the reviewed QA tooling.** These verdicts establish the inspected implementation and correction delta; real voyages, terminal cargo/receipt outcomes, full return/export, original-slot hash equality at runtime, GPU screenshots/readability and performance remain root-owned live acceptance work.

## Offered-label visibility delta

Root's subsequent capture-only revision at `capture-opening-clarity.gd:61–66` walks the actual offered contract Label's ancestors, calls `ScrollContainer.ensure_control_visible(offered)`, and waits three frames before GPU capture. The block is inside the 1600×900 / 1280×720 loop, so each resized capture receives the visibility adjustment. It retains the actual preaccept Label/text assertion and normal native mouse acceptance afterward. No campaign or production source change is present in this delta. **Spec PASS; Code quality PASS retained by fresh static recheck.** Actual rendered visibility/readability still requires root's image inspection; this reviewer ran no test/GPU process.

Final frozen capture script SHA-256 from fresh bytes: `tools/capture-opening-clarity.gd` = `a99b4e3e296900151b98c23c4fbc04b4e41693cf8d66ce6de691fbf5ecab2798`. This supersedes the prior capture hash in the table while preserving its review history.

## Continued-command and return-hint revisions

Fresh final delta review of `task-continued-voyage-accept-fix.patch`, the author's matching report, the supplemental freeze and current source: **Spec PASS; Code quality PASS. No new actionable P1/P2.** No author tests or actual voyage/GPU processes were repeated by this reviewer.

The final continued driver at lines 34–35 merges a literal dictionary with String keys for `commandId` and `expectedRevision`, and casts revision to `int`. The actual root-cause correction is the command-key shape: `Codec.command_data` uses `_data`, which rejects non-String dictionary keys; current product UI explicitly documents this StringName pitfall and writes String keys at lines 128–130. Campaign `_count` already accepts finite integral floats. The integer cast matches the product envelope, but was not sufficient by itself; the author's retained intermediate failure established that distinction. No production Codec/Campaign widening or state repair was introduced.

The source-identity exception at continued-driver lines 89–96 matches only the exact path `tools/play-continued-voyage.gd`, classifies its old first-run entry as an unexecuted QA reference, and records recorded/current hash, drift and `executedByFirstJourney:false`. Empty current source fails and returns. Every other recorded first-run source remains under strict equality, and the current executing driver is still frozen in the second result's `sourceHashes` and verified at completion. Exact raw checkpoint/final-campaign equality and post-adopt material checks remain unchanged. There is no broader path/prefix/category whitelist.

Independent fresh read-only verification found all **19 other first-run source hashes match**, the current continued-driver hash matches the supplemental freeze, the old self inventory hash matches its recorded upstream context, and both actual evidence files match the freeze's immutable identities:

| Evidence | SHA-256 |
| --- | --- |
| Successful `journey-first.json` | `c07a1ccd6dafa04d6030b1ad1de70529ce8231e18ff46dfa3f0f65130cb1f21e` |
| Failed `journey-second.json` | `91f9e47e3e4f7abf352bad33418e27837b5f88e3fb6f38d1413bdbc872c247f7` |

The author's fix report records a detached real adoption/acceptance regression of 16/0 with zero accepted time, actual 20-grain load/no second lease/stock deduction, and preserved original deadline. This reviewer inspected the report and diagnostic code rather than rerunning it. It is acceptance-command evidence, not a complete second voyage. Replaying the successful first voyage solely for its formerly unexecuted QA reference is unnecessary; the new second voyage still needs a fresh unused output path.

The root's new `capture-return-clarity.gd` retains the reviewed strict return capture. Before ordinary parent run, it checks explicit fresh output through the shared synthetic JSON path guard. Its overridden source inventory adds its own file, the guard and approach-clearance source; inherited `unchanged_sources()` checks them. After each actual steward-consequence capture it uses inherited `focus_control()` to scroll/re-resolve the real `repay_debt` Button, verifies it is disabled and its real tooltip directs the captain to Xiamen, sends an actual `InputEventMouseMotion`, waits 60 frames, and invokes the inherited GPU capture for the extra hint. This occurs for both 1600×900 and 1280×720. It adds no fake control, campaign mutation or custom Storage path/cleanup. The wrapper's two extra screenshots still require actual tooltip visibility/readability inspection.

Fresh final source identities for this revision:

| Source | SHA-256 |
| --- | --- |
| `tools/play-continued-voyage.gd` | `c41b8ac67420a2fae5198d3b0687f46f201e5e68878f61aa0332b9af1e53d26c` |
| `tools/capture-return-clarity.gd` | `dbfe86242d1840a1e1698e581ef5e26c20a87905c87e6cef708f3745908c8e60` |
| `tools/qa-journey-paths.gd` | `e7ba67b3f07bf3cfedb84338e7a2a9eca617ff8d51507e761dd2360f353f4421` |

Prior review/freeze entries above remain historical. Final static Spec/Quality verdicts remain PASS for the reviewed QA corrections; full second-voyage delivery/return/export and native screenshot acceptance remain root-owned.

## Repayment-control contract correction

**Correction: the earlier return-wrapper tooltip assumption and its associated static approval are withdrawn.** The real UI renders `repay_debt` as a Button at `mingqi_interface.gd:471` and the explanatory paragraph as a separate `repay_debt_reason` Label at line 472, with visibility driven by nonempty text at line 473. `_repay_reason()` returns the Xiamen Lin-house instruction. The earlier wrapper incorrectly expected the Button's empty `tooltip_text` to contain that instruction. This reviewer should have reconciled the wrapper with the already inspected actual Label contract. The production UI was correct and remains unchanged.

Root reports the actual old wrapper stopped at 318 assertions / 1 failure after three PNG captures; those failed-native-return artifacts remain preserved, and the prior wrapper is retained at `build/port-approach-work/capture-return-clarity.gd.before-label-fix`. This reviewer did not run or inspect GPU images in this correction pass.

Fresh delta/source recheck confirms the corrected wrapper at lines 23–28 focuses the actual typed Button and actual typed Label through inherited `focus_control()` (ancestor scrolling, wait and visible-control re-resolution). It requires the Button disabled and the Label visible with text containing `厦门林家商行`, then captures the real paragraph. The tooltip check, artificial hover request and 60-frame hover wait are removed. Both resolution-specific steward captures still trigger this actual Label path. Shared output/source guards and inherited strict Continue/slot cleanup are unchanged, and no campaign/production/second-driver edit is present in the inspected wrapper delta.

**Spec PASS; Code quality PASS for the corrected paragraph contract.** Actual corrected GPU capture, screenshot count and readability remain root-owned live acceptance. Root's reported inherited 34/0 guards were not repeated by this reviewer.

Latest capture-return wrapper SHA-256: `0eab3d2bebb438fdc3d8f866d9369e355e860460cb3a886a391be06544b77fb9`. This supersedes the earlier `dbfe8624...` wrapper hash while preserving the failure/review history above.

## QA egress delta

**Spec PASS; Code quality PASS. No actionable P1/P2 in this QA-only delta.** Review is limited to the four changed QA tools against `port-approach-and-voyage-clarity/qa-source-freeze-final.json` and the prior reviewed source identities above. The product `wet_route_egress.gd` implementation and its behavior belong to the separate builder/reviewer. No complete voyage, GPU run, production test, user-save write, old-evidence write or Git operation was performed by this reviewer.

- All four QA source inventories now include `modules/naval_simulation/navigation/wet_route_egress.gd`. Both journey drivers retain completion-time source equality checks; the opening capture wrapper checks its added source inventory at finish, and the return wrapper includes it through the overridden inventory consumed by inherited `unchanged_sources()`.
- Both `navigation_diagnostics()` returns include the actual live `wetRouteEgress` and `egressClearance` records, then deep-copy the whole returned dictionary with `.duplicate(true)`. Consequently historical stage data detaches route/recovery/egress nested dictionaries and arrays from subsequent live updates. The change reads diagnostic state only and adds no navigation/command/arrival action.
- Continued-voyage input now requires a recorded first-run entry for the exact new module before restoring or advancing. The ordinary strict source-hash loop then validates that module, because the sole existing exception remains the exact executing continued-script path. Old pre-egress first evidence lacking the new module entry fails this gate; no prefix whitelist, checkpoint repair or changed adoption/material rule is introduced.

Fresh comparison checked the whole four-file delta, not merely the visible matching lines: undoing the declared module inventory insertions, diagnostic fields/deep-copy addition and one continued input gate reconstructs each frozen baseline hash. The two journey files additionally changed LF to CRLF; normalizing that formatting difference is required for their exact prior hash match. The two capture wrappers match their prior raw-byte hashes after only undoing the inventory addition. All nine other QA files in the historical final freeze match their frozen hashes unchanged.

| QA source | Previous final-freeze SHA-256 | Current reviewed SHA-256 |
| --- | --- | --- |
| `tools/play-opening-story-journey.gd` | `2391e92f4990da386dff8b60b1622864e7d6aad4f12c7b6aae042e803ad695cc` | `fd4dbd6bdb9830dabbd9531d67758cceb6c984089402323f6614103cff8d7237` |
| `tools/play-continued-voyage.gd` | `c41b8ac67420a2fae5198d3b0687f46f201e5e68878f61aa0332b9af1e53d26c` | `53202bfb733bc6eb34558bf88d348fe94d6fa3c2d4de668962a6eca4e9a33d00` |
| `tools/capture-opening-clarity.gd` | `a99b4e3e296900151b98c23c4fbc04b4e41693cf8d66ce6de691fbf5ecab2798` | `8c8eba56eb7e943438549303ce40151887f256b28a4c09eec1c90b68f5521572` |
| `tools/capture-return-clarity.gd` | `0eab3d2bebb438fdc3d8f866d9369e355e860460cb3a886a391be06544b77fb9` | `248bd2ad530848b1c9f5e8adede39bcdac785af51ba2e4b2a09b969b88212e85` |

This static acceptance covers instrumentation and provenance for the new egress phase. It does not claim the product repair works or that a new voyage/capture has passed. Existing evidence/freeze files remain historical; root must freeze the actual final module and tools, then validate fresh gameplay/capture outputs in unused paths.
