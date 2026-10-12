# Genuine return capture acceptance

2026-10-12. Owned changes: `tools/capture-opening-return.gd` and this report. No domain/UI/sea/island/particle/performance changes; no Git mutation. CodeGraph index unavailable as established by the parent task; focused RTK reads used.

The new tool accepts an explicit `--journey=` record, never builds a replacement campaign. It requires zero journey failures, `actualSafeReturn=true`, actual Kinmen port, a living flagship, settled positive first convoy and authentic first-return receipt, offered `convoy-002`, and one or two actual surviving original transports. Both-sunk and missing-transport records are rejected. `SaveCodec.encode` encodes the unchanged `final.campaign`; decoded equality verifies the exact input. Both ordinary router validation and `Runtime.adopt_save` on the formal geography must pass. Any safety failure stops with its exact reason. No pose, health, cargo, crew, receipt, history or order repair is allowed.

Actual GPU acceptance, once authorized, uses MainScene's normal `mingqi-continue` control with an isolated checkpoint and settings/legacy slots. Mouse events open journal/convoy pages and accept the next commission. At 1600×900 and 1280×720, the tool captures the actual first-return reply, casualties, steward consequence, offered next commission, accepted next commission and each actual transport's route. Zero sunk original transports requires two actual loading voyages with 10 grain per ship; one sunk requires one actual loading voyage with 20 grain. In both cases, the actual loaded transport IDs must equal the original living transport IDs, total load must be 20, Kinmen stock must decrease 20 and original lease must not be charged again. Actual deaths/casualties/history and sunk transport material state are retained. Journal death/wounded numbers must match the real first-claim receipt; steward death text must agree with actual steward survival rather than require an invented death. Any person on a sunk transport must remain actually dead. Each PNG has a real snapshot, UI text/rectangles, engine/GPU data, source hashes and journey SHA-256. The exact accepted input save is retained beside the images.

Optional `--save-readback` clicks normal Save and Main Menu, reads the isolated checkpoint, then uses normal Continue again. If saving is unsafe, it records the exact skip reason and does not bypass the safety gate. User checkpoint/settings/backup/rollback/staged file existence and hashes are checked before/after, and only fresh slots owned by this process are removed. Output must be a new directory inside `res://docs/migration/evidence/opening-story/`; existing evidence is never overwritten.

Verified without a GPU window:

- Guard tests were first observed red: 8 assertions, 8 failures for the missing guards.
- Zero/one-sunk extension first observed red: 12 assertions, 2 failures (two-survivor admission and clear both-sunk rejection). Test fixtures are incomplete guard-only ship shapes; never encoded/adopted or used as journey evidence.
- Current guard self-test: `OPENING_RETURN_GUARD_TESTS assertions=12 failures=0`, Godot exit 0.
- `--headless --check-only --script res://tools/capture-opening-return.gd`: exit 0.
- Running without `--journey=` correctly rejects before any save/scene/window work: `explicit --journey= successful evidence required`, exit 1, captures 0.

GPU acceptance requires parent authorization, a directly successful journey record, and frozen domain recovery sources. Execution/failed-run evidence is recorded below. No claim of original-game manual footage, all historical chapters, pixel equivalence or performance acceptance is made.

## Authorized strict preflight: rejected evidence precision

The parent authorized a strict preflight on the actual formal/deep/manual-fire successful journey, with GPU allowed only if that preflight passed. The executed command was:

```powershell
rtk proxy 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe' --headless --path 'C:/Users/dains/Documents/Git/ming-armada' --script res://tools/capture-opening-return.gd -- --journey=res://docs/migration/evidence/opening-story/journey-formal-manual-fire-return.json --preflight-only
```

Actual result: exit 1. Preserved output:

```text
FAIL: SaveCodec rejects unchanged journey: canonical-port-mismatch: ports.xiamen
OPENING_RETURN_CAPTURE_COMPLETE captures=0 assertions=4 failures=1 preflightOnly=true
```

The file reports `failures=0`, `actualSafeReturn=true`, and `final.campaign.currentPortId=kinmen`; it passed the journey eligibility gate. Exact unchanged encoding then failed the codec's canonical port equality. Read-only comparison found:

| Field | Actual journey JSON | Source Catalog |
| --- | --- | --- |
| `ports.xiamen.position.x` | `-306.257095844739` | `-306.2570958447386` |
| `ports.xiamen.position.z` | `-38.2821369805923` | `-38.28213698059233` |

