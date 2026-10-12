# Second-voyage aftermath UI — implemented, runtime acceptance pending

Root owns `game/ui/mingqi/mingqi_interface.gd` and `tests/test_second_voyage_aftermath_ui.gd`. Baseline, scoped patch and observed test record are under `build/second-aftermath-work/ui`.

The new current decision appears before completed earlier scenes, retaining their original order. A compact dynamic bill shows actual delivery/loss, base/bonus/revenue, cash/debt, prospective20% payment/remaining cash, verified carrier beneficiaries and bounded actual support increment. Scope explicitly excludes unproven escort casualties. Completed decisions display live cash and their receipt, without proposing the same payment a second time. No added game economy, prices or invented casualties.

Three-port and unavailable-payment reasons are visible text. Native eligibility remains required; the UI never supplies port/native/witness fields. Existing debt input and independent repayment remain authoritative. Existing scenes retain their previous reason handling and command builders.

Presentation TDD: RED7/4 -> GREEN19/0; completed-payment preview RED22/1 -> GREEN22/0; legacy support explanation RED23/1 -> GREEN23/0. Final root direct Godot test107/0/exit0 adds nine real Control->Runtime->Campaign branches across all three ports, strict V2 roundtrips, and a separate100 repayment at Xiamen. These use constructed domain arrival fixtures with real native bridges, explicitly not voyage/GPU proof. Old opening UI59/0/exit0.

One initial PowerShell RED-output wrapper incorrectly expanded variables and returned misleading shell0. Preserved as diagnostic; the immediately repeated direct RTK Godot run returned actual exit1 and is the counted RED. No product change was based on the wrapper exit.

Root will run combined full suite and actual current-source voyages once all reviews pass, then capture native mouse branches and normal Save/Continue from the genuine second-voyage checkpoint. No human fun/balance research or graphics improvement claimed here.

Independent review corrections: ship-specific exclusions were present in domain data but invisible; new real-Control regression RED108/1 -> GREEN108/0 now shows them. Existing support value was absent; RED110/3 -> GREEN110/0 now shows current support, prospective capped value and actual increment. Completed bill shows current support and actual receipt without a new-payment forecast. Domain and economy were not changed by these UI fixes. The reviewer independently reproduced exclusion visibility before and after.
