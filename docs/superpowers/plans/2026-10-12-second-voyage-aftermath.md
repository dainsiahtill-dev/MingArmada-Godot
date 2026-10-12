# 第二趟交差后「钱先给谁」Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 本计划只交付设计；主线程选择执行时，沿已有自主授权推进，不再请求阶段审批。

**Goal:** 第二份合法交差之后，在厦门、金门或近岸补给点任一安全锚泊港的船上账册，让玩家比较并执行一次偿债去向、真实分红或留本决定；自然返家后也可核账。

**Architecture:** 新增窄域 `SecondVoyageAftermath`，复用 `story-choice` 命令、固定剧情回执、Campaign 原子事务和原生安全港守卫。OpeningStory 只分派新场景并合并投影，旧三场七选择保持原义；债务继续由现有 `repay-debt` 兑现，无通用承诺系统或新返航合同。

**Tech Stack:** Godot 4.7.2 / GDScript；现有 Campaign、Runtime、Godot Control UI、SaveCodec V2；Windows D3D12 / Forward+ 图形验收。

**Spec:** `docs/superpowers/plans/opening-story-work/second-voyage-playable-choice-spec.md`。本文末列自主收窄与规则调整，执行以本文明确覆盖的差异为准，其余原规格约束仍成立。

**状态与证据边界：** 2026-10-12 只读代码后编写；未改产品源码，未执行新增测试，未证明第二趟真实航行或 GPU 验收已通过。CodeGraph 实际返回项目无索引，本次依其指示使用 RTK 精确读取。旧 `MingArmada` 目录与参考游戏只读；导航由主线程及导航子任务独立处理。

## Global Constraints

- 1650 年原创船长，出生年 1631；不代入历史名人。原三场七选择、原 V2 存档继续合法。
- `R=claim.details.baseReward+claim.details.bonus`，`P=floor(R/5)`。按时全交 250/50；迟到全交 200/40；部分实交 15 粮 150/30；交零无分红。
- 来源必须是 `convoy-002` 的合法固定 claim，合同为 settled 或 failed；旗舰实际在 `xiamen`、`kinmen`、`forward-supply` 三个既有港之一原生安全锚泊才可决定。海上不允许，仅修改 currentPortId 或传入假 portId 不构成资格。
- 只复用真实港务、偿债和手动/海图操船；无新敌船、伤亡、库存、价格、收益、第三委托、补员或新同伴。
- 不修改导航、地形、港口距离、合同路线、海面或 GPU 素材。返厦门无反向运输合同、传送或自动清债。
- 回厦门和留本选择不扣钱、不减本金、不奖励声望；分红不治伤、不改变船员数量，不新增战斗属性。
- 接收人只含可证明参加本航且支付时仍存活的健员/伤员；俘虏、背景商船、死者不计入。无证据则缩小表述与范围，绝不猜人数。
- 所有 shell 命令以 `rtk` 开头；测试产物写独立 QA 目录，正式用户存档和历史 QA 证据不得覆写。

## Review Focus

1. 交差后先治疗、转移人员或再次发生伤亡，再分红/保存：历史支付名单不能错误地由当前人数重算。Task 1、3 覆盖按事件切点重放。
2. 第二航旧存档只有运输船 load 名单，护卫 `escortIds` 只是任务安排：不把安排当实际参与。Task 1 覆盖受益范围与不可证明的人员混合。
3. 玩家途中花钱或选择后改主意：返航目标不冻结资金，不自动偿债，也不能反复领分红。Task 2、4 覆盖。
4. 拥护已达 98/100，或 P 很小：界面显示实际增加，不能始终声称 +4。Task 1、3、4 覆盖。
5. 第一关旧快照、海上 claim、投影失败、重复命令与导入：保持旧兼容和原生事务边界。Task 2、3、5 覆盖。

## 已核查的实际接缝