The journey evidence writer uses `JSON.stringify(...,"\t")`, while `SaveCodec.encode` uses full-precision serialization. No rounded coordinate was replaced, no campaign or production/tool source was edited, and no safety check was weakened. The tool stopped before router/native adoption and before all isolated/user slot operations. GPU was not launched; therefore PNG/snapshot capture and user-slot before/after hash assertions were not run.

Failure input journey SHA-256: `b491c92088346b19d9b7b0bd397cad393b6bc37e8631b4d07eeb5333bc9396c0`.

Frozen capture-tool SHA-256: `dba3e0d484dcb0af2a4dab94dfdfd5fb163ce88335e182324cca1757fc9202cf`.

A new actual journey evidence record retaining full numeric precision is required before trying the strict preflight again. This failure is retained here even if a later run succeeds.

## Authorized QA presenter correction

The parent authorized one capture-harness correction while retaining frozen production and journey records. The harness disables the scene's regular presentation/physics processing to observe an immutable returned campaign. Local navigation clicks open journal/convoy UI panels without a Campaign command, so they had no automatic scene presenter call; the existing native compact-chart blocked state could remain stale.

`button()` now calls normal `scene._present(0)` after the real mouse click, only when both scene/MainScene still exist and that exact scene remains `main.current_scene`. Saving and returning to the menu therefore cannot present a retired scene. Each capture also refreshes this actual active scene and requires the actual compact chart to be hidden whenever an operation/menu panel is open. Metadata records actual `panelOpen`, `menuOpen` and `minimapVisible` values. No production visibility rule or game state was changed.

Headless regression checks use the actual Mingqi interface panel flags and native SeaChartOverlay chart visibility; a small scene-owner probe avoids constructing the full sea/GPU scene and never creates or restores a campaign. The new reproduction first failed as intended: `OPENING_RETURN_GUARD_TESTS assertions=16 failures=1`, with `frozen-scene QA presenter refresh hides actual native chart after journal opens`. After the correction, the same self-test passed 16/16, exit 0. It also confirms no presentation call after MainScene switches away or the owner is freed. Fresh `--headless --check-only` passed, exit 0.

QA-only scoped diff: `return-capture-presenter-qa-scoped.patch` (79 lines), relative to the preceding frozen tool SHA-256 `dba3e0d484dcb0af2a4dab94dfdfd5fb163ce88335e182324cca1757fc9202cf`.

New frozen capture-tool SHA-256: `6f3b2734a4ca7b58d8ce42818edad677475b95431805b1b1aa76245f013cb4cb`.

Scoped QA patch SHA-256: `923f20e03b55fe72e16f6c5343d57717b908162229577c9b2283247b2d2af837`.

At completion of this presenter correction, GPU remained unrun. The then-current journey's reported unberthed grain ship was not repaired by this QA change; a new full-precision, genuinely safe exported-checkpoint record still had to pass the original strict preflight before GPU acceptance. The previous precision failure remains preserved above.

## Full-precision safe journey: preflight passed, first GPU run stopped

The final actual journey record SHA-256 is `9b88b2da35fb9a965989d00618a7949d614c2af3cf0ca6dcc91bc992da03657c`; the frozen capture tool remains `6f3b2734a4ca7b58d8ce42818edad677475b95431805b1b1aa76245f013cb4cb`. Both hashes were checked live immediately before execution. Strict `--preflight-only` completed exit 0:

```text
OPENING_RETURN_CAPTURE_COMPLETE captures=0 assertions=126 failures=0 preflightOnly=true
```

Normal router safety, actual formal-geography native adoption and material preservation all passed. Only then, as authorized, one visible GPU process ran:

```powershell
rtk proxy 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe' --path 'C:/Users/dains/Documents/Git/ming-armada' --script res://tools/capture-opening-return.gd -- --journey=res://docs/migration/evidence/opening-story/journey-formal-manual-fire-return.json --output=res://docs/migration/evidence/opening-story/native-return-final --save-readback
```

Actual GPU: `Intel(R) Arc(TM) 130T GPU (16GB)`, D3D12 / Forward+. The process exited 1 and stopped at the zero-casualty UI assertion:

```text
FAIL: visible actual casualty consequence matches real claim
OPENING_RETURN_CAPTURE_COMPLETE captures=1 assertions=292 failures=1 preflightOnly=false
```

The unchanged real claim contains zero dead and zero wounded. The actual Xu Fu label is `许福 · 老水手\n工钱结清，愿意与你共担风险。`; production story projection appends numeric casualties only when dead or wounded is positive. The QA assertion required both `死亡0人` and `受伤0人`, so this is a confirmed zero-case harness/text expectation mismatch. No invented casualty text was displayed and no state was changed. Both stewards are alive; no steward death text is present. The tool remains frozen pending the parent's decision on this QA assertion.

