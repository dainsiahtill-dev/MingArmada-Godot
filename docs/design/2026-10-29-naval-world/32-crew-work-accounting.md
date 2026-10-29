# 逐 tick 船员工时账 · 接线提案

2026-10-29。状态：**接口与架构选择已锁定，尚未实现、未运行**。本文件是既有 `ship-fire-control` 课题的接线设计补充；不是新实验、通过报告或生产完成记录。方案须与 [30 号权威合同](30-mingqi-fire-authority.md) 和 [31 号阶段交付](31-fire-skirmish-delivery.md) 一起审阅。当前只读源码观察不构成 Godot、GPU、存档或正式航程验收。

## 问题与源码边界

`Encounter._fixed_tick` 的实际顺序是：先 `tick += 1`，再战术/AI，随后物理、岸碰、船碰、延迟炮口、弹体、火控，最后终局。`_launcher_operators` 根据当前 tick 的剩余操作秒数计算人数；tick 0 的两秒操作在 tick 120 的端点快照中已经为零。端点零并不表示 `(119/60,120/60]` 这一段没有占人。

`MingqiRuntime.advance` 每次实际调用 `simulation.advance_fixed()` 后，先 `bridge.reconcile()`，再 `campaign.advance(STEP, ..., bridge.command_context())`。`reconcile` 会调用 `reconcileShips`、更新 controlsSequence、同步伤亡并推进 `nearTicks`。因此工时必须由 Native 在执行 tick 时产生，并跨越这次同 tick 重投影保留；事后读取 Campaign 人口、当前 `_available_crew`、`min(before,after)` 或 `nearTicks`，都不能恢复实际已接受区间。

`Campaign._advance_boarding` 目前只在一整秒完成时取期末人口、期末距离和期末参加者。它不能消费期末 `availableCrew` 来代表此前一秒。登船磨损捐人、奖船调拨也仍直接使用总 able；接入火控时必须分别改为当前未占岗余员。

另有原有失败边界：`Campaign.advance` 在验证 business native context 前已经提交宏观时钟。新工时路径若沿用该顺序，拒绝的重复/过期工时仍可能增加时间。新路径应先完成身份、范围、工时和秒数预检，再提交任何宏观/业务变更；无扩展旧路径应由既有 oracle 保证原行为。

源码接缝：`modules/naval_simulation/encounter.gd` 的 `_fixed_tick/_launcher_operators/_advance_fire/_apply_damage/_apply_update/reconcile_ships`；`game/runtime/near_field_bridge.gd` 的 `capture/command_context/reconcile/sync`；`game/domain/mingqi/campaign.gd` 的 `advance/_project/_advance_boarding/_boarding_command`；`game/domain/persistence/save_codec.gd` 的 boarding schema 与关系校验。

## 时间与人数选择

锁定整数 **人 tick** 作为账本单位；1 人 tick = 1/60 人秒。人数、tick 和人 tick 均为非负安全整数；对外显示或计算一秒平均人数时才除以 60。火控核心实际有效灭火工作 `Fire.step.workSeconds` 仍是人秒；它与占岗工时不同，不能拿有效灭火工作释放仍在岗位/途中/返回的人员。

tick `k` 的账覆盖区间 `((k-1)/60,k/60]`。Native 在 `tick += 1` 前冻结该区间的起点 roster、人数、占岗与必要的距离见证，再执行当前顺序。伤亡发生在此离散步的右边界：保留起点账和真实期末人口，不用期末人口回写过去。此约定不声称模拟了弹丸 sweep 内每一微秒的人口历史。

