# 旧账新帆：剧情与玩法整合验收

截至2026-10-12，当前开场切片的证据闭环已完成：最终冻结生产源一次fresh无filter **103/103脚本通过**，正式首航 **29/0**，正常Continue/保存读回和真实第二委托20粮装载已证明；开场9图与RETURN15图共24张均由Root亲看。最终独立证据校验 **1052/0**。**第二趟20粮实际出航/交差、已定位的港内避碰死锁、两项UX问题和新增剧情仍待完成**；不宣称已验证好玩、上瘾、性能或1650—1683全主线。历史失败保留，没有回填船位、伤亡、货物或存档字段。

当前分工遵循用户指令：先开发有后果的剧情与玩法，海岛、岸线、海面与粒子等待外部REA对接。本轮文档收尾未修改生产、QA工具、图形或性能设置。CodeGraph本轮无索引，独立审查采用RTK定向读取。

## 已落地的有限玩法范围

- 三段原创开局对话、七个可选决策。工钱/分红影响既有接舷初始士气；领航为两艘真实粮船代规划浅水航路，免费逐船选路保留。首次交差使用实际粮、损失、死伤，留守账房接待，阵亡管事不继续发言。
- 在厦门安全锚泊时可真实偿债，同时扣银与本金；全部清偿的信用奖励只获得一次。故事历史来自真实收据，重复点击、过期命令、超额支付与伪造记录被拒绝，旧v2继续兼容。
- 原生航海日志、当前目标和既有护粮/贸易/修理/船只页面相连。返港会面可跳过；海上claim只指向前往金门安全靠港，不宣称已见账房。真正会面受实时安全/锚定门禁保护。
- 修复真实UI→Runtime的StringName新键问题，涉及剧情、委托、战术、偿债、帆装和治伤；没有放宽领域纯数据合同。39项真实UI-runtime检查包括150两帆改与3伤员12两治疗的进行中作业。
- 中间航点在原18m到达范围交接下一点，最后港口仍按真实25m/低速卸货。低速导航辅助复用既有船型/船员/损伤操舵预算、湿路和权限门禁；默认关闭路径保持旧oracle。
- 部分损失后，一艘真正沉没的原粮船可由合格幸存原粮船独运第二委托20粮；正常两船仍各10粮。低员真租船可安全治疗，服务权限同时locked/disabled，不能借此航行。沉船/死亡/首航罚损保留；两艘均沉没的新替租、死亡补员和第三份可重复委托尚未实现。
- 原已付租粮船真正卸货后，在当前实际港位≤55m/水平速度≤.75且无威胁、攻击、工作、接舷或新控制意图时，经原native交易自动锚泊；旗舰仍由玩家正常dock。只在旧自动航程的真实到港交接中中和残舵，保留新显式舵帆、目的地和active order。存档仍要求全船安全，不新增船位补丁或保存捷径。

## 最终代码身份、TDD与独立审查关闭

当前到港修复[身份清单](../superpowers/plans/opening-story-work/arrival-berthing-final-hashes.json)与实际文件匹配：Campaign SHA `beead54a168dc323eb0fe928fc436e9cf0d64d40e5d2b851fdcd477021b068c1`；Bridge SHA `19cea28a36f55766126f066a5941f21477688a96f35e1815709629dcbabfbb9f`；测试SHA `72940022677c33925d8dc053f98c7d5af13c58abc756b46b438412340e66536d`；累计scoped patch SHA `279557688dc548851d1b4d94aeb82915f80b0fe9fb56bb8f3ede4854c9295259`。

[到港/QA独立审查](../superpowers/plans/opening-story-work/task-arrival-berthing-code-review.md)已关闭P1真实autopilot残舵、首到港显式帆控制覆盖和P2新ownership路径的snapshot结构校验回归。真实native tick RED747/4、新帆RED863/2、P2 RED980/6与六SCRIPT ERROR全部保留；作者当前GREEN980/0、零脚本错误及四项scoped通过已读证据，不由文档工作重复运行。两条临时arrival-control数组默认空且不持久化，P2新增检查只作用于非空上下文；未新增Schema/命令、复活船员或回填船位。

Domain/Runtime/UI相关细节及RED/GREEN见[原开局代码审查](opening-story-code-review.md)、[导航](../superpowers/plans/opening-story-work/task-navigation-report.md)、[低速AI独立审查](../superpowers/plans/opening-story-work/task-autopilot-code-review.md)、[恢复方案审查](../superpowers/plans/opening-story-work/task-recovery-code-review.md)。Root五文件身份清单仍全匹配；Recovery中的Campaign `5290c193…`与旧Bridge基线`b1802c07…`仅是各自scoped审查时的前源，当前已由独立验证的arrival增量更新为上述beead/19cea，不把旧包或全dirty diff称为当前源。