Preserved failed-run directory: `docs/migration/evidence/opening-story/native-return-final`. It contains one actual `first-return-consequence-1600.png`, metadata, exact accepted native save and `capture-result.json`. The final console count is 292; the result records 290 assertions before its own two write/flush checks. It records failures 1, `originalSlotsUnchanged=true` and `isolatedSlotsCleaned=true`. The user-slot hash assertions passed; original slot hash maps are not serialized by this tool version.

The PNG SHA-256 is `4e095e44e3325d65c95850e1a6ee8a554e8637ce32a5d2a8c36116582bab5947`, independently matched against metadata. All 22 capture source hashes matched live files after the process exited, and the journey SHA-256 remained unchanged. Metadata confirms actual `panelOpen=true`, `menuOpen=false`, `minimapVisible=false`; the presenter correction works on the real GPU scene.

Next commission acceptance, the other screenshots and normal save/readback were not reached. No second GPU process was started, the existing editor was not touched, and the failed directory will not be overwritten by a retry.

## Authorized zero-casualty QA correction, awaiting retry review

The parent permitted only the zero-casualty assertion correction and persistent user-slot hash maps. Production `opening_story.gd` was read directly: the first-return story projection always states actual `船员死亡%d人、伤员%d人`, while Xu Fu's relationship adds `死亡%d人、受伤%d人` only when casualties are positive. The QA tool now checks the actual live snapshot/claim and the normal production projection rather than inventing duplicate zero text.

The relationship label must exactly match the actual snapshot's Xu Fu projection in either branch. The actual first-return projection must contain the actual claim's dead/wounded totals. Positive dead/wounded totals still require both exact numeric relationship phrases. For 0/0, the tool requires both stewards alive in the actual claim and current campaign, each claimed ship present/alive with current wounded and casualty ordinal zero, and the native crew equal to the current campaign crew for every near ship. Enemy casualties are outside the claimed fleet and are retained. The healthy relationship must contain no invented death/injury text. All existing codec, formal/native safety, material preservation and positive-casualty assertions remain.

The result schema now retains `originalSlotsBefore` and `originalSlotsAfter`, each using the existing `{exists, sha256}` map per `user://` path, plus `userDataDir` for independent path resolution. The actual equality assertion still runs; no user save/settings bytes are exposed or written.

Ten detached assertion-only fixtures cover healthy zero text, invented injury text, dead steward, current wounds, casualty authority, native crew mismatch, first-return projection mismatch, correct positive numbers, incorrect positive numbers and omitted positive injury text. Fixtures are never adopted/encoded/saved. The existing numeric-only predicate was first observed red: 26 assertions, 1 failure on healthy zero text. The corrected self-test passed 26/26, exit 0; fresh `--check-only` also passed, exit 0. No complete 103-script suite or new reviewer/GPU process was run for this QA correction.

Scoped diff: `return-capture-zero-casualty-qa-scoped.patch` (113 lines), relative to the preceding frozen presenter version. Read-only `git apply --check --reverse` passed, exit 0.

New frozen tool SHA-256: `82ed6a15ad36b6bbcedd3b00f6d25dfa27c9413d6c72563597c88abe9301cd02`.

Scoped patch SHA-256: `30eba2cb1b8ce098d0668674eabf5d04875f458f5239e997724a73296b8a9d34`.

The actual journey SHA-256 remains `9b88b2da35fb9a965989d00618a7949d614c2af3cf0ca6dcc91bc992da03657c`. The `native-return-final` failed capture and preceding precision failure remain preserved. The planned fresh retry directory is `native-return-verified`; GPU execution awaits the parent's patch review and authorization.

## Second GPU run and actual export ownership diagnosis

After the parent reviewed/authorized the zero-casualty QA patch, one GPU process ran in fresh `native-return-verified`, with strict preflight still executing inside the tool. It reached 14 actual screenshots at both sizes and accepted the actual next commission: Kinmen stock 50 to 30, two original grain ships each loaded 10, total 20, leasePaid 0, real `kinmen-supply-deep` loading voyages. The process exited 1, final console `captures=14 assertions=643 failures=1`; the artifact records 641 assertions before its two write/flush checks. The precise failure is `saved checkpoint preserves mingqi-1650-enemy.representation`. The normal UI save-and-menu and native checkpoint disk read had already succeeded; the final Continue/readback screenshot was not reached.

