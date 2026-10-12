# Task 2: Relative voyage information and Xiamen repayment copy

Implemented in the writable `ming-armada` checkout. Production scope is only `game/ui/mingqi/mingqi_interface.gd`; regression scope is new `tests/test_voyage_ui_clarity.gd`. Existing UI tests were not edited. No Git mutation, GPU/editor operation, campaign deadline/state mutation, navigation change or runtime change.

CodeGraph root discovery reported no project index; worker used targeted RTK fallback discovery, not fabricated CodeGraph results. Applied TDD and verification-before-completion. Root owns combined full suite, real voyages and current native capture; these remain outstanding integration acceptance, not claimed by this worker.

## Behavior

- Offered contracts: `接单后开始计时`, including deadline zero. No duplicated domain duration constant.
- Active contracts: `deadlineAt - simulationSeconds` produces remaining or genuinely overdue seconds. Positive fractional durations round up rather than promising expiry prematurely. Clock-only snapshots update the existing label without rebuilding the Control tree.
- Delivered, failed and settled contracts: recorded outcome, no continuing deadline display. Existing actual receipts remain the source of financial/cargo details.
- Underway voyages: relative ETA, keeping actual leg/progress. A passed ETA says `预计时间已过，尚未抵达`, never creates or implies arrival.
- Loading voyages: offered acceptance prerequisite first; otherwise real runtime availability and `canDepart`/`departReason`. No absolute stale ETA. Unavailable runtime cannot promise readiness even if an old `canDepart` is true.
- Arrived/lost/interrupted voyages: recorded arrival/loss or interrupted preparation context, no stale ETA/leg forecast. Existing current-voyage references, route fields and buttons remain intact.
- Debt-only `not-in-port`: directs the player to `厦门林家商行` for both domain and native reasons. Generic `_reason("not-in-port")` remains unchanged; unsafe Xiamen, debt/financial limits, native checks and command guards retain their behavior.

## TDD evidence

Before production changes, the new real Control-tree snapshot test ran with **23 assertions / 19 failures**, exit 1. Failures were expected missing behavior, with no parse/runtime errors:

```text
anchored Kinmen debt refusal identifies the actual creditor port
native wrong-port debt reason identifies Xiamen too
offered zero deadline is acceptance timing rather than expiry
loading voyage never shows stale ETA
offered loading voyage identifies acceptance prerequisite
active contract displays remaining deadline
underway ETA is relative to campaign time
clock advance refreshes same contract label without stale duration
clock advance refreshes voyage countdown
expired active contract shows actual overdue duration
passed ETA never asserts arrival
loading voyage reports failed runtime preparation
loading readiness uses actual runtime departure approval
arrived displays outcome rather than stale travel forecast
lost displays outcome rather than stale travel forecast
interrupted displays outcome rather than stale travel forecast
delivered keeps recorded outcome without misleading deadline
failed keeps recorded outcome without misleading deadline
settled keeps recorded outcome without misleading deadline
```

After implementation: **332 assertions / 0 failures** across the five covering tests, each exit 0. Godot `4.7.2.stable.official.ed1daf0bf`.

```text
VOYAGE_UI_CLARITY_TESTS assertions=23 failures=0
OPENING_STORY_UI_TESTS assertions=59 failures=0
OPENING_STORY_UI_RUNTIME_TESTS assertions=39 failures=0
MINGQI_UI_TESTS assertions=195 failures=0
NATIVE_READINESS_TESTS assertions=16 failures=0
```