- `game/domain/mingqi/opening_story.gd`：`SCENES`/`CHOICES`、`choice_definition`、`scene_reason`、`choice_reason`、`apply`、`project`、`_objective` 已形成完整三场流程；固定键是 `campaignId + ':story:' + sceneId`。
- `game/domain/mingqi/campaign.gd`：`_valid_command` 校验剧情静态定义；`command` 对副本同步原生状态，先 `_docked` 后剧情 apply，最后 `_project` 成功才 `_state=s`。现有 commandId 重放返回原回执；固定场景键约束不同 commandId 重复选择。
- 同文件 `_convoy_details` 的第二航 load 仅含真实承运粮船；`voyage.escortIds` 中写有旗舰/快船，但不能证明二者实际随航。`crewSupport` 已在接舷创建时进入 `clamp(value,10,90)`，不是新造的战斗收益。
- `game/domain/persistence/save_codec.gd`：严格 `story-choice` schema、`_story_receipt`、`_opening_history`、`_crew_history` 和合同关系验证；原 schema 没有第二航附件。现有 schema 扩大 scene 枚举本身不足以证明动态支付。
- `game/runtime/mingqi_runtime.gd`：`_eligibility` 已遍历 story.scenes，依原生锚泊/安全状态投影；`snapshot` 已提供 story。一般无需新 command 类型。
- `game/ui/mingqi/mingqi_interface.gd`：`_build_story` 通用选择按钮、`_story_signature` 重建条件、`_repay_ok`/`_debt_quantity` 实际偿债入口可直接沿用。

## 最小设计与不可误读的取舍

三个方案放同一短账单下。只在合法第二 claim 后向 story.scenes **追加** `second-return`，旧存档/首航仍是原三场；未 claim 时不添空剧情盒子。claim 在海上发生时给目标「驶往厦门、金门或近岸补给点，安全锚泊后核账」。这是船上账册，无岸上具名NPC会面前提；已经自然返厦门的玩家无需再赴补给点。

对照账单必须显示：实交/实损、基础报酬、奖金、R、现银、剩余本金、支付 P 后余银、既有 crewSupport 与实际增量。船况和港务引用当前真实船只，不造一份叙事库存。死亡字段最小范围为「承运船本航已核实死亡 N」，护卫无完整来源时明确「护卫伤亡未列入本账」，不能写「全队无人伤亡」。旧伤显示「当前伤员」，不称本航新增。

台词固定最多两句，由无具名生命状态的「交差账单」发言：

> 这趟实交{delivered}粮，实收{R}两；现银{silver}两，旧债{principal}两。
> {偿债去向}、给本航已核验船员分两成，或先留船本，这笔钱由你安排。

`偿债去向` 在实际厦门安全锚泊时为「在厦门还债」，其他合格港为「回厦门还债」；两句数量不变。

R=0 时第一句仍是「实收0两」，绝不称「赚来的钱」。不让不在 people 中的许福扮作可证明在场的活船员。

### 三个 choiceId

1. `return-xiamen` / **在厦门偿债**（当前厦门）或 **回厦门偿债**（其他合格港）：同一 choiceId，一次记录目标意图，无拟还金额入存档。当前建议还款 `min(silver,principal)` 只作实时预览；实际厦门安全锚泊后使用现有整数输入和独立 `repay-debt`。在金门/补给点的目标「驶回厦门，安全锚定后偿债」；已经厦门的目标直接「向林家商行偿还本金」，不要求离港重返。实际部分还款显示本场决定之后真实已还累计额及当前本金；本金清零才显示「旧账已清」。若债已清，按钮拒绝「本金已还清，无需再立偿债目标」。零银仍允许定目标，明示「当前无银可还，实际偿债仍须有足够银两」。目标是提醒，不锁定后续操作；玩家随时打开其他面板、买卖、港务、返航，不需“修改承诺”事务。
2. `share-proceeds` / **分给已核验随航船员 · {P}两**：立即扣 P，既有 crewSupport 标称增加 `A=min(4,max(1,floor(P/10)))`，实际增加 `D=clamp(before+A,-100,100)-before`。P50/A4，P40/A4，P30/A3；P>0 才存在 A。关系明确记「第二趟实付 P 两，受益 N 人，拥护实际 +D」。crewSupport 已影响未来新接舷的初始士气；不改已有接舷、不承诺胜率、伤害或速度。若已到100，提示「拥护已满，本次不会再加；支付仍会记账」，允许玩家自愿选择。
3. `keep-capital` / **留作船本**：零支出、零新增关系分。目标「核对船况与本钱」，按钮带去已有 ship/port 面板；显示真实维修/治疗/贸易入口，无伤员不显示治疗任务。回应「现银仍{silver}两，未偿本金仍{principal}两；下一笔支出由你决定」。

