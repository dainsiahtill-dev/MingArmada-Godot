# 操船与炮战参考实现验收

日期：2026-10-11。对应 `2026-10-11-naval-reference-implementation.md` Task 2。本文记录本任务实际 headless 证据；全套回归、主产品存档往返和 GPU/交互画面由主线程集成验收。

## 学习依据与本作选择

只读学习来源：`C:/Games/Pirates-REA-Reference-20261011/naval-study/deep/README.md`、`deep/battle-details/DETAIL.md` 第 2–5 节、同目录 `battle_state.py` 的装填/分批发射、`naval-study/reference-code/naval_reference.py` 的 `ship_step`。原作的整型转向惯性、船型响应、转弯损速、船员对装填的作用值得学习；内部速度 8000/6000 和半正弦高度不是本作米秒弹道参数。

原作部分装填采用二次进度，且 pending 的最后一颗可能重新进入首发分支。这里没有复制该随机重入，也没有新增部分装填存档字段。本作沿用有限炮组、每舷独立 cooldown 与单次耗弹，用确定性分批间隔提升可读性。仍使用 `9.81m/s²` 重力轨迹、原 moving-box swept collision、真实命中一次结算；没有表现层命中/减员副本。

## 实现与合同

- `manual_handling.gd` 的原 `build` 参数默认、目标角速度、加速度上限、船员/船壳/风帆系数保持。末尾可选 `responsive=false`；明确开启时返回内部 `responseRate=6.0`。`sanitize` 接受有限 4–8/s，否则拒绝整个请求。旧请求无该字段仍使用 4/s，保持冻结轨迹。新控制器仍在原 dry-yaw-inertia × acceleration × power 预算内输出力矩。
- `manual_sailing_assist.gd` 仅延长货物增加惯性后的恢复时间预算：重舰基准 24s、其他船 18s，乘 `1 + clamp(cargoMass / dryMass, 0, 1)`，故最多 48s/36s。只计唯一接受时间；仍需一秒真实迎风低速停滞、原安全水深路径检查、逃离 50° 风区、两秒渐进复帆。手动舵、收帆、手调帆和暂停依然立即接管/取消。
- `cannon_system.gd` 提供实际 launch solution、装填/有限齐射参数、保护船射道检查、HUD 状态派生。`encounter.gd` 仅在批准的两个配置标志下调用增强 helper；无标志维持旧算法。
- 增强齐射健康小炮组间隔 8 ticks（0.133s），八炮重舰 9 ticks（0.150s），末炮分别在 0.267/0.400/1.050s。间隔随船员不足乘 `1 + (1 - crewFraction)`；炮数不增加、不随机重入。弹种在触发时锁定；中途切换不改已排队炮弹。
- 正常装填沿用 `7s × [1 + (1-crewFraction) × 1.5] × reloadMultiplier`。极端装备倍率的下限为本次最后一炮时间再加 0.35s，避免装填先结束导致齐射重叠。每个被接受齐射仍只扣一次对应库存，两舷装填独立；没有船员不可发炮。
- 发炮前检查所有炮口与葡萄弹五条实际 launch velocities，预测保护船线性运动，使用同一 moving-box slab sweep；触发被挡时原子拒绝，不扣库存、控制序号或 cooldown，不新增事件。每个延迟炮再次按当前权威状态检查，友船进入射道则抑制该炮。
- 保护船查询来自 `Encounter._enemy`，保留连续遭遇的敌对政策；中立船也受保护。预测最多 8s、0.1s 一段，重力 chord 最大垂向误差约 0.013m，包围盒加 0.2m 余量；先解析排除远射道，避免 HUD 对清空舷侧做大量 sweep。这里只读预测，不推进船/炮弹或游戏时间。
- `naval_practice_runtime.gd` 的真实练习构造明确开启两个标志；已有 notice 字段提示迎风恢复/停止。`naval_practice.gd` 接入炮况、当前弹种用途和射程、按钮 disabled 与 tooltip。表现事件和权威快照没有新增字段。

## 主线程接入接口

```gdscript
# 必须在新建/载入/重建同一 live runtime 时一致传入。
configuration.referenceHandling = true
configuration.referenceGunnery = true
var encounter = Encounter.new(configuration)

# 同一 canonical snapshot 可直接派生显示状态，无写入。
var advice = Cannon.broadside_status(native_snapshot, player_id, "starboard")
# Continuous Mingqi 使用真实 packet.runtime.policy；三参数调用仍兼容。
var scoped_advice = Cannon.broadside_status(native_snapshot, player_id, "starboard", policy)
```

