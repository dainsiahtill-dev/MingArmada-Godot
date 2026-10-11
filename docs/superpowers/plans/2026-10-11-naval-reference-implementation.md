# 海战参考全量落地 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Track each step below.

**Goal:** 将已批准的五项改进接入现有 Godot 产品路径，并用真实运行、截图及回归检查验收。

**Architecture:** 沿用唯一接受时间、权威快照、波高采样与已有力学积分。场景层负责水色和岸浪；表现层负责事件水花、船浪、损伤与水手；物理/海战层负责操纵、弹道与结算。

**Tech Stack:** Godot 4.7.2 / GDScript / spatial shaders / Jolt / ArrayMesh / 原始 PNG。

**Spec:** docs/migration/pirates-learning-plan.md；新增依据 C:/Games/Pirates-REA-Reference-20261011/naval-study/deep/README.md 及该文档链接的 asset-details、battle-details、RENDERING_AND_COLLISION.md。

## Global Constraints

- 仅修改 C:/Users/dains/Documents/Git/ming-armada；原网页项目及原作参考目录只读。
- 保留原波高/法线及船体水线合同，不创建第二时钟、第二积分或重复命中/减员。
- 新贴图保留原字节，按真实 alpha/RGB 用途选择；全部候选不等于全部必须载入。
- 3D 水手与物理击飞保留；近远距离预算明确；沉船及断桅为本作状态驱动表现。
- 每个实现任务提交有效回归测试与局部报告；禁止修改他人负责文件、禁止 git commit/push/stage。
- GPU 验收由主线程统一运行；工作者仅 headless 测试，避免多个游戏窗口。

## Review Focus

- 暂停、倒退时间、载入、换场景：特效冻结、清理、无复播。
- 倒车、侧滑、急转、停船：船浪只反映真实向前速度，无方块和跨段连线。
- 连续齐射与近岸：体积水花有有界预算，不穿岛；命中只结算一次。
- 低速/迎风/重舰：辅助转向可用且守力学预算，玩家主动舵优先。
- 帆损/船壳损/船员中弹/沉船：状态驱动、动画与刚体无双写，退出无泄漏。

## Tasks

### Task 1: 立体落水与船浪

Files: game/presentation/water/water_splashes.gd、wake_trails.gd、独立水花/船浪 helper/shader；tests/test_reference_water_volume.gd；tests/test_pirates_water_effects.gd（必要回归适配）。

Interfaces: configure(water_sampler: Callable)、apply_snapshot(now: float)/apply_snapshot(native: Dictionary)、add_event(event: Dictionary)、diagnostics() -> Dictionary、dispose() 保持兼容。真实 event.position/time 决定出生点与生命周期。

- [ ] 读取新增原始粒子/动画参数，记录原证据与本作缩放选择。
- [ ] RED：验证立体几何、有限生命周期、暂停/回退、预算与速度/转弯船浪行为。
- [ ] GREEN：水柱/伞状壳、水环、空间飞滴和弱雾；船首/两侧浪，历史尾迹渐隐。
- [ ] headless 局部回归；报告文件 docs/migration/reference-implementation-water.md。

### Task 2: 操船与炮战