| 边界 | 预期占岗/工作 |
| --- | --- |
| 外部命令在 tick 0 接受两秒 launcher 操作 | tick 1…120 的账每步占 4 人；tick 120 端点剩余操作秒数可为 0；tick 121 开始可用 |
| AI 在 tick 1 右边界接受相同操作 | tick 1 的过去区间不占新岗；tick 2…121 占 4 人；tick 122 开始可用 |
| 外部 tick 0 派遣，转岗 120 tick | tick 1…120 均占岗且不灭火；tick 121 首次灭火 |
| AI tick 1 右边界派遣，转岗 120 tick | tick 2…121 转岗；tick 122 首次灭火 |
| tick `k` 内熄灭并开始返回 | 本步原岗位继续占人；其后完整 120 个 tick 返回；返回完成的端点不能追溯释放最后一步工时 |
| tick `k` 伤亡 | 账保留 `totalAbleAtStart` 与 `totalAbleAtEnd`；下一步使用新人口；当前捐人/调拨使用真实期末未占岗人数 |

**已发现但未修复的 AI 边界差异：** 当前 `_ai` 在 `tick += 1` 后立即执行火控命令，随后同 tick `Fire.step` 就递减新派遣的 transferTicks。因此当前 AI tick 1 派遣会与外部 tick 0 派遣同时到岗。锁定修复位置为：仅收集 AI 的辅助 `launch-fire` / `fire-control` 意图，在 `_advance_fire` 之后、`_finish` 之前的右边界实际预检并执行。其第一段占岗、转岗和新弹体运动从下一 tick 开始；最终预检看到本 tick 的真实伤亡和位置。原 AI 舵帆、普通炮口与 RNG 顺序保持原 seam。不能只在 receipt 文案中改名掩盖这一格差异。替代方案是改变全体命令的 tick 约定，影响面更大，本轮不采用。

## 最小 producer / consumer 提案

锁定 Native 配置 `crewWorkAccounting:true`，默认关闭。账通过 **out-of-band、显式启用** 的 `Encounter.crew_work_receipt()` 提供；不增加普通 `snapshot()` 的字段，不生成普通战斗 event，不改变无扩展快照/oracle。方法为不可破坏 peek，返回最后一个真实接受 tick 的冻结副本。锁定 receipt 精确五字段，row 精确十字段：

```text
Encounter.crew_work_receipt() -> {
  version: "crew-work-r1", battleId, tick: k, stepSeconds: 1/60,
  ships: [{
    shipId, totalAbleAtStart, totalAbleAtEnd,
    launcherCrew, fireDutyCrew, availableCrew, unavailableCrew,
    position: {x,z}, velocity: {x,z}, hullAtStart
  }]
}
```

`tick>=1`，区间起点为 `tick-1`；`ships` 至多 128 行，恰好覆盖该区间起点的真实 Native roster，每个 ID 一次。沉没/本步退出 near 的船仍保留这一步的记录；新船从首次真正接受的区间开始记账。`position/velocity/hullAtStart` 是起点几何和存活见证，避免用末端刚进入 36 米范围的姿态补造整个过去 tick 的登船资格。它是离散 60Hz 资格采样，不宣称捕捉连续跨界时刻。Campaign 的阵营、最低留船人数和其他 boarding/work 排他规则仍由原业务 authority 决定。

纯 helper 合同锁定为 `CrewWork.sample(input) -> {ok,row,reason}`。input 精确字段为 `shipId,able,launcherCrew,fireDutyCrew,operational,position:{x,z},velocity:{x,z},hull`；初始 `totalAbleAtEnd=able`。人数为 `0..1000` 整数，launcher 上限 4，fire duty 上限 128。`CrewWork.finish_row(row,able_end)` 只更新实际期末人数，要求 `0<=able_end<=totalAbleAtStart`；不得反写过去工时或改几何。

每步逐船严格满足：

```text
launcherCrew + fireDutyCrew + availableCrew + unavailableCrew == totalAbleAtStart
0 <= totalAbleAtEnd <= totalAbleAtStart
```

row 中 `*Crew` 是该一个 tick 内的人数，数值同时等于本步对应人 tick；不能将它误读为完整一秒工时。launcher 与损管按原优先级裁剪，不能给同一个起点 roster 重复分配。`fireDutyCrew` 包含待命、转岗、作业、返回。无法作业的人口进入 `unavailableCrew`，不能变成可用贡献；起点非 operational 船即使保留人口，也没有可用登船劳动。`totalAbleAtEnd` 是边界人口及检查见证，不参与重算已经冻结的起点账。实际有效灭火 `Fire.step.workSeconds` 由原核心及其独立测试验证，不加入这份严格十字段 row，也不从 duty 人数推导。

