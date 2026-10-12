# 第二航程实际阻塞审计

日期：2026-10-12。范围：只读实际第二航程与现行源代码，另做零步、孤立标量几何探针。没有重跑航程、改产品/测试/存档、操纵正在运行的船体或制造到港回执。CodeGraph 未索引状态由主线程预先核实；本审计使用 RTK 定点源码读取，未声称有 CodeGraph 审查结果。

## 结论

第二航程确实没有完成。粮船乙于全局 **1108.2666666666667 秒实卸 10 粮**；粮船甲仍持有 10 粮，直到全局 **2999.8 秒**保持 `underway`。20 粮实交、结算、厦门返港和全船存档均没有证据。

主要阻塞是 **实际湿船体进入了规划器保守起点圆不能通过的岸边区域，空航线分支关闭全部自动操纵，重复规划也无法离开该起点**。不是先前 25–55 米末端避船恢复问题。甲在约 130 米外停止，`route.points=[]`、`reason=unsafe-endpoint`；起点圆失败，目标圆通过，当前船体本身通过原生九点湿深检查。

不能通过删除起点检查或放宽到港条件解决：**1064.8 秒的真实位置存在中间转向姿态触岸反例**，即使最终朝向和前方直线船体采样都湿。

## 证据身份与边界

- 实际航程：`docs/migration/evidence/opening-story/port-approach-and-voyage-clarity/journey-second-corrected.json`，SHA-256 `0092a8c59c2235ccef226292d8d1a3f7bae09208612b99da42d9fce664b74dc5`。
- 正常接续首航 599.8 秒、金门待接单完整存档；接单真实装 20 粮，复用已付租船，截止 1799.8 秒。执行 `depart`、旗舰目录航点导航、快船 `protect` 粮船甲。没有敌船复活。
- 本轮实际接受 12,000 个 0.2 秒步进，共 2400 秒；记录为 67 assertions / 5 failures。163 个阶段包含每 15 秒采样；最终 `canSave=false`，`saveReason=save-fleet-not-anchored:mingqi-1650-flagship`。
- 所有本轮新伤亡/沉船回执为空；甲、乙各有 20 名可用船员、最低要求 8，船体和帆均为 100。不能把停滞归于伤亡或缺员。
- 早先 `journey-second.json` 的命令键类型失败不属于本次航行证据；GUI 捕获只证明画面，本报告没有用其替代第二航程。
- 本报告分析时，实际记录里的 Encounter / Bridge / Catalog 哈希与源文件一致。Encounter：`51f6ba1eca84b5c925000c5db7d8a33b2718f9d770613263f9548e28c7d68faf`。Planner 没有单列在 journey 的 `sourceHashes`，但 `source-freeze.json` 的 `files` 与分析时源码均为 `6a20aa8c9f557afb67ad334055fe80df05b6494e3693eb1a368571876de0f486`。后续实现应作为新候选另留证据。

## 实际时间线

| 全局时间 | 粮船甲实际状态 | 业务结果 |
|---|---|---|
| 599.8 | 金门原船位，正常装 10 粮；乙另装 10 粮 | 合同 active，deadline 1799.8 |
| 944.8 | `(106.85089,253.61786)`，目标 `(-60,250)`，速度 1.70054 | 目录段投影已切至第二段 |
| 1034.8 | `(24.76846,417.56712)`，速度 1.38762，目标 `(-60,250)`；现有 route 非空 | 当前圆安全域仍可规划 |
| 1049.8 | `(11.16292,429.06448)`，目标 `(-60,320)`，距港 130.22758，速度 1.00067；route 首次在采样中为空 / unsafe-endpoint | 快船 protect 同阶段首次显示 blocked / unsafe-depth |
| 1064.8 | `(9.52423,429.84922)`，速度 0.01142，零帆、零舵，空 route | 甲未到港 |
| 1108.2667 | 甲仍未到港 | **乙真实 shipment-arrived 回执，10 粮** |
| 1109.8 | 甲距港 130.45243，速度 0.00887，帆舵 0 | delivered 10 / lost 0 |
| 1799.8 | 甲距港 132.63830，速度 0.00227；空 route 持续 | 截止点仍未完成，之后有甲 shipment-late 回执 |
| 2909.8 | 同一岸边缓慢漂移，桥接目标重新变为 `(-60,250)` | 最近航段投影回到 leg 1；未解锁空 route |
| 2999.8 | `(14.305785,431.149896)`，heading 2.77846017，速度 0.001798，距港 133.69985，距当前中间目标 195.79743；甲载粮 10 | active / in-progress；无 claim，无厦门 dock，无最终存档 |

