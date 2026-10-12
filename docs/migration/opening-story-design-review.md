# 旧账新帆：独立玩法与规格审查

2026-10-11。只读审查新 [design](../superpowers/specs/2026-10-11-opening-story-gameplay-design.md)、[domain brief](../superpowers/plans/opening-story-work/task-domain-brief.md)、[UI brief](../superpowers/plans/opening-story-work/task-ui-brief.md) 与现有护粮、原生投影、港口、权限和存档接口。此文审的是设计/依赖，不是未冻结新代码的验收；未改生产、未跑开发者相同代码测试、未开GPU。

## 判断

设计可建立在已有真实护粮链上，三个场景可选、选择有固定成本与收据、两份存档隔离的方向合理。**付费领航可以产生真正航线效果，旗舰权限也可保留**；无需增加假速度/火力增益。需要收紧港口安全契约、说明领航与免费改线的关系，并让情报内容和失败出口实际可见。

## 可操作发现

### F1：港口安全条件应明确为已靠泊，而非只有55米内低速

**级别：P2，接口要求，实施前澄清。** domain brief 写“true safe dock via `_safe_dock`”。现有 [Campaign._safe_dock](../../game/domain/mingqi/campaign.gd) 检查旗舰活着、港口55米内、水平速度≤0.75、无待发炮击/接舷/600米内敌意目标；它本身不检查 `currentPortId` 或真锚定。[Runtime._dock_fact](../../game/runtime/mingqi_runtime.gd) 也采用相同弱事实。仅复用该函数会允许帆仍展开、航路/指令仍有效但临时低速的船支付故事选项。

现有 `_docked(s,native,policy,flagshipId)` 额外要求领域 `currentPortId`、真实 `isAnchored` 与正确停泊距离。原生 [is_anchored](../../modules/naval_simulation/encounter.gd) 的条件是速度≤0.05、yawRate≤0.01、rudder=0、sailDeployment=0、无navigation、无active order。

**最小处理：**公共 `native_safe_dock` 若用于故事/还债，应核 `currentPortId==目标港`，验证当前 native fence，再采用 `_docked` 或等价强事实；`story-choice/repay-debt` 纳入 `NEEDS_NATIVE`。读取UI eligibility不能代替命令时重新校验。开局 offered 阶段故事付费不应强制“租用旗舰已可操控”，否则未接委托的 old-ledger 会被错误锁死：个人港口交易与船舶操控授权是不同合同。

### F2：45两领航应诚实表达服务内容，不能冒称免费航路的独占解锁

**级别：P2，玩法价值/文案建议。** 当前 [choose-route](../../game/domain/mingqi/campaign.gd) 和 [护粮界面航路选择](../../game/ui/mingqi/mingqi_interface.gd) 已允许免费将每艘粮船改为同一条浅路。付费分支实际提供的是一次帮两船规划及一笔商行信用记录；其航路本身并非新解锁内容。

**已由主 Agent 澄清本轮定位：**45两是领航服务/两船规划和人物关系选择，保留免费手动换线、不封锁旧流程。这符合兼容要求，本项不要求改本轮既定规则。完成选择后显示两船实际路线与1.6米吃水，旗舰3.2米仍需深水；不承诺独家捷径、必定躲敌、速度提升或额外安全系数。更深的领航价值可在后续有明示规则和真实验证时扩展。

还应覆盖“玩家已经手动选了浅路，再选领航”这一输入：仍只能执行一次，显示实际选择，不把路线本来已浅描述为刚新解锁。stay-deep会把两船恢复深路，也应明示这个实际操作。

### F3：船员拥护已有接舷作用，其他关系效果需限定真实范围

**级别：P2，效果范围/审查纠正。** 先前消费者扫描排除整个Campaign，遗漏了实际接舷规则；本结论已按原函数重新读取修正。`_boarding_command/start-boarding` 明确将进攻方初始士气设为 `clamp(s.reputations.crewSupport,10,90)`；`_advance_boarding` 进一步用该士气参与据点控制变化和失败判断。因此补薪/分红的crewSupport变化有实际接舷后果。当前默认50可由补薪提高到60，留资分支会降到46，这不是纯展示分数。

**最小处理：**工资/分红可以诚实表达船员拥护与接舷准备士气的改善，不扩大为火炮装填、航速、火力或整个海战的统一增益。当前merchantCredit/militaryTrust尚未见折价、军方权限或炮术消费者，可显示关系和人物回响；情报则通过真实库存消息形成作用。80两与免费保留资本同样清楚，不把可选工资投资包装成强制战斗升级。源冻结后可检查真实start-boarding是否读取选择后的crewSupport，避免UI暗加数值。

### F4：60两情报需要显示实际买到了什么

