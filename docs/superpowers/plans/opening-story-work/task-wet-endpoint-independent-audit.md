# Wet endpoint independent audit

2026-10-12。只读架构审查；本轮只写本报告。使用 systematic-debugging 与 requesting-code-review 的证据/契约检查。未修改源码、未运行全程、未推进物理。CodeGraph 对 `C:/Users/dains/Documents/Git/ming-armada` 返回未索引，以下源码使用 RTK 精准 fallback。

## 结论与证据等级

**已证根因链：起点圆形包络失败，自动驾驶在可用的局部船体检查前停止。** 船体当前满足 native 九点吃水检查，不代表其外围所有朝向的保守规划圆都满足检查。当前接口仅接收位置、尺寸、terrain、sea level，不接收 heading/velocity/yaw/peers，无法表达从特定真实姿态驶离狭窄位置的合法动作。

最小推荐：保留后续圆形安全域与 A*，增加专用、受控、有限的有向起点连接。先证明真实姿态至一个圆形安全节点的转向和位移可行，再衔接现有 Planner。不能直接删除起点 `_wet`、缩小全局 radius、将 `_feasible` 通过视为完整动作安全、或放宽 final approach 距离。

数值证据来自并行审计员的 `build/port-approach-work/second-voyage-audit/gates.json`，本审查已读取核对。其 mode 明确为记录标量的零步几何探针；historical tack/previous controller 内部状态不可恢复。几何可行不等于物理逃脱或抵达已证。

## 实际源码链

- `modules/naval_simulation/navigation/wet_route_planner.gd:13-18`：radius = `hypot(length,width)/2 + 8`；起终点任一 `_wet` 失败即 `unsafe-endpoint`。`_wet` 每 4m 采样圆内地形，严格要求有限且 `height < sea_level - draft`。`_segment` 每 4m 检查相同圆。A* 32m 网格；节点、边、平滑共享一百万采样预算。
- `modules/naval_simulation/encounter.gd:644-657`：规划失败写入空 points，指数退避重试上限 1800 tick；空路径直接零舵、收帆并返回。因此之后的 steering/recovery 无机会执行。重试同一无方向位置门槛不会使被锁船主动驶离。
- 当前文件没有 `_safe_heading`。实际相关函数为 `_wet_hull`（252）、`_feasible`（635）、`_navigation_steerage`（750）。`_wet_hull` 用当前方向的船首/中/尾乘左/中/右九点，阈值与 draft 不变；`_feasible` 检查风、前方近船及 0/15/30/45m 船体；`_navigation_steerage` 检查每 10° 原地转弧及 15/30/45m，但不包含真实转弯漂移和预测邻船时域。
- `Encounter:519-520,768-818`：每次真实 core.step 后 `_shore` 按平移与旋转扫掠细分，九点船体阻挡，二分安全比例，再校正位置、消除向岸速度/角动量。`modules/physics_engine/ships/ship_dynamics.gd:275-286` 的 contact impulse 根据质量、惯量、接触臂移除法向接近速度。此保护应保持；碰撞拦截本身不证明规划动作可顺利完成。
- `Encounter:711-749`：现有 final approach 要求授权、25~55m、速度不超过 0.75、单点路径、目标不变，并调用带刹停/漂移/转弧/邻船预测的 `Approach.assess`。本例距离远大于其授权范围；不能扩大该范围来掩盖 endpoint 问题。可复用几何原语，不能继承其“接近最终目标”的业务含义。
- `game/runtime/near_field_bridge.gd:56-62`：从 `campaign.locate_route` 最近线段取得目标；业务中间点只在 18m 内前进。`game/domain/mingqi/campaign.gd:103-114` 每次重新最近投影，未要求 leg 单调。因此目标可能随漂移变化；实录确有 1049.8/1064.8 的 `(-60,320)` 与 2999.8 的 `(-60,250)`。具体切换边界本审查未数值验证，不能将它宣称为唯一根因。
- `campaign.gd:508` 仍要求最终港 25m 内且 speed <= 0.75 才实际抵达。连接点、nav target 变化都不得触发或伪造 arrival/reward。

## 数值已证

grain-a draft=1.4，Planner radius=26.681541692269406。