最终评估的 `reward=100` 是未完成评估中的金额计算，**不是已结算收入**；`casualties.settlementReceipt=null`，命令列表里没有 `claim-convoy`。

## 可重复的源码路径与门槛

1. `Catalog.DATA.routes["kinmen-supply-deep"]`：金门 `(282.149929,107.485687)`、`(131.368233,337.991608)`、`(-60,250)`、补给港 `(-60,320)`。目录最小深度 8；甲载 10 粮的实际吃水为 1.4。
2. `Campaign.locate_route`（campaign.gd:103）按当前位置对各段投影后选择最近段，没有已通过段的单调约束。`NearFieldBridge._apply`（near_field_bridge.gd:51）把 `leg+1` 交给 native，并只在距离中间点 18 米以内提前切下点。实际远距投影会切至末段，也可能再切回；这是本次记录里的次要行为，**并非空 route 永久停机的必要原因**，因为两个目标的圆都湿。
3. `Encounter._autopilot`（encounter.gd:640）创建/重试 `Planner.plan`。`wet_route_planner.gd:14` 的 `not _wet(start) or not _wet(target)` 直接返回 `unsafe-endpoint`；这里 `_wet` 要求半径 `hypot(length,width)/2+8` 的整圈采样都湿。
4. 甲为 36×10 米商船，半径 **26.681541692269406 米**。正式地形证明起点圆碰到岸边，而目标圆通过。实际朝向下的九点船体仍湿，因此这里的 unsafe-endpoint 不等于整船已经搁浅，也不等于港口太浅。
5. `_autopilot` 的 `current.points.is_empty()` 分支（约 655）没有已拥有 approachRecovery 时，直接 `rudder=0; sailDeployment=0; return {}`。它发生在 `_tack_course`、普通低速 `_navigation_steerage` 和 `_final_approach_clear` 之前。甲没有 approachRecovery，无法靠后面的恢复逻辑离开；重试间隔最终封顶 1800 tick / 30 秒，仅重复拒绝原位置。
6. `_final_approach_clear`（约 711）本身还要求 25 < distance ≤ 55、速度 ≤ 0.75、单末端 waypoint 等。本例 130 米外、route 空；扩大该门槛不能修复上游提前 return。
7. `Campaign._inspect`（campaign.gd:498）真实到港仍要求距港 ≤ 25 米且速度 ≤ 0.75；`_arrive` 才卸货/写 receipt。甲从未满足距离条件，业务拒绝正确。

风向为 `(-1,0)`、12 m/s；native no-go + fade 合计 50°。最终甲直接朝当前目标的风角 **67.696°**，无前方船；它不是被直接迎风禁止或船首障碍卡住。早期航行确有折返、避船和换航点，但历史 tack / previous 内部值未记录，不能从 15 秒采样重建每一帧实际转舵原因。

## 零步几何探针

入口：`build/port-approach-work/second-voyage-audit/gates.gd`。结果：同目录 `gates.json`，141 条记录，`acceptedSeconds=0`。分析辅助：`summarize.py` / `recorded-stage-summary.json`。探针新建孤立 Encounter 的物理配置，使用只读 SnapshotCore 提供每阶段已记录 pose、velocity、yaw；正式 HeightField / reference geography；没有 campaign、adopt_save 或 step。

可复现命令：

```powershell
rtk proxy python C:/Users/dains/Documents/Git/ming-armada/build/port-approach-work/second-voyage-audit/summarize.py
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://build/port-approach-work/second-voyage-audit/gates.gd
```

| 实际记录时刻 | 起点圆 / 目标圆 | 当前九点船体 | 圆内首个违规地形样本 | 原地直转全部 181 个姿态 |
|---|---|---|---|---|
| 1034.8 | 湿 / 湿 | 湿 | 无 | 湿 |
| 1049.8 | **不湿** / 湿 | 湿 | `(-11.51862,434.38294)`，height +7.44575 ≥ -1.4 | 湿 |
| 1064.8 | **不湿** / 湿 | 湿 | `(-13.15731,423.16768)`，height -0.25152 ≥ -1.4 | **不湿** |
| 1109.8 | **不湿** / 湿 | 湿 | `(-12.93989,423.56336)`，height -0.92288 ≥ -1.4 | **不湿** |
| 2999.8 | **不湿** / 湿 | 湿 | `(-8.37576,436.46835)`，height +0.33174 ≥ -1.4 | 湿 |

