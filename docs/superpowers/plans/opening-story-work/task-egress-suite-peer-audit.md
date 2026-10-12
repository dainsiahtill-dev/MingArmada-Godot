# Egress suite peer audit and test-only proposal

## Conclusion

The sole whole-suite failure is an outdated fixture expectation, not evidence that the Egress safety guard failed. Corrected wet-first course selection lets the recorded flagship turn and move. Fresh measured translation plus yaw makes its unchanged259-second conservative envelope intersect the Egress connector, so the navigator correctly latches furled neutral hold. No actual collision occurs in the five-second probe. Do not relax the predictor, hull sampling, budgets, authority, goal or terrain.

Product and frozen test files remain unchanged. Proposed test changes exist only in `build/second-aftermath-work/egress-suite-audit/test-only-proposal.patch` / `proposed_test.gd`, pending independent review and parent authorization to apply.

## Immutable failure and source identity

`docs/migration/evidence/opening-story/second-voyage-aftermath/all-tests-initial-failed.json` records112 selected,111 passed,1 failed. The only failure is `tests/test_wet_route_egress.gd`,61 assertions/1 failure, exit1: `actual native short turn keeps independently checked connector ownership`. Tick300 owner exists but `holding=true`, reason `predicted-peer`, peerId `mingqi-1650-flagship`; own max speed .00044150110375.

The audit loaded current Encounter SHA256 `0910d581c7a5f4642edc9d3ddcb826a9b42f5936655be441f1527458526c9df9`, old frozen body `5a86e578f41846b90ccd21c74f89518c6994441ce9beb2018bcfefc5fe7698e9`, unchanged Egress `9b63a8ec7cb2dfa115c8f0d411f6e65e1010f53d3a909e72f9f2b7b93b9ee586`, and recorded fixture SHA256 `0092a8c59c2235ccef226292d8d1a3f7bae09208612b99da42d9fce664b74dc5`. Start hashes and the untouched frozen test copy hash are saved in `audit.json`.

## Numeric proof

Both bodies start from identical recorded scalars, same formal terrain/wind/goal/cargo/draft, with real native physics. No live trajectory edits are performed.

- Own: position `(14.3057849963,431.1498958736)`, heading2.778460172, velocity `(.00173664976,-.00046661805)`, yaw0, dimensions36×10/draft1.4, mass151000, goal `(-60,250)`. Initial directed southern32m connector clearance is true, horizon259, padding1.860295337.
- Initial flagship: position `(-24.9754657831,323.8861729678)`, velocity `(.00384728462,.02223605546)`, yaw .000111003794, dimensions32×9/draft3.2. Its259-second angular padding is .238923427; actual center separation114.230131m.
- Old5a86 at300 ticks: flagship selects side−1, remains near its old no-go direction, yaw .000078199692, angular padding .168316215. Own Egress remains unheld and all actual own hull samples wet.
- Current0910 first holds at tick9=.15s. The immediately preceding tick8 snapshot reproduces the exact numerical guard: flagship position `(-24.9752893188,323.8897203246)`, velocity `(-.00049346554,.02974533232)`, yaw .020235819337, angular padding43.555369778. First intersecting own travel footprint is node `(14.3057849963,399.1498958736)`, heading−1.570796922, own padding1.860253733.
- Unchanged continuous SAT returns true for259s, false for5s and0s. Counterexamples setting only peer velocity to zero or only yaw to zero both return false. Thus this is a combined measured-motion envelope rejection, not an invented physical collision or a depth/speed/permission failure.
- At300 ticks current flagship side+1 has yaw .032041541231 and angular padding68.965884374. Own is holding, sails0/rudder0, actual own hull wet throughout; own max speed matches the old run.

`audit.gd/json/log` preserve initial, first-hold and each60-tick snapshots, controls, positions/velocities/yaw, actual hull checks, and the first envelope overlap. SAT reconstruction is forensic numeric code, not a product edit. These are short scalar/native fixtures; no historical controller replay or complete campaign claim.

## Independent safe control fixture

`single-boat.gd/json/log` selects only the same recorded grain vessel at Encounter construction, before any native step. Same own recorded pose/velocity/yaw, wind, terrain, hull/crew/sails/cargo/draft and navigation goal are restored during setup. Peer removal is a declared independent initial fixture; no peer, velocity or yaw is erased while a scenario is running.

At300 ticks/5s: real native owner remains present and unheld, fresh clearance true, all actual hull samples wet. Heading becomes3.064460172, yaw .062010217548; position `(14.3058172216,431.1499809767)` and max speed .00044150110375. This demonstrates the positive safe-turn behavior separately from the recorded moving-peer hold.

## Test-only proposal and RED/GREEN

Keep the original recorded fleet case and all existing rejection/authority/depth/goal cases. Replace only the stale unconditional unheld expectation with explicit fresh `predicted-peer`/flagship hold, sails0/rudder0, and no actual zero-horizon flagship overlap. Add a separately constructed single-boat300-tick safe case, checking fresh ownership, wet hull and unchanged goal.

- Current frozen test/whole phase:61/1, the stale unheld assumption, preserved as immutable initial failure.
- Proposed standalone test against old5a86 body:68/2, exit1. Exact failures: `recorded moving-peer fixture triggers fresh conservative peer hold` and `fresh predicted-peer rejection keeps furled neutral control`. Old wet-order body fails to evolve the same peer into the newly expected measured threat.
- Proposed standalone test against current0910 body:68/0, exit0. `candidate-green.log` and `candidate-unit.json` carry accurate current loaded SHA; `candidate-red.log` / `candidate-old-body-unit.json` carry accurate old-body SHA. Standalone reports write only to this audit directory.
- Proposed patch `git apply --check` passed. Patch is not applied to the frozen test. Its eventual normal test scratch destination is preserved; only standalone probe reports are redirected.

Parent must obtain independent review before test-only application/final test freeze and run all112 once. Runtime product0910 and runtime artifactSources22 do not include tests and remain unchanged by this proposal. No full voyage, wind convention, save/arrival gate, product patch or QA modification is introduced.

## Corrected probe-output side effect

The first standalone candidate copies accidentally retained the original mutable scratch report path, `build/port-approach-work/wet-route-egress/unit.json`. Concurrent candidates overwrote it with68/2 and a misleading current disk SHA for the old loaded body. The raw overwritten bytes are preserved as `untrusted-overwrite.json`; that report must not be used as evidence. The mistake was reported to parent immediately.

Generator now redirects red/green reports to separate audit paths and records the old loaded body hash correctly. Fresh red/green reruns produced the68/2 and68/0 results cited above. No historical JSON restoration or byte reconstruction was attempted. The immutable whole-suite failure, frozen product/test/QA and runtime evidence were not modified; the unrelated scratch file is not a primary phase record.