**支配性判断：** 原规格在平静无伤员局只扣 P、不改关系值，且没有已实现的未来反馈机制；按当前可玩的资源状态，留本弱支配分红。新增小额既有拥护收益使两者交换流动资金与关系；上限4小于首航+8，按真实 P 缩放避免少量收入同获最高回报。此为设计数值，必须通过测试核实兑现，不能宣称已经玩家平衡测试。达到100时边际值为零如实展示，不伪造额外奖励强行消除所有状态下的支配。

### 参与与存活的最小可证明范围

本版本按钮明确「已核验随航船员」，账单标「本次仅含承运船」；只有第二装载 load 中且实际有该合同 voyage 的船可进入名单。已失去船体/已沉没的船不作为发放地点；死亡只保留账目，不发给死者。按合法伤亡/crew-transition 在支付切点计算 able、wounded，prisoners 不加进人数。

治疗只在 able/wounded 间移动，不失去资格。load 至支付期间若某船发生跨船人员转入/转出，该船整组保守排除，显示「{ship}人员曾跨船调动，本航受益人数暂不能核清」；其他可证实承运船仍可受益。原因是聚合 bucket 没有个人身份，不能把转入战利品人员视为本航原随航者，也不能准确分离混合后的伤亡归属。无剩余合格船员则拒绝分红。不要创建新身份系统来弥补这个窄场景。

收益 P 是一次船员集体支出，不逐人整除、不把余数归到虚构个人；保存每艘合格船 able/wounded 与总人数。后续治疗、死亡、转移不追扣、不重发，也不让既存合法回执失效。

## 源文件责任与接口

**新增 `game/domain/mingqi/second_voyage_aftermath.gd`（RefCounted 静态函数）：**

```gdscript
const SCENE_ID = "second-return"
const CHOICES = ["return-xiamen", "share-proceeds", "keep-capital"]
static func choice_definition(choice_id: String) -> Dictionary
static func quote(state: Dictionary, choice_id: String) -> Dictionary
static func apply(state: Dictionary, choice_id: String, port_witness: Dictionary) -> Dictionary
static func project(state: Dictionary) -> Dictionary
static func receipt_error(state: Dictionary, receipt: Dictionary) -> String
static func crew_at_event(state: Dictionary, ship_id: String, before_event_id: String) -> Dictionary
```

静态定义给 portId=null（只在新scene表示需按实际当港解析）、routeId=null、buyIntelligence=false 与合法ID；不能把动态支出伪装成固定 silverCost。`quote` 先要求 state.currentPortId 属于三港白名单，返回 `{ok,reason,portId,claimId,revenue,silverCost,supportAward,supportBefore,supportAfter,beneficiaries,beneficiaryCount}`；海上/未知港失败。quote仅领域资格，不能自证原生锚泊。`apply` 在 Campaign 草稿上扣钱/改拥护，消费命令守卫成功后从同一native快照构造的只读 port_witness，返回现有 `{ok,reason/message,details}`；不写 settlements、chronicle 或 revision。`project` 返回 `{scene,objective,relationNote,bill}`；无合法claim时返回空字典。`receipt_error` 只读，返回空串表示新回执有效；不调用会检查“已选择”的实时 quote。

