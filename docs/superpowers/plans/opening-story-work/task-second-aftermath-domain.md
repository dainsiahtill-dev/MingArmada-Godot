# Second voyage aftermath domain lane

Plan: `docs/superpowers/plans/2026-10-12-second-voyage-aftermath.md`, Task 1, domain apply from Task 2, receipt validation helper from Task 3.

Writable repository: `C:/Users/dains/Documents/Git/ming-armada`. Ambient `MingArmada`, reference game, historical QA, navigation, graphics, performance, integration sources and UI untouched by this lane. No Git staging, commit, push, reset or cleaning. Root runs combined full suite once after integration.

## Files and interfaces

- `game/domain/mingqi/second_voyage_aftermath.gd`: RefCounted static choice_definition, quote, apply, project, receipt_error, crew_at_event. Existing three-scene behavior remains integration lane's responsibility.
- `tests/test_second_voyage_aftermath.gd`: scoped domain behavior, history reconstruction, source identity, JSON number/order compatibility.
- `tests/second_voyage_aftermath_fixture.gd`: explicitly constructed automation fixtures using old legitimate second load, real Campaign sync arrival/cargo loss/casualty boundaries, and actual claim command. No hand-authored success claim. Does not prove a player journey or a safe native dock.

`apply` writes only captain.silver and reputations.crewSupport on the caller's draft. It checks a safe witness, returns the exact new-scene details + aftermath attachment, and never appends settlements/chronicle or advances revision. Campaign owns native authorization, fixed receipt persistence and atomic commit.

`project` returns `{scene,objective,relationNote,bill}`; `scene.bill` also carries bill. Existing scene and choice shapes preserved. Account speaker: `{id:'aftermath-ledger',name:'交差账单',role:'船上账册'}`; two sentences. Bill fields: delivered, lost, baseReward, bonus, revenue, silver, principal, dividend, remainingSilver, supportBefore, supportAward, supportAfter, supportDelta, beneficiaryCount, beneficiaries, verifiedDeaths, currentWounded, scopeNote, exclusions.

Schema: ten details fields (kind, sceneId, choiceId, portId, silverCost, reputationEffects, routeId, convoyReceiptId, intelligence, aftermath); nine aftermath fields (contractId, revenue, silverBefore, silverAfter, supportBefore, supportAfter, beneficiaries, beneficiaryCount, portWitness). No planned repayment amount. Return goal and keep-capital have zero payment and zero support effect.

## Evidence

Command for every scoped run:

`rtk proxy "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --headless --path . --script tests/test_second_voyage_aftermath.gd`

- Initial RED: process 1, `SECOND_VOYAGE_AFTERMATH_TESTS assertions=1 failures=1`; exact failure `second aftermath domain implementation exists`. No missing preload parse error.
- First meaningful GREEN: process 0, 94 assertions / 0 failures.
- JSON number and field order regression: RED 97 / 3, process 1; recursive semantic comparison GREEN 97 / 0, process 0. Godot Dictionary equality and numeric Array membership distinguish decoded floats from generated ints; semantic numeric comparisons preserve V2 round trips.
- Duplicate load-carrier regression: RED 107 / 1, process 1; explicit uniqueness check GREEN 107 / 0, process 0.

Constructed boundary cases produce formal claim revenues 250 / 200 / 150 / 0; expected shares 50 / 40 / 30 / refused, nominal awards 4 / 4 / 3 / 0. Exact sufficient cash accepted, one less rejected. Two proved 20-person carriers yield 40 recipients. A real casualty boundary with able=0 yields ten wounded survivors and ten actual deaths for that carrier; wounds remain eligible and deaths excluded. Real sinking removes that group. Flagship, fast escort and background trader never included.

Explicit aggregate-history unit slices cover prior treatment, prior mixed transfer, and later transfer after payment. These slices exercise pure historical reconstruction and are deliberately labelled neither gameplay actions nor Codec-valid full saves. Integration tests own full legal business-action lineage and independent SaveCodec chain validation.

## Rulings

Ruling: support 98/100 preview is a constructed arithmetic boundary, never evidence of a legally reached support state. Existing legitimate sources in current code are initial 50 plus original fixed story effects, maximum 68. Consequently high/unexplained old support remains compatible for original gameplay and both zero-effect new choices, while actual new share refuses `unexplained-crew-support`. Root accepted this correction to conflicting cap and history requirements. Cost if wrong: a future legitimate support source requires inclusion in replay; preview already displays actual cap delta 2/0.

Ruling: count comparisons use semantic finite numeric equality and normalized integer buckets. Exact type equality would reject JSON-decoded legitimate historical evidence. Cost if wrong: numeric schema validation remains necessary in SaveCodec; this module does not authenticate arbitrary untyped JSON.

## Review boundaries

Check actual fixed claim/load/contract binding, real second-carrier uniqueness, load < claim < choice with receipt revision increments, sorted unique recipients, prisoner/dead/sunk/mixed exclusions, current-to-cut reverse reconstruction, canonical or legitimate load baseline, later treatment/loss/transfer compatibility, support replay and nonshare old-state compatibility. Native safe docking remains Campaign/Runtime authority; witness receipt checks historical port coordinates and fixed safety fields, not a recreated historical callable. SaveCodec must independently validate complete schemas and crew-event chains.

No signature-level provenance, global coordinated economic-ledger tamper resistance, actual GUI/GPU journey, Continue acceptance, performance, human enjoyment or product completion claim from this lane.
