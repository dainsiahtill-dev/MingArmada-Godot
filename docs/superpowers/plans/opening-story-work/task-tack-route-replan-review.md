# Tack route replan independent review

2026-10-12。独立只读 Spec / Quality 审查。只写本报告；未改产品源码、未重跑全程。CodeGraph 本会话已确认该项目无索引，使用 RTK 精准 fallback。技能沿用 systematic-debugging / requesting-code-review 的证据与契约检查。

## 结论

**Spec PASS（本次最小重规划保 tack 范围）。Quality PASS，无未关闭的本次阻塞发现。** 可以进入协调者负责的完整测试和冻结 first→second 实际旅程。

此批准只证明：相同目标、吃水及有效首航点的成功导航重规划，不再仅因计时器到期而撤销仍安全的未完成 tack。**历史实际 tack 方向未被记录，仍未知；本次测试不是旧失败旅程的完整复原，也不证明第二趟 deadline、卸货或奖励已通过。**

## 审阅输入和冻结身份

- 计划：`docs/superpowers/plans/opening-story-work/task-tack-route-replan-plan.md`。
- 完整 scoped diff：`build/port-approach-work/tack-route-replan/encounter.preedit.gd` 对当前 `modules/naval_simulation/encounter.gd`。
- 基线 SHA-256：`c3a87bed5f145cf7041e1240a2db065233ca629a343d8814db25502406d844e0`。
- 当前 Encounter SHA-256：`5a86e578f41846b90ccd21c74f89518c6994441ce9beb2018bcfefc5fe7698e9`。
- 新测试 `tests/test_tack_route_replan.gd` SHA-256：`02bb49bd5db2d68c3d022daa303d4e04054b4e4dfe511df02f5c142e8dd182fd`。
- Egress SHA-256仍为 `9b63a8ec7cb2dfa115c8f0d411f6e65e1010f53d3a909e72f9f2b7b93b9ee586`；Approach仍为 `6a303f0ff243d446a4200fa06215959991ac1584250f03928764d905eac25df3`。本次 scoped diff 没有这两个模块改动。
- 输入fixture SHA-256：`0092a8c59c2235ccef226292d8d1a3f7bae09208612b99da42d9fce664b74dc5`。

上述当前hash均由本审查读取文件字节独立计算，并与 `build/port-approach-work/tack-route-replan/unit.json` 比对。

## 根因证据及其限制

已读取 `build/port-approach-work/second-voyage-audit/upstream.json`。其使用冻结旧 Encounter `51f6ba1...`，明确标注零步假设分支；历史 tack 与 previous-controller 内态缺失，previous以局部速度/yaw线性重建，tack +1为显式假设。

在989.8标量姿态、假设未完成+1 tack、其余输入不变时：fresh route 保留side+1、rudder+1；只改变 checked 使重规划到期，结果side-1、rudder=-0.570320614。1004.8同样从+1/+1变为-1/-1。两侧150m采样均湿。该单变量反例证明无条件 `erase("tack")` 可以引发非必要反向，不证明历史失败当时必定处于+1侧。

另有1049.8初次选侧排序问题的独立数值证据，按协调者授权不混入本次修复。该时刻原空route会提前return，不能把未执行的选侧分支当成实际历史执行路径。

## Spec检查

当前修改只在 `_autopilot` 成功取得 Planner 结果后、覆盖旧 route 之前计算 `_keep_tack_after_replan`，以有条件保留代替无条件清除。

- 必须存在旧 tack、成功 result、非空旧路线；旧goal与当前goal相同，旧draft与当前实际draft相同。
- 必须仍受控制，无 manualHandling、同目标人工接管标记或有效战术命令。
- 旧/新points均非空，按原45m规则求出的有效首点相同。
- **旧多点路线首点已在45m内时直接不保留**，防止重规划删去已到航点后隐藏航段推进事件。
- 当前保留侧的150m `_wet_ahead` 必须通过；不使用新吃水阈值或地形例外。
- `_tack_course` 的原风变、逆风角、settledTicks、legTicks及完成后切侧逻辑不变。保留旧对象并不冻结计数器；后续正常控制仍可更新或结束它。
- 原45m pop仍清tack；失败、空route、目标/leg/draft变更不保留。新增predicate不改重规划频率、Planner、帆舵算法、速度、力预算或业务deadline。

## 本轮发现与修复

初次冻结版本的 `_effective_route_point` 比较有一个边界：旧points=[距船不足45m的首点,goal]，fresh流程会pop首点并清tack；expired流程重规划直接返回[goal]，比较双方有效首点都是goal，于是保留旧tack，新route已是单点而不再执行pop。计时器到期因此隐藏了本应发生的航段推进。

已直接反馈builder与协调者。最终补充旧多点首点<45m的拒绝条件；新增expired对照回归。原fresh pop与expired省略首点两条路径现在都清旧legTicks。该发现已关闭。

## RED / GREEN与实际覆盖

- 最初 RED：builder会话工具输出为6 assertions / 2 failures、exit1。失败为 `same safe goal/leg/draft replan keeps unfinished tack side` 和 `only checked expiry cannot reverse helm on equivalent leg`。原始RED未落盘，本审查不冒充独立读取该日志；已独立读取旧基线无条件erase及上述upstream单变量数值反例。
- 航点边界 RED：builder报告35 / 1，失败 `expired replan cannot hide an old45m waypoint advancement`；同样为会话输出。
- 最终 GREEN：本审查已独立读取 `build/port-approach-work/tack-route-replan/unit.log` 与 `unit.json`，35 assertions / 0 failures，运行源码hash与冻结文件一致。
- 覆盖同goal/leg/draft仅checked变化、goal/leg/draft改变、失败、空路线、manual/tactical接管、当前侧150m浅区、风变、fresh和expired两种45m推进、计数器保持及原settling更新。
- 另含60次正式 `Encounter.step(1/60)`：实际位移>0.5m，假设+1未完成tack仍存活。这是一秒局部运行，不代表完整航段或旅程通过。

## 剩余接受工作

协调者继续全套回归与同一冻结源码的first→second真实旅程，记录 actual到港、deadline、粮货、奖励及必要GPU证据。旧Egress审查报告保留其独立范围和未完成的功能接受边界；本次保tack批准不会将旧低速连接诊断自动升级为完整修复证据。
