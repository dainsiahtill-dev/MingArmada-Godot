# 旧账新帆 Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or executing-plans; local task ownership is disjoint and no commits are requested.

**Goal:** Make existing 1650 trade/convoy gameplay tell a consequential opening story, with repayment and clear next actions.

**Architecture:** Campaign remains the only business authority. Pure OpeningStory projects receipts and applies fixed, once-only choices; native dock facts protect gameplay actions. Godot UI emits guarded intents and reads runtime projections.

**Tech Stack:** Godot 4.7.2, GDScript, existing v2 SaveCodec, native main-menu router.

**Spec:** ../specs/2026-10-11-opening-story-gameplay-design.md

## Current Evidence and Completion Boundary

更新于本地 2026-10-12（Asia/Shanghai）。当前1650开场切片的首航/保存续玩证据闭环完成：最终fresh无filter103/103脚本、真实首航29/0、普通Continue/readback、RETURN15图及实际第二委托20粮装载已证明，最终证据核验1052/0。Root已亲看9开场+15RETURN共24图。**第二趟20粮真正出海/交差、港内避碰死锁、两UX和未来医治/战术/结账新增内容仍待完成，不宣称好玩上瘾或全主线已验。** 最终逐项验收由 [gameplay acceptance](../../migration/opening-story-gameplay-acceptance.md) 维护。

| 证据 | 当前可确认 | 边界 |
| --- | --- | --- |
| [最终fresh strict runner](../../migration/evidence/opening-story/all-tests-verified.json) | Root session59006完整结束exit0；同一次运行filter=null，discovered/selected/runs均103，103个独立脚本全部PASS、failed=0。本次文档更新独立核SHA、103 unique runs与discovered同集合、每个completion marker/exit0/passed及无SCRIPT/PARSE/ERROR诊断、timeout/processError/reasons | 103是脚本数，不是断言数；只证明最终源headless验证，不替代真实保存续玩或GPU验收 |
| [最终源实际正式地形首航](../../migration/evidence/opening-story/journey-formal-manual-fire-return.json) | Root session22273完整29断言/0失败；1524.2秒真实结算40粮，奖励400+100=500两，16份旗舰开火/13份命中敌舰收据；actualSafeReturn=true、canSave=true、saveReason为空；最终银915、债400、convoy-002仍offered | 四艘原船hull/sail100、crew无死伤、两名管事alive；实际grain-a/b与旗舰/快船均rudder=0、sails=0、navigation无、水平速度0。普通保存门禁生成非空confirmedCheckpointJson，尚不等于正常Continue/readback或第二航次已执行 |
| [历史未锚泊fullprecision旅程](../../migration/evidence/opening-story/journey-formal-manual-fire-return-unberthed-fullprecision.json) | Arrival修复前29断言/1失败；1472秒真实结算40粮，奖励400+100=500两；16份旗舰开火、13份命中敌舰收据；1682秒实际安全dock并购买情报，最终银915 | 2400秒 `canSave=false`，`saveReason=save-fleet-not-anchored:mingqi-1650-grain-b`，`confirmedCheckpointJson=""`；保持失败身份，不证明最终Arrival新源已通过真实航程 |
| [旧 rounded 旅程](../../migration/evidence/opening-story/journey-formal-manual-fire-return-rounded.json) | 旧27/0证明该次实际战斗、交粮及返港会面 | 旧序列化保留的精度不足；没有确认检查点，不能代替存档恢复证据。对应严格预检失败保留在 [RETURN报告](opening-story-work/task-return-capture-report.md) |
| [最终开场GPU运行记录](../../migration/evidence/opening-story/native/run-result.json) / [九图sidecars入口](../../migration/evidence/opening-story/native/01-old-ledger-1600.json) | Root亲见session71038完整结束exit0、captures9/assertions56/failures0，并逐张亲看全部九图；主审独立核九对PNG=imageSHA、每份9个sourceHashes匹配最终Campaign `beead54a…` / Bridge `19cea28a…`等当前源，Godot4.7.2及1600×900/1280×720 | run-result明确记录Root实际观察，非sidecar累计；九个sidecar仍无assertions/failures，仍无summary.json。范围仅开场选择、偿债及离港画面，不含first-return、第二旅程、RETURN或性能验收 |
| [RETURN首轮失败记录](../../migration/evidence/opening-story/native-return-final/capture-result.json) / [唯一PNG的sidecar](../../migration/evidence/opening-story/native-return-final/first-return-consequence-1600.json) | Root亲见进程终止292断言/1失败/1PNG；capture-result实际保存290断言/1失败，两个计数分别归因。preflight.ok=true、originalSlotsUnchanged=true、isolatedSlotsCleaned=true；Root亲看第一PNG，本次只读核PNG SHA及sidecar22项source身份 | 唯一error为 `visible actual casualty consequence matches real claim`：QA错误要求零死伤时也显示“死亡0、受伤0”；生产按真实无死伤省略数字，Root确认画面正确，无生产修复需求。整次RETURN失败，未完成15图、保存readback/完整Continue或第二实航 |
| [历史开场九张PNG及sidecars](../../migration/evidence/opening-story/native-preberthing/01-old-ledger-1600.json) | 此前session19406九图56/0和当时来源核验仍归档保留 | 这是Arrival前历史图，不能用其sourceHashes替代最终源九图身份 |

