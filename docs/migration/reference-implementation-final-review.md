# 海战参考实现独立审核

日期：2026-10-11。审核者只读实现，唯一仓库写入为本报告；未 stage、commit、push，未启动 GUI、浏览器或共享 `verify-godot.mjs`。本报告审查已批准计划及实际实现，不把工作区所有 HEAD 差异归为本轮。

## 当前结论

**最终复审：两项独立发现的 P2 均已修复并重跑闭合；冻结源码范围内未发现未解决 P1/P2。** 主线程已确认实现冻结，仅截图工具/文档可继续更新。GPU 观感、全套回归和性能验收由主线程负责，本报告不替代其证据。

### 已修 P2：HUD 炮况未使用连续战役权威敌我策略

位置：`modules/naval_simulation/combat/cannon_system.gd:93`、`:104`，调用点为 Legacy/Mingqi/练习 HUD 的 `broadside_status`。

`broadside_status` 仅依据 `team` 决定敌舰与保护船；实际 `Encounter._enemy` 在 continuous 模式优先使用 `hostileTargets` 并排除 `capturedShipIds`。因此 Mingqi 的俘获或非敌对对象仍可能显示为“可齐射”的敌舰，实际命令则返回 `friendly-fire-blocked`。同一 helper 也未获得权威当前锁定目标/战术抑制信息；显示建议必须与实际发炮路径保持一致。

独立 Godot 4.7.2 headless 复现：连续模式，player 为 fuchuan，另一艘 hostile-team merchant 位于 `(0,45)`；`hostileTargets.player=[]`，静水无风，开启 `referenceGunnery`。

```text
INIT_ERROR=
HUD={ phase: ready, label: 可齐射 · captured, targetId: captured, ... }
ACTUAL={ ok: false, reason: friendly-fire-blocked }
```

复现脚本位于 `C:/Users/dains/AppData/Local/Temp/reference_review_repro.gd`，最终运行 exit 0，无脚本错误。最初复现清理误调用不存在的 `Encounter.dispose`；删除这条测试清理后重跑，以上为干净结果。

修复复审：`broadside_status` 新增可选四参数 policy；分类先排除 captured，再使用对应 shooter 的 hostileTargets，最后回退 team。Mingqi HUD 从既有 `runtime.policy` 传入。相同独立复现传入 `e.policy` 后，HUD=`blocked/友船遮挡/targetId空`，实际仍返回 `friendly-fire-blocked`；exit 0，无脚本错误。该敌我分类问题已闭合。

最终兼容复审：未知 team 默认按受保护对象处理，明确 policy 仍可建立敌对；缺 kind/高度等弹道几何时显示“射界待确认”，不访问缺失字段或伪称安全。reload/no-ammo 等已有字段仍优先显示。Mingqi 无 native flagship 时隐藏炮况。独立运行 lean 10/0、gunnery 42/0、Mingqi UI 195/0，均 exit 0，无脚本错误。

### 已修 P2：支撑范围外的远岛房屋仍可见

位置：`modules/scene_engine/world/world_view.gd:170`，以及始终可见的 `_build_ports` 房屋 `:207–235`。

新远景地形只为 `focus.distance_to(island) <= 1500 + radius` 的岛生成 tile；旧 Ports/house 没有对应距离或支撑检查。产品相机 far=4000，所以 1500 米截断外仍有可见房屋而无地形。128 tile 上限耗尽时也需遵守相同“可见建筑必须有支撑”的约束。

独立 headless 复现：岛心 `(2000,0)`、radius=100、focus=0、相机 far=4000 且朝向岛屿；使用与新增测试相同抛物地形函数、近景半径0。实际 `DISTANT=0 HOUSES=9 FRUSTUM_VISIBLE_MESHES=45`。没有 GPU 截图替代声明；此处直接读取 Node 可见性、真实相机视锥以及实际远景 terrain 集合。临时脚本 `C:/Users/dains/AppData/Local/Temp/reference_review_distant.gd`，exit 0。

修复：删除1500米生成截断，保留128 coarse tiles硬预算；`_island_supported` 根据真实成功生成的近/远 tiles 验证完整岛屿支撑。每岛 Ports、dock、house 通过同一支持结果控制可见性；IslandDetails 的可选 `terrain_support` 回调叠加其既有 focus 距离，预算不足时也不会显示无支撑细节。每次窗口更新重新评估，dispose 清支持节点、tile索引、视觉列表和回调。

独立重跑相同2000米复现：`DISTANT=4 HOUSES=9 FRUSTUM_VISIBLE_MESHES=45`，原先缺失支撑的房屋现在有完整远景tiles。扩展测试 `test_distant_island_support` 独立31 assertions/0 failures，覆盖2000米岛屿、近远不重叠、无远景碰撞、dispose释放及六个大岛耗尽预算后的港口隐藏。该问题已闭合；未以此替代实际GPU画面验收。

## 已审核的规格与实现链路