## 一次fresh严格headless：最终103/103脚本通过

[all-tests-verified.json](evidence/opening-story/all-tests-verified.json)是Root最终session59006的完整字节副本，运行exit0；UTC `2026-10-11 18:33:41.640–18:42:59.814`，北京时间为 `2026-10-12 02:33:41.640–02:42:59.814`。文件SHA256为 `17b927b6e8bfbc444b64b7eb85757862819a45fce27922624bfeab8613bfac20`。

独立核查确认：filter=null；discoveredTests与runs均为103个不同脚本、集合相同；每项exit0、completionMarker存在、passed=true，无timeout/processError/reasons或SCRIPT/PARSE/ERROR诊断。summary为selected103/passed103/failed0/passedAll=true；runner自检16/0。**103是测试脚本数，不是断言数。** 新arrival测试在这轮运行中通过。本次文档工作仅核落盘记录，未重复长跑；headless通过不等于GPU、真实可续玩或整部主线通过。

旧[102脚本完整记录](evidence/opening-story/all-tests-verified-preberthing.json)SHA `915f2be716a7deb733c04bbd5f2b004233cced014cdfc165c175afe6314ffb3f`、[初次103但未修残舵的完整记录](evidence/opening-story/full-suite-arrival-before-rudder-review.json)和[session9221主动中止记录](evidence/opening-story/full-suite-ownership-review-interrupted.md)均保留。前两项不能替代最终源覆盖，中止的一轮不计103/103。

## 最终源原生开局UI：九张真实PNG，56项检查/零失败

[native evidence](evidence/opening-story/native/)当前01–09九张原生PNG与对应sidecar覆盖1600×900、1280×720、Godot4.7.2/Intel Arc GPU。Root session71038已exit0，完成输出为`OPENING_STORY_GPU_CAPTURE_COMPLETE captures=9 assertions=56 failures=0`；Root逐张亲看全部九图，工钱、路线、欠款、滚动和日志呈现正常。独立核查九PNG散列全部等于各自imageSha256，每图九项sourceHashes共81项均匹配当前实际文件，包括新Campaign beead/Bridge19cea。

[run-result.json](evidence/opening-story/native/run-result.json)SHA `87109de2214c7965d9ed52141a4f3b61b320d29f065d9b00592fb714310c8c50`记录Root观察的session、exit、真实completion输出与逐图检查列表；本审独立读取这份观察单据和图/源散列，没有重复启动GPU。**不存在native/summary.json，九个图片sidecar自身没有assertions/failures字段**，56/0不伪称从sidecar推导。旧session19406的九图已归档到[native-preberthing](evidence/opening-story/native-preberthing/)，不与当前源混合。

实际鼠标选择使银650→570→475→375、本金400→300；委托与真实粮船航路随选择变化。Root亲看工钱、领航、偿债、离港等图。本次独立另看当前[海上日志](evidence/opening-story/native/08-at-sea-journal.png)和[航行画面](evidence/opening-story/native/09-sailing-1600.png)：日志未被小地图覆盖，收起后地图恢复。之前覆盖源自截图harness冻结了正常presentation，生产本已有每帧规则；QA调用同一 `_present(0)`恢复该规则，没有改生产UI来修假问题。

当前九图只证明开局选择、偿债和离港；整趟护航由29/0旅程、返港续玩由下节独立15图与实际保存读回证据证明。

## 最终RETURN与正常Continue：15图、真实保存读回通过

[最终证据校验](evidence/opening-story/final-evidence-verification.json)SHA `8992c52ef759d29f479f533579deccf6d8db9d1b6ca3a57f4c1a116e1e0eb0f4`是Root实际运行exit0的最终1052检查/0失败记录，替代初次1020检查单据。它核验首航29/0与原checkpoint、当前源身份、完整103脚本、开场9图/RETURN15图、实际20粮装载和12个原用户槽位前后及live磁盘存在性/散列。

[native-return-complete结果](evidence/opening-story/native-return-complete/capture-result.json)SHA `f2244a1742f25fed3c1a316263159f010c94cfed7c479086582965401bfef1ee`记录799项/0失败、15PNG；Root console最终801项/0失败按不同计数时点另记。Root已亲看全部15图，名单与剩余问题见[逐图检查](evidence/opening-story/native-return-complete/root-visual-inspection.json)（SHA `cadd38e5555fa8509315052583f993981c8e0c5a26e778ca8b4c561240b1dccc`）。本审只读核15组图/源散列、保存原字节与用户槽位，没有重跑GPU或测试。