| 实录时刻 | 位置 x,z | 目标 | 当前九点船体 | 起点圆 | 终点圆 |
| --- | --- | --- | --- | --- | --- |
| 1049.8 | 11.1629218019,429.0644846160 | -60,320 | 湿 | 干 | 湿 |
| 1064.8 | 9.5242306989,429.8492221626 | -60,320 | 湿 | 干 | 湿 |
| 2999.8 | 14.3057849963,431.1498958736 | -60,250 | 湿 | 干 | 湿 |

2999.8 首个圆内坏点为 `(-8.3757566959,436.4683541814)`，height `0.3317353468`，高于所需 `-1.4`；实际 heading `2.778460172`，speed `0.001798245`。

2999.8 南向节点 `(14.3057849963,399.1498958736)`：风角通过，181 个原地转向姿态、每 0.5m 平移九点采样均湿；从节点至 `(-60,250)` 的原 Planner 成功。1049.8 对应南向 32m 节点也有几何连接及后段 Planner 成功。

**必须保留的反例：1064.8 南向 32m 平移采样湿、后段 Planner 成功，但转弧采样干；八邻居无完整几何通过。** 不可凭节点安全、直线湿或当前 hull 湿批准转向。以上全部未包含 drift/braking/peers 动态包络，未实际推进。

## 最小实现契约

1. 常规 planner 路径及 fail-closed 预算保持。只对已区分的“start 圆失败、target 圆通过、真实当前姿态湿”尝试 bounded connector；真正干船体、干目标、非有限值、超预算仍拒绝。起点检查失败原因应可区分，不能拿任意 `unsafe-endpoint` 通用解禁。
2. 从当前真实 heading、velocity、yawRate 建立候选。完整转弧、平移扫掠及制动/横移/帆力余量必须通过当前吃水；预测邻船也必须通过。已有 `Approach` 原语可供复用，但 authority 与 distance 规则单独保持明确。仅几何九点采样不构成连续整块船底的数学无碰撞保证，应与现有 native 契约表述一致。
3. 使用已有受船员/船况约束的 steering/braking，不设置位置或 heading、不停钟、不传送。每次真实 step 保留 `_shore` 和船间 contacts；动态环境或控制变更后重新验证，失败即安全制动/hold。只有实际进入可安全衔接的圆形域才交还普通导航。
4. **连接首点不能走普通的 `<45m` 自动弹出分支**（Encounter:654）。32m 连接点一创建就会被跳过。平滑同样不得删除受保护的初始连接。完成判据应检查真实当前位置的圆安全和剩余连接/后续路径，而不是孤立距离阈值。
5. 连接状态绑定 navigation target、draft、真实控制所有权；manual/order/capture/lock/disabled/sunk/失去船员或船况、目标变化等立即失效。重算和尝试次数有界。bridge 最近投影导致目标变化时不得继续旧目标的连接。
6. 不改变 terrain、sea level、draft、depth、18m 业务中间点规则、最终港 25m/0.75 抵达条件、货物和奖励。修复需要以真实移动回到原业务路线结束。

## 必要测试边界

- 红例重现：2999.8 原 Planner 仍报 start unsafe；新连接在动态许可成立时真实连续 step 有进展并到圆形域，之后原 Planner 接管。必须报告实际位置、heading、最小吃水余量、contacts/hold、target 和控制状态。
- 对照反例：1064.8 当前湿/直线湿/后段可达但转弧干；不得放行同一南向动作。另覆盖干当前 hull、干目标、窄条岸、NaN/Inf、预算耗尽。
- 动态边界：有残留 velocity/yaw、刹停不足、moving peer 横穿、peer 转向/controls 改变、失去 authority、draft 增大。已批准连接须因新风险收回；不允许靠岸线不断夹停形成“通过”。
- 生命周期：32m 连接不被45m pop或平滑吞掉；到安全域才切换；失败/重试不无限创建状态；navigation 从320改250后旧 connector 失效；手动接管不能被恢复逻辑覆盖。
- 现有 normal route、unsafe endpoint、预算与 deterministic fixture 继续匹配；`tests/test_naval_simulation.gd` 的原 Planner/reference checks 不应为迁就恢复而刷新预期。
- 最终业务接受：另由协调者运行授权的真实第二趟，证明到港卸货与奖励成立；本报告、零步几何候选、短程恢复均不替代全程接受。