最终fresh runner UTC为 `2026-10-11T18:33:41.640Z` 至 `2026-10-11T18:42:59.814Z`，对应本地 **2026-10-12 02:33:41.640–02:42:59.814**。完整记录SHA256为 `17b927b6e8bfbc444b64b7eb85757862819a45fce27922624bfeab8613bfac20`。本次只读核验既有记录，没有重跑测试。

旧 [102/102 preberthing记录](../../migration/evidence/opening-story/all-tests-verified-preberthing.json) 保留UTC16:45:58.823–16:55:26.810的一次完整运行；[初轮103/103](../../migration/evidence/opening-story/full-suite-arrival-before-rudder-review.json) 保留P1/P2审查前阶段结果，不能冒称最终源验证。[session9221中止记录](../../migration/evidence/opening-story/full-suite-ownership-review-interrupted.md)明确不是完整103/103；它不参与最终全套通过计数。

历史29/1旅程原始字节SHA256仍为 `047bbdefc56515f148feab299e1dd2173cc92caa0a50c80d19956c7014ee821f`。其中`actualSafeReturn=true`仅证明当时dock和会面成功，最终全船安全保存失败也保持历史身份；不被旧rounded27/0或新29/0覆盖。

最新session22273（`--manual-fire --return --deadline`）记录SHA256为 `9b88b2da35fb9a965989d00618a7949d614c2af3cf0ca6dcc91bc992da03657c`。本次Python只读核该JSON、12项sourceHashes与当前实际文件字节全部一致，并解析非空`confirmedCheckpointJson`：v2、campaignId及simulationSeconds一致，**checkpoint.state精确等于final.campaign，无数值近似容差**。确认检查点JSON字符串SHA256为 `6165c126693f88312b896cb1ea2e14c2678255bf74cac6841a6b632aaabd7fc2`。settlement、safe-first-return、fleet-moored-checkpoint均为实际1524.2秒stage；这些证据已证明首航及正常保存门禁生成检查点，未宣称磁盘槽位正常Continue/readback或RETURN GPU完成。

最终开场GPU `native/run-result.json` SHA256为 `87109de2214c7965d9ed52141a4f3b61b320d29f065d9b00592fb714310c8c50`，已实读其Root观察说明、session71038、完整completionOutput、9/56/0及九个亲看文件名，身份相符。它的范围仅开场图；返港15图与正常保存续玩另由下述最终RETURN证据证明。