All 14 PNG hashes independently match their metadata. The 12-path `originalSlotsBefore`/`originalSlotsAfter` maps match each other and actual live files, `originalSlotsUnchanged=true`, and `isolatedSlotsCleaned=true`. All 22 then-recorded capture source hashes and the immutable journey hash were checked live after this failure. `native-return-verified` remains a failed run and will not be overwritten. Its isolated checkpoint was cleaned; this tool version did not yet preserve the actual saved bytes before the comparison failure.

The parent then authorized one CPU-only detached export reproduction. `tools/diagnose-return-export.gd` reads the immutable real `confirmedCheckpointJson`, confirms exact state equality with real `final.campaign`, configures formal Height/Runtime, strictly adopts without Storage, accepts a legitimate actual two-ship 20-grain commission, then calls normal `Runtime.export_save` once. No GPU, original record repair, production change or user-slot write is involved. The helper compiled and executed exit 0, `assertions=34 failures=0`; output is retained in `docs/migration/evidence/opening-story/return-export-diagnostic` with exact original checkpoint/export JSON bytes, full-precision before/after snapshots and every field difference.

The actual runtime before/after enemy record differs **only** in `representation`: `near` to `route`. HP/hull 0, sail 87, crew, exact position/heading/speed, cargo, people authority, controls and native stamps all remain identical for that enemy. Across the full campaign there are 12 differences including normal revision/projection bookkeeping; the only material difference is that enemy ownership representation. Export decoding matches the actual post-export campaign exactly (`decodedDiffs=[]`). Before export, actual native IDs exclude this enemy, `capturedShipIds=[]`, current port is Kinmen. Exact normal-export SHA-256: `80c8769101f688a7b723164cc5ac991dd8f09212b3bc88cbaa73f64754bd5f2f`.

Source path: `mingqi_scene.gd` normal `save-and-menu` calls `Runtime.save_checkpoint`; `mingqi_runtime.gd:261` `export_save` calls `Bridge.sync` then full safety and serialization. `near_field_bridge.gd:214` supplies actual current `_near_ids` to `Campaign.reconcile_near`. Native construction at port (`mingqi_runtime.gd:68`) excludes uncaptured enemy ships. `campaign.gd:647` sets representation to `near` only for actual near IDs, otherwise `route`; its `effective_draft` is read-only. This is a normal owner transition after restoring a checkpoint with the former sea encounter's sunk enemy representation, not a crew/HP/pose/cargo change.

## Narrow save-comparison QA patch, awaiting parent review

The parent authorized a narrow QA correction after the actual CPU evidence. Strict comparison remains the default. Only the normal UI saved-checkpoint comparison receives an actual before-save native/safety context. A representation difference is allowed only for an enemy with **exact hull 0 before and after**, at a safe actual port, absent from actual before-save native membership and uncaptured, with exactly `near` to `route`. Every other field in its complete record, including otherwise tolerated native stamps/revision, must be exactly equal; no missing/extra field, material mutation, living/captured/present enemy or reverse ownership change can use the exception. Restore/source preservation and second Continue have no exception context.

The actual UI disk read's original JSON is now written with exact readback to `normal-ui-save-v2.json` and its hash/context saved **before** state comparison. A later comparison failure therefore preserves the native saved bytes even after isolated-slot cleanup. The second Continue compares to the already Codec-validated decoded disk state, retaining the normal native epoch bookkeeping rules, rather than compare to pre-export representation ownership.

Eight additional compare-only regression cases cover the sole allowed transition and default/restore, live, native-present, captured, changed-cargo, reverse and unsafe rejection. Fixtures never import/save a campaign. First observed red: 34 assertions / 1 failure. Corrected self-test: 34/34, exit 0; fresh check-only and read-only scoped patch reverse-check: exit 0.

Scoped diff `return-capture-saved-ownership-qa-scoped.patch` is 111 lines relative to `82ed6a15...`.

New frozen capture-tool SHA-256: `ec1247ad92bd0a8f71e78013c990ebc50ebabaa269a38f52e36d1fb8773e3c55`.

Scoped patch SHA-256: `ff3aee91921bd60c646c2af22bf2db7af5e6c97471686b8c808e00131d4acff1`.

CPU diagnostic-helper SHA-256: `e145e8aec75c59aa9673b965acd6910d14e8a262e95050280e4e00213a913bdd`.

At this save-comparison patch handoff, no GPU retry had run. Both failed GPU directories and precision-failure history remained preserved pending the parent's review and authorization for a new fresh directory.