待后续实现到位，再做 Spec/Quality 与连续 step 证据复核。本报告不宣称修复完成。

## 实现复核记录 A：未冻结初稿

审阅 `task-wet-route-egress-plan.md`、新 `wet_route_egress.gd`、Encounter 接口及初始测试。此节记录发现时状态；源码仍由 builder 修改，不构成最终批准。

Spec 初步符合：专用 `wetRouteEgress` owner 独立于普通 points，现有 Planner 起终点和45m规则未删除；仅实际当前位置 Planner 成功才交还；独立 clearance 包含 measured yaw、制动余量、有限 connector、连续移动 peer SAT，每 tick 复验，失败 latch hold。未扩大 final approach。

已直接提交 builder 的待修事项：

- **P1，真实 footprint 被扩大九点采样漏掉。** 初稿只调用 `Clearance._wet` 检查 padding 放大矩形的九点。扩大后的位置不是原九点的超集，局部浅斑可命中真实船角但避开扩大后的九点。必须保留真实 footprint 并验证运动不确定域；增加薄浅斑反例。不能据扩大九点宣称连续整块区域已覆盖。
- **P1，行进阶段取消导航残留旧输出。** 初稿 `navigate(null)` 删除 owner，未先清旧 connector 帆/舵；下一 step 因 owner 消失且无 navigation，跳过清理。若正在0.1帆量行进，会保留旧输出。初始撤销测试只在 acquisition 后帆为0的转向阶段执行，无法发现；应加行进阶段取消与权限撤销测试，并保持明确新人工 controls 的优先权。
- **测试事实错误。** 1049.8 原始 speed=1.000673387，超过新0.35进入门槛，不能要求真实状态立即 acquire。应检验真实高速被拒绝；另设明确标注低速变体以隔离几何，不把变体称为原始实录。
- **Quality，重试预算。** 空 unsafe-endpoint 每 tick 直接重跑包含多个 Planner 的候选搜索，绕开已有 retryAt；应采用有界重试/共享采样预算并留确定性失败状态，避免每船每秒60次复杂重规划。

QA 源检查：两个 voyage 驱动的 diagnostics 末尾 `duplicate(true)` 正确冻结 owner/clearance/route；source inventory 包含新模块。continued driver 另加“首趟证据必须包含新模块 hash”硬 gate，符合必须重跑冻结首趟的证据要求；观察到的改动没有改变航行逻辑。尚未核对最终冻结 patch/hash。

## 实现复核记录 B：冻结低速候选

独立比对 `build/port-approach-work/wet-route-egress/encounter.preedit.gd` 与当前 Encounter 的完整 scoped diff，读取新模块、测试、unit JSON/log，并再次计算磁盘 SHA-256：

- `modules/naval_simulation/encounter.gd`: `c3a87bed5f145cf7041e1240a2db065233ca629a343d8814db25502406d844e0`
- `modules/naval_simulation/navigation/wet_route_egress.gd`: `9b63a8ec7cb2dfa115c8f0d411f6e65e1010f53d3a909e72f9f2b7b93b9ee586`
- `tests/test_wet_route_egress.gd`: `241a2dc9bc15a962cd0b4523423d77c84b3b4a857c8e8b51656d257782f57486`

**Spec：低速连接机制的安全与作用域审查通过；“实际第二趟已修复”的接受未通过。** **Quality：此冻结版本未留本次已发现的 P1；完整动态成功证据仍缺。** 该结论允许协调者继续真实旅程验证，不能据此宣布导航问题完成。

已关闭的实现问题与源码依据：