首轮RETURN失败保持在 `native-return-final`，不覆盖或改成通过：capture-result SHA256 `e9f86914080343cce69bee3f8f46f6646aedf2dc40da03ad54c37c529804bd9d`；唯一 [1600返港PNG](../../migration/evidence/opening-story/native-return-final/first-return-consequence-1600.png) SHA `4e095e44e3325d65c95850e1a6ee8a554e8637ce32a5d2a8c36116582bab5947`与sidecar一致。sidecar实际 `story_relation_xu-fu` 为“许福 · 老水手 / 工钱结清，愿意与你共担风险。”，claim无死亡/伤员，未声称发生不存在的损失。读取时22项sourceHashes全部匹配，含该失败的QA工具冻结 `6f3b2734…`；后续只修QA断言会使这一旧工具身份成为历史前源，不冒称此22项永久匹配当前工具。

该失败产物确认严格preflight成功和首帧返港呈现，不将它扩大为保存readback/完整正常Continue已验收。Root完整审查并逆应用QA-only零case修复，self-test26/1→26/0/check-only通过，生产12sourceHash未变；工具随后更新为`82ed6a15ad36b6bbcedd3b00f6d25dfa27c9413d6c72563597c88abe9301cd02`。旧失败22项当时源身份保留，不能称其中旧QA工具仍匹配live当前。

Root授权唯一一次[第二RETURN尝试](../../migration/evidence/opening-story/native-return-verified/capture-result.json)，实际14PNG后停止：console643/1、artifact641/1（SHA `0aa33831910b6c7bc796ff116cb7c49bfb7285a9e186bc4c01e1bb78f094a9e4`），唯一失败为`saved checkpoint preserves mingqi-1650-enemy.representation`。主审独立核14组图/sidecar SHA及当次308项sourceHash，用户slots before/after完全一致、cleanup真。普通UI save_and_menu/read_checkpoint已成功，但未完成全saved material比较及第二Continue，故不勾完整续玩或RETURN。该目录名不表示通过，不能覆盖本失败。

第二次尝试已实际通过UI承接convoy-002：库存50→30，两艘各10、总20，新deep voyages为loading；没有真实第二航次出海或交粮证据。随后只读[export诊断](../../migration/evidence/opening-story/return-export-diagnostic/diagnostic-result.json)artifact31/0与Agent终止34/0分来源保留：source checkpoint精确等immutable9b88；normal export解析state精确等actual after.campaign，enemy其余字段不变、仅合法near→route（hull0、未俘/native absent）；allFieldDiffs12、material仅该归属、decodedDiffs为空。生产/Codec不变，不计作GPU或实航通过。

Root已审窄QA补丁并观察34/1→34/0/check-only0，只允许上述合法dead-enemy归属变化；之后唯一`native-return-complete --save-readback`已实际完成。旧两失败目录保留，后续成功不能覆盖历史。

[最终证据核验](../../migration/evidence/opening-story/final-evidence-verification.json)SHA `8992c52ef759d29f479f533579deccf6d8db9d1b6ca3a57f4c1a116e1e0eb0f4`为Root实际exit0的1052/0，替代初次1020。[RETURN最终结果](../../migration/evidence/opening-story/native-return-complete/capture-result.json)artifact799/0、Rootconsole801/0、15图；[Root逐图检查](../../migration/evidence/opening-story/native-return-complete/root-visual-inspection.json)记录亲看全部15。普通UI保存、磁盘checkpoint读回和第二Continue通过，saved first settled/second active、原两船各10粮、enemyhull0、银915债400保留。[实际UI保存原字节](../../migration/evidence/opening-story/native-return-complete/normal-ui-save-v2.json)SHA `e1969b7e9c079ccc193283d33de1937d76b2f91767fb2aa2cf3945fe9a8b538d`精确等normalUiSaveSha与slotSha；12个原用户slot before/after/live存在与散列相同，cleanup真。

[精度核验说明](../../migration/evidence/opening-story/root-verification-notes.md)保留Root补强时误把默认15位截图sidecar当exact state的一次QA失败；最终使用immutable checkpoint/raw save/live GPU及CPU normal-export，无round或修写产物。它不是新GPU/游戏失败。Root逐图发现但未修的两UX：金门债务按钮须明确到厦门偿债；期限/ETA应剩余时长与明确准备状态，offered0不应让玩家自行计算。连同港内避碰死锁保留下一优先，不把15图通过说成玩家体验达标。