普通UI save_and_menu、磁盘read_checkpoint和第二次Continue均成功；saveReadback.ok/checkpointStateVerified/diskRead为true。[实际正常UI保存原字节](evidence/opening-story/native-return-complete/normal-ui-save-v2.json)SHA `e1969b7e9c079ccc193283d33de1937d76b2f91767fb2aa2cf3945fe9a8b538d`精确等normalUiSaveSha256与slotSha256，不从截图sidecar生成或修写存档。保存/Continue后保留首委托settled、第二委托active、原粮船各10粮、enemy hull0、银915与债400。12个原槽位映射前后相同，本审当时核当前磁盘也一致；隔离槽位清理成功。

精度边界见[Root核验说明](evidence/opening-story/root-verification-notes.md)：补强核验时误把默认15位浮点格式的PNG sidecar用作exact state产生一次QA失败，随后改用immutable checkpoint、实际raw save、live GPU比较及CPU normal-export。没有round、修补或把sidecar encode为存档；这不是新游戏/GPU失败。最终1052/0和原GPU产物不变。

Root逐图仍发现两项未修UX：金门债务按钮泛提示“请靠泊”，实际偿债必须到厦门；期限/ETA用绝对模拟秒、offered状态含0，应改为剩余时长及明确准备状态。它们和港内末段避碰死锁均列下一迭代待办，不因最终QA通过而隐藏。

## RETURN首次尝试（历史）：保留失败，仅修QA断言

[native-return-final失败记录](evidence/opening-story/native-return-final/capture-result.json)SHA `e9f86914080343cce69bee3f8f46f6646aedf2dc40da03ad54c37c529804bd9d`记录290项检查/1失败、仅1PNG；Root亲见的进程终止输出为292项/1失败，两项计数按不同来源并列，不能把JSON的290冒称292。唯一失败是`visible actual casualty consequence matches real claim`：己方首航零死伤，该条可见后果文案未显示伤亡数字，QA却强求可见“死亡0/受伤0”。Root确认这不要求生产改对白或制造伤亡。

已独立核[唯一sidecar](evidence/opening-story/native-return-final/first-return-consequence-1600.json)与[真实PNG](evidence/opening-story/native-return-final/first-return-consequence-1600.png)散列一致；当次22项capture sourceHashes全部匹配冻结源，包含修正前QA工具版本，后续QA改动不能抹掉该历史身份。Root已亲看PNG。记录中的preflight.ok=true、originalSlotsUnchanged=true、isolatedSlotsCleaned=true；它支持该次严格预检及用户槽位保护，但该次完整RETURN失败，当轮未勾普通Continue/readback总验收。

该次失败后仅修QA零伤亡断言；Root完整审查、独立逆应用及self-test26/1→26/0/check-only通过，生产12项源码身份未变。QA工具更新为`82ed6a15ad36b6bbcedd3b00f6d25dfa27c9413d6c72563597c88abe9301cd02`，因此旧失败22项manifest中的旧QA工具身份是历史，不能再宣称全部匹配live当前源。Root随后授权唯一一次`native-return-verified` GPU，结果见下节；不覆盖首次失败。

## RETURN第二次尝试（历史）：14图后失败，当轮续玩未通过

[native-return-verified记录](evidence/opening-story/native-return-verified/capture-result.json)SHA `0aa33831910b6c7bc796ff116cb7c49bfb7285a9e186bc4c01e1bb78f094a9e4`保存641项检查/1失败，Root亲见console643项/1失败；完成14PNG后停止，不是预期完整15图通过。唯一错误为`saved checkpoint preserves mingqi-1650-enemy.representation`。目录名包含verified不构成成功证据，历史内容保留，不覆盖或重新命名为通过。

独立核14组PNG/sidecar散列全匹配，14×22项当次sourceHashes共308项均匹配该次QA工具及冻结生产源。原用户槽位before/after映射精确相同、originalSlotsUnchanged=true，isolatedSlotsCleaned=true。Root实测普通UI的save_and_menu与read_checkpoint成功；但在完整saved material比较及第二次Continue前被上述断言停止，**该轮严格Continue/readback与RETURN总验收未通过**；后续最终成功独立列于上节。

本次也记录了真实第二委托接单装载：金门库存50→30，两艘原租粮船各10、总20，沿kinmen-supply-deep新voyage仍为loading；该结果是实际UI/领域交易，不是第二航次已出航或已交20粮。原实际首航及checkpoint29/0证据仍有效。