`referenceHandling/referenceGunnery` 为可选 bool，错误类型使 reset 原子拒绝；保存在 Encounter.config，不导出额外快照字段。`reset()` 默认沿用当前 config。外部 save loader 如果重新 `Encounter.new`，须由同一 live factory 重传两个标志。主线程负责 LegacyRuntime/MingqiRuntime 的显式 live 工厂开关及 adopt_save 一致性；不能让载入后的同一游戏退回旧手感。旧 fixture、旧裸构造和旧快照仍可直接读取。

`broadside_status(native, ship_id, side, policy={})` 正常返回 `phase,label,rangeMeters,arcDegrees,targetId,reloadSeconds`；不可用返回 `phase,label`。禁用阶段：`unavailable/no-guns/not-operational/reloading/no-ammo/blocked`。`ready/out-of-arc/out-of-range/no-target` 可保持按钮允许空水发炮，label 给出目标、±25° 调头建议、80/190/250m 靠近建议。敌人与保护船使用同一 predicate，顺序完全对应 `Encounter._enemy`：不同 ID、capturedShipIds 优先保护、hostileTargets 存在 source 条目时按明确名单（包括空名单）、否则双方非 neutral 且不同 team。Mingqi caller 应传真实 `snapshot().runtime.policy`；无 policy 的 Legacy/Practice 继续普通 team 判定。权威 command 仍作最终验权与结算。

显示包可省略 `team`：helper 按 neutral 处理未知归属，完整物理几何中的未知归属船仍受射道保护；明确的 hostileTargets 仍可建立敌对关系。显示包若省略任一存活船的 `kind`、高度或必要运动几何，helper 在真实炮组/船员/装填/库存检查后返回 `no-target` / `射界待确认`，不派生目标、不臆造船型或高度。此阶段保留原空水发炮意图能力，最终接受/保护检查仍由真实 Encounter 执行；不能把这类精简显示包当作权威开炮许可。

## RED/GREEN 与数值

先写并执行两个新测试。初始操船真实失败：响应未增强、无限/越界响应未拒绝、最大货物重舰迎风恢复超时。初始炮战真实失败：八炮齐射过快、友船射道未阻断且消耗库存、零 crew 可发炮、没有快照炮况 helper。随后 HUD 三项先 RED 再 GREEN；极端 reload 装备重叠齐射也单独 RED/GREEN。

初定四分之一船员两秒转角增加 15% 的阈值过高：早期力矩已被旧加速度预算夹住，不能用更强助力兑现。保留预算后实测 3.936° → 4.082°（约 +3.7%），验收要求可测 >2% 改善，明确不宣传大幅增益。

静水零初速，两秒完整 crew 转向实测：

| 船型 | 无货 | 满额货物 | 原加速度上限 |
|---|---:|---:|---:|
| 渔舟 | 9.960° | 8.241° | 16°/s² |
| 商船 | 6.424° | 5.058° | 8°/s² |
| 重舰 | 4.818° | 3.793° | 6°/s² |

最大货物重舰从迎风静止出发，经真实 `Simulation -> Encounter -> Physics` 恢复，在接受时间 24.0167s 完成复帆，航向 -52.448°，恢复 phase=idle，并获得实际风力速度。零 crew 不转向且不平移；松舵一秒内 yawRate <0.001rad/s、额外航向变化 <1°。暂停清空恢复且快照/接受时间不变。

14m/s 风、15s 直行起步实测渔舟 3.892、商船 3.125、重舰 3.081m/s。固定风向下重舰持续转舵可能转到更有利风角，末速高于直航，因此不拿这种场景错误证明“转弯无损速”。同初速 3m/s、零风、零帆的对照中三型转舵末速均低于直航，损失来自现有水动力。

## 本任务验证结果

