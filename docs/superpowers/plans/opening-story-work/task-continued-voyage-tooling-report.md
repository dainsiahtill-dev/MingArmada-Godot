# Continued-voyage QA tooling

Scope: QA scripts only. No production/domain/runtime/physics/UI/testsuite or Git operations. Root owns real voyage execution, full suite and GPU validation. CodeGraph review unavailable (root verified no index); focused RTK source inspection used.

Preserved baseline: `build/port-approach-work/play-opening-story-journey.gd.before`. Historical `journey-formal-manual-fire-return.json` SHA-256 remains `9b88b2da35fb9a965989d00618a7949d614c2af3cf0ca6dcc91bc992da03657c`; process guard tests read it without writes. No user Storage, GPU capture or old evidence writes occurred.

## Changes

- Both journey drivers require one explicit unused `--output=res://docs/migration/evidence/opening-story/...json`. Missing, duplicate, existing, outside, traversal, ambiguous Windows/ADS/device and linked-directory paths reject before runtime configuration/advancement. `--preflight` validates paths and compiles driver preloads with zero runtime advancement, creates no output. Path-only preflight does not promise that voyage contents or gameplay are valid.
- First driver preserves original captain intents, formal geography and legal command/helm/fire behavior. It records held-key transitions, command results, assertion details, native route/recovery/motion diagnostics and actual wall time separately from accepted simulation time. Source freeze now includes approach clearance, Catalog/geography and continuation/audit tools. Final output uses full-precision JSON and unused path recheck; no legacy implicit evidence overwrite remains.
- Continuation reads the actual first `confirmedCheckpointJson`, strictly decodes through normal Codec and checks exact equality with the first final campaign. It verifies frozen first-run sources, configures identical reference geography/enhancements, and uses normal `Runtime.adopt_save` without Storage or campaign edits. The immutable raw checkpoint is retained byte exact.
- Post-adoption material audit mirrors reviewed `capture-opening-return.gd`: all gameplay fields exact; positions/headings exact; pose speed roundoff below `1e-8`; existing epoch ticks exact. Normal native epoch allocation, revision and projection/observation stamps are recorded as differences. No representation/ownership exception is granted during adoption.
- Actual `convoy-002` uses `kinmen-supply-deep`, loads 20 from actual Kinmen stock through authority, reuses paid original ships, retains original `+1200s` deadline, departs through authority and protects a real transport with available fast ship. No enemy spawn or restoration occurs; a dead historical enemy must remain dead.
- Outbound flagship uses Catalog supply waypoints. After real arrived/lost terminal evaluation and normal claim, it returns through reversed supply waypoints connected to reversed Catalog outer-route waypoints to Xiamen. Live surviving controllable companions receive normal rally intents; docking waits for actual authority and full-fleet mooring/export safety. No poses, damage, cargo, receipts or transport injection is present.
- Native advancement requests accepted `0.2s` steps, bounded at 2400 accepted seconds for outbound plus return. Aggregate step count/accepted time replaces duplicate per-step assertions. Evidence includes source hashes, raw checkpoint/material audit, commands, assertions, 15-second diagnostic stages, casualty/crew/person changes and actual claim receipt, final snapshot and normal full-fleet checkpoint. Actual `delivered=20/lost=0` remains required; a failure records truthfully and exits nonzero.

## Verification observed

1. Guard selftest initially failed because helper was absent (RED); final `JOURNEY_OUTPUT_GUARD_TESTS assertions=18 failures=0` (GREEN).
2. Checkpoint audit selftest initially failed because helper was absent (RED); final `JOURNEY_CHECKPOINT_TESTS assertions=10 failures=0` (GREEN). It rejects cargo/HP/position/time/old-epoch changes and excessive speed change; permits only reviewed owner stamps/numerical speed roundoff.
3. Actual zero-advance adoption of immutable historical 29/0 checkpoint: `JOURNEY_ADOPT_DIAGNOSTIC assertions=8 failures=0 differences=33 acceptedSeconds=0.0`. Raw checkpoint equals first final exactly, but differs from legitimate adopted campaign. All 33 differences are recorded; material violations empty. Revision `92987→92989`, nextId `10→11`, renewed native control projection/observation stamps and one fresh native epoch. No voyage accepted or advanced.
4. Process verifier checks both successful zero-advance path preflights, real normal-entry overwrite/outside/missing-input rejections, immutable historical SHA and absent output side effects. Final `JOURNEY_PREFLIGHT_VERIFIER assertions=12 failures=0` is recorded in `build/port-approach-work/qa-tooling-preflight.json`.

The adoption diagnostic is immutable at `build/port-approach-work/qa-tooling-adopt-diagnostic.json`; rerunning its default refuses the existing file. The diagnostic/source selftests are separate from production tests.

## Root execution after review/freeze

Run `rtk proxy python -X utf8 tools/verify-journey-preflight.py` from the writable project for cheap guards only.

Real voyage commands, **not executed by this worker**:

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tools/play-opening-story-journey.gd -- --manual-fire --return --deadline --output=res://docs/migration/evidence/opening-story/port-approach-and-voyage-clarity/journey-first.json
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tools/play-continued-voyage.gd -- --journey=res://docs/migration/evidence/opening-story/port-approach-and-voyage-clarity/journey-first.json --output=res://docs/migration/evidence/opening-story/port-approach-and-voyage-clarity/journey-second.json
```

Limits: no claim of successful new first/second voyage, actual 20/0 delivery, return/checkpoint, final approach timing, gameplay pacing or GPU/performance quality. Those require root's frozen live runs. Directory-link rejection implemented via actual native `DirAccess.is_link`; this worker did not create a Windows junction fixture. The final full suite and visible native capture remain root-owned.

## Independent review correction and confirmed write fix

Reviewed baseline retained at `build/port-approach-work/play-opening-story-journey.gd.review-before` before edits. Raw indentation confirms baseline lines 187 (`for member`) and 191 (`if all_near`) each have three tabs; loop body has four. Fleet docking decision already follows the complete aggregation loop. The reviewer withdrew that P2. No fleet navigation, docking threshold or captain behavior was changed.

Confirmed evidence-write P2 fixed in the first driver only. `write_verified` refuses existing files/directories, checks directory creation/open, stores exact full-precision JSON bytes, flushes, checks `get_error`, closes, and verifies byte-exact readback. `check(written.ok)` contributes any write failure to the final nonzero exit. Completion marker now includes actual `writeOk`; a written JSON body describes gameplay checks before this final I/O check, so the completion marker/exit is authoritative for write success. A failed write is not retried over the partial file.

Focused `test-first-journey-evidence.gd` observed RED (missing verified writer), then GREEN `FIRST_JOURNEY_EVIDENCE_TESTS assertions=5 failures=0`. It writes only a fresh build fixture, checks exact full-precision bytes/readback, refuses overwrite without changing prior bytes, and refuses a directory output. No disk-full fault injection was performed. First driver successful zero-advance preflight and normal-entry historical-overwrite rejection were rechecked after the writer change; no voyages, production suite, GPU or unrelated coverage was run.

Review-scoped fix delta: `task-continued-voyage-tooling-review-fix.patch`; final tooling freeze includes nine files, adding only this focused selftest to the eight existing tools.