只读[export诊断](evidence/opening-story/return-export-diagnostic/diagnostic-result.json)SHA `a8df17293fe62bbd0b999d95c0926dd35ea1a5f1739a5726efabb2712f7ef592`记录31/0，Agent终止34/0按不同来源区分。本审核其[source checkpoint](evidence/opening-story/return-export-diagnostic/source-confirmed-checkpoint-v2.json)的state精确等于不可变9b88首航checkpoint；[普通export](evidence/opening-story/return-export-diagnostic/normal-export-v2.json)SHA `80c8769101f688a7b723164cc5ac991dd8f09212b3bc88cbaa73f64754bd5f2f`解析state精确等于实际after.campaign。诊断before→after的enemy其余字段逐项相同，仅representation由near→route；它hull0、未俘获且native中已不存在。allFieldDiffs12主要为revision/控制投影与观察序列及归属，materialDiffs仅该归属、decodedDiffs为空。

这定位了普通`Runtime.export_save→bridge.sync→reconcile_near`的正常归属更新；诊断是脱离用户槽位的CPU调用，不是新的GPU Continue或实际航程。生产/Codec未改。Root已审查窄QA补丁并观察34/1→34/0/check-only通过，只允许上述实际沉没、未俘获、native absent的enemy合法归属变化。之后唯一`native-return-complete --save-readback`实际完成的保存读回/第二Continue结果见上节；两个失败目录继续保留，不被新成功覆盖。

## 当前正式地形首航：29/0，交差、返港与正常checkpoint成立

[当前真实首航记录](evidence/opening-story/journey-formal-manual-fire-return.json)是Root session22273完成后的正式地形、deep旗舰航路运行，采用实际W/S/A/D和与UI相同的炮击提示。文件SHA `9b88b2da35fb9a965989d00618a7949d614c2af3cf0ca6dcc91bc992da03657c`已独立核对；12项sourceHashes逐一匹配当前实际文件，没有沿用修复前的历史身份。

| 事实 | 当前真实记录 |
| --- | --- |
| 整趟结果 |29项检查/0失败，最终accepted模拟时间1524.2秒；不是GPU或性能结果 |
| 实际炮战 |独立按chronicle.kind/causeIds重算，旗舰16份near-fire、13份near-hit/cargo-loss命中enemy，与combatProof一致；不把queued当开火 |
| 交粮与报酬 |原40粮全部实际交付、lost0；claim收据为基础400+奖金100=500两，无pending货物 |
| 金门会面 |正常dock、first-return选择buy-intelligence的真实收据，actualSafeReturn=true；采集情报时刻1524.2、费用60两 |
| 船与人物 |四艘出航船hull/sail均100，able crew分别60/20/20/18、wounded/dead均0；两位原steward alive=true；不是复活或补员 |
| 全船安全 |原租粮船按正常到港交易泊住；旗舰/快船正常dock。最终四船实际速度0、rudder/sails中性、无navigation，全队通过正常安全存档门禁 |
| 资金与后续 |captain.silver915、debt.principal400；convoy-001 settled，convoy-002 offered |
| 正常安全checkpoint |runtime.canSave=true、saveReason为空，confirmedCheckpointJson非空；解析出的state与final.campaign精确相等，无epsilon或字段回填 |

settlement、safe-first-return与fleet-moored-checkpoint三个实际阶段均记录在1524.2秒。确认的v2 checkpoint字符串长42445字符，来自驾驶工具的普通runtime.export_save路径；本次只读解析与比较，没有重新encode、改写record或注入完成。此前grain-b漂移导致安全存档失败的问题，现在有同正式地形的实际完整首航证据支持修复，超出单测fixture或静态代码关闭的范围。

本节首航记录证明真实首航和正常checkpoint创建；后续普通Continue/保存读回与15图RETURN另由上节最终证据证明。实际第二委托20粮装载已证明，仍没有第二次20粮出航/交差证据。

## 节奏限制：到港末段仍有无决策等待风险

当前29/0证明功能闭环，不能证明航程已好玩或时长合理。独立核实际记录：近场`victory/hostiles-neutralized`在277.85模拟秒；粮船乙20粮在327.4166667秒卸货，粮船甲20粮直到1524.0秒卸货，两船交付相隔约1196.6模拟秒。

