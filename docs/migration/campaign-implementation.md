# 当前 1650 campaign 原生领域实现

本阶段范围为网页开发工作树 `9ad6a44daecd4ec36a8172d83ff27493feffe5dd` 的 `packages/adventure-core/src/mingqi` 现有规则。原网页保持只读；新源代码、参考夹具、测试和临时转译均写入 `C:/Users/dains/Documents/Git/ming-armada`。参考夹具保存实际读取的 14 个 TypeScript 文件 SHA256；导出工具直接转译这些文件并运行原 `MingqiCampaign`，未以手写预期代替网页规则。临时 JavaScript 运行目录在成功导出后清理，Godot 游戏不调用 JavaScript。

## API 与依赖边界

入口：`game/domain/mingqi/campaign.gd`，继承 `RefCounted`，纯 Dictionary/Array/标量状态。没有 Node、Input、场景访问、文件槽读写或墙钟推进。

```gdscript
const Campaign = preload("res://game/domain/mingqi/campaign.gd")
var campaign = Campaign.new(1650, "林船长", "mingqi-1650")
var state: Dictionary = campaign.snapshot()
var result = campaign.command({
    "type": "accept-convoy",
    "commandId": "accept-1",
    "expectedRevision": state.revision,
})
var accepted = campaign.advance(1.0, near_ids, context)
var json = campaign.serialize("2026-10-11T00:00:00.000Z")
var restored: bool = campaign.restore(json)
```

`snapshot` 深拷贝；`command` 捕获并验证 JSON 数据后在候选状态执行；失败不替换 campaign 状态。`restore` 完成整个 v2 解码与关系验证后才原子替换。所有持久字段、命令和回执继续使用网页的 camelCase 名称。方法提供 `allocate_native_epoch`、`project_native`、`sync_near`、`reconcile_near`、`native_policy`，并保留相应网页 camelCase 别名。

领域层接收可信原生适配器的 `context.native`：

- `snapshot`：`battleId/tick/time/ships`；ship 包含 `id/controlsSequence/visual.position/visual.velocity/visual.heading/hull/sail/crew/rudder/sailAngle/sailDeployment/autoTrim/ammo/ammoType/cooldownSeconds`。
- `events`：实际战斗事件；命中货损与实际人员观察分别去重。事件损伤不会重复扣除 crew。
- `validateCurrent: Callable`：检查捕获的 tick、序列和实例仍有效。
- `project(state, anchorShipIds, phase): Callable`：完整批次投影；成功返回 `{ok:true,snapshot:...}`。`phase` 为 `live` 或 `fresh-startup`。
- `isAnchored(shipId): Callable`：真实锚泊证据；可选 `hasActiveOrder`、`supportsPrizeRetirement`；`pendingAttacks` 来自实际原生状态。
- `context.applyOrder: Callable`：提交战术命令；领域记录使用实际 simulationSeconds。

只有 Dictionary 快照不足以授权港口或俘获操作。回调只属于瞬时上下文，不能进入 JSON 状态。适配器必须在拒绝投影时保持自己的状态原子性。`advance` 与源代码一样先提交已接受的经营时钟；业务投影失败时保留已消费秒数，不提交候选人员、接舷或作业结算。

## 已实现的现有规则

