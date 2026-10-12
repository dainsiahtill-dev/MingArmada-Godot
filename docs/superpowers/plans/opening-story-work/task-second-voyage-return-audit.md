# 第二航程返厦失败：方向选择、帆力与订单边界审计

2026-10-12。只读实际航程和冻结源码；21个阶段/船体组合的零步探针。未改产品、运行完整航程、编辑用户存档或伪造dock/save。

## 结果与主要结论

当前实际第二趟 **20粮按时全交并真实claim**，但没有返厦成功。77 assertions / 2 failures分别为 `actual safe Xiamen docking through authority`、`normal confirmed full-fleet final checkpoint exists`。不能因完整测试与UI检查通过而标记玩法完成。

返厦至少有两种不同停滞：

1. **旗舰、粮船乙：有效路线、满帆，却被控制器指向210°禁航方向。** 在实录末态，原生物理来风180°，210°只有30°夹角，小于35°禁航角；零帆力符合物理。方向选择链有可复现错误：120°抢风侧不湿、240°侧湿，`_tack_course` 的排序仍选120°；随后45米单点避浅无条件加90°，得到210°，没有重新检查禁航区。两船保持210°后既没有推进力，也不会达成tack的“对准原120°且速度≥1.2”计时条件。
2. **粮船甲：返航Rally期间再次成为 `unsafe-endpoint`，且Rally持有者禁止egress。** 从1454.8首次采样到空route，最终仍空路、零帆；`_egress_authorized` 通过 `_approach_authorized` 拒绝任何active order。这个限制真实存在，但不能直接删除；需要正常控制权转换或支持战术owner的独立契约验证。

**不是风向传递取反。** 正式wind、native配置、自动调帆、no-go与已记录sailDebug使用一致的“来风”约定。

## 不可变证据

- 实际记录：`docs/migration/evidence/opening-story/wet-route-egress/journey-second.json`。
- SHA-256：`92b76d0daa85d64cf0ff5c2cecdd4f80e3accd3feecf8843ddbe34fd58a310e4`。
- Encounter记录哈希与审计时源码一致：`5a86e578f41846b90ccd21c74f89518c6994441ce9beb2018bcfefc5fe7698e9`。审计固定副本：`build/port-approach-work/second-voyage-audit/return-encounter.frozen.gd`。
- `ship_dynamics.gd` 当前与本phase `source-freeze.json` 一致：`9aecfd2d6001d382af132ffb88eaeea19c7c27c0bc075a120d26b65f22f95526`。journey的sourceHashes没有单列该文件，因此另核phase清单。
- 探针入口/输出：`build/port-approach-work/second-voyage-audit/return.gd` / `return.json`；实际返程109个stage提取：`return-timeline.json`。

