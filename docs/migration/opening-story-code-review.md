# 旧账新帆：冻结范围代码审查

2026-10-11。Spec 与 Standards/quality 两轴；Standards 由独立子审查员复核，本文汇总。只读生产和 scoped patch，不重复运行作者相同代码测试，不启动 GPU、不操作 Git。CodeGraph 已无索引，使用 RTK 定向读取。运行次数来自作者/主 Agent；本审另核源码、散列、截图 sidecar，并亲自查看两张已有 PNG。

## 范围与身份

- [设计](../superpowers/specs/2026-10-11-opening-story-gameplay-design.md)、[Domain brief](../superpowers/plans/opening-story-work/task-domain-brief.md)、[UI brief](../superpowers/plans/opening-story-work/task-ui-brief.md)。
- [Domain scoped patch](../superpowers/plans/opening-story-work/domain-scoped.patch)，SHA256 `5b7cff5e0ff0e15a92bd952a351d93d7510f5b25cbd4254b05c648b91d23d8cc`；[五文件身份](../superpowers/plans/opening-story-work/domain-source-hashes.json)与 Campaign、SaveCodec、OpeningStory 及两份测试相符。以编辑前快照为准，不审整个 dirty branch。
- [UI 最终 scoped patch](../../build/opening-story-ui/scoped-ui.patch)，SHA256 `876f39f0c52da10eb73ad985b1cfa37db6d482f26cfc5b0d15ca39f9a035a5f2`、735行；UI 源码 SHA256 `baa673b5a8bb75994e3234e832341a51c5c34b203a7ef8cfe4bca52e5d5c88e9`。与[UI 报告](../superpowers/plans/opening-story-work/task-ui-report.md)、[Q2增量报告](../superpowers/plans/opening-story-work/task-ui-q2-report.md)全部相符。旧初次包及 Q1阶段 `c7cadac…` / `69b376…` 已被替代。
- [Root 最终 integration scoped patch](../superpowers/plans/opening-story-work/root-integration-scoped.patch)，原始字节 SHA256 `a14a8c158e9258b97c0c00d9d9c9e2f1957e5d41ed6a9bf476be70e1f990ff32`、388行；只含 Runtime 接线、Scene 默认日志、Runtime 测试、截图工具及真实驾驶工具。
- [Root 五文件身份](../superpowers/plans/opening-story-work/root-integration-source-hashes.json)最终五项全部匹配。途中发现 driver 与初次清单失配，已按新 outer 路线/实际 fast protect order/sourceHashes 接线重冻；driver 现为 `184ed165720e170ce85cfc952f8d9ef7ded8566706cdf0b7dd852b43154934fc`，截图工具 `310f8f7…`。旧失败395秒证据仍是旧 driver 的真实输出，不冒称新 driver 已通过。
- [导航 scoped patch](../superpowers/plans/opening-story-work/navigation-scoped.patch)，SHA256 `104cf22233bea11d6560a428b5f54b7f8c916ad2564fea9e63fab8005915307c`；[四文件身份](../superpowers/plans/opening-story-work/navigation-source-hashes.json)全部匹配，原 Domain 五文件冻结未变化。

## Spec

**Domain：未证实新增规格阻断。**

- [OpeningStory](../../game/domain/mingqi/opening_story.gd)纯投影三个场景、七个选择、objective/relations/history。没有新根级故事状态；原创人物为对话记录，没有物理角色生成或租用旗舰所有权变更。
- [Campaign](../../game/domain/mingqi/campaign.gd)经 strict intent、既有 BUSINESS/NEEDS_NATIVE、candidate 与原生同步后最终 commit。故事/还债检查实际 currentPortId，再 `_docked` 真锚定；同 commandId 重放原收据，canonical scene receipt 禁止换 ID 再获益。
- pilot 先对两船执行真实 `route_for_vessel` 吃水校验；任何一船失败都在改路/扣款前拒绝。两船实际 routeId/locate_route 变化，原 pose/escort/权限不改。Bridge 导航确实消费路线；完整旅程另验。
- first-return 由留守林账房说话，阵亡的林管事只在关系条说明事实。对白按真实 claim 报告 delivered/lost/dead/wounded，部分/失败不冒称成功。情报显示实际粮库存、采集时刻与65%可信度。
- crewSupport 确实进入原接舷初始进攻士气，未宣称炮速/火力增益。商行信用/军方信任没有虚构折价权限。免费手动选路保留，45两明确为两船代规划服务。