**动态当港窄分派：** `_valid_command` 仍只验scene/choice静态合法性，命令禁止增加portId/native/portWitness字段。Campaign story-choice 分支若且仅若 sceneId=second-return：同步native后读取草稿 `s.currentPortId`，核三港白名单，再原样调用 `_docked(s,native,policy,s.flagshipId)`；其现有 `_safe_dock` 已检查相对该港距离≤55、速度≤0.75、存活舰体、无待决炮击/接舷及600范围合法敌舰，`_docked` 另验实际 isAnchored。通过后将观察到的当港写入details，生成下述见证，再apply。旧三scene继续严格比较 definition.portId；不得把旧场景portId设null、通用允许任意港或绕过固定港条件。OpeningStory 新scene的scene_reason/choice_reason直接委托新模块，Runtime仍沿原生facts.story gate。

`crew_at_event` 返回 `{ok,reason,able,wounded,prisoners}`，用现有可信 casualty 与 crew-transition 的 before/after 链切片重建；后续链从 current 倒推到切点，必要时用原 canonical crew/合法 load 基线补足无事件船。未知/断裂来源失败，不用受检 beneficiaries 自证。必须保留现有 SaveCodec 对事件链的独立验证，不把此函数当唯一链合法性依据。

**修改文件：**

- `opening_story.gd`：增加模块 preload、新 scene/choice 注册和方法窄分派；project 有条件追加新场景、合并真实关系/目标。原 definition 数值、reply 与首航场景渲染不改。
- `campaign.gd`：复用现有 story-choice 分支；仅第二场景窄分派动态当港、quote/apply及原生见证。保留 native/docked/project 提交顺序；不改 claim 算法、人员人数、偿债实现或新增 business 字符串。
- `save_codec.gd`：仅新增 scene 专属附加 schema、第二回执历史验证与 support 历史校验；旧 story 回执禁止携带新附件。无全局新顶层字段、无版本迁移。
- `mingqi_runtime.gd`：新投影沿既有 facts.story 门禁，只有确有不足才小改；禁止 UI 凭 currentPortId 代替原生安全资格。
- `mingqi_interface.gd`：新增短账单渲染与中文原因；复用三按钮、债务输入、现有港务页面；必要时补 `_story_signature` 动态 A/D/N 变更避免陈旧报价文案。
- 新测试 `tests/test_second_voyage_aftermath.gd`、`tests/test_second_voyage_aftermath_runtime.gd`、`tests/test_second_voyage_aftermath_save.gd`、`tests/test_second_voyage_aftermath_ui.gd`；`tools/verify-godot.mjs` 只按其现有测试注册方式纳入。
- 新 GPU 操作/证据脚本可用 `tools/play-second-voyage-aftermath.gd`；只读主线程实际第二航输出，不修改其导航工具/输入/输出。

## 回执与 SaveCodec 精确边界

命令形状保持 `{type:'story-choice',sceneId:'second-return',choiceId,commandId,expectedRevision}`。固定键仍为 `{campaignId}:story:second-return`；同一回执既是一次选择证明，也是分红实际支付证明。无需原稿的 aftermath-plan/crew-dividend 双键，无反复改计划记录。三选一不可重选只约束此场一次支出，所有正常港务与偿债始终可用。

沿用旧 details 字段并只给新 scene 增加必需 `aftermath`：

```text
kind=story-choice, sceneId=second-return, choiceId=<三选一>, portId=<命令当时实际xiamen/kinmen/forward-supply>
silverCost=P（仅share-proceeds，否则0）
reputationEffects={crewSupport:A（仅share-proceeds，否则0）, militaryTrust:0, merchantCredit:0}
routeId=null, convoyReceiptId=<固定第二claim>, intelligence=null
aftermath={contractId:'convoy-002', revenue:R,
  silverBefore:<count>, silverAfter:<count>,
  supportBefore:<-100..100>, supportAfter:<-100..100>,
  beneficiaries:[{shipId:<id>,able:<count>,wounded:<count>}], beneficiaryCount:<count>,
  portWitness:{flagshipId:<id>,position:{x:<finite>,z:<finite>},speed:<nonnegative finite>,
    hull:<positive <=100>,anchored:true,pendingAttacks:false,activeBoardings:0,hostileWithin600:false}}
```

