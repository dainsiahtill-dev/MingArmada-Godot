# Costly first voyage: transport and medical continuation

Status: production source and focused tests frozen. Root owns final formal-terrain journey, real combat/UI capture and full-suite acceptance. This task did not modify Encounter/autopilot, physics, graphics, UI or journey tools, export, spawn agents, or mutate Git. Prior reports/evidence remain intact; all new artifacts use `recovery-*` / `.recovery-before` names.

## Resulting behavior

Second convoy acceptance still requires the actual safe Kinmen port, anchored ships, real20 grain stock, original paid lease, empty cargo, sufficient able crew, no active work/boarding, a terminal previous voyage, capacity and actual loaded draft admission through the existing route check.

- Two living valid original grain ships retain the original two voyages,10 grain each,20 stock decrement, zero new lease fee,1200-second deadline and source receipt/message shape. Original healthy two-boat golden fixtures pass unchanged.
- Exactly one genuinely sunk original may be omitted, witnessed by its actual loss/sunk casualty/sink history. The other **original** leased grain ship must pass every normal preparation check and carry20 in one real voyage. A healthy living original that is away, low-crewed, working, occupied or otherwise unavailable cannot be silently dropped. The native ship poses, identity, ownership and permission remain authoritative.
- Both wrecks cannot be replaced in this scope. When convoy002 exists after a positive first claim and the surviving original later also sinks, acceptance returns `convoy-transports-sunk`; the projection explicitly discloses no replacement source. Zero-delivery first failure does not invent a second offer.
- Original hull0, dead/wounded/prisoner counts, people deaths, casualty ordinals, first claim and lost first bonus remain unchanged. Ordinary native observation/projection fences can advance normally; tests compare historical/resource identity rather than incorrectly treating those fence revisions as resurrection.

Per Root's additional personnel review, **single-carrier convoy002** critical people are only original stewards who are alive and actually aboard this carrier at acceptance. The normal two-carrier contract retains both original IDs. The first contract's critical IDs, death receipts and already-lost bonus remain unchanged. A real20 delivery with the participating steward alive and within deadline can earn the new50 bonus; this is not a guaranteed reward or revival of the old steward.

## Medical access and movement separation

`Campaign.genuine_lease(id,state)` recognizes only original house-lin grain-a/grain-b/flagship/fast IDs backed by canonical first acceptance, real40 load, paid50 lease and exact original four-ship roster. It grants no new right to unsigned, foreign or arbitrary background house-lin ships.

`native_policy` reuses the existing service-only permission pattern for a genuinely leased, living, stopped original at the actual declared port berth: controllable for native service anchoring, **locked and disabledMotion** while below minimum. Actual service commands and NativeReadiness still require the live native anchored berth and safe flagship/port; lease data alone never authorizes remote treatment or sailing.

Treatment uses the existing4 silver/person,30 accepted seconds/person, actual available wounded, crew capacity, work/boarding limits and atomic native projection. Payment reserves work; it does not instantly heal. Completion transfers exactly the reserved wounded count into able crew and does not restore deaths. Below-minimum transport cannot accept the next task or navigate until the actual minimum is restored; active work prevents departure.

NativeReadiness now quotes one actual wounded person to decide generic treatment readiness, so insufficient funds, missing wounded, capacity and work limits agree with Domain. UI's exact selected quantity remains subject to the existing exact quote/command validation.

Campaign explicitly refuses departure with a below-minimum/disabled or locked flagship, in addition to the pre-existing global active-work guard. **Root** separately added the matching `Runtime.snapshot.canDepart` guard (crew≥minimum, not disabled or locked). This worker did not edit Runtime; its observed source SHA is recorded independently and the new focused test exercises Root's actual Runtime behavior.

## Optional return objective

A genuinely claimed positive first result, no first-return choice and an unaccepted offered convoy002 now guides:

- At sea/elsewhere: return to Kinmen and establish safe anchoring; it does not claim the clerk has already been met.
- At Kinmen: optional clerk conversation, still guarded by real runtime safety/anchoring eligibility.
- Directly accepting convoy002 skips the meeting objective and follows loading/underway/claim progression; no command is blocked for missing dialogue.

Failed/zero-delivery claims retain the recovery objective. Return copy explains the real20 grain supply task, current Kinmen stock, normal two-carrier or single-survivor concentration of risk, and unsupported all-wreck replacement. The preceding OpeningStory test's one intentional objective expectation was updated to the new optional meeting behavior; all other fixture/state expectations remain.

