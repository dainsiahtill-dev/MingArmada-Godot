# Mingqi 火患状态、采购与岗位权威合同

2026-10-29。承接 [29 号火攻合同](29-fire-control-loop.md)，课题仍为 `ship-fire-control`。本文是正式接线前的规范；生产代码尚未接入，测试尚未执行。不能据此宣称 Campaign、保存、正式入口或登船工时已经通过。

## 最小状态与旧档

保留 v2 envelope。每艘 vessel 可有两个严格可选对象，不改变 `crew.able/wounded/prisoners/minimum` 的含义：

| 对象 | 数据合同 |
| --- | --- |
| `fireControl?` | 冻结 `ship-fire-r1` 十字段，复用 `FireControl.valid`，未知键、bool 数字、分数计数、非有限值、错误版本拒绝。 |
| `fireLauncher?` | `{ammo:{"fire-ball":整数0..60,"thorn-ball":整数0..60},cooldownSeconds:有限数0..120,operationSeconds:有限数0..2}`，复用 `FireLauncher.valid`。 |
| `damage.fire` | 有 `fireControl` 时必须严格等于 `fireControl.heat`，只是现有业务投影，不能独立推进或清零。 |
| `availableCrew` | native snapshot 的当前可用人数派生值；不是人口，不存盘，不写回 `v.crew.able`。 |

人数派生与 native 使用相同顺序：`able` 是实际存活能动人数；先预留正在操作 launcher 的至多4人，再在剩余预算中计算 `FireControl.reserved_crew`。不能把同一批人同时分给 launcher、扑救、炮组或登船余员。有效 `assigned/pending` 均不能超过这份预算。

`controllableShipIds` 继续按总 able、所有权和真实租约决定；不可用 `availableCrew` 取代授权门槛。否则冷待命抽光人员后，会失去取消岗位的权限。可用人数只影响实际岗位能力。

旧档缺两个可选字段时，decode/restore/near_field_setup 保持缺失；不以初始化工厂免费补库存。第一次真实命中可以创建 `FireControl.initial(0)` 再点燃；第一次成功采购只 lazy 创建需要的零库存对象并增加已付费单位。新航程也不免费填库存。

旧档 `damage.fire>0` 却没有 `fireControl` 单列为 `legacy-fire-unresolved`：结构解码可以保留该旧值；安全港、修船、自动到达与安全保存必须视为危险。不得为了读取方便把它清零，也不得擅造燃料、热学过程或扑救物资。转入新规则的明确迁移操作尚未定义、尚未实现；测试只要求旧值不丢、无库存赠送和安全拦截。

## 实际权威往返

1. Native 是近场火势、岗位时钟、整数伤亡余量及 launcher 截止时间的推进者。Campaign 不另跑一份 DOT。
2. Campaign `_sync` 接受原 battle/tick/controlsSequence fence 后，校验并深拷贝 snapshot 的完整 `fireControl/fireLauncher`，同步 `damage.fire`。已有扩展突然在 snapshot 缺失须拒绝，不能当作熄灭或回库。
3. `near_field_setup` 仅显式转发已有对象；Bridge 每 tick reconcile 不重置 `crewDamageCarry/workCarry/assigned/pending/transferTicks`，不再加整份储备，也不把剩余冷却换回12秒。
4. 保存的是 snapshot 剩余秒。Native 再构建时转换为该新 epoch 的截止 tick；同 epoch reconcile 保留既有真实截止时间。普通炮 reload、延迟炮口 due 与弹药不因新岗位变化重排。
5. `fire-payload-launched/hit/splash` 是独立真实事件，Campaign/SaveCodec 接受其明确类型并保留源事件身份。它们不得进入普通 `hit` 货损分支；DOT也不冒充普通 hit。
6. 所有伤亡/俘获/调拨后重新裁剪岗位，使人口合同成立；不能把本在岗的人作为奖船可调拨余员。

## 安全与近远场

以下任一条件成立即为 `fire busy`：现有 `damage.fire>0`、`fireControl.heat>0`、任一 `assignedFirefighters/pendingFirefighters/transferTicks>0`，或 `fireLauncher.operationSeconds>0`。

`fire busy` 拦截 dock、repair、refit、自动 `_arrive` 卸货/到港、arrival anchor、安全保存。只改 UI 禁用或 dock 命令不成立；Campaign 权威命令、自动航程、Runtime 安全门及展示事实必须一致。危险原因应优先报告为 `ship-fire-busy`；保存应报告 `save-fire-busy:<shipId>`。无规则核的旧正火值使用同一安全门。

火已灭且无岗位/转岗/操作时，单纯 launcher 剩余冷却不阻止安全保存；精确保留其剩余秒。Bridge `_unsafe`、初建 native 和 reconcile 的 pin 仍须包含 `cooldownSeconds>0`，直到归零，防止远场冻结装填。活火/busy 船即使远离旗舰也保持权威推进。

在港 enemy 跳过、ordinary heritage berth 跳过，都必须先排除上述需要继续 tick 的船；不能让分支顺序绕过 pin。自动到港的 Campaign `_inspect/_arrive` 与 Bridge `_arrival_anchors` 也使用相同 busy 判定。