**SaveCodec：新收据与本金闭环符合当前规格。**

- [SaveCodec._story_receipt](../../game/domain/persistence/save_codec.gd)核 canonical scene receipt、exact cost/effects/port/route/causeIds；pilot 在真实 accept 后，old-ledger/pilot 在首次实际离港/抵达/损失/claim 前，first-return 在真正 claim 后，均核 chronicle 顺序与 revision。
- `_opening_history`从400本金起，按 chronicle 核正整数金额、before/after 连续性、严格增大的还债 revision、累计≤400及最终剩余本金；全清仅一次6信用，清偿后不能再付款。
- 情报严格对应一份 persisted entry，sourceId 指向真正 buy-intelligence，event simTime/库存副本/可信度一致。没有伪称可重建旧交易未保留的历史库存。
- 旧v2无新 receipt 仍为400本金；原 chapter/creditor/dueAt 与v1/v2槽位隔离不变。`_relations`实际调用新 `_opening_history`。

**Root Runtime / Scene：未证实新增接线阻断。**

- [Runtime](../../game/runtime/mingqi_runtime.gd)派生 detached `packet.story`。故事/偿债 eligibility 同时要求 ready、实际 currentPortId、原安全港 facts 与 `encounter.isAnchored(flagshipId)`，与 Campaign 强 `_docked` 的命令再次验证一致。低速靠港但有舵意图不会被当成锚定。
- player 暂停可计划，loading/error/result 不可提交；没有新墙钟或 UI 自行扣银。复用同一 Runtime→Bridge→Campaign→native candidate 通道。
- [Scene](../../game/scenes/mingqi/mingqi_scene.gd)只在无 initial_save 的新游戏打开日志；续档仍开原菜单，打开日志不自动接单、完成任务或生成奖励。
- Runtime 测试含真实 rudder 0.3 导致 unanchored 的拒绝、扣银/本金、同 ID 重试、保存/载入、离港后拒绝、detached packet。截图工具用真实 Control 鼠标事件与实际 Domain 收据，隔离 `user://tests/opening-story-capture-PID` 槽位，无结果/货物注入。

**导航：最小中间点交接符合当前要求；不等于整个旅程通过。** [NearFieldBridge](../../game/runtime/near_field_bridge.gd)仍调用未改的 exact `locate_route`，只在实际同步船位距中间目标≤18m时将 native target index 增一；final index不跳过，fresh_startup 的 null导航优先。只改变 native navigation目标，不改业务 leg/progress、pose、货物、escort、权限、到港收据。

[NavigationContract](../../modules/contracts/navigation_contract.gd)命名原有18m常量，[Encounter](../../modules/naval_simulation/encounter.gd)仅以它替换原计划导航刹船 literal；原非规划30m、湿路线 Planner、避碰、逆风、控制与炮战不变。新目标仍从实际船位调用原 wet planner，未把“跳过中间点”当成穿越陆地许可。到港仍使用实际25m范围与≤0.75速度；14m/2m/s、26m/低速不交付，14m/低速正常交付的定向 fixture 已明确标为单测初始条件。

**UI：故事/偿债/整备两条服务的命令合同缺陷已修复。** 日志只消费投影，objective 按钮只开页面；choice 同时要求投影 enabled、原生 eligibility、当前银两；readonly packet 未被写入。私有 form/focus、WeakRef/token/generation/mount 围栏保持。

## Standards / quality

**Q1 · P1 · 已关闭：初次 UI command envelope 的 StringName 键。** 旧 dot assignment 新增 commandId/expectedRevision 导致首次真实 GUI 10项 invalid-command。新冻结 UI 使用 String 下标，assign-order 的内部 id 同样修复，point/targetId/range/order 的新增字段均为 String。主 Agent真实 UI→Runtime复跑23/0、payload keys全String，实际补薪/领航/偿债扣款；证据与 `69b376…` 相符，关闭原 envelope 阻断。旧 Control 测试1707/0本身不能关闭它。

**Q2 · P2 · 已关闭：整备 refit / treat-wounded 的 StringName 参数。** [UI](../../game/ui/mingqi/mingqi_interface.gd)666–667旧冻结使用 `intent.slot = "sails"` / `intent.quantity = int(...)` 新增键。`_send`深复制保留键类型，[SaveCodec](../../game/domain/persistence/save_codec.gd)68要求 key 为 String，合法改帆/治伤被 command_data 拒绝。这是既有服务遗漏，影响故事后整备，不是 Domain 账务问题。

