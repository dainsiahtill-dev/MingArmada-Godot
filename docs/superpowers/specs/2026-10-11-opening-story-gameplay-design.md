# 旧账新帆：1650 开局剧情与玩法

用户授权继续自主开发，并明确当前分工：外部 REA Agent 负责海岛、岸线、海面逆向；本地优先让剧情与玩法更有趣。相关海面与粒子工作冻结，待逆向完成再对接。沿用已确定的厦门原创青年船长、继承负债商船、商业与战争相连的方向。

## 本轮可玩结果

在已有 Mingqi 1650 两段真实护粮闭环上增加人物决策、偿债与航海日志。玩家拥有的是承家号；明旗号和粮船属于林家短借，剧情不混淆所有权。原创水手许福、领航陈阿海与林家管事提供不同建议，不将原创台词写成历史名人原话。

三个可选场景按实际进度出现；忽略剧情不会封锁原有护粮流程：

| 场景 ID | 条件 | 选择与真实后果 |
| --- | --- | --- |
| old-ledger | 厦门，首程未离港，委托 offered/active | settle-wages：80 两，crewSupport +10；keep-reserve：0 两，crewSupport -4。固定开局成本，不循环发放关系收益。 |
| pilot-plan | 厦门，convoy-001 active 且两粮船均 loading | hire-pilot：45 两，两粮船换到 xiamen-kinmen-shallow，merchantCredit +1；stay-deep：0 两，两粮船走 xiamen-kinmen-deep。保留全部既有 escortIds、原地姿态和旗舰操控权限；浅航线仍核对船型实际吃水，失败原子回滚。 |
| first-return | 首程实际 claim-convoy settled/failed，玩家安全靠金门 | crew-dividend：80 两，crewSupport +8；buy-intelligence：60 两，militaryTrust +2、merchantCredit +3，并采集补给点当前粮库存、observedAt、sourceId 与 confidence 0.65；keep-capital：0 两。失败或部分交付呈现不同对白，不伪造完美胜利。 |

港口实际安全条件由现有 Runtime/Native context 核验，战斗中和远程航行不能通过日志付钱、改航路或偿债。剧情选择只能执行一次；同 commandId 重试返回原 receipt，不重复扣钱或加关系。

`repay-debt` 在厦门安全靠港执行，quantity 为正整数，不能超过余额或剩余债务。实际扣银与债务本金同时变化；全部还清仅一次 merchantCredit +6，拆分支付不能刷信用。日志把还债作为个人长期目标，维修和改帆继续使用原有系统。

剧情只借助真实 Campaign receipts 推导进度，不引入另一份权威任务状态。日志显示当前目标、可做决策、人物观点、选择回响和真实结算的损失；下一步链接打开现有对应面板，不自动领取报酬或自动完成任务。

## 数据与分层

`game/domain/mingqi/opening_story.gd` 是无引擎场景依赖的纯规则/投影；定义原创内容与固定效果，接受 detached campaign data。Campaign 统一执行 `story-choice`、`repay-debt`，沿用 revision、idempotent receipt、native 投影与原子回滚。SaveCodec 支持新 receipt，严核参数、前置因果及还债总额，旧 v2 无新 receipts 时保持 400 两债务的兼容。

`MingqiRuntime.snapshot()` 提供 `story` 投影和基于真实 dock facts 的 choice/payment eligibility。UI 只发 intent，不修改货物、银两、航路、章节或关系。现有两份 v1/v2 存档与 Legacy 1661 历史主线保持各自独立。

## 验收

必须证明选择真实扣银/改航路、浅水限制不放宽、两份相反选择产生不同记录、旧存档兼容、选择与还债存读后不重复、伪造/越级/过期/不安全操作原子拒绝。通过真实 Godot 主菜单进入 1650，点击剧情选项与现有接委托/离港按钮，亲自查看 native viewport 截图；至少覆盖 1600×900 和 1280×720，日志长文本可滚动且不遮掉操作按钮。

这一轮实现开局人物与经营选择，不将整个 1650—1683 历史主线标为完成。现有护粮/俘获/维修玩法服务剧情；之后可在实际游玩反馈上扩展委托类型、人物长期承诺和章节。