- 当前真实姿态先以无 padding 的九点检查，拒绝 `current-depth`；随后每个转弧/平移 pose 检查真实九点、各点的3×3不确定域采样及扩大矩形九点。新增 nonzero yaw + 当前真实船角薄浅斑反例，避免转弧采样网格绕过精确当前 heading。
- `navigate`、policy.navigation reconcile 取消旧 owner 时清旧 rudder/sail/recovery；实际权限、draft、goal 失效同样清理。人工接管先对旧 goal 设置 `egressRevokedGoal`，再应用新 controls；旧空 route 不再覆盖明确新人工帆舵。新 navigation 或 policy目标切换清 fence 与 retry 状态。
- 1049.8 保留真实 speed=1.000673387，超过0.35进入门槛时拒绝；1064.8 干转弧也拒绝。试验性的高速 `assess_stop` 已从最终源码删除，未扩大为未经证明的停车或转向能力。
- 候选搜索失败后重试间隔120tick；正常 Planner 的旧 retry/预算保持。owner 连续复验，失败或超过259秒 latch到零舵收帆制动；危险消失不会自行开帆。
- 执行 speed cap=0.35，帆量<=0.1；转向误差>1°、速度达到cap或角速度>0.005时收帆制动。进入保持低速；续期 assess 对0.05速度瞬时余量仍检查制动预算。力与角加速度仍由原 Manual/Native 限制。
- owner 的 node 与普通 route.points 分离，因此32m连接不会被45m pop或路径平滑删除。交还必须从真实 current position 调用不变的 Planner 成功，恢复原目标；未新增位置/heading设置、业务抵达、奖励、吃水或地形更改。

当前已独立读取的运行证据：

| 证据 | 实际支持 | 不支持 |
| --- | --- | --- |
| `build/port-approach-work/wet-route-egress/unit.json`、`unit.log` | 当前 Encounter/module hash匹配；61 assertions、0 failures；exact高速/干弧拒绝、moving peer、薄浅斑、权限与控制交接、fresh hazard hold | 完整连接平移、handback或整趟成功 |
| 同一 unit 中300 native ticks | 2999.8标量fixture真实推进5秒，heading从2.77846转至3.06446，所有检查到的实际九点船体湿；owner仍active、无hold、最大speed约0.0004415 | 不能写成“已驶离”；位移接近零且尚未handback |
| `recorded-windows.json` | 96个独立记录姿态的南向32m检查，首个通过是2489.8，padding约1.8602979 | 不是从1049.8连续推进到2489.8；也不是八方向最早可能成功时间 |
| builder报告7731tick handback | 最后显式current-depth补丁前加载的候选曾有物理成功路径；builder确认已含81点邻域，可指导下一验证 | 未独立读取该运行输出且非当前冻结hash，不能作为最终候选通过证据 |

builder另报告旧 approach 回归132/0；本审查未独立读取该输出，不冒充独立复跑。未重复全程或native长窗测试。

剩余接受门槛：从1049.8真实位置、速度、角速度开始保留原 `_shore`/contact，自然降速后由同一冻结候选实际获取连接并handback；需记录全过程是否真实湿、是否受岸线夹停、帆/速度上限、目标及控制权。随后才由协调者以冻结 first→second 正式旅程证明deadline、卸货和奖励。审查时 builder 报告自然推进600秒仍未获取，长窗尚未结束，因此此处明确保持功能接受未通过。长run若在最后补丁前启动，必须标记启动时实际加载源码版本，不能用结束时磁盘新hash倒填。

采样边界：3×3不确定域加密仍是数值采样；不宣称对任意尖峰 terrain 的连续数学覆盖。原native每步岸线扫掠与contacts继续承担真实位移最后约束。该限制须与现有九点船体契约一起理解，不能把“预测通过”解释为取消物理碰撞保护。

自然演化探针另有输入限制，已直接告知builder与协调者：`natural.gd` 继承测试 fixture，fixture 显式将所有船 `native.sailDeployment=0`，再恢复记录 velocity/yaw。实录1049.8旗舰的 nativeDiagnostics 为 sailDeployment=1、rudder=1，因此不能称“完整原始peers controls复现”；甲船位置、速度、角速度真实，peer初帆和旧controller内态并不完整。该长窗是隔离标量fixture的真实native诊断；正式冻结first→second才具有完整业务运行上下文。无需把此诊断包装成全程证据。

后续校正：上一段记载本审查当时读取的 fixture 文本，不能据此确定已经启动进程加载的版本。builder 随后说明 natural 在05:37:27启动前已移除帆0覆盖，保留peer原帆舵；更早2999探针才统一清帆。本审查未取得该进程启动时的独立源码快照，故**撤回“该 natural run 已证peer帆归零”的判断，加载时帆量版本未独立确认**。旧controller内态缺失、最后current-depth guard前加载、不是正式campaign重放的限制不变。builder随后报告自然推进800.0167秒仍未获取，由协调者停止；该结果仍不能作为修复成功证据。
