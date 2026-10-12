# Opening story domain implementation

Status: domain source and directed tests frozen. Runtime/UI wiring and actual GPU journey acceptance belong to Root/UI worker; this task did not edit those files, open GPU windows, change graphics, export, run the full suite, or perform Git mutations.

## Files and authority

- `game/domain/mingqi/opening_story.gd`: static `project(state)` and `apply(candidate,sceneId,choiceId)`; pure detached JSON projection and candidate-only effects. Preloads Catalog only, so Campaign/SaveCodec can consume it without a dependency cycle.
- `game/domain/mingqi/campaign.gd`: adds strict `story-choice` and `repay-debt` to existing BUSINESS/NEEDS_NATIVE, preserving the original revision, command idempotency, candidate clone, native safety/projection and final commit path.
- `game/domain/persistence/save_codec.gd`: accepts both new receipt kinds and validates their canonical definitions/chronology. Old v2 root fields remain unchanged; no story root field, interest, due-time migration or chapter mutation was added. Existing debt `creditorId` and `dueAt` remain exact fixture values; principal is now an integer 0..400 witnessed by valid repayments.
- `tests/test_opening_story.gd` and `tests/test_opening_story_save.gd`: meaningful RED/GREEN and directed regression using the actual Runtime/Encounter/NearFieldBridge native authority, plus source fixtures at the native observation boundary.

Pre-edit Campaign/SaveCodec copies are `campaign.gd.before` and `save_codec.gd.before` in this directory. `domain-scoped.patch` compares those snapshots with only this task's final sources and includes complete new module/tests; it excludes inherited changes. `domain-source-hashes.json` pins the five delivered source/test files.

## Choices and consequences

| Scene / choice | Silver | Actual effect |
| --- | ---: | --- |
| old-ledger / settle-wages | 80 | crewSupport +10 |
| old-ledger / keep-reserve | 0 | crewSupport -4 |
| pilot-plan / hire-pilot | 45 | merchantCredit +1, plan both original grain voyages on the shallow route after both real cargo drafts pass existing `route_for_vessel` |
| pilot-plan / stay-deep | 0 | plan both original grain voyages on the deep route |
| first-return / crew-dividend | 80 | crewSupport +8 |
| first-return / buy-intelligence | 60 | militaryTrust +2, merchantCredit +3, snapshot actual forward-supply grain stock at current accepted simulation time, confidence .65 |
| first-return / keep-capital | 0 | retain capital without a reputation change |

Reputation changes clamp -100..100. Crew support is described as affecting existing boarding initial morale, not sailing/cannon speed. Merchant credit is not represented as a price discount. Pilot fee buys two-voyage planning and a relationship benefit; the original free per-voyage `choose-route` command remains available, with no route unlock or safety/velocity promise.

The story receipt identity is `campaignId + ':story:' + sceneId`, with fixed details keys:

`kind, sceneId, choiceId, portId, silverCost, reputationEffects{crewSupport,militaryTrust,merchantCredit}, routeId, convoyReceiptId, intelligence`.

Existing command idempotency returns the original receipt for replayed command IDs. A fresh command cannot repeat a completed scene. Costs and definitions are checked before mutating the candidate. Both pilot routes preserve escorts and actual poses; Campaign uses its existing `locate_route` afterwards and retains flagship permissions. All new actions require the relevant `currentPortId` plus `_docked` for the flagship, which incorporates `_safe_dock` and the actual `isAnchored` native query. Port proximity alone does not authorize dialogue/payment. A native projection refusal leaves Campaign unchanged.

## Projection and narrative correctness

`project` derives offered/loading/underway/finished/claimed first and second convoy objectives from the actual contracts/voyages, without completing anything. Scenes retain completed choices/replies but disable choices. Locked scenes expose only their current prerequisite prompt. History comes from actual story receipts and chronicle time.

许福 and 陈阿海 are original fictional dialogue characters. The inherited 承家号 and borrowed 明旗号/fast ship are explicitly distinguished. Dialogue records do not add physical personnel or change ownership. Relations reflect choices and actual claimed casualties.

