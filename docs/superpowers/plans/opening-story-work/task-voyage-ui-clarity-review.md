# Task 2 independent review

Reviewed the supplied scoped patch, Task 2 plus Global Constraints, implementation report, and necessary existing Campaign/Runtime/UI call paths. Read-only review; only this report was written. CodeGraph had no project index according to root discovery; no repeated discovery or fabricated indexed results. No author covering-test rerun, full suite, GPU/editor operation, source edit, or Git mutation.

**Spec: NEEDS FIX. Quality: NEEDS FIX.** One P2 finding; no financial/safety-gate mutation found in the scoped delta.

## Finding

- **[P2] `game/ui/mingqi/mingqi_interface.gd:625`: first offered contract falsely promises acceptance starts its timer.** `_contract_timing` returns `接单后开始计时` for both contracts. Actual `convoy-001` starts with `deadlineAt=1800` (`game/domain/mingqi/campaign.gd:44`), and its acceptance branch changes status/loading/accounting without resetting that deadline (`campaign.gd:320–336`). `Runtime.advance` advances Campaign time without an offered-contract pause (`game/runtime/mingqi_runtime.gd:208–230`; `campaign.gd:536–550`). A player who spends 1000 simulation seconds before accepting therefore receives 800 seconds remaining, although the offered label promises a new timer; waiting past 1800 yields immediate overdue status. Preserve the existing deadline/business rules: use accurate neutral offered copy (for example `接单后显示剩余期限`) or distinguish the fixed first deadline from the actual acceptance-relative second contract. Add a regression using the real first-contract deadline and advancing pre-acceptance clock. The literal plan phrase about acceptance timing conflicts with existing first-contract behavior; resolve its wording without changing domain state.

## Verified scope

- Active deadlines derive from `deadlineAt - simulationSeconds`; overdue and passed ETA branches do not manufacture arrival. Positive fractional remaining seconds use ceiling.
- Offered deadline zero is never rendered as expiry. Terminal contract/voyage branches remove stale deadline/leg forecasts and identify recorded outcomes. The existing receipts supply actual cargo/reward details.
- Existing watcher refresh reads current snapshots, so clock-only updates refresh labels without rebuilding controls. Loading copy checks offered membership, `_operational()`, and actual runtime `canDepart`/`departReason`; unavailable runtime cannot promise preparation approval through the new presenter.
- Debt-only `not-in-port` directs to Xiamen in both domain and native-reason paths. Generic `_reason`, repayment limits, native eligibility, button predicates, command dispatch, and financial/deadline state remain unchanged from baseline.
- New regression tests cover wrong-port and unsafe Xiamen, clock-only updates, loading availability/readiness, elapsed ETA, terminal branches, and snapshot non-mutation. They omit real delayed first acceptance, which is why the incorrect offered promise passes.

## Identity and verification limits

Independent SHA256 readback matches author report:

- Baseline UI: `baa673b5a8bb75994e3234e832341a51c5c34b203a7ef8cfe4bca52e5d5c88e9`
- Reviewed UI: `f81b5adc9398cdead4e4af70662c5c26aaf9f1ecae7b75be8e796f0b9352688c`
- Reviewed new test: `1b24fbafe9ee2447dc0b5f6b167a1bf089c53905c66bd19deb6be83119dc4c92`

Author reports five covering scripts, 332 assertions/0 failures; this review does not claim an independent execution of those tests. Current native visual layout, normal saved/continued real clock progression, combined full suite, and real voyages **Cannot verify** in this scoped review; root owns those checks after source freeze.

## Scoped P2 follow-up review — final verdict

**Original P2: ADDRESSED. Final Spec: PASS. Final Quality: PASS.** These verdicts apply to the reviewed Task 2 source scope; integration acceptance remains root-owned.

- `mingqi_interface.gd:625` now checks actual positive offered `deadlineAt`: `接单前也计时` plus relative remaining/overdue duration. Zero/unset deadline retains acceptance-timing copy. This preserves the root ruling and the actual fixed first deadline 1800.
- `_deadline_timing` extracts the unchanged active timing math; no domain mutation, business constant duplication, acceptance/button predicate, financial gate, or runtime command change in the correction. Terminal and loading presenters are unchanged. No important fix-induced regression found.
- New real regression (`tests/test_voyage_ui_clarity.gd:17`) advances fresh Campaigns to 1000 and 1900, configures Runtime from those real states, and emits the actual UI acceptance button into `Runtime.command`. It checks offered and active timing plus preserved deadline 1800. This covers the original failure rather than merely matching presenter internals.
- Independently verified the correction patch exactly equals actual diffs from both preserved pre-fix copies. Their SHA256 values match the originally reviewed UI/test. Current UI SHA256 `0d39c357434dd52ea2f62ddbb9bc027c3f1c591ab4faa991310e5dd931d64dd8`; current test SHA256 `7f57fb1afeef5d63ce2f0185eafa2b79d687abe74a512bea3620e64bb035fa83`.
- Read the appended author evidence: RED 37/2 then GREEN 37/0, five covering scripts 346/0. No independent rerun in this follow-up; no GPU/full-suite/source/Git action.

**Cannot verify here:** current native wrapping/spacing of the longer offered copy or real combined Task 1/2 saved/continued voyages. Root must inspect current native screenshots and perform its frozen-source integration checks separately; scoped approval does not claim those results.