使用 Godot `v4.7.2.stable.official.ed1daf0bf`，直接命令形态：

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_reference_handling.gd
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_reference_gunnery.gd
```

- `test_reference_handling`: 33 assertions，0 failures。三船起步/低速转向/货物/零 crew/松舵/越界/迎风恢复/风力/转弯损速/暂停。
- `test_reference_gunnery`: 42 assertions，0 failures（包括最终审核修复）。健康和缺 crew 节奏、有限炮数、单次耗弹、独立装填、极端装备不重叠、友船触发原子拒绝、延迟炮重新检查、锁定弹种、真实重力、25° 边界、不同射程、实际 HUD、无效时间、单弹最多一次 hit、实际 hull 损失与事件之和一致、己方炮弹 TTL 回收，以及 continuous policy 的 captured/空敌对名单/显式中立及同队敌对/缺省 source 回退。
- `test_reference_gunnery_lean`: 10 assertions，0 failures。未知归属保护、明确 policy 覆盖、省略船型/高度的部分包、真实 MingqiUI fixture 精简包、显示不修改输入、实际装填/耗尽弹药仍禁用。
- `test_mingqi_ui`: 主线程在炮况行高度集成修复后直接重新验证，195 assertions，0 failures；精简包炮况、真实命令、防重复点击及 HUD 生命周期全部通过。
- `test_naval_simulation`: 冻结 72 cases / 51,559 assertions，通过；未改 fixture。
- `test_ship_physics`: 24 tracks / 16,557 assertions，通过；max oracle error `1.455e-11`，未改 fixture。
- 局部回归 8/8：manual_sailing_assist 11、sailing_input 49、sailing_runtime 13、naval_invariants 72、naval_practice 58、naval_practice_scene 16、save_compatibility v2 PASS(0)、layer_boundaries 16 assertions/47 files。全部退出 0，未出现脚本/资源错误。
- 所改已追踪文件 `git diff --check` 通过。未运行 GUI、全套 verify-godot.mjs，未 commit/stage/push。

## 局限与剩余集成验收

射道预测按保护船当前速度与航向外推，不保证炮弹发出后玩家突变方向/瞬移仍安全；后续炮会重新检查，但已经发出的炮弹继续由真实碰撞结算。预测覆盖完整 TTL、不提前依据未来波浪移除，因此可能保守阻止实际会先落水的射道。它不改变 live 海浪时钟或碰撞。

尚需主线程记录 Legacy/Mingqi 工厂开关及保存/载入一致性，运行完整套件、真实 GPU 中的炮况可读性/迎风操作/连续齐射/近岸表现与性能。局部 headless 通过不能代替上述产品验收。

## 最终审核修复：continuous 炮况敌对一致性

审核发现 P2：hostile-team 的已俘船或暂不敌对船，位于 `(0,45)` 的实际射道内时，旧 HUD 仍显示 ready；权威 continuous policy 已按保护船拒绝。新增测试走真实 `reconcile_ships` 应用 capturedShipIds/hostileTargets，并直接比较 HUD phase 与 `command(...fire...)` 的结果。先确认 5 项行为 RED，再加入可选第四 policy 参数及一致分类，GREEN 为 42 assertions。额外覆盖 explicit hostileTargets 对 neutral/player team 的覆盖，以及 source 不存在时的普通 team 回退。

本次仅修改 helper、测试及报告，未改 authority、主线程 UI 或冻结 fixture。重新运行旧 `test_naval_simulation` 72 cases/51,559 assertions 与 `test_naval_practice_scene` 16 assertions，均退出 0、无脚本错误。主线程将 Mingqi HUD 的第四参数接入真实 runtime.policy，再由独立 reviewer 复审。

## 后续全套反馈：精简 Mingqi UI 包

全套反馈定位到 `_policy_enemy` 对可选 `team` 的直接访问。新增 focused 测试先得到实际 `team`/`kind` 脚本错误和 1 项行为 RED；原 `test_mingqi_ui` 的显示投影同时没有 `kind` 与 `position.y`，因此只修 team 默认值会留下弹道几何访问错误。加入未知归属保护和缺几何的只读降级后，focused GREEN 为 10 assertions，原炮战 42 assertions 再次通过，均无脚本错误。

过程回归：helper 修复后直接运行 `test_mingqi_ui`，所有炮战/命令断言已通过且无脚本错误，195 assertions 曾有 4 项独立紧凑布局失败。生命周期测试使用 `naval.ships=[]`，HUD 新增双舷炮况两行后最小高度 378，旧要求 ≤350；缩短精简包提示后同样失败。主线程在真实 native flagship 不存在时隐藏炮况行，重新直接运行取得 195 assertions / 0 failures。本次问题已闭合；helper 子任务仅编辑 Cannon、新 focused 测试及报告，没有编辑 UI、原 fixture 或运行全套 runner。