Files: modules/physics_engine/ships/manual_handling.gd、game/runtime/manual_sailing_assist.gd、modules/naval_simulation/combat/*、必要 runtime/input/UI；tests/test_reference_handling.gd、tests/test_reference_gunnery.gd。

Interfaces: 继续现有 controls/input 与权威 fire/hit/splash 事件合同；若必须增加字段，兼容旧快照并通知主线程。

- [ ] 读取新 battle_state 与原运动算法；以本作米秒重新选择参数。
- [ ] RED：小船/商船/重舰起步、低速转向、回舵、转弯损速；齐射/装填/弹种/安全射界。
- [ ] GREEN：现有力学预算内完善辅助；保持真实弹道与扫掠碰撞；可读反馈接入现有 HUD。
- [ ] headless 局部回归；报告文件 docs/migration/reference-implementation-handling.md。

### Task 3: 破损与船员

Files: game/presentation/ships/ship_view.gd、game/presentation/crew/crew_view.gd、必要独立 helper、modules/physics_engine/impacts/*；tests/test_reference_ship_damage.gd、tests/test_crew_impacts.gd。

Interfaces: apply_snapshot(ship, wind, consumed)、apply_events(events)、dispose() 兼容；伤害来自已结算船状态与事件，不改海战数值。

- [ ] 读取原关键帧/事件/落水状态机，区分学习参数和本作选择。
- [ ] RED：分级损伤、帆洞、断桅/沉船单次时间线；水手接管/恢复/落水/回收。
- [ ] GREEN：全部 LOD 破损一致；3D 岗位动作、有限刚体击飞与落水生命周期。
- [ ] headless 局部回归；报告文件 docs/migration/reference-implementation-damage-crew.md。

### Task 4: 海面分层与整体验收（主线程）

Files: modules/scene_engine/ocean/original_water.gdshader、projected_ocean.gd、独立 sea detail shader include、tools/capture-reference-water.gd/新增验收脚本、provenance 新接入清单。

- [ ] 读取新增海面调用链，保留原波高和法线。
- [ ] 将水色微纹、广域白浪、岸浪、浅水焦散和风向高光分层；设置 bounded 默认强度。
- [ ] 串接真实产品路径，执行完整 tools/verify-godot.mjs。
- [ ] 实际 Godot 高/低/远镜头、多时刻、暂停、齐射、破损与船员截图并人工查看；记录性能范围。
- [ ] 独立规格/质量审核，修复阻断问题，保存逐项验收报告。

## Execution record

用户“全量落地”批准上轮已保存的范围；新报告作为补充依据。任务 1/2/3 负责不同文件，可并行；共享 naval_world_view/combat_effects 的集成由主线程协调，避免写冲突。已有工作区含前轮未提交修改，保留现场，不建立丢失这些修改的另一个 checkout。

## Approved expansion: updated interactive demos

用户进一步要求对新 `island-water` 示例与破损素材安排多个专家并行实现。沿用既有地理、五波、浮力、事件及 accepted time；新示例四组 Gerstner 与 Cat Island 是学习场景的选择，不替换本作合同。

### Task 5: Original damage masks and coherent rig assemblies

Owner: damage/crew worker. Files: ShipDamage/ShipView/shader、专门测试、独立损伤贴图 provenance。

- [ ] 对六档 hull / 五档 sail PNG 检查 RGB/alpha 与原 shader 用法。
- [ ] 原字节复制并绑定私有材质；船壳保持不透明，帆孔按 alpha 裁切；当前 subtype0 全损对应080，100作为已记录候选。
- [ ] 桅杆、帆、横桁、合并索具、旗帜按同一甲板 pivot 倒伏；全部六船型与三LOD一致；暂停/回退无累计变换。
- [ ] 原资产色板适配本作木船/帆颜色，真实 GPU 重拍及回归。

### Task 6: Godot ocean optics

Owner: ocean worker. Files: ProjectedOcean/original_water + optics helpers/includes/test/report。

- [ ] 适配 Godot reverse-Z、真实逆投影矩阵，接入深度吸收/折射与浅深水色。
- [ ] 有限反射方案、Fresnel、排除海面反馈、暂停/低档/退出的预算及资源生命周期。
- [ ] 不改变原波高/法线与船体水线；主线程显式启用产品接口并拍摄开关/角度对照。

### Task 7: Island surface and wet shoreline

Owner: island worker. Files: TerrainChunk + detailed shader/helper/test/report。

- [ ] 原高度/顶点颜色/碰撞保留，沙草岩细节按坡度与高度混合。
- [ ] 湿沙与水下细节从海面材质复制同一 accepted time/waves/shore uniforms；无独立时钟。
- [ ] 近/远地形共享视觉方案且无地形缺口；私有材质/释放与预算验证。

### Final acceptance after expansion

- [ ] 三组专家各自局部回归、独立复审；共享文件由 root 串接。
- [ ] 冻结后的完整 headless runner；真实 Godot 截图与 PNG/JSON 哈希索引、逐图人工验收。
- [ ] 独立前台 GPU 性能窗口，保留失焦/变更等无效条件；固定截图 tick 不当成 FPS。
- [ ] 导出/打包资源检查；完整验收报告与当前限制。