新建 Planner 对上述坏起点再运行，仍返回 `unsafe-endpoint`。最终直接目标航向下的 0/15/30/45 米原生船体采样均湿，前方无船。这个结果仅区分圆包络和有向船体，不授权自动取消检查。

存在值得实现验证的**几何候选连接**：2999.8 从实录位置向南 32 米到 `(14.305785,399.149896)`，course `-PI/2`。风角安全；181 个原地转姿态、每 0.5 米平移的九点船体采样通过；从此节点到 `(-60,250)` 使用原 Planner 可规划。1049.8 的同类南向节点 `(11.162922,397.064485)`也通过。

**反例不可省略**：1064.8 向南 32 米的平移和后续 Planner 可通，但当前姿态转到南向的中间船体样本不湿；枚举八个相邻 32 米节点，没有同时通过风角、转弧、平移和后续 Planner 的候选。不能将末端朝向湿、直线湿或某个时刻成功当成普遍安全逃脱证据。

这些候选尚未计算完整漂移、制动、转弧误差、连续 peer 运动包络；**不是物理执行成功、实际抵达或完整航程成功证据**。

## 排除项与次要发现

- 末端 25 米判定：甲始终 130 米外；扩大到港半径会伪造交付。乙的真实到港回执证明原条件可达。
- 末端避船死锁：甲停滞阶段 `_ship_ahead=false`，无恢复 owner；空 route 提前返回，未进入末端避船分支。
- 全局 deadline 太短：乙在接单后 508.4667 秒到达；甲直到接受额外 2400 秒仍停滞。提高 deadline/运行预算只推迟暴露。
- 伤亡、缺员、坏帆、货损：甲健康，20/8 船员、10 粮完整，lost 0；这些权限/资源无需修复。
- 目标本身 unsafe：两种实际 target 的圆通过，失败在起点。不能改港口坐标以掩盖。
- 快船护航：`protect` 无威胁时取被护船 heading 的垂直 60 米点。1049.8 首次记录 `blocked/unsafe-depth`；`_safe_point` 拒绝战术点后订单停止，快船后续漂移。这是可见的另一项玩法限制，但甲此后前方无船，甲规划空路原因仍是自己的起点圆。需另做护航站位选择验证，不能据此忽略战术深度检查。
- 记录细节：`navigation_diagnostics` 中 route 字典不是 deep duplicate，`stamp` 到最后序列化期间 `checked/distance` 等可被后续 tick 更新；因此本报告不用这些字段推断精确失败 tick、重试次数或历史 controller 状态。逐阶段真实 pose/core motion/业务回执与最终空 route 足够证明上述死锁。未来 QA 应对瞬态诊断 deep-copy。

## 最小安全修复建议与验收

为**规划失败的湿船体起点**增加独立、有界的有向脱离连接，使船通过真实控制移动到现有 circle-safe planner 的安全域，再交回原 Planner。保留正常规划算法、港口坐标、目录最小深度、25 米 / 0.75 条件和原生接触处理。

必须同时证明当前完整船体、转弧、实际平移、漂移/制动、风向和动态 peers；拒绝 unsafe target、干船体、干转弧、缺员/死亡/俘虏/锁定或手动控制。只调用已有船型/船员/船体缩放的操纵预算，短时受控并持续复核；目标变化/权限丢失立即撤销。没有安全连接时保持安全等待并明确阻塞原因。不能扩大推力/转速、强行 pivot、teleport、heal、改货物/到港回执，也不能简单放开 `_wet(start)`。

最低验证顺序：先 exact 1049.8 / 2999.8 正向几何与 native 控制用例、1064.8 干转弧拒绝、移动 peer/低刹车/目标太浅/权限变化反例；再原生实际移动到安全域、回归普通规划和到港；最后冻结新候选，从同一真实首航 checkpoint 重跑正常第二航程，要求20粮真实实卸、真实终态claim、全船厦门dock与正常Codec完整存档。不能把本报告零步探针或原有105/105测试当成新修复验收。

本审计仅完成定位和候选建议；实际第二航程仍失败，后续产品修复与新证据属于另一个候选。