- 完整开局：三港、七个原始身份、uint32 seed/randomState、1650-01-01、1631 出生、650 两、400 两债、两名管事和真实背景出库 10 粮。
- 19 个源命令：`accept-convoy/buy/sell/depart/choose-route/assign-order/claim-convoy/dock/repair/refit/start-boarding/board-action/allocate-prize/release-prisoners/treat-wounded/take-prize-cargo/resolve-prize/sell-prize/incorporate-prize`。
- 粮价按真实库存逐单位报价；容量、银两和安全港条件再次校验。只有 grain 的交易已实现；12 个商品名是 schema/货舱支持，不代表完整 12 商品经济。
- 首合同 40 粮、50 两租费、每船实交、迟到/沉没/人员条件与奖励；实交后解锁第二合同，金门实出 20 粮、复用既有租船，向近岸补给点交付。
- 近远场保持同一船 ID、货物、人员、损伤、控制与序列；远场按源规则沿四条真实路线推进、卸货、损失或中断。货量单位 100kg；`near_field_setup` 输出 `cargoMass=sum(cargo)*100` 和实际吃水。准入要求 `draft < minimumDepth`，等深拒绝。
- 租赁回执与原始所有权推导控制、敌意、缺员禁航、维修锁和俘获船状态，友方外交身份不直接授予控制权。
- 三接舷据点、行动、参与者、士气、真实秒数、每 10 秒人员耗损、胜负回执、俘虏和配员；俘获货物、放行、救人弃船、出售与永久编入。
- 港口 55m、速度、近敌、待处理攻击、接舷和锚泊校验；维修、厦门帆装改造、伤员治疗费用/预留/完成、释放俘虏。前线修理能力沿用源规则上限。
- 保留 reputations、intelligence、people、chronicle、settlements，以及源代码当前会实际改变的信用字段。当前源代码没有独立债务偿还命令或未来历史进程；未新增。

## v2 持久契约

`game/domain/persistence/save_codec.gd` 只编码/解码 v2：`mode=mingqi-1650`。拒绝其他版本，由外层未来的 v1 路由处理旧 1661，不能把此 codec 当作已完成 v1 兼容。

校验覆盖：16MiB/深度/节点/实体上限，重复与危险 JSON 键、非有限数、严格字段形状、ID 和 uint32、时间补偿、日期、原始角色与港口、船容、航程、近场 fence、命令幂等与回执、日志时间顺序、双合同实收/奖励/人员历史、作业付款与完成、俘获证据/处置，以及伤亡序号和完整人员变更链。旧 v2 缺少 `prizes/casualtyOrdinals` 时补空字典，不制造历史回执。JSON 写出使用完整浮点精度，避免 Godot 默认短浮点格式改变航路/港口坐标。

## 本次直接验收

Godot `4.7.2.stable.official.ed1daf0bf`，2026-10-11：

```powershell
rtk proxy node tools/migration/export-mingqi-reference.mjs
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_mingqi_rules.gd
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_save_compatibility.gd
```

两个脚本均 `PASS (0)`。首次行为 RED 为尚不存在 campaign 脚本；实现后原 JS 全状态序列 GREEN。后续增加了原生上下文业务序列、严格存档拒绝序列，每次修正后直接复跑。

规则套件逐步比较实际原 JS 结果和整个状态：开局/买卖/首合同/路线/离港、1000 秒背景运粮、六种战术意图、接舷与 120 秒实耗、11 人拒绝/12 人配员、89.999+.001 秒治疗边界、两个合同全部交付、维修/改造、俘虏释放、取货/放行/救人/编入/成功出售与容量拒绝、近远场原子交接与 1200 秒真实远场卸货、100kg 单位和等深拒绝。

存档套件比较原 validator 导出的 32 个案例（6 个接受、26 个拒绝），另验 web-save-v2 导入、原生往返、旧 v2 可选字段补齐、失败原子性、版本拒绝与 detached snapshot。成功售船和救人容量角落使用源 validator 接受的旧 v2 人员基线；这些是明确的领域单元夹具，不称为真实炮击或导航证据。

## 仍需外层完成与验收

本文件不关闭整款迁移。真实 Godot 原生海战/航行适配器的快照与投影、UI 的全部命令入口、pause/fast-forward、真实锚泊/导航/弹丸、战斗中的跨域回滚、运行时安全保存资格、文件槽/读回/回滚和 1661 v1 路由需要外层联调验收。当前测试证明领域规则与显式原生契约数据的来源一致，不证明真实引擎场景的游戏流程已经通过。1650–1683 长期规划、完整未来主线和网页尚未接入的上岸玩法没有借此次领域移植提前完成。