**级别：P2，功能闭环。** design规定保存补给点实际grain库存、observedAt、sourceId和0.65confidence，数据后果明确；但UI input contract没有独立的情报展示字段，只要求scene.reply/history.message。若只显示“获得情报”和关系加分，玩家看不到这60两的实际信息。

**最小处理：**用实际receipt/intelligence生成reply或目标detail，显示地点、当时粮库存、采集时间与消息可信度；载入后保留这份历史读数，不每帧换成全知实时库存。首次交差时补给点常仍为0粮，这正可说明第二趟20粮的用途；不得凭付费就显示必定安全或敌舰位置。

### F5：全失败与低现金分支的下一步必须真实可执行

**级别：P2，失败体验/验收要求。** 当前首程有交付才解锁convoy-002；零交付的claim会failed。first-return允许failed是正确的，但下一目标不能无条件显示第二趟“接补给委托”。先还400债、租船50、补薪80、领航45会让650两开局只剩75两；若首程零交付，也不会有报酬补充。仅显示“修船后再出海”可能无法支付实际维修整单。

这不是要求本轮凭空给钱或把失败改成功，也不声称已经复现一个必然软锁。**最小处理：**依据实际船况、现金、港口、库存和委托状态推荐现有可做动作；无法继续的失去旗舰等终态应明确提供既有返回/安全检查点恢复入口。免费keep-capital在资金不足时仍可用，付费项给实际原因。first-return位于金门，偿债只在厦门，目标必须明确回厦门而非显示在金门直接付款。

## 已核对的真实行为链

### 航路变化不会只停留在JSON

`OpeningStory`应只修改Campaign的候选克隆；两个route都通过现有 `route_for_vessel`，严格使用 `draft < minimumDepth`，并保留escortIds与pose。

[NearFieldBridge._apply](../../game/runtime/near_field_bridge.gd) 对 underway 航程读 `Catalog.DATA.routes[voyage.routeId]`，以 `locate_route` 选实际下一航点，写入 `policy.navigation`，再调用真正 `Encounter.reconcileShips`。loading时没有立即导航，现有depart会重新定位航段并变为underway。因此只要保留这条正式投影链，领航选择会在起航后产生真实航点；不需要瞬移船只。

静态路径成立不等于真实航行已经验收。源冻结后的runtime复验应看两船不同选择的实际navigation/轨迹，并确认旗舰仍可控、浅吃水不被放宽。domain测试只断言routeId不能替代该运行证据。

### 租用权限不必因新剧情丢失

`Campaign.native_policy` 根据真实accept-convoy收据与contract的active/delivered/failed/settled状态保留已付租船的escortIds和粮船控制权。领航选择不应清理这些字段，也不应改 `ownerId` 或把明旗号变为自有船。原设计和brief明确保留，方向正确。

### 回港对话可比领取报酬更严格

当前claim-convoy检查真实粮船抵达/损失后结算，本身不强制旗舰回金门。新first-return另要求金门安全靠港，能真实表达“回去见人”，但objective应显示这个额外前置条件：已领取海上结算仍需驶回/靠泊，不能让UI暗中搬船或自动完成任务。

### 一次性选择与还债应走现有事务

现有 `Campaign.command` 先检查合法字段、BUSINESS commandId收据、revision，再clone并同步真实native。native投影成功后才提交 `_state`。[Bridge.command_context](../../game/runtime/near_field_bridge.gd) 用battleId/tick/controlsSequence和consumed fence防止复用旧上下文。

新选择除原commandId重试外，还需用canonical `campaignId:story:sceneId` 拒绝同一scene的另一choice/新commandId。还债canonical ID按commandId区分，但sum/principal和全清奖必须连续且只一次。不能把复用可变state或UI按钮禁用当权威去重。

## 源冻结后的独立spec/quality审查重点

- old-ledger收据发生于首次离港前；pilot-plan在首程accept之后且两船loading；first-return在真实claim收据之后。SaveCodec应按纪事/收据因果顺序验，不只检查最终contract.status。
- 关系增量、费用、route与情报字段来自固定choice定义；造假的choice/cost/payment/本金/清债奖不能通过保存验证。合法后续免费改线不应被误判为原领航receipt篡改。
- 旧v2无story receipts仍为400债；新增字段不引入第二权威，保存失败保持bytes/状态/generation。
- 高吃水拒绝发生在扣款前，两船任一失败不能只改另一船。native projection失败不能留下扣款、路线或收据。
- UI显示的是原创对话人物、领航服务和真实记录，不宣称unique 3D人物已生成、NPC已入编或任务已完成。按钮只发真实意图，仍经过现有generation/revision围栏。
- 当前港口前置条件、实际现金不足和completed/locked状态变化可见；长文本和免费选项在目标分辨率不被裁掉。

以上为可操作审查输入。已发主 Agent 的港口接口提醒、免费换线与情报展示建议；等待冻结的scoped source package后再判定实现是否满足，不重复运行开发者同码测试。