探针读取真实native/core pose、velocity、yaw、rig、crew、hull、draft、cargo stats；同正式HeightField。SnapshotCore只读返回记录；没有campaign或step。调用原生 `_step_sail(...,dt=0)`仅在新建孤立core中计算帆力，不移动船体。历史tack/previous仍未记录；tack明确枚举无/-1/+1，previous只用实测速度/yaw的一帧局部线性近似。active order从真实assign-order命令与对应stage status重建。

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://build/port-approach-work/second-voyage-audit/return.gd
```

输出 `READ_ONLY_RETURN rows=21 acceptedSeconds=0`。本报告的方向/帆力候选没有通过真正返航验证。

## 实际返程时间线

| 全局时间 | 实际事件或状态 |
|---|---|
| 599.8 | 正常接单装20粮，deadline1799.8 |
| 1410.2 | 全20粮已交，真实claim：基础200+奖金50、lost0，银两1165；接受时间810.4秒 |
| 1410.2 | 旗舰navigate `(-60,250)`；甲/乙/快船各收到Rally厦门 `(-306.257096,-38.282137)`；旧protect被superseded |
| 1424.8 | 甲 `(-41.96,332.83)`，船艏106.80°、速度3.5156、满帆，仍持cached有效route；此刻新起点圆已不能重新规划 |
| 1454.8 | 甲首次采样route空/unsafe-endpoint，`(-45.85,339.81)`、船艏167.06°、速度0.1446、零帆；Rally仍active |
| 1506.0 | 旗舰导航到目录回程点 `(131.368233,337.991608)` |
| 1544.8 | 乙首次采样route空/unsafe-endpoint，`(-65.72,330.32)`、160.79°、速度0.0430、零帆；后来重新进入可规划位置 |
| 1633.8 | 旗舰导航到外海回程点 `(-280.516685,235.954131)`；后续再无新的navigate命令 |
| 1799.8 | 快船Rally已completed；旗舰 `(-18.89,338.73)`、227.42°、速度0.7300、满帆；甲仍空route |
| 1859.8 | 乙首次采样到“帆>0.95、速度<0.05、forwardForce=0”，船艏205.77°；route已有效 |
| 1949.8 | 旗舰216.67°，接近禁航边界，速度0.0291、满帆但帆力只106.53N；乙208.89°、帆力0 |
| 2174.8 | 旗舰首次采样到同类满帆低速零推力，210.33° |
| 2249.8起 | 旗舰/乙均接近稳定210°，route有效、满帆、帆力0 |
| 2999.8 | 旗舰、两粮船仍在补给港附近，快船在厦门附近；没有dock命令，没有最终完整存档 |

最终甲/乙货舱均已实卸；此前旧phase“甲留船10粮”结论不适用于这份新证据。

最终关键标量：

| 船 | x,z | 船艏（规约0–360°） | 速度m/s | 帆 | route |
|---|---|---:|---:|---:|---|
| 旗舰 | -40.285865,320.910488 | 210.00000000004 | 0.001668 | 1 | 有效，目标外海回程点 |
| 粮船甲 | -75.590162,339.650351 | 167.065149 | 0.001973 | 0 | 空，unsafe-endpoint，Rally active |
| 粮船乙 | -63.124155,322.687916 | 209.999999744 | 0.001556 | 1 | 有效，目标厦门，Rally active |
| 快船 | -316.165783,-73.339726 | 241.444°附近 | 0.00722 | 0 | Rally completed，nav已清 |

## 风向与原生帆力：逐层核对

1. 实际 `final.naval.wind={direction:{x:-1,y:0},speed:12}`。
2. Encounter构建core时把 `environment.wind` 原样传入；`Encounter.set_wind`同样对每船调用`core.set_wind(wind)`，没有翻转。
3. `ShipDynamics.set_wind`（224）取x及z（无z则取y），所以内部归一化wind为`(-1,0)`；角度180°，表示来风。
4. `_step_sail`（431）使用 `apparent=-normalized_wind*speed-velocity`，因此低速时视风速度指向+x；no-go输入使用视风的负向与船艏点乘，即来风与船艏夹角。
5. 自动调帆使用 `atan2(wind.direction.y*speed+vz, wind.direction.x*speed+vx)-heading` 的半角，与上述约定一致。
6. `_no_go_efficiency`（629）35°以内为0，35–50°按fade平方过渡，50°以上为1；原生hard no-go（361）还禁止无assist时35°以内的前向滑行。无需改物理阈值或符号。

实际末态sailDebug中 `relativeWindDirDotForward≈0.8660254=cos30°`、`trueWindSpeed=12`、`apparentWindSpeed≈12`、sailDeployment1、forwardForce0，直接支持“船艏位于禁航区”。

零dt原生core复算，使用各船实际velocity和相应自动trim：

| 船 | 航向 | no-go efficiency | forwardForce N |
|---|---:|---:|---:|
| 旗舰 | 记录210° | 0 | 0 |
| 旗舰 | 候选240° | 1 | 45653.6571 |
| 粮船乙 | 记录210° | 0 | 0 |
| 粮船乙 | 候选240° | 1 | 47779.4770 |

改航向的两行是孤立物理候选，不是合法转向/抵达证明；实际移动仍需完整转弧、peer、深度及控制预算验证。

## 120°不安全侧如何变成210°稳定停推

当前 `Encounter._tack_course`（607）候选为 `wind_from±PI/3`，即120°与240°。湿深不同的时候，sort comparator返回**候选b的湿状态**，而非候选a应否在前。最终真实位置直接调用该函数：

| 船 | `_wet_ahead(120°)` | `_wet_ahead(240°)` | 无tack分支真实输出 | 所选120°前45米地形height |
|---|---|---|---|---:|
| 旗舰 | false | true | side -1 / 120° | +1.593359m（吃水3.2） |
| 粮船乙 | false | true | side -1 / 120° | +2.244783m（吃水1.2） |

这不是推测符号错误：冻结源码实际函数调用，在不安全/安全各一的输入上选择了不安全侧。具体boolean反例是`a=-1`不湿、`b=+1`湿时，比较器返回`wet(b)=true`，其含义却是“a应排在b前”，从而让不湿a在前。甲1424.8、乙1454.8等返回途中位置也呈相同湿侧排序。

额外直接调用冻结 `_autopilot` 的末态反例（明确假设无tack、保留同一cached route、不触发重规划）：旗舰输出side-1、rudder约`-1.21e-12`、帆1、assist空；乙输出side-1、rudder约`7.66e-9`、帆1、assist空。不是只用手写算式猜desired，而是完整自动舵源码在已观察停推位置再次生成近零转舵/满帆的稳定控制。

之后 `_autopilot`（685附近）只看所选方向前45米的一个地形中心点；不够深时执行 `desired += PI/2`，120°加90°得210°。没有对新方向再次做no-go或完整湿深/转弧评估。末态两船 `_ship_ahead(currentHeading)=false`，所以避船分支不介入修正；最终desired仍210°，与实际稳定船艏几乎完全相等。

稳定反馈：tack仍指向原120°，船实际被避浅补丁指向210°；两者差90°，不满足tack对准≤12°条件；实际速度又远低于1.2，因此tack的45秒换腿/负进展换舷计时不前进。帆继续依据远目标距离开到1，却被物理no-go乘为0。

对于旗舰，现有tack若为-1，成功重规划保留检查 `_wet_ahead(-1)=false` 会清掉；新建又选错-1，重复同一210°结果。乙还因active Rally被禁止保留任何tack，每次无进展重规划都会重新选择。历史tack未记录，无法指定首次出错tick；但这套末态反馈可由精确实录标量重建，且长期210°/零力状态直接可观察。

## Rally权限边界：另一个阻塞，不能混作风向错误

返程命令是真实Rally，而非普通navigate。当前 `_keep_tack_after_replan`（732）遇active order即false；`_approach_authorized`（829）也拒active order，`_egress_authorized`依赖它。

在实际命令/状态重建的孤立fixture里：

- 甲1454.8/2999.8均start-circle false、goal-circle true、Planner unsafe-endpoint、Rally active，egress authorized=false。没有几何评估结果 (`egressClearance=null`)；不能写成“egress几何证明没有出路”，它根本没有获得执行权限。
- 乙2999.8 route正常，假设安全side+1、同goal/firstpoint/draft重算，keep tack=false；仅在孤立fixture移除orders后同调用=true。
- 仅移除fixture订单也会让甲egress authorized变true，但这只是权限反例，**不是合法的玩家动作，更不证明几何plan会成功**。独立命令契约审计负责通过真实navigate API核对取消Rally与可接恢复；本报告不越权给订单恢复加白名单。

独立审计后续回报见 `docs/superpowers/plans/opening-story-work/task-return-command-contract-review.md` 与 `build/port-approach-work/return-command-contract/probe.json`：真实 `navigate(shipId,point)` 可取消Rally，保持motion exact，恢复相应授权；但甲2999.8的8个egress候选仍全部拒绝（3个wind、5个自身当前位置转弧`swept-depth`）。1410.2返程起点的四船直接厦门Planner均通过。因此改用合法navigate有明确权限依据，**不能声称仅取消末态Rally就能救出甲**。这些命令/几何结论来自独立审计回报；本报告未重复执行其探针。

## 最小改进建议

先修已证方向选择逻辑，不改风或物理：

1. 湿/干侧排序以安全侧优先；使用正式单边wet对照验证，不只测两边都湿。
2. 不把固定`+90°`当作总能航行的避浅结果。最终输出航向必须再次满足既有风角、湿深和peer门槛；优先检验已有另一侧安全抢风航向。若两侧或完整转弧/制动范围都不安全，保持安全等待/重新规划，不任意旋转到禁航区。
3. 无论使用哪侧，保留已建立的转向状态边界、原Manual预算、native shore/contact与到港25米/0.75；不要提高推力强行穿过no-go。
4. Rally处理独立决策：若返程本意是日常逐船航路导航，使用既有合法navigate取消订单并交回相应导航权限；若产品要Rally自行恢复，则需明确战术owner/命令抢占/目标一致性协议，不能直接删所有active-order门禁。两者应由命令契约审计和主线程定scope。

最低定点测试：final旗舰/乙一湿一干只能选240°；最终desired不能落入50°安全风角以内；两侧干/peer阻挡/转弧干安全拒绝；保留已有换舷和控制权取消负例。然后以短native段证明真实摆脱210°停推并保持接触和权限约束，最后才值得冻结候选跑完整真实航程。

当前审计没有证明返厦已修好。20粮按时交付/claim是已证成果；安全厦门dock与全船完整save仍是未完成项。