粮船甲540秒位于约(272.3397,80.8152)，水平速度0.02368m/s；720、900、1080、1260、1440秒仍缓慢挪动，速度约0.02146→0.01621m/s，1440秒才到约(289.6902,81.6845)。[正式靠港节奏审计](../superpowers/plans/opening-story-work/task-port-approach-pacing-audit.md)SHA `26464b687674a6b1e14e125c85aa9be6fe99327f4d0af9775f9853279392adf7`现已定位**港内自动避碰缺少合适恢复决策，形成末段停滞/死锁**，列为待修第一优先；不是水深/Planner起点不安全、18m中间航点或性能问题。

该只读静态审计的41帧（300–1500s）Planner与实际九点船体湿度全部通过；420–1470s的36帧当前朝向均被船挡住，desired±60°两候选均失败，原代码于是收帆且禁止blocked低速转向恢复。750s的真实desired原代码未尝试，却通过现有可行性与静态SAT转动/直线路径采样；450s反例则在开始转约1°即碰背景商船，不能无条件直转或移除避碰。背景商船与已到港粮船造成的局部交通阻塞，需要保留湿度、风、船体尺寸及动态碰撞安全来恢复。

审计没有推进physics时间，也未逐tick复原全部route cache、tack、yaw或接触事件；静态可行不等于真实动态安全，不能把它计作航程重跑、已实施修复或第二航次完成。当前生产未改，不能以扩大25m卸货范围、补写交付或改船位来掩盖等待。

本QA旅程记录accepted模拟时间，没有真实玩家的输入/等待wallclock数据；不能从1524.2模拟秒称“25分钟已合理”，也未验证下一航次设计的8–12分钟实际游玩目标。下一迭代优先消除无决策港口等待，再验证第二趟20粮实际航行与医疗、战术、结账取舍；不得补写交付、改船位或放宽存档安全守卫。当前不修改生产，先保留该玩法缺口。

## 历史正式地形旅程：29/1，战斗/交差/会面成立，checkpoint失败

[unberthed全精度历史记录](evidence/opening-story/journey-formal-manual-fire-return-unberthed-fullprecision.json)采用同正式地形、原deep航路、真实W/S/A/D与正式命令；12个sourceHashes对应当时修复前冻结源，不能声称与当前到港修复源相同。独立核查其时间与收据：

| 事实 | 历史记录 |
| --- | --- |
| 实际旗舰炮击 | chronicle中16次near-fire，13次near-hit/cargo-loss命中敌舰；未把queued=true当射击成功 |
| 实际交粮/报酬 |1472模拟秒结算40粮、货损0；基础400+奖金100=500两 |
| 实际安全返港 |1682模拟秒真dock与first-return情报选择；actualSafeReturn=true |
| 银两 |915两；来自真实工钱、租费、领航、报酬与60两情报费用 |
| 最后观察时间 |2400 accepted模拟秒，有界延长QA观察，未改任务期限 |
| 安全保存 |canSave=false；save-fleet-not-anchored:mingqi-1650-grain-b |
| 已确认checkpoint |confirmedCheckpointJson为空 |
| 总结果 |29项检查/1失败；不能写成完整旅程全通过或可继续存档 |

历史证据SHA256：`047bbdefc56515f148feab299e1dd2173cc92caa0a50c80d19956c7014ee821f`。全精度JSON写出只修证据精度，不回填state。未锚船必须通过真实航行、低速/安全到港与原交易泊船，再经正常dock、runtime.canSave/export_save；缺checkpoint明确失败。当前新源29/0与正常checkpoint证据独立列于上节，不用新成功覆盖该29/1失败或rounded27/0精度问题。

## 历史记录与下一步

历史失败继续保留：[未修航点首航](evidence/opening-story/journey-flat.json)13/4、395.07秒旗舰沉没/交0；此前[部分成功](evidence/opening-story/journey-flat-outer-tactical.json)交20损20不能证明第二委托可玩；[正式27/0 rounded记录](evidence/opening-story/journey-formal-manual-fire-return-rounded.json)只支持真实战斗、交粮和会面，当时canSave仍false，并且默认JSON精度使canonical double失真。它不是可续玩存档，不能将舍入后的snapshot补写字段来伪造恢复。

已证明当前源的真实首航、全船安全泊住、正常checkpoint/Continue/保存读回与第二委托实际20粮装载。仍待第二航次真正出海和交差、优先修复港内避碰死锁与两项UX，并实现新的医治、战术、结账剧情取舍。恢复方案的124/0和当前RETURN装载证据不能代替第二实际旅程。当前实现仍是1650开局与有限委托链，不是完整1650—1683主线；新增任务、长期人物承诺、章节和结局继续留在整体目标。