[正式靠港节奏审计](opening-story-work/task-port-approach-pacing-audit.md)SHA `26464b687674a6b1e14e125c85aa9be6fe99327f4d0af9775f9853279392adf7`已定位港内末段避碰恢复缺口，列为下一实施第一优先，仍未修复。41真实帧Planner/九点船体湿度全部通过，36帧当前朝向被船阻塞、±60°候选不通过可行性检查；750s真实desired静态可行但未被试，450s旋转碰船反例禁止无条件转向。静态诊断不是动态恢复证明，也不是18m/水深/性能问题；8–12分钟真实玩家目标仍未测，第二真实航次仍待验收，未来剧情仍未实施。

## Source Identity and Review Links

本轮文档更新只核实际记录、确认检查点精确等值、12项sourceHash、review/manifest与文档链接，不另审或改生产/QA。以下最终源身份已由主审独立核过；之前scoped来源保留历史身份，不再冒称全部是当前源码：

- [最终Arrival manifest](opening-story-work/arrival-berthing-final-hashes.json) / [累计scoped patch](opening-story-work/arrival-berthing-final.patch)：当前Bridge SHA `19cea28a36f55766126f066a5941f21477688a96f35e1815709629dcbabfbb9f`，Campaign SHA `beead54a168dc323eb0fe928fc436e9cf0d64d40e5d2b851fdcd477021b068c1`，新测试SHA `72940022677c33925d8dc053f98c7d5af13c58abc756b46b438412340e66536d`，累计patch SHA `279557688dc548851d1b4d94aeb82915f80b0fe9fb56bb8f3ede4854c9295259`；主审核5项当前身份全匹配。
- [Recovery manifest](opening-story-work/recovery-source-hashes.json)是此前6项冻结：Campaign `5290c193…`为已审Arrival增量的前源，现由`beead54a…`取代；其余5项由主审核仍匹配。原 [Domain报告](opening-story-work/task-domain-report.md) / [Domain patch](opening-story-work/domain-scoped.patch) 保留原始阶段证据。
- [Root manifest](opening-story-work/root-integration-source-hashes.json)：主审核Runtime、Scene、Runtime测试、开场截图工具、真实驾驶工具5项当前SHA全部匹配；[Root scoped patch](opening-story-work/root-integration-scoped.patch)保留接线/QA来源，不使用全部dirty working tree作审查包。源码身份匹配不等于新GPU/旅程执行完成。
- [Autopilot manifest](opening-story-work/autopilot-source-hashes.json)保留Encounter与定向测试冻结。此前 [Navigation manifest](opening-story-work/navigation-source-hashes.json)中的Bridge `b1802c07…`是Arrival前源，现由`19cea28a…`取代；旧Encounter项由Autopilot冻结替代。不把这些前源SHA写成当前。
- [UI Q2报告](opening-story-work/task-ui-q2-report.md) / [累计UI patch](../../../build/opening-story-ui/scoped-ui.patch)：当前UI SHA `baa673b5a8bb75994e3234e832341a51c5c34b203a7ef8cfe4bca52e5d5c88e9`，真实UI→Runtime测试SHA `4a66da91648d59346f33cfc1f155a4dff233ee7b55018a31f77922c5fe114523`，与最终Q2报告相符。Q1/Q2 StringName命令键问题已关闭。
- [设计审查](../../migration/opening-story-design-review.md) 与 [代码审查](../../migration/opening-story-code-review.md) 保留原独立审查、已关闭发现及阶段限制。后续导航、Autopilot、Recovery分别完成独立Spec/Standards只读复核；最终 [Arrival与QA独立审查](opening-story-work/task-arrival-berthing-code-review.md)已关闭P1/P2及首arrival新舵帆保护事项，review SHA `3c2e1df7407723510c288020d206877e4e7bb6cd9e638d5de4eb344fe41b557a`本次实核相符。当前完整验收由主审汇入 [gameplay acceptance](../../migration/opening-story-gameplay-acceptance.md)。