`crew_work_receipt()` 不清空账。`capture/reconcile/sync/_apply_update` 和普通命令投影均不得清空、重算或按新 controlsSequence 改写已生产账。本轮只保留最后一个 tick，不新增 drain/ack 协议。Runtime 保持“接受一 tick → 立即消费该 tick”的原循环；若调用方绕过该循环连续推进而漏掉中间账，consumer 必须因 cursor 缺口拒绝，不能用最后一个 endpoint 补足整个区间。批次推进须作为以后显式扩大的合同。

Bridge 给 `native` context 附加 `crewWork` 冻结账与 `validateCrewWork` Callable。后者在原 `validateCurrent` fence 成立时，将 context 副本与该 Encounter 的 `crew_work_receipt()` 真实副本逐值比较；绑定 Encounter 实例、battleId、tick、完整 row 与起点 roster。普通 context 仍验证当前 controlsSequence，工时本体不因同 tick reconciliation 的序号增长而改变。这里的“验真”是内部权威对象及闭包 fence，不声称密码学认证。不得接受 UI/命令自报的人数或只凭形状正确的字典。

普通 context 的 `consumed` 是每次创建的局部 fence，不能独立阻止同 tick 两份 context 重用同一账。锁定 Campaign 可选持久 cursor `crewWorkCursor:{battleId,tick}`；`nearTicks` 已被前面的 reconcile 更新，不能充当该 cursor。启用 accounting 时从原真实 Native fence 的当前 tick 建立 cursor；同 epoch 只接受紧邻的 `cursor.tick+1`。即使没有 active boarding/work，成功推进也提交 cursor，使新建 context 不能重放同 tick。新 epoch 第一真实 tick 必须通过原 native 实例/epoch fence 验真；只重建 cursor 起点，不把旧 epoch 差值兑换为劳动。旧 epoch、同 tick、倒退和缺口均拒绝。

生产提交顺序锁定为：完整预检 → 单一 staged Campaign 副本计算宏观时钟、业务与新 cursor → 原 Native 原子投影 → `_state=staged` 一次提交。本轮不新增 drain/ack；cursor 的同一事务提交就是单次消费凭据。无业务分支也必须先验证工时、秒数和 cursor，再提交宏观时钟/cursor，不能沿旧函数的 early-return 先改时钟。失败投影、拒绝 context、只读 preview、普通 capture 和重复 reconcile 均不改变 cursor；失败后的同一真实账仍可通过新合法 context 重试一次。原命令 fence 可在失败时失效，但不能因此吞掉 Native 冻结账。

所有重复 tick、缺口、未来 tick、旧 battleId、旧 Encounter、同 ID 重复、未知 shipId、缺失 roster、人数/工时越界、NaN/Inf/bool、秒数与 tick 数不符、篡改本体、已消费票据，都在任何时钟/业务提交前拒绝。新工时路径的 `seconds` 必须等于真实 Native 账覆盖的 tick 数 / 60；不得把同一个 endpoint 拿去推进任意秒数。

## Boarding 一秒窗与存档

锁定仅为明确启用新核的 boarding 增加可选字段；旧字段和没有扩展的旧分支保持原样：

```text
boarding.crewWork?: {
  version: "crew-work-r1",
  ticks: 0..59,
  attackerPersonTicksByShip: {shipId: nonnegative_integer},
  defenderPersonTicks: nonnegative_integer
}
```

每接受一步，从其冻结起点见证确定合法参加船。攻击贡献为 `max(0,row.availableCrew-crew.minimum)` 人 tick；守方贡献为 `row.availableCrew` 人 tick。仍按原所有权、距离、相对速度、active work、其他 boarding 的排他顺序分配，一船不能同时贡献给两个 boarding。每步加入真正合格的船；本秒中途退出的已有贡献保留，中途加入的船不补过去劳动。

