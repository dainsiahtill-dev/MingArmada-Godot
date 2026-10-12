# Second-voyage aftermath independent Spec + Quality review

Date: 2026-10-12. Writable repository: `C:/Users/dains/Documents/Git/ming-armada`.

Status: **SPEC PASS / QUALITY PASS for the implemented Tasks1–4 scope after three review findings closed.** No open actionable implementation finding or established P0/P1 defect. Task5 acceptance is intentionally outside this review and remains pending; this is not whole-plan or playable/GPU completion.

## Scope and method

Approved source: `docs/superpowers/plans/2026-10-12-second-voyage-aftermath.md`; original playable-choice spec remains applicable where the approved plan does not explicitly replace it. Reviewed the actual new domain module, integration own baselines/patches under `docs/superpowers/plans/second-voyage-integration-work`, and the UI own baseline/scoped patch under `build/second-aftermath-work/ui`. Earlier `opening-story-work/*.before` files predate unrelated opening work and were excluded as feature diff baselines.

Using `code-review`, `caveman-review`, and `verification-before-completion`. The parent has already established CodeGraph has no project index; this review uses exact RTK source reads rather than inventing indexed results. All shell commands begin with RTK. No product source edited by reviewer; no Git staging, commit, push, reset, cleanup, or formal user-save writes. The isolated Control probe is a new review-only artifact under `build/second-aftermath-work/independent-review`.

## Spec findings

1. **[P2, closed after independent rerun] Mixed carrier exclusions were not visible.** Approved plan L70 requires the ship-specific explanation `人员曾跨船调动，本航受益人数暂不能核清`. `second_voyage_aftermath.gd:L145` supplies this in `bill.exclusions`, but the original `_story_bill` at `mingqi_interface.gd:L370` rendered only `scopeNote`. Repro: run `build/second-aftermath-work/independent-review/exclusion-control-probe.gd`; original actual Control output was `expected_visible=false`, exit1, while count20 was displayed. Root appended projected exclusions; the same probe now outputs `expected_visible=true`, exit0. Constructed presentation-only data; no legal-save, voyage, or GPU claim.

2. **[P2, closed after independent rerun] The bill showed the increment without current support.** Approved plan L47 requires `既有crewSupport与实际增量`. The original `_story_bill` only displayed `船员拥护+4`; before/after fields were unused. Root now displays current50, prospective54 and actual+4 in `mingqi_interface.gd:L371`; arithmetic98→100/+2 previews are covered. The completed bill at L367 displays current support with the actual receipt and avoids a second payment forecast. Fresh independent UI110/0/exit0; the extended isolated Control probe outputs both `expected_visible=true` and `support_visible=true`, exit0.

3. **[P2 validation gap, closed after independent rerun] Legitimate transfer save proof was absent.** Approved plan L165 requires a dividend to survive later transfer and strict save. Initial pure-domain `transition_slice` explicitly is not a Codec-valid full save. Added `tests/test_second_voyage_aftermath_save.gd:L98` builds a formal second claim, processes a constructed observation of an existing canonical enemy through real casualty conservation, then actual native `start-boarding`/three `board-action` commands and domain progression to earn a held prize. `legitimate_transfers` at L134 executes actual `allocate-prize` of12 crew from original grainA20→8. Before payment, only unaffected grainB20 receives; after payment, the original40-person roster stays valid. Replacing it with current28 is rejected. Independent fresh SaveCodec400/0/exit0 and actual encode/decode verify both complete histories. No product transfer defect established or product fix needed. These are constructed automation observations, not an actual enemy-capture journey.

## Quality review