定向修复的作者记录可追溯：[中间航点交接](opening-story-work/task-navigation-report.md)、[低速自动转向恢复](opening-story-work/task-autopilot-report.md)、[原租船临床服务和单船续航](opening-story-work/task-recovery-report.md)、[安全到港泊船最终报告](opening-story-work/task-arrival-berthing-report.md)。Arrival TDD包含真实native tick残舵RED、新舵/帆保护RED及ownership畸形行RED980/6（六次SCRIPT ERROR）；最终GREEN980/0零SCRIPT ERROR，四项scoped记录通过。独立审查已核这些日志和冻结来源，没有重跑同码；fixture/headless结果也不替代真实旅程。

## Global Constraints

- Writable root: C:/Users/dains/Documents/Git/ming-armada. Old Three.js and reference directories are read-only.
- Every shell command starts rtk. CodeGraph unavailable in this session; use focused RTK fallback.
- No sea/island/shore/particle development, no performance work, no commit/push/reset or release/package export. Normal runtime save export remains required by checkpoint acceptance.
- Preserve authentic receipts, revision checking, native ownership and two isolated save modes.
- Original dialogue; clearly describe borrowed versus owned ships.
- Review and real screenshots required before claiming current gameplay complete.

## Review Focus

- Repeated clicks/replayed old command IDs must not double-pay or farm support/credit.
- Full/partial/failed delivery must produce honest dialogue and available continuation.
- Old v2 saves remain accepted; fabricated debt payments/choice effects are rejected.
- Stale revisions, insufficient money, excessive draft and hostile port context reject atomically.
- UI remount/generation changes reject stale callbacks; small screens expose all choices and next actions.

## Task 1: Domain choices and repayment

**Brief:** opening-story-work/task-domain-brief.md

- [x] Add meaningful failing tests for each scene, actual routes, replay, debt and forged/legacy saves.
- [x] Implement OpeningStory and Campaign/SaveCodec integration under brief ownership.
- [x] Run scoped domain/save regressions; preserve full commands/outputs in [task-domain-report.md](opening-story-work/task-domain-report.md).
- [x] Independently review scoped source, strict command/receipt/save contracts and detached projection; amend material findings.
- [x] Complete the bounded recovery follow-up: actual original lease enables safe service only; below-minimum ships remain locked/disabled; a genuinely sunk original permits one surviving original to carry20. Healthy originals retain10+10 and oldv2 fixture behavior. [Recovery report](opening-story-work/task-recovery-report.md) records limits and tests.

Domain完成不意味着全沉船替换、招募死者替补或无限后续委托已实现。旧沉船、死伤和首程失去的奖金仍保留；双沉船及零交付不能被包装成成功续航。

## Task 2: Story journal and next objective

**Brief:** opening-story-work/task-ui-brief.md

- [x] Add failing UI intent/remount/accessibility tests against the agreed projection.
- [x] Implement story journal and real repayment form in Mingqi interface.
- [x] Verify scoped UI regressions; preserve [task-ui-report.md](opening-story-work/task-ui-report.md) and [Q2 real service-button report](opening-story-work/task-ui-q2-report.md).
- [x] Independently review readonly snapshot/intent boundaries and stale callbacks; close Q1/Q2 with real UI→Runtime39/0, including refit/treat-wounded.
- [x] Capture and inspect the historical nine opening native screenshots at both target sizes after runtime wiring. 56/0来自此前session19406，仅记录历史图；RETURN不包含在这项完成标记内。
- [x] Verify final-source session71038九张开场GPU图：Root实际完整终止9/56/0并逐张亲看，主审另核PNG及全部source身份；run-result记录观察，旧图独立归档。

## Task 3: Runtime integration and actual journey acceptance