## Persistence checks

No new root state, version, receipt kind, new ship or invented lease fee was introduced. SaveCodec now validates:

- Convoy002 load/voyage count1 or2; canonical original participating carrier IDs and generated index voyage IDs, exact route/origin/destination/deadline,20 load/zero lease as before.
- Single-carrier omission only when the other original hull is0 and a genuine loss/sunk history precedes acceptance; a currently healthy omitted original or fabricated carrier/load/voyage is rejected.
- Critical-person list derived from the loaded carrier and death-receipt chronology, retaining any participating person who was alive at acceptance even if later killed. Removing such a person cannot farm the bonus.
- house-lin treatment work/payment must follow a genuine lease whose roster contains that ship. A forged work/payment reassigned to an unleased background ship is rejected.
- Existing completed treatment crew history, casualty chronology, price/time/reservation, old v2 saves and healthy two-boat contracts remain validated.

The codec provides structural/causal consistency, not cryptographic anti-tamper protection. Tests intentionally corrupt detached internal fixtures to verify rejection; those corrupted fixtures are not accepted gameplay actions.

## TDD and directed verification

Godot `4.7.2.stable.official.ed1daf0bf`. Exact invocation pattern:

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_convoy_recovery.gd
```

The same prefix ran the eight additional scripts below. Root's final `verification.json` was not overwritten.

- `recovery-red.json`: meaningful42 assertions /6 failures (single transport continuation, low-crew leased medical permission/lock, treatment commit and return objectives).
- `recovery-red-affordability.json`:110 assertions /1 failure caught the generic treatment hint advertising unaffordable care; it now consumes the actual domain quote.
- `recovery-red-service-save.json`:112 assertions /1 failure demonstrated a forged house-lin work/payment switched to an unleased background carrier; the lease-before-payment roster guard rejects it.
- `recovery-green.json`: final nine direct runs, all exit0, no Godot error diagnostics.

| Exact test | Final result |
| --- | --- |
| test_convoy_recovery.gd | 124 assertions,0 failures |
| test_mingqi_rules.gd | original full business/navigation/healthy two-convoy golden PASS(0) |
| test_save_compatibility.gd | original web-v2/forged-save cases PASS(0) |
| test_opening_story.gd | 116 assertions,0 failures |
| test_opening_story_save.gd | 122 assertions,0 failures |
| test_native_readiness.gd | 16 assertions,0 failures |
| test_opening_story_runtime.gd | 45 assertions,0 failures |
| test_opening_story_ui_runtime.gd | 39 assertions,0 failures |
| test_near_field_bridge.gd | 13 assertions,0 failures |

Counted tests total **475 assertions,0 failures**, plus two original fixture/oracle suites PASS(0).

The focused recovery test covers actual domain-created first arrivals/losses/casualties, safe real native dock, single20 loading/stock conservation, unchanged wreck/deaths, duplicate/stale rollback, forged carrier/load/voyage/personnel/save rejection, single second settlement/bonus chronology, normal10+10, living-away/low-crew refusal, true all-wreck history after a positive claim, independent below-min medical rights, actual1801 native ticks healing7→8, active/finished save continuity, unauthorized/unsigned/foreign/background service refusal, affordable quantity/capacity/actual anchoring, and real Runtime below-min/locked flagship departure behavior.

Some tests supply deterministic native observation fixtures to the real Campaign synchronization boundary to generate casualties/arrivals; these are explicitly unit fixtures, not presentation footage or acceptance teleports. The medical work test runs actual Runtime ticks and native service guards. No complete captain/combat voyage is claimed by this report.

## Artifacts and limits

- `campaign.gd.recovery-before`, `save_codec.gd.recovery-before`, `opening_story.gd.recovery-before`, `native_readiness.gd.recovery-before`, `test_opening_story.gd.recovery-before`: independent pre-edit snapshots.
- `recovery-scoped.patch`: only this task's four production files, the intentional objective expectation change and complete new focused test.
- `recovery-source-hashes.json`: final owned-source/test hashes; frozen Encounter SHA remains unchanged. Root-owned Runtime observed SHA is recorded separately.
- `mingqi_runtime.gd.recovery-runtime-observed`: read-only observation of Root's already-applied departure guard, excluded from this worker's owned patch.

Unsupported here: all-wreck replacement/new leases, recruiting dead crew replacements, extra ports/commodity economy, repeated third contracts and guaranteed combat victories. Root's current formal/manual/deadline journey and final strict headless suite remain the acceptance authority.