非分红时名单为空、人数0、银前后相等、support前后相等；R仍引用合法claim用于同账单验证。新 schema 不接受 plannedRepayment、claim 自带奖额、任意新声望字段或任意 user-supplied recipients。

必须验证：固定 scene/key/choice 配对、唯一回执、chronicle causeIds 与当前惯例 `[commandId,receiptId]` 一致，第二 load < claim < choice，revision 严格递增，claim 属于同 campaign 和 convoy-002 且 ct.receiptId 对应；R/P/A 重新计算，银后=银前-P 且非负，support后=clamp(before+A)。收款 shipIds 去重/排序、属于第二load真实承运船、支付前未沉没、无上述混合身份事件，人数为支付切点真实桶而非当前桶。非分红 choice 不得带钱/拥护效果。

`portId` 严格三港枚举；portWitness由通过真实native守卫的Campaign生成，不接受命令或UI提供。SaveCodec核flagshipId、有限坐标、相对回执portId的距离≤55、speed≤0.75、hull>0、锚泊及安全布尔/计数固定值；单独把合法港改成另一合法港也应因历史坐标不符拒绝。这是支付当时的见证，不要求保存时 currentPortId 仍等于回执港；选择后真实离港/跨港保存应合法。既有dock回执没有完整港口details，不能从其message猜历史港，也不能把当前native位置倒用为历史位置。存档仍非签名原生遥测，SaveCodec不能独立证明有人协调伪造的完整历史native快照；实际原生授权由Runtime可信bridge及Campaign门禁保证，测试必须证明假的currentPortId/UI字段无法绕过，禁止宣称JSON能重建或认证历史native callable。

`crewSupport` 当前已精确搜索 domain/runtime，写入源为初始50和 story-choice 的动态 reputationEffects 循环；执行前再确认是否有并行新增来源。对含新第二场景**分红**回执的档，按 chronicle 重放所有合法 story-choice 的 crewSupport clamp 变化，校验新回执 before/after 和最终值；不能只验 before/after 两个相互自证数字。没有新分红回执的旧档沿原验证规则；第二场景留本/返航只验零效果和before=after，不因本功能新增全局规则被拒绝。发现其他已有合法来源时纳入该来源，不拒绝旧合法存档；旧档首次尝试新分红若历史无法解释现有support，则明确拒绝该分红，其他原有玩法与留本/返航仍可用，不擅改旧值。该报价拒绝需同步加入 Task 1/3 的旧档兼容测试。

**诚信限制：** 当前存档不是签名账本，旧贸易回执没有完整资金 details，不能声称本次新增字段能抵御任意协调修改整个历史/余额的攻击。本轮保障动态金额、合法claim绑定、一次性、关系链、受益船员与债务连续性；对真实事务的实际扣银用 runtime 前后和 Continue 验证。不可为宣称全局银两防伪而重构整个旧经济账本。

## Task 1：纯投影与可证明分红报价

**Files:** 新增 aftermath 模块和 `tests/test_second_voyage_aftermath.gd`；引用原 `test_convoy_recovery.gd` 的合法第二航构造方式，避免手填成功claim。

**Interfaces:** 产出以上 choice_definition/quote/project/crew_at_event；消费正式 state/settlements/chronicle，不依赖 native simulation。

- [ ] 写失败测试 `test_reward_shares`：正式生成 R=250/200/150/0，断言 P=50/40/30/拒绝，A=4/4/3/无；初始拥护98实际+2，100实际+0；银=P可付，P-1拒绝。
- [ ] 写失败测试 `test_participants_and_cut_points`：两承运船、单幸存船、仅伤员、仅俘虏、沉船、背景船、未经证实护卫、转移混合船、治疗前后与支付后新死亡；只计算符合范围的真实存活桶，回执生成后读档不因后来伤亡失效。
- [ ] 写失败测试 `test_scene_copy_and_projection`：claim前无新增scene；海上claim目标要求三港之一靠港；三个合法港都有新scene，厦门按钮「在厦门偿债」、另两港「回厦门偿债」；失败R0仍允许留本/返航；旧伤不称新伤、护卫未知不称全队无人伤亡；两句文本、实时银/债/P/A/D。
- [ ] 运行 `rtk proxy "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --headless --path . --script tests/test_second_voyage_aftermath.gd`，确认缺实现导致预期失败。
- [ ] 实现纯函数、三方案投影与上述明确原因；事件切点逻辑保持只读，绝不读取待验证回执名单作为人数来源。
- [ ] 同命令通过，输出 `SECOND_VOYAGE_AFTERMATH_TESTS ... failures=0` 且进程0；按授权做本任务独立提交或留待主线程统一提交，仅暂存本任务文件。