- [x] Add story projection/eligibility to MingqiRuntime snapshots and native docking protection.
- [x] Verify scoped actual runtime choice, repayment, replay and opening save/load flow; keep this distinct from the post-voyage save/Continue acceptance below.
- [x] Preserve the actual native pose/cargo/permissions at waypoint handoff; reuse opt-in existing assist budgets for low-speed navigation with wet/blocked/service gates. Complete independent reviews and scoped regressions for both repairs.
- [x] Complete final Arrival code/TDD/independent review: safe original leased carrier berth, genuine first-arrival automatic rudder ownership, first-arrival new controls/navigation/orders preservation, default-empty compatibility and P2 malformed-row rejection. Keep originalP1/P2 failures and final980/0 logs.
- [x] Exercise main-menu entry and opening UI choices with final-source native GPU screenshots at both target sizes, retaining historical九图归档。
- [x] Root personally inspects all nine final-source opening screenshots and closes layout/action findings；主审核当前PNG/source身份，session71038记录完整56/0，不把headless文本检查当成看图。
- [x] Record the final one fresh unfiltered strict run of103/103 scripts after all P1/P2 corrections, independently review frozen packages and document limitations.
- [x] Preserve historical first-convoy formal-terrain combat,40粮结算及安全返港会面的真实收据；旧29/1归档仍保持保存失败身份，不能认证最终Arrival新源。
- [x] Verify final-source actual first voyage session22273：formal29/0、40粮/500奖励、16fire/13hit、安全靠泊；新记录SHA与12项sourceHash已核，历史失败不覆盖。
- [x] Create a real post-voyage confirmed checkpoint JSON through the ordinary full-fleet save gate；checkpoint.state与final.campaign精确一致，原收据/资金/船员/路线保留。
- [x] Complete strict normal Continue/readback from the real checkpoint：实际UI保存与磁盘checkpoint/第二Continue通过，不用sidecar生成存档，raw bytes/slot SHA完全一致。
- [x] Complete RETURN native capture and Root personal inspection of all15 images：native-return-complete artifact799/0、console801/0；两次失败完整保留。
- [x] Close bounded first-voyage/save/Continue/RETURN evidence with final1052/0；不扩成第二实际航次、已修港口节奏或全历史游戏通过。

## Task 4: Bounded Remaining Closure

只处理上述已有流程的有限闭环，不新增历史章节、任务系统或美术/性能范围，也不以改健康、货物、姿态、记录或降低安全门槛制造结果。

- [x] Verify genuine safe anchoring of the leased fleet in the final-source actual first voyage；session22273实际四船停妥、canSave=true、成功生成检查点，历史粮船乙未锚泊失败仍归档保留。
- [x] Obtain real confirmedCheckpointJson through the normal save gate and verify exact final-state equality；此生成阶段已证，不先勾续玩。
- [x] Verify complete normal Continue/readback and RETURN：最终15图及原保存字节见上述证明；[RETURN tool report](opening-story-work/task-return-capture-report.md)和两旧失败目录保留历史，不改生产迎合错误QA。原用户slot安全及隔离清理已核。
- [x] Verify genuine UI loading of convoy-002：库存50→30、原租两船各10粮，总20；保存/Continue后active委托和实际cargo保留。
- [ ] Execute and verify the actual second twenty-grain voyage/claim, then implement future medical/tactical/aftermath choices；优先解决已定位的港内避碰死锁与两UX。
- [x] Update final bounded acceptance links after actual results are verified; retain archived29/1、oldrounded27/0、旧102、初轮103、中止9221、两次RETURN失败及所有早期RED，不用新成功覆盖历史身份。

第二补给委托已有真实UI20粮装载和正常保存/Continue证据，最终RETURN15图通过；**第二趟20粮native实际出航/交差仍未验收**。未来医疗取舍、战术、aftermath新增剧情尚未实施，港内避碰死锁与两UX仍待修。本轮未实现或验收1650–1683全历史玩法，也没有真实玩家节奏/上瘾或性能结论。