## 旗舰在港付费采购

命令固定目标为旗舰，不接受任意 shipId，也不借用粮水货单：

```text
{type:"buy-fire-supplies", commandId, expectedRevision,
 item:"suppression"|"fire-ball"|"thorn-ball", qty:正整数}
```

| item | 单价 | 加入位置 | 上限 |
| --- | ---: | --- | ---: |
| suppression | 2两/份 | `fireControl.supplies` | 600 |
| fire-ball | 12两/枚 | `fireLauncher.ammo["fire-ball"]` | 60 |
| thorn-ball | 24两/枚 | `fireLauncher.ammo["thorn-ball"]` | 60 |

价格是本轮原创候选，不是历史价格结论。`Campaign.quote_fire_supplies(item,qty)` 是只读报价，至少返回 `{ok,item,qty,unitPrice,cost}` 或 `{ok:false,reason}`；它不是实际 native 锚泊证明。真实提交仍要求当前安全港、实际旗舰锚泊、存活和权限、无 busy、无待决攻击，以及现有单次 native fence。

在 `_state` 副本中一次预检数量、价格乘积、银两、上限、权限与安全。成功才扣 `silver -= unitPrice*qty`，lazy 建零库存对象，加精确 qty 并经原 `_project` 原子提交。超上限、bool/分数/NaN/无限数量、未知 item、银两不足、海上或危险状态全部拒绝；不得部分买入、自动补满、先扣银后失败。相同 commandId 沿原 receipt 幂等，不重复扣银/加货。暂不出售/退款。

采购 receipt details 固定为 `kind:"fire-purchase"`，包含 `portId,shipId,item,qty,unitPrice,cost,silverBefore,silverAfter,stockBefore,stockAfter`；关系校验确认 `cost=unitPrice*qty`、`silverBefore-silverAfter=cost`、`stockAfter-stockBefore=qty` 及对应容量。买入 suppression 不触碰 launcher，买入载荷不触碰扑救 carry/岗位；不触碰 `cargo`、饮用水或普通炮弹。

首版作为港内购买成品载荷/损管准备的服务，真实消耗银两，受舰上600/60容量限制。暂未实现港口此类商品的有限供应、采购等待、装备质量、载重/体积、失窃/损耗、港口生产链、跨港价差或长期经济验证；不能称为完整采购库存平衡。准备份代表取水、工具和消耗品的预备工时，不是消耗饮用水货物，也不是无限免费海水扑救。

## 登船人秒门槛：本轮不提前接入

当前 `_advance_boarding` 在每个整秒读取期末人数。仅把它替换为期末 `availableCrew` 有已知边界错误：launcher在第120tick末结束，第二秒内仍被占用的人可能被期末脉冲再用于登船。

正确方案必须由 native 提供每个已接受 tick 的真实可用人秒/岗位占用回执，覆盖命令在 tick 内受理、操作截止、扑救途中/返回及该 tick 末伤亡。期末 snapshot 不能冒充过去整段工时；`min(before,after)` 也不能伪装精确积分。

建议新增临时批次合同 `crewWorkByShip`（名称待native接口锁定），每项绑定 `battleId,tick,shipId,stepSeconds,totalAbleAtStart,launcherPersonSeconds,fireDutyPersonSeconds,availablePersonSeconds`，单位统一人秒。必须证明同 tick 各岗位之和不超过起点人口乘已接受秒，拒绝重复/旧 epoch/未来 tick。上述派生批次只在权威 handoff 中使用，不写 vessel.availableCrew 存档字段。

为保留原整秒控制/士气脉冲，带火控的 boarding 需要持久化不足一秒的攻/守有效人秒 carry，按原 remainder 分窗，消费完整一秒的真实劳动；具体字段尚未锁定，不进入本次正式 schema。旧无扩展路径保留原 oracle；启用新 carry 从当前已接受 tick 开始，不补造过往劳动。参加者资格、伤亡捐人、奖船调拨也必须使用没有被其他岗位占用的人。

必须先做四个失败夹具：第120tick launcher结束、扑救第120/121tick到位、灭火后120tick返回、同tick伤亡。直到真实 tick 回执和人秒 carry 具备验证证据，不能接入新登船路径，也不能宣称已杜绝同人双岗。当前自动实验的岗位秒只是数值核局部证据，不能替代此接线验收。

## 实施与验收状态

预备合同保存于 `fixtures/mingqi_fire_authority_acceptance.gd`，尚未纳入当前可发现测试集；实施1650接线时移入tests，以缺少 `quote_fire_supplies` API 守门，之后测试付费/幂等/上限、严格可选字段和旧档零赠送、carry/冷却往返、危险安全门与远船 pin。该草案未执行，不把未来缺API作为当前功能回归失败。

生产改动待独立Demo/GPU门槛之后，按 `Temp/research/mingqi-fire-authority-draft.md` 顺序落地。真实RED/GREEN、旧native oracle、旧web fixture、正式runtime、安全保存/重建、暂停、自动到港与登船工时回执分开登记；文档和测试存在本身不算通过。