累计 60 步时，攻击/防守有效人数分别为本窗人 tick / 60，再进入原 `advance/hold` 控制、士气、20 秒与 10 秒脉冲。`elapsedSeconds` 仍只数完整一秒；新分支 `remainder=ticks/60`，`clockCompensation=0`，不再累加浮点 remainder。清空本窗工时后继续下一窗。carry 中按船保留攻击贡献，便于检查资格与磨损来源；不得仅保存期末 participants 后声称它代表整个窗口。

当前边界的资格与历史工时分别使用：过去有贡献不能使已经转岗、伤亡、离场的人现在还能捐人。第十秒磨损捐船必须贡献过本窗、当前仍合法且有未占岗留船余员；守方也须有当前未占岗人。奖船调拨只能从当前未占岗余员扣除，并保持原 minimum/maxCrew/囚犯看守约束。无当前合格人时，本次磨损不凭空找人或借用损管/launcher 岗位。

新建 boarding 在 native `crewWork` capability 存在时立即建立空 `crewWork`，从创建边界之后的第一个真实 tick 记账。旧 active boarding 的不足一秒尚无历史逐 tick 账，且旧 schema 允许任意 `[0,1)` remainder，不能补造或丢弃：锁定保持整个旧 boarding 原分支，直到它结束或主动 cut-lines。不得在下一整秒悄悄切换并清零非对齐余量。

Native policy 增加 `auxiliaryWorkBlockedShipIds`，包含所有没有 carry 的旧 active boarding 的攻击船、参加者与目标船；在它结束前拒绝这些船的 `launch-fire` 和 `fire-control` 转岗。真正被命中的 lazy 火情可以继续燃烧，但分配为 0；用户可先割断缆索再调派救火。恢复得到“旧 active boarding 没有 carry，但其相关船已有非零新火控岗位/在途/返回或 launcher 操作”的状态必须拒绝，不能猜测过去工时。单纯库存或剩余 reload 不等于占岗，不能因它补造工作或抹掉真实冷却。

代价明确：旧 active boarding 在结束/割缆前不能使用新增辅助岗位，即使船已起火。此限制换取旧 arbitrary remainder 与原登船结果不受新工时过渡改写；新建 boarding 走新核，不承受该兼容限制。

SaveCodec 应使用严格可选字段和关系校验：未知字段拒绝；attack map 只含真实、非目标 shipId；每船 attack 与 defender 的人 tick 都不超过 `ticks*1000`；空窗必须空工时；`ticks/remainder`、整数和有限性一致。保存/恢复必须逐值保留 carry，重建 Native 时只重置新的 batch fence/epoch 起点，不清空已经取得的半秒工作。Runtime 当前仍拒绝 active boarding 的安全 checkpoint；codec 往返是状态正确性验收，不代表解除这条安全存档规则。

## 备选方案与取舍

| 方案 | 结果 |
| --- | --- |
| 期末 availableCrew × seconds | 已知在 launcher 截止、转岗到位/返回和伤亡边界失真；拒绝 |
| min(起点人数,期末人数) × seconds | 丢失真实起点劳动，也恢复不了岗位变更和加入/退出时刻；拒绝 |
| 每步浮点人秒 + 补偿 | 可行，但需额外补偿与容差关系；固定 60Hz 下整数人 tick 更直接 |
| 把每步工时写入持久 event/settlement | 增大存档与去重压力，混淆 transient handoff 与经济回执；不采用 |
| 全局把旧登船改成 60Hz 连续争夺 | 会改控制/士气脉冲及旧结果；本轮保留一秒窗 |
| 每人永久身份及亚步死亡时刻 | 可表达更细历史，但超出当前全员桶模型与最小接线范围；不宣称本提案已有此精度 |

## 预先声明的接受标准

以下均为**待实现、待运行**；本文件没有通过数或命令输出。