已最小改为 `intent["slot"]` / `intent["quantity"]`；独立 Standards 子审查员先发现，本审直接核源并通知主 Agent。[Q2 patch](../../build/opening-story-ui/scoped-ui-q2.patch)88行，SHA256 `4a6039d4ecacc7954946533304f1d38729cf5ac71094b9247616bd0b7273db87`；本审核最终源码、增量/累计patch及报告散列匹配。扩展真实 UI→Runtime 测试从 RED36/8到GREEN39/0；初始自有继承船 refit 实扣150并建 active工作；治伤 fixture 经 strict SaveCodec.encode/Campaign.restore 合法载入，实扣12并建 quantity3 active工作，没有改内部state或假称工期已完成。主 Agent也报告39/0；新证据覆盖原23项与两服务，Q2关闭。测试源码 SHA `4a66da91648d59346f33cfc1f155a4dff233ee7b55018a31f77922c5fe114523`。

未证实额外 Domain/Root/导航质量缺陷。独立 Standards 子审查员完成导航四文件核对：共享常量单向消费、fresh-startup/final港口优先、同步真实pose与原子投影保留，没有绕过湿路规划或修改战斗/physics。纯 RefCounted/Catalog、候选提交、detached projection、历史校验符合现有结构；不提出无需求的 Dictionary 重构或性能工作。曾考虑“任意 depart 会使合法晚选故事无法存档”，复核后撤回：初始 offered 无租用旗舰操控权限，任何合法首次 depart 已关闭 loading 场景，没有证明合法失败序列。

## 验证证据与界限

| 证据 | 可确认 | 界限 |
| --- | --- | --- |
| [Domain报告](../superpowers/plans/opening-story-work/task-domain-report.md) | 作者报告263/0，另两份旧fixture/oracle PASS；五文件身份一致 | 本审不重复运行，无新GPU或全流程试玩 |
| 主 Agent strict runner | 五个 opening_story suites新跑5/5，Runtime45/0 | Root最终五文件身份匹配；不证明完整护航；全工程strict runner另在运行 |
| 主 Agent真实 UI→Runtime | 原23/0，新增服务39/0 | Q1/Q2关闭；最终 UI与测试身份匹配 |
| [九图原生证据](evidence/opening-story/native/01-old-ledger-1600.json) | 主 Agent报告52/0并亲看四关键图；本审核九张PNG SHA全部匹配sidecar | Q1阶段真实native按键/固定tick，不是FPS或整个航行结局；最终capture工具已加入九源文件SHA，待重拍关联最终来源 |
| [1280偿债图](evidence/opening-story/native/06-debt-payment-1280.png)、[领航后图](evidence/opening-story/native/04-pilot-consequence.png) | 本审亲看中文/按钮可读，银475→375、本金400→300；领航文字明确免费手动选路 | first-return仍locked，无伪造NPC完成/战绩；美术不在本轮 |
| [导航报告](../superpowers/plans/opening-story-work/task-navigation-report.md) | 作者RED47/3→最终64/0；八定向脚本exit0，计51783断言/0及两旧oracle PASS | 真实tick改善中间点，不替代战斗生存或完整护航；本审不重跑同码 |
| [真实驾驶失败](evidence/opening-story/journey-flat.json) | assertions13/failures4；最后395.0667模拟秒旗舰hull0、交付0、合同active；真实命令无状态注入 | 诚实失败记录，不能写成完整护航通过。后续新Nav/driver必须另跑真实旅程 |

九图 state chain 为银650→570→475→375、本金400→300、actual currentPortId随后null；证明开场选择、付款和离港。first-return 纯域分支/存档可审，原生完整航行→抵达→claim→返港对话仍待旅程证据。失败后的“回港修整”是提示，不是新恢复任务或任何资金/伤亡状态都能继续经营的保证。

当前结论：**Spec/Standards 未证实未解决的 Domain/Root/UI/导航代码缺陷；Q1/Q2均关闭，本 scoped 代码审查冻结。完整护航与返港闭环尚不能宣布验收完成；主 Agent全量strict suite、最终来源截图和新真实旅程验证继续。**