- 读取已批准 implementation plan 及 water、damage-crew、handling 三份实现报告；后者保存后补读，未把临时缺失当作缺陷。
- `NavalWorldView` 先给 CombatEffects 提交 native accepted time，再应用各船快照与 presentation events；给 ShipView/CrewView 同一个 `native.time`。水花、尾迹、船损时间线和海面 shader 没有新增墙钟、Timer 或自行累积的粒子模拟。
- `WaterSplashes` 按真实 event.time/position 计算 age，拒绝未来、过期、非有限、重复与超预算事件；回退清空节点和去重缓存。环、柱壳与飞滴遵守同一 water sampler。规模固定 32 splashes × 24 droplets；2.8s 释放。surface_only 沉船泡沫隐藏柱、伞壳和飞滴。
- `WakeTrails` 用速度在船向上的投影，倒车/纯侧滑不新发尾迹；时间回退清理，重复时间不更新几何，传送断开历史。32 trails、64 samples、6.5s 生命周期；附着浪每船三块、合计最多 96。几何用同一 accepted wave time。
- `configure_surface_filter` 从真实 terrain sampler 接入，水柱起点在陆上拒绝；水环/柱壳/尾迹/附着浪移除带陆地顶点的三角形，飞滴按当前位置过滤。该实现是有限顶点采样，不是任意弯曲海岸的数学精确裁切，真实近岸画面由主线程验收。
- `ShipDamage` 是独立表现状态：由 hull/sail 的既结算比例驱动 shader 与有限 clip，未再次扣伤害。首次已终态快照 seek 到末态、不补播事件；回退清标记，健康快照恢复；三个 LOD 模型一起更新，终态均隐藏。事件使用 scheduled accepted birth time，持续沉没快照不重启。
- `ImpactPool` 保持既有真实 Jolt 骨架路径：全局 12 rigs，target/event/slot 去重 256 项；重复 phase 不老化、回退释放、入水单次事件、湿态 1.2s 和最长 7s 回收。CrewView 清每帧损失预算，动画 pause 后才转 physics skin，恢复清 override。入水回调接入 CombatEffects 的小比例 splash。甲板碰撞矩阵随当前损伤模型的 transform 更新。
- `manual_handling` 的新 responseRate 只在显式开关开启时生成，保留既有角加速度/力矩/健康预算；缺省维持旧 4/s。重载恢复延长 accepted timeout，未添加助推力或第二物理积分。
- `Encounter` 增强发炮先检查每个炮口/葡萄弹射道，再单次扣弹与设置 cooldown；延迟炮再次检查友船。真实 launch velocities 和现有 moving-box sweep/重力/命中结算继续负责弹道。读取 `_advance_projectiles` 确認每颗弹命中后移出，不因表现事件再结算。
- Legacy/Mingqi 两 Scene 在 configure 前显式 enable；真实 native factory 将两标志传给 Encounter，save/adopt 的重建复用相同 runtime profile。练习 factory 显式开启；无标志裸 Encounter 路径保持旧合同。新增 `test_reference_product_modes` 覆盖实际安全 checkpoint export/adopt 后 profile 不丢失。
- `surface_layers` 仅 fragment 细节，风向及风速沿 NativeWorld → WorldView → ProjectedOcean uniform 接入；原 wave height/normal 与船体采样合同未改。白浪强度受质量、风速、视距限制；shader 的 GPU 实际观感未由此审核运行。

## 原有脏文件与额外修复边界

`export_presets`、checkpoint/development-access、Windows delivery、既有参考水库等工作树差异不自动归为本轮。本次只追踪父任务列明链路及新接入。

船浪二次复审：旧静态链路 `WakeTrails.pose.position` 是船尾，`ShipWave.center` 加 `0.51L` 恢复船心，然后 `along=0.51L` 放在船首；旧链路本身没有双倍偏移。新实现把转换移到 caller 的独立 attachment 副本，helper 的 pose.position 明确为船心，历史样本不被改写；船首轮廓改为二次曲线。当前新链路静态未见 P1/P2，GPU 形状由主线程验收。

远岛新增实现已审核：128 coarse chunks 硬预算、近远同坐标不重叠、无碰撞/植被、通过 `_owned` 释放且 dispose 清字典。最终扩展边界测试独立31/0通过；范围外建筑支撑问题已按上面记录闭合。

## 最终独立 focused 验证

直接使用 Godot `4.7.2.stable.official.ed1daf0bf --headless --path C:/Users/dains/Documents/Git/ming-armada --script ...`；未调用共享 runner。

| 运行 | 本审核最终结果 |
|---|---|
| HUD policy 独立复现 | blocked 与实际 friendly-fire-blocked 一致，exit 0 |
| 2000米远岛独立复现 | 4 个真实远景 terrain tiles 支撑保留的9栋房屋，exit 0 |
| `test_distant_island_support.gd` | 31 assertions / 0 failures |
| `test_reference_gunnery_lean.gd` | 10 assertions / 0 failures |
| `test_reference_gunnery.gd` | 42 assertions / 0 failures |
| `test_reference_water_volume.gd` | 133 assertions / 0 failures |
| `test_mingqi_ui.gd` | 195 assertions / 0 failures |

上述最终执行全部 exit 0，无 Godot SCRIPT ERROR、ERROR 或 WARNING。Mingqi UI打印两个viewport及首包尺寸，均为430×333。未写实现文件或测试文件，临时独立复现脚本在系统Temp下。

## 证据边界

CodeGraph 目标未索引，父任务本会话已确认；审核使用 RTK 源码回退，未伪造索引结果。所有 shell 命令均以 `rtk` 起始。

本审核独立执行上表 focused headless 复现与测试；其他 worker 回归数字仅来自其报告，未伪称本审核重新执行。主线程全套、GPU、性能结果须由主线程最终验收报告记录。未读取或改写外部原参考资产。