- `OpeningStory.SCENES`/`CHOICES`, old `_reply`, `_scene_text`, and `_choice_label` are byte-identical to the feature own baseline. The original three scenes/seven definitions remain separate; the new scene is appended only after a bound legal second claim. Direct new-scene `OpeningStory.apply` refuses missing native context.
- Campaign's new dispatch is limited to `second-return`. It checks the three-port whitelist after native sync, retains `_docked` and the original old-scene fixed port comparison, and produces the historical port witness from that same accepted snapshot. Strict command fields prevent UI/caller-supplied port/native/witness fields. Receipt/state commit remains after native projection; the rejection regression verifies no campaign resource or receipt mutation.
- R/P/A derive from fixed `convoy-002` claim/load identity, actual terminal voyages/arrival evidence, and contract receipt binding. Claim/load/choice chronicle ordering and receipt revisions are checked. Fixed story ID and both command replay guards prevent repeat payment.
- Recipients are sorted unique proved load carriers; current or historical able+wounded counts exclude prisoners, sunk ships, unproved escorts/background vessels, and mixed cross-ship groups. The reverse event-chain reconstruction does not use received beneficiaries as its own evidence. Existing independent Codec schemas, business relations and crew-chain checks remain active.
- New-scene conditional attachment schema is strict; old scenes cannot carry it. Historical witness coordinates are validated against the receipt port, not save-time currentPortId. Nonshare choices have zero payment/support effect and no persisted planned repayment. The existing debt history validates principal continuity, rather than treating a return intent as repayment.
- Source search confirms existing support writes remain initial50 and canonical old story effects plus the new share. Global replay is applied only to new shares; unexplained old support remains compatible with old play and both zero-effect new choices. 98/100 are preview arithmetic fixtures, not evidence of a legally produced payment state under the current source set.
- Save test numeric tolerances are restricted to `macroRemainder`/chronicle simTime (absolute1e-12) and vessel pose position/speed (relative1e-12). Currency, counts, crew, receipt revisions, witness data and support stay exact. This is test comparison only; product Codec validation was not loosened.
- Runtime is byte-identical to the integration own baseline. Navigation, terrain, reference effects, assets and performance files are outside the scoped patches. No new economics, enemies, casualties, people, inventory or future contract content added by this feature.

## Fresh independent execution

Every command used this exact prefix:

`rtk proxy "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --headless --path . --script <path>`

| Path | Observed result | Exit |
|---|---:|---:|
| `tests/test_second_voyage_aftermath.gd` | 107 assertions / 0 failures | 0 |
| `tests/test_second_voyage_aftermath_runtime.gd` | 105 / 0 | 0 |
| `tests/test_second_voyage_aftermath_save.gd` | 400 / 0 after transfer coverage | 0 |
| `tests/test_second_voyage_aftermath_ui.gd` | 110 / 0 after both UI fixes | 0 |
| `tests/test_opening_story.gd` | 116 / 0 | 0 |
| `tests/test_opening_story_save.gd` | 122 / 0 | 0 |
| `build/second-aftermath-work/independent-review/exclusion-control-probe.gd` | original exclusion false → final exclusion/support true | 1 → 0 |

Initial independently observed new tests were domain107/runtime105/save349/UI107, all exit0. Save346→349 added three explicit old reference-state compatibility rows; save349→400 added legitimate transfer lineage. UI107→110 added exclusion/current-support display checks. These are constructed automation checks through domain/native/Control boundaries, not actual player voyages or GPU proof.

## Reviewed source identity

- Domain: `ed878a22ced050aa11a22c4a874e31a9eb29f3d22812408e1e21304486a26beb`
- OpeningStory: `4135a4a47a107ac4ba097ed19213a25e6f85ee0097f23bc940971df92f57aafa`
- Campaign: `fe5c7b04a52096f022fc893d2d1f8518535c32fd21b99909c454ee877342b5f3`
- SaveCodec: `7aa5c109d2a8f12d36338af8aaa5c5a32118a4bfcb0f9a9e1b6a1541d50b952a`
- Runtime unchanged: `2824661d6a63af6580874eeb89037ddc2434791605b26831a705c129dfef4dea`
- Initial UI: `acf1ee1f8928c9943a3e000ab373cbdec2057624619d3a6c7ade4bd18686c90f`
- Exclusion fix UI observed: `690c1fbad84c633b484f236c8f648fcb6455a0a5146329879d71a921e5c36395`
- Final reviewed UI: `fae0ce2b3e767df684a800e7bd916fe111f4034dbdc346cd31469eb1f000417c`
- Final UI test: `35d37a885917a25d3c7b93f01025d45ae9e58284003facd217b93fe57cd7d938`
- Final save test: `f33ca1a2cd2d51062c9305b003874ac12673878e187acfc16dc2a59b930341e9`
- Runtime test: `10d425dfe21d95e1d1e47fff8e13fd9acb8a487529306944719c6f9bc56efc4e`

Final reviewed hashes were freshly collected after independent UI110, Save400 and Control-probe execution. Root can freeze and regenerate the final scoped UI package including both reviewed fixes. No whole-plan completion claim: full suite, actual current-source voyages, native mouse/GPU branches, small-window visual acceptance and normal disk Save/Continue remain Task5 obligations owned by root. Do not claim signature-level native telemetry authentication or coordinated whole-economic-ledger tamper resistance from these checks.

Conservative interpretation: the zero-cash goal remains enabled and discloses current cash0/current repayable0; independent repayment retains its cash refusal. Current ship status and existing repair/treatment/trade quotes remain accessible through the existing ship/port goal panels. These reuse the approved plan's existing-page scope rather than introduce a second inventory or price model. Arithmetic98/100 preview coverage does not authorize unexplained-history share payment.