1. 外部 tick 0 launcher：前两秒恰好 480 人 tick 占岗，tick 120 账仍占人，tick 121 释放；期末 operationSeconds=0 不改变过去账。AI tick 1 发射占 tick 2…121，不能借用 tick 1 的过去工时。
2. 外部 tick 0 派遣 4 人：tick 120 工时仍为转岗、有效灭火为 0，tick 121 才有工作；AI tick 1 派遣的首次工作为 tick 122。4→0、0→4、4→2 的在途重派与熄灭自动返回均验证完整 120 步。
3. 固定伤亡夹具：分别在岸碰/船碰、普通弹丸、火 DOT 同步触发伤亡，账保留真实起点和期末人数；有效灭火取核心结果；下一步岗位裁剪正确；不由终态人口倒推前一秒。沉没不复活、不生成负人数。
4. 同一 boarding 窗跨越 launcher 截止、灭火到位、返回完成、加入/退出与伤亡，分割推进与等价逐 tick 推进得到同一 carry、脉冲和人口变更。包含“期末看起来有余员、实际本秒全程占岗”的失败夹具。
5. 不足一秒的 carry 经 encode/decode 和新 Native epoch 重建逐值保留；恢复后只补真实新 tick，不能整秒补满、清零已有贡献、重复施加士气或重复磨损。严格拒绝篡改的 carry/map/ID/上限/NaN/Inf/bool。
6. 重复/过期/未知 ID/缺步/未来步/旧 epoch/旧 Encounter/篡改票据全部原子拒绝；比较前后 Campaign、Native、宏观时钟、carry、库存、事件、receipt cursor，证明没有半提交。失败 projection 不吞账，重新构建合法 context 可消费一次。
7. 同 tick 多次 `capture/reconcile/sync/command_context` 及 controlsSequence 增长保留同一已生成账；两份独立 context 只能成功消费一次。普通预览/命令不消费 labour。暂停不产账；重开/恢复/离场销毁旧 fence。
8. 旧无扩展 Native snapshot/oracle、原 AI/RNG、炮口 due/reload，以及旧无扩展 boarding 完整结果均保持既有冻结比较。不能只比较新 receipt 的字段数量。
9. 独立实验接回已有 `ship-fire-control` Demo/论文与真实 1650 Runtime：先形成失败夹具和 CPU 账本证据，再取得连续 GPU、真实入口、暂停/恢复/退出及安全门证据。实验 FPS、静态图或源码审阅不替代完整 Runtime 验收。

性能成本尚未测量。候选账本应报告每 tick CPU 时间、临时复制量、未消费窗口上限及有界释放；不能以局部算法成本宣称完整游戏 FPS。

## 精确接线失败夹具提案

下列为读源码后预先写定的待运行测试。可由实现方放入专用 crew-work 测试，且继续运行现有 `test_naval_fire_control.gd`、`test_fire_skirmish_native.gd`、`test_mingqi_live_projection.gd`、`test_mingqi_rules.gd`、`test_mingqi_runtime.gd` 以及原 Native oracle。测试文件存在或本表列出都不代表已经执行。