## Final authorized GPU acceptance: passed

The parent reviewed the 111-line save-comparison patch, checked its exact hash and reverse applicability, and independently verified the actual CPU export evidence. One authorized GPU process then ran in fresh `native-return-complete`, retaining original strict preflight and using actual normal UI save/second Continue. It naturally terminated exit **0**:

```text
OPENING_RETURN_CAPTURE_COMPLETE captures=15 assertions=801 failures=0 preflightOnly=false
```

`capture-result.json` records **799 assertions / 0 failures / 15 captures** before its two own write/flush checks. All 15 actual PNG hashes independently match their metadata. Actual sizes are 1600×900 and 1280×720; every operation-panel capture records the compact chart hidden. Actual engine/device: Godot 4.7.2, D3D12 Forward+, Intel Arc 130T 16GB. This is not a performance measurement.

The genuine next-commission transaction persists two original loading grain voyages on `kinmen-supply-deep`, each carrying 10 grain. Actual Kinmen stock moves **50 to 30**, total load **20**, leasePaid **0**; crew/deaths and old receipts remain governed by the real domain. Actual final Continue remains at Kinmen with silver **915**, active convoy-002 and both original grain ships carrying 10. No casualty or state was manufactured.

The normal UI disk checkpoint is retained as exact `normal-ui-save-v2.json`. Its SHA-256, witness SHA-256 and actual isolated slot SHA-256 all equal `e1969b7e9c079ccc193283d33de1937d76b2f91767fb2aa2cf3945fe9a8b538d`. The result records `diskRead=true`, `checkpointStateVerified=true`, `saveReadback.ok=true`, plus actual export ownership context. The saved enemy's representation is legitimately `route`; the actual second Continue compares against that verified decoded disk state. The final real `save-readback-1280.png` is present.

The 12 original user save/settings/backup/rollback/staged path maps are retained as `originalSlotsBefore` and `originalSlotsAfter`; they are exactly equal and independently match current real file existence/hashes via recorded `userDataDir`. `originalSlotsUnchanged=true` and `isolatedSlotsCleaned=true`. All 22 recorded capture source hashes match current files. The real source journey remains SHA-256 `9b88b2da35fb9a965989d00618a7949d614c2af3cf0ca6dcc91bc992da03657c`, and capture source remains `ec1247ad92bd0a8f71e78013c990ebc50ebabaa269a38f52e36d1fb8773e3c55`.

Final evidence: `docs/migration/evidence/opening-story/native-return-complete/capture-result.json`, exact initial/native UI save bytes, and these 15 PNG/metadata pairs:

- `first-return-consequence-1600`, `actual-casualties-1600`, `steward-consequence-1600`, `next-commission-offered-1600`
- `first-return-consequence-1280`, `actual-casualties-1280`, `steward-consequence-1280`, `next-commission-offered-1280`
- `next-commission-accepted-1600`, `transport-route-mingqi-1650-grain-a-1600`, `transport-route-mingqi-1650-grain-b-1600`
- `next-commission-accepted-1280`, `transport-route-mingqi-1650-grain-a-1280`, `transport-route-mingqi-1650-grain-b-1280`
- `save-readback-1280`

The process has ended. The original editor PID 8384 was never operated on. Failed `native-return-final` and `native-return-verified`, the rounded-evidence precision failure, and actual CPU export diagnostics remain intact. Production code and original journey/state were never edited by this capture task. The parent owns the independent final helper and visual inspection of every PNG; this report confirms execution/data/hash acceptance, not unperformed parent visual sign-off or all historical chapters.

Commands, prefixed with RTK:

```powershell
rtk proxy 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe' --headless --path 'C:/Users/dains/Documents/Git/ming-armada' --check-only --script res://tools/capture-opening-return.gd
rtk proxy 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe' --headless --path 'C:/Users/dains/Documents/Git/ming-armada' --script res://tools/capture-opening-return.gd -- --self-test
rtk proxy 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe' --headless --path 'C:/Users/dains/Documents/Git/ming-armada' --script res://tools/capture-opening-return.gd -- --journey=res://docs/migration/evidence/opening-story/journey-formal-manual-fire-return.json --preflight-only
# GPU run only after parent authorization:
rtk proxy 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe' --path 'C:/Users/dains/Documents/Git/ming-armada' --script res://tools/capture-opening-return.gd -- --journey=res://docs/migration/evidence/opening-story/journey-formal-manual-fire-return.json --output=res://docs/migration/evidence/opening-story/native-return --save-readback
```