## Task 2：一次真实选择事务与旧场景分派

**Files:** aftermath 模块、opening_story.gd、campaign.gd；测试 `test_second_voyage_aftermath_runtime.gd`。

**Interfaces:** 新模块 `apply(state,choice_id,port_witness)` 输出 details，由Campaign新scene窄分支直接调用；OpeningStory原apply签名供旧三scene沿用，其新scene读投影/quote分派不需要native参数。Campaign仍接收原 story-choice command，不允许输入port或native见证。

- [ ] 写失败测试 `test_atomic_share_choice`：合法原生锚泊下分红银恰减P，拥护按上限变化，债/健员/伤员/死人/库存/合同均不变；同commandId回原receipt，不同commandId拒绝第二次，换另一个choice也拒绝。
- [ ] 写失败测试 `test_intent_is_not_repayment`：三港return-xiamen/keep-capital均零经济变化；补给点和金门repay-debt仍拒绝。厦门选择后立即出现真实偿债入口且尚未扣银，不要求先离家再回来；部分偿100后本金300/信用不增加，最终清余300一次+6；目标只按计划之后真实repay回执给已还额。
- [ ] 写失败测试 `test_native_fences`：三港分别用真实native安全锚泊成功；未锚定/不安全/海上/未知港/假currentPortId与native位置不符/命令额外portId或portWitness/缺native/陈旧revision/投影拒绝/事件buffer满均拒绝，银、关系、债、收据数不变。旧三scene在原规定港外仍拒绝；已经作业不阻断无冲突的分红，但不得绕过原生锚泊门禁。
- [ ] 运行对应 headless 脚本，确认失败；接入分派和副本内 apply，不动导航与 claim 分支。
- [ ] 重跑新增脚本及 `tests/test_opening_story.gd`、`tests/test_opening_story_runtime.gd`，各自 failures=0、进程0；核对原SCENES的原三场数据、七选择数值未改变。提交范围同 Task 1。

## Task 3：严格 V2 回执与跨时间兼容

**Files:** save_codec.gd、aftermath 模块验证函数、`tests/test_second_voyage_aftermath_save.gd`。

**Interfaces:** `receipt_error(state,receipt)` 只验证新scene；旧 `_story_receipt` 分支不放宽；crewSupport 历史来源确认后增加独立重放。

- [ ] 写失败测试 `test_old_v2_and_new_roundtrip`：web-save-v2、旧首航有/无choice、旧第二load、旧第二claim均合法；三港分别三choice的 encode/decode全字段等价；新分红后治疗/真实伤亡/转移/返厦偿债再保存也合法；选择后真实跨港时不能用当前港错误否决历史港见证。
- [ ] 写失败测试 `test_forged_aftermath_receipts`：错误/第一航claim、R/P/A改1、外来campaign、重复新键、重复commandId、改顺序/revision、删附件/添未知字段、非分红扣款、未知portId、三合法港互换但历史坐标不符、非有限/超距/超速/未锚/不安全portWitness、伪造已还债，均拒绝。
- [ ] 写失败测试 `test_forged_beneficiaries_and_support`：受益列表重复/死人/俘虏/背景/未验证护卫/零人数/桶数+1/转入混合/支付后人数偷换；supportBefore与After同步伪造+10、当前support单独+1、100封顶伪加，均拒绝。
- [ ] 运行新增脚本确认失败；实现条件附件 schema 和事件/crew/支持历史核验，复用现有严格类型与计数约束。旧scene携带aftermath必须拒绝。
- [ ] 运行新增 save 脚本、`test_opening_story_save.gd`、`test_save_compatibility.gd`、`test_crew_impacts.gd`、`test_convoy_recovery.gd`，均 failures=0/进程0。记录防伪具体范围；不宣称签名级防篡改。提交范围同 Task 1。