| ID | 固定操作与必须观察的断言 |
| --- | --- |
| CW-N01 关闭/开启与快照 | 同一个无扩展初态、seed、输入，各走固定 180 tick，分别关闭/开启 accounting；普通 Native snapshot、普通事件、炮口 due/reload 与 RNG 逐步相同。关闭时不产工时账；开启时每 tick 一个精确五字段 receipt，每行精确十字段，snapshot 没有附加 receipt/available 字段。修改返回副本后再次读取与原账相同。 |
| CW-N02 两秒端点 | 起点 able=40，外部 tick 0 成功发射；tick 1…120 每行 launcherCrew=4、availableCrew=36，合计占 480 人 tick。tick 120 endpoint 的 operationSeconds=0，同时其 receipt 仍为 launcherCrew=4；tick 121 receipt 为 launcherCrew=0、availableCrew=40。每步 conservation 等式成立。 |
| CW-N03 AI 右边界 | equipped hostile 在 tick 1 右边界首次成功辅助发射；该步 receipt launcherCrew=0，新的 projectile age=0，operationSeconds=2。tick 2…121 占 4 人，tick 122 释放。AI tick 1 派遣 4 人时，tick 1 receipt duty=0，tick 2…121 转岗，tick 122 才有有效灭火工作；旧普通炮口/helm/RNG 比较保持。 |
| CW-N04 伤亡与重投影 | 固定 tick `k` 在 Native projectile/contact/fire 路径扣人，令起点 40、期末 37。receipt start=40、end=37，原岗位/可用人数不回写为 37；tick `k+1` 起点为 37。连续 `capture→reconcile→command_context→sync` 增长 controlsSequence 后，tick `k` receipt 的全部字段和起点 geometry 仍逐值相同；有 sunk 情况的 unavailable 人口守恒。 |
| CW-C01 无业务重复 | 没有 active boarding/work 时，以真实 tick 1 context 成功 advance(1/60)，确认时钟和 crewWorkCursor 同时提交。新建另一份 tick 1 context，再 advance(1/60) 必须拒绝，Campaign 全状态与时钟不变；不能依赖第一份 context 局部 consumed。 |
| CW-C02 验真与缺步 | 单独篡改 receipt 的 shipId、重复行、人数、position、tick、version 或未知字段；尝试缺 tick、未来 tick、旧 battleId、旧 Encounter、seconds=2/60 而仅一个 tick。全部在宏观时钟/carry/cursor/Native 投影之前失败。遗漏中间真实 tick 后不得用最后一个 receipt 补账。 |
| CW-C03 投影拒绝重试 | 使用真实有效 receipt，但令原原子 project seam 返回失败；比较宏观时钟、人口、carry、settlements、cursor 全状态相同，Native receipt 仍可 peek。重新构建合法 context 消费同一 tick 成功一次，再建 context 重放拒绝。 |
| CW-C04 一秒劳动数值 | new boarding 的攻击船 able=40、minimum=12，外部 tick 0 launcher 占 4 人，其他资格固定。前两个窗口攻击贡献各为 `60*(40-4-12)=1440` 人 tick，即平均 24 人；tick 120 的 endpoint 不能把第二窗变为 28 人。第三窗无其他岗位时平均 28 人。改变 render frame 分组而内部仍每 tick 提交，比较相同控制/士气/elapsed 与 carry；不通过一个末端 receipt 批量补步。 |
| CW-C05 起点几何 | 构造刚在 tick `k` 末从 36 米外进入范围的船；该 tick row 的起点仍在外，不贡献过去劳动，下一 tick 才有贡献。离开、相对速度越界与目标本步沉没各独立覆盖；结果描述为离散采样，不宣称连续越界精度。 |
| CW-C06 磨损与奖船余员 | 在第十秒窗口令某 donor 历史贡献大于 0，但当前人员全在 launcher/fire duty 或只剩 minimum；不得从其岗位扣登船磨损或奖船船员。加入另一个当前合法、有留船余员且有本窗贡献的 donor 才可捐人；验证原 crew-transition 回执、看守和容量关系。 |
| CW-C07 旧局兼容 | 恢复无 carry 的 active boarding，设原 remainder=0.123、clockCompensation 为合法原值。它一直走旧算法到结束/割缆；普通火炮与原结果比较不变。攻击船/参加者/目标出现在 auxiliaryWorkBlockedShipIds；新 launcher/转岗拒绝，lazy 火情为 0 duty。割缆后解除阻挡。旧 active+非零辅助占岗的恢复明确拒绝，不清余量。 |
| CW-S01 半窗恢复 | 新 carry 接受 30 tick，记住每船 attack 人 tick 与 defender 人 tick，encode/decode 后逐值相同。新 Native epoch 第一真 tick 正确验真，从已存 30 步接着累积，另外 30 步只触发一次原一秒脉冲；旧 epoch context 拒绝。Runtime active-boarding 安全 checkpoint 仍拒绝。 |
| CW-L01 暂停与生命周期 | 暂停后反复 peek/capture/reconcile 不增加 tick、cursor 或 carry；恢复后只计新 tick。重开/restore/离场使旧 Encounter context 全部过期；同名 shipId 不能跨 epoch 把旧 row 混入新账。 |