Exact commands (new test RED and GREEN used the same command):

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_voyage_ui_clarity.gd --quit-after 120
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_opening_story_ui.gd --quit-after 500
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_opening_story_ui_runtime.gd --quit-after 500
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_mingqi_ui.gd --quit-after 500
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_native_readiness.gd --quit-after 500
```

Only launcher warning: RTK has no global hook installed. Godot output had no engine/script warning or error. Existing Runtime test exercised real guarded story, refit and treatment commands. Existing UI test retained 1600/1100 viewport HUD dimensions `(430, 333)`.

## Independent review artifacts

- Baseline: `build/port-approach-work/mingqi_interface.gd.before`
- Scoped patch: `docs/superpowers/plans/opening-story-work/task-voyage-ui-clarity.patch` (UI delta from supplied baseline and new regression test only).
- Baseline SHA256: `baa673b5a8bb75994e3234e832341a51c5c34b203a7ef8cfe4bca52e5d5c88e9`
- Final UI SHA256: `f81b5adc9398cdead4e4af70662c5c26aaf9f1ecae7b75be8e796f0b9352688c`
- New test SHA256: `1b24fbafe9ee2447dc0b5f6b167a1bf089c53905c66bd19deb6be83119dc4c92`

No additional design ruling required. New test must be included in root full-suite enumeration. Native visual layout and real clock progression on saved/continued voyages remain root verification responsibilities.

## Independent review P2 correction (current final state)

The preceding implementation record is historical. Its universal offered-contract acceptance timer statement and final hashes are superseded here. Independent review identified the real first contract's fixed initial `deadlineAt=1800`, unchanged by acceptance; root ruled to preserve those business rules and correct the copy.

Current offered presenter distinguishes existing deadlines: positive `deadlineAt` shows **`接单前也计时` plus actual remaining/overdue duration**. Zero/unset deadline retains `接单后开始计时`. Active contracts reuse the same relative deadline presenter. Domain/runtime deadlines and all button predicates are unchanged.

Added real delayed acceptance regression: create fresh `Campaign`, call its real `advance(1000)` or `advance(1900)`, configure actual Runtime from that legitimately advanced campaign, apply its actual snapshot to Interface, then press the actual `contract_accept_convoy-001` button through `Interface -> Runtime.command -> Campaign`. No direct state edits, fabricated save or mocked result in these two cases. The tests assert offered timing before acceptance, successful existing acceptance, unchanged deadline 1800, and identical timing after acceptance: respectively remaining 800 seconds and overdue 100 seconds. This verifies business clock behavior and actual UI/Runtime acceptance; it does not substitute for native physical simulation over those durations.

Review-fix RED before production correction: **37 assertions / 2 expected failures**, exit 1:

```text
first offered deadline remains visible before delayed acceptance at 1000.0
first offered deadline remains visible before delayed acceptance at 1900.0
```

After correction, fresh covering commands (same five scripts above, `--quit-after 500` for all) each exited 0, **346 assertions / 0 failures**:

```text
VOYAGE_UI_CLARITY_TESTS assertions=37 failures=0
OPENING_STORY_UI_TESTS assertions=59 failures=0
OPENING_STORY_UI_RUNTIME_TESTS assertions=39 failures=0
MINGQI_UI_TESTS assertions=195 failures=0
NATIVE_READINESS_TESTS assertions=16 failures=0
```

No engine/script errors or warnings; only RTK launcher global-hook warning. Full suite/GPU/new review not run by worker per root ownership.

Review freeze preserved before edits:

- `build/port-approach-work/mingqi_interface.gd.reviewed`, SHA256 `f81b5adc9398cdead4e4af70662c5c26aaf9f1ecae7b75be8e796f0b9352688c`.
- `build/port-approach-work/test_voyage_ui_clarity.gd.reviewed`, SHA256 `1b24fbafe9ee2447dc0b5f6b167a1bf089c53905c66bd19deb6be83119dc4c92`.
- Review correction delta: `docs/superpowers/plans/opening-story-work/task-voyage-ui-clarity-review-fix.patch` against those reviewed copies.
- Cumulative `task-voyage-ui-clarity.patch` updated against original supplied baseline.
- Current UI SHA256: `0d39c357434dd52ea2f62ddbb9bc027c3f1c591ab4faa991310e5dd931d64dd8`.
- Current test SHA256: `7f57fb1afeef5d63ce2f0185eafa2b79d687abe74a512bea3620e64bb035fa83`.