## Task 4：真实 UI 三选项与兑现目标

**Files:** opening_story.gd、mingqi_interface.gd，必要时 mingqi_runtime.gd；`tests/test_second_voyage_aftermath_ui.gd`。

**Interfaces:** 使用 story.scenes 新scene、bill 与 `runtime.eligibility.story['second-return']`；现有按钮名规则保留，例如 `story_choice_second-return_share-proceeds`。

- [ ] 写失败测试 `test_real_controls_dispatch`：真实实例挂接Runtime，点击三个分支的真实Control，各独立合法checkpoint；厦门真实按钮「在厦门偿债」，金门/补给点为「回厦门偿债」。确认只发sceneId/choiceId/revision和commandId，无UI指定港/native；验证真实新receipt与银变化，不以伪packet按钮测试代替。
- [ ] 写失败测试 `test_dynamic_cost_and_refusal`：当前银不足、R0、无合格船员、拥护封顶与安全资格变更时，按钮、可见原因、账单预览一致；quote显示以后若revision变化仍由Campaign拒绝，UI刷新后可重试。
- [ ] 写失败测试 `test_debt_objective_and_partial_fulfillment`：返航目标打开海图/港务所需现有页面；途中花钱后偿债输入上限实时变小，不保留旧Q自动付款；部分偿还只显示实际累计/剩余，清零才完成。
- [ ] 运行失败测试；实现短账单、实时后果、中文拒绝原因及现有港务入口。不放三屏新对白，不新建通用目标管理器。已选场景保留回执摘要，正常港务可随时继续。
- [ ] 重跑新 UI 脚本与 `test_opening_story_ui.gd`、`test_opening_story_ui_runtime.gd`，failures=0/进程0；确认小窗口下三选项及下一步可阅读，无旧场景被新面板遮住。提交范围同 Task 1。

拒绝原因至少映射：`second-convoy-unclaimed`＝「先完成第二趟并领取实际报酬」；新scene的`not-in-story-port`＝「在厦门、金门或近岸补给点安全锚泊后，再打开船上账册」；旧scene原固定港提示不改。`unsafe-port`沿现有真实安全原因；`no-dividend-proceeds`＝「本航没有可分报酬」；`no-verified-beneficiaries`＝「暂无可核验的存活随航船员，不能发放」；`insufficient-silver`＝「当前银两不足支付{P}两」；`story-completed`＝「本次安排已记账，仍可自行港务或偿债」。

## Task 5：真实航次、GPU 操作和安全 Continue 闭环

**Files:** 新 `tools/play-second-voyage-aftermath.gd`、测试注册 `tools/verify-godot.mjs`（需要时）；验收报告 `docs/qa/second-voyage-aftermath/acceptance.md` 和独立产物子目录。不修改主线程第二趟导航工具。

**Interfaces:** 输入主线程本轮实际第二航最终正常厦门checkpoint，先核验其原有正式第二claim与真实安全港；无需中途不存在的补给点checkpoint，也不创建新来源claim。输出来源hash、命令/事件ID、结果state、截图、可安全Continue存档。旧QA文件只读。