Per Root's additional review, `first-return` is spoken by a distinct original **留守金门的林账房** (`npc.id = 'lin-clerk'`), because the actual convoy's 林管事 (`steward-a`) may have died. The 林管事 relation respects `people['steward-a'].alive`. Return dialogue reports actual delivered/lost grain and dead/wounded totals for full, partial and failed outcomes; no loss is concealed. Purchased intelligence reply displays actual grain stock, observation time in seconds and 65% confidence.

`debt.canRepay` is domain readiness (positive balance, positive silver, Xiamen); Root combines this with actual native dock/UI eligibility.

## Repayment and save checks

`repay-debt` takes only type/commandId/expectedRevision/positive integer quantity. It subtracts actual silver and remaining principal at Xiamen's safe, anchored berth. Its receipt is `campaignId + ':repay-debt:' + commandId`, with details `kind,portId,amount,beforePrincipal,afterPrincipal,creditAward`. Partial credit award is 0; the final payoff awards +6 once, clamped by existing reputation bounds.

Save validation enforces:

- Exact scene/choice cost, port, reputation effects, optional route and intelligence definition; canonical scene receipt identity and cause IDs.
- Pilot after the actual first acceptance; old-ledger/pilot before departure/arrival/loss/claim; return after the genuine first claim receipt.
- Purchased intelligence has one matching persisted entry, canonical receipt source, forward-supply grain field, exact observation event time and .65 confidence.
- Repayment chronology has strictly increasing receipt revisions, continuous before/after principal from 400, actual positive amounts, principal equal to 400 minus distinct payments and the sole final payoff award.

The codec is consistency validation, not a cryptographic anti-tamper system. Existing historic trade receipts do not contain a complete inventory ledger, so the new intelligence validator checks the paired immutable story receipt/entry rather than pretending to reconstruct every past stock movement from legacy receipts. Actual stock is sampled directly at command execution.

## Verification

Godot: `4.7.2.stable.official.ed1daf0bf`. Each test was executed directly, keeping Root's final `docs/migration/evidence/verification.json` untouched:

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_opening_story.gd
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_opening_story_save.gd
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_mingqi_rules.gd
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_save_compatibility.gd
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_mingqi_live_projection.gd
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_native_readiness.gd
```

`domain-red.json`: meaningful feature RED, 6 assertions / 4 failures (missing story command, repayment and projection). Preliminary test type-inference errors and an early concurrent Root preload were corrected before recording this RED; they were not treated as feature failures.

`domain-green.json`: final six direct runs, exit 0, no Godot errors:

| Test | Result |
| --- | --- |
| opening_story | 116 assertions, 0 failures |
| opening_story_save | 122 assertions, 0 failures |
| mingqi_rules | source golden PASS (0), including original initial state, navigation, business, boarding/prize/care/contract fixtures |
| save_compatibility | web v2 / old optional buckets / original forged save cases PASS (0) |
| mingqi_live_projection | 9 assertions, 0 failures |
| native_readiness | 16 assertions, 0 failures |

The four counted tests total **263 assertions, 0 failures**, plus two original fixture/oracle suites passed. Tests cover all seven choices, duplicate/fresh replay, stale/extra/unknown/early intents, actual dock/anchoring, native projection refusal, poverty rollback, one too-deep grain vessel rejecting the entire plan, unchanged permission/escorts/pose, reputation clamps, intelligence content/readable reply, all first/second convoy objective phases, old fixture compatibility, forged receipt costs/choices/effects/payments/principal/awards/order, and split payments preventing repeated credit awards.

Partial and failed return tests start from the original departing convoy fixture, submit loss/arrival native observations to real Campaign synchronization, generate actual claim receipts, then dock and choose through an actual native bridge. They are domain boundary tests, not GPU collision footage. JSON roundtrips compare all fields recursively, with only a 1e-12 relative allowance for numeric serialization of native poses (initial strict Dictionary equality produced last-digit numeric false failures; resources and canonical receipt values remain literal-checked).

Runtime/UI review and real playable journey screenshots remain Root's separate acceptance work.