- [ ] 新脚本 preflight 验证输入source hash、SaveCodec、真实claim、原生到港安全事实；输入不满足时明确拒绝，无 _state 改钱/改位置/补receipt。运行脚本不创建参考游戏或旧目录写入。
- [ ] 正式Godot地形上，从同一个本轮真实第二航厦门正常checkpoint开三个独立分支：分红实际扣银/加拥护；留本实际不变；点击「在厦门偿债」只记目标，再独立点击现有repay-debt才扣银减债。验其已发生的真实返航与安全锚泊来源即可，不要求离开厦门再返航。若另有自然生成的合法补给点checkpoint，可额外通过真实海图/操帆返厦测试去向；无该来源则标该额外路径未测，禁止构造位置或伪造一次新旅程。
- [ ] 图形模式启动实际1650场景，通过真实UI进入船上账册并操作按钮；保存结账前、分红后、厦门实际偿债后、Continue后四组截图和对应state/readback。GPU截图不得来自单独伪UI模型。使用主线程最新验证过的实际返厦产物确认到港前置，不能用本计划或旧截图代替。
- [ ] 治疗变体来自有真实伤亡来源的合法checkpoint；每船q人扣4q、完成需30q模拟秒，死亡不变；无伤员成功局不生成治疗。并行作业时不把工期相加冒充全队等待。
- [ ] 迟到/部分/零收入用于领域与原生集成变体；没有实际图形航行取得该变体时，明确标「自动化构造领域测试，非实玩证据」。不制造敌船或修改库存求截图。
- [ ] 用 UI 原有存档/Continue 和导入路径验证真实落盘再读回，选择、银、债、拥护、分红名单一致；海上存档仍拒绝。每个分支独立测试用户目录，保留正式用户档与备份。
- [ ] 执行 `rtk proxy node tools/verify-godot.mjs --godot "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe"`，保存真实输出；新增/受影响组通过后全套仅跑一次，失败先归因，不靠重复跑掩盖。
- [ ] 验收报告逐项列实际命令/claimId/choiceReceiptId/repayId/workId、源hash、GPU后端、截图路径、模拟时间与wallclock、通过/失败/未测。主动阅读并按按钮目标30–60秒仅设计目标；如未做真人体验测试，明确「可玩流程已测，乐趣未作玩家研究」。

## 对原规格的自主调整及依据

1. **双事务改为一条 story-choice。** 一次性场景已具固定键、原子提交、commandId重放、原生资格及历史投影；再建计划和分红两条回执会扩大重复扣款与部分成功边界，当前玩法无需该复杂度。
2. **去掉持久拟还Q与改计划回执。** 回厦仅目标意图；金额在真实厦门支付时选。自由买卖/港务与普通偿债不锁，减少承诺系统却保留真实返航与清债取舍。
3. **分红增加有限既有crewSupport。** 原无伤员局纯扣钱缺实际关系回报；A随P缩放、最高4、总上限100。披露现有接舷士气引用，不新建即时buff，不保证战斗结果。
4. **参与者明确收窄为已证实承运船。** load没有护卫名单，escortIds不足以证明实际护卫；聚合人员转移不能凭空恢复个人身份。UI准确表述范围，混合船保守排除，避免以推测给人发钱。
5. **说话者改成账单。** 不凭空给既有人物添加生存/在船证据，保留两句内内容与行动重点。
6. **仅补给点改为三港船上核账。** 主线程本轮第二航实际最终存档在厦门，中途没有补给点checkpoint；自然返家的玩家不应为决定钱怎么花再远航。允许厦门/金门/补给点真实安全锚泊，海上仍禁；新scene动态当港窄分派，不扩大旧三场固定港。厦门按钮与目标直接偿债，但点击选择绝不代替真实repay命令。此条自主覆盖原spec的「仅补给港」要求。

## 计划自审

- 原规格触发、实际收益、三取舍、现有治疗/债务、失败分支、保存兼容、可见反馈均有对应任务；更广海上追击/前置口头承诺仍不做。
- 所有新增接口在本计划定义；任务间消费一致。历史名单按支付切点验证，不能与当前名单混淆。
- 回执固定一次与玩家自由后续行动并存；选留本不禁未来还债，选偿债不提前扣钱，选分红不自动治疗。
- 真实航行来源沿主线程本轮实际第二航厦门正常checkpoint核验；本计划不越界修改导航，不造补给点中间档、新claim或来回旅程，不把本设计文档当成功证据。
