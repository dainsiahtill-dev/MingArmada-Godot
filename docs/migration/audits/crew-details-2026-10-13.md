# 船员击飞、落水与拾救细节审计

2026-10-13；只读当前 `ming-armada` 源码及保留证据。未启动 Godot、浏览器或 REA，未改生产代码。主线程已确认 CodeGraph 未索引，本审计使用 RTK fallback；不宣称 CodeGraph 审查结果或本轮运行通过。

## 当前实际游戏已有

- **真实海战接线**：`game/scenes/mingqi/mingqi_scene.gd:133-147` 每物理回调推进权威，记录船姿并推进 impact；有 fire 或 crew damage hit 时即时表现。`game/runtime/mingqi_runtime.gd:335-340` 判定该事件，`game/presentation/world/naval_world_view.gd:208-230` 创建船员、供水面采样、先套快照再转移真实 hit。并非只存在参考 demo。
- **同一蒙皮从动作转到击飞**：`crew_view.gd:272-332` 以 canonical hit、炮弹速度和本次快照减员预算挑最近显示船员，暂停原动画、采样世界骨姿并转入物理池。`impact_pool.gd:52-128` 创建18个 native `RigidBody3D`、17个 `PinJoint3D`；全场最多12个 articulated rigs，非每船12个。`crew_view.gd:334-359` 用真实 Jolt pose 驱动皮肤，非致命结束清 override、回岗位。
- **甲板与海面**：`deck_stations.gd:12-37` 提取实际 active GLB 支撑三角形，`impact_pool.gd:30-46` 注册 concave deck，`crew_view.gd:165-186,361-370` 随相邻物理帧更新甲板。`impact_pool.gd:88-91` 开启 CCD；`impact_bone.gd:44-74` 提供单向水面支持、重力、甲板/水阻与 wet 沉降；出生水下不会抬到水面。
- **入水只发一次**：`impact_pool.gd:148-169` 18骨接触合并成每人一个 `crew-water-entry`；`naval_world_view.gd:168-171,212` 已接为水花，带真实 accepted time/world point，scale=.45。当前水花调用通用炮弹水花资源路径（`water_splashes.gd:95-100`），有反馈，尚非原作独立 body splash 资产复刻。
- **人数与岗位/LOD**：`crew_view.gd:100-128,198-209,236-270` 单船24/8/2显示上限、全场120 standing、1800米外释放；helm/haul/load-cannon/lookout/walk/idle 按状态选6个 authored clips，walk 是有限 .3米巡回；reduced motion固定四分之一动作相位。显示人物是抽样表现，不是一名逻辑人员一名实体。
- **炮击数值权威**：`modules/naval_simulation/encounter.gd:471-480` 先扣 hull/sail/crew 再输出一次 hit。`game/domain/mingqi/campaign.gd:685,712-723` 将 native crew损失结算可战/伤员/死亡，并留 receipt；沉船清空全部人员。击飞、入水、表现回收不重复扣人。

## 不足或未实现

1. **落水救援玩法缺失**：池状态只有 `airborne`、`deck-contact`、`water-contact`；casualty最长7 accepted秒、nonlethal1.25秒、wet1.2秒回收（`impact_pool.gd:122,155-179`）。无长期 overboard权威记录、游泳/漂浮木动作、海上拾救条件、容量/阵营/重复救援规则、救起人数receipt或存档。nonlethal结束回站位只是动画恢复。该缺口属于新增玩法，需要协调 native/campaign/save，而非扩大可视池即可完成。
2. **现有“救人弃船”不可当落水救援**：`game/ui/mingqi/mingqi_interface.gd:853-854`、`campaign.gd:1079-1088` 只在俘获船处理流程中接收其伤员/俘虏、验证接收容量和两船距离，写 `prize-rescue`；不读取水中人物。旧航海 `legacy/adventure_session.gd:400` 的遇险渔船接近标记同样不是逐人拾救。
3. **沉船并无全员连续落水过程**：终态立即清 standing（`crew_view.gd:198-205`），只有含crew damage的hit启动击飞（272-296）；没有单独 sink事件派发全员跳海、甲板疏散或浮木幸存者。当前仍正确只按已结算损失做有限hit表现。
4. **骨骼与动作简化**：17个pin保持连接，但没有人体关节角限制（`impact_pool.gd:109-121`）；无肢体命中/局部受伤、起身过渡/攀梯/上下炮台/甲板任务导航。动作取决于站位角色与船状态，不代表每个炮手实体参与装填权威。
5. **预算下表现省略属当前设计**：12池满、未显示船员或1800米外不会产生更多rig；依旧结算战斗人数。不得把省略表现当减员丢失，也不得以扩大至参考40槽称救援完成。
6. **完整实际 Mingqi命中落水链需本轮验证**：现有 `test_crew_impact_schedule.gd:75-127` 验证每physics callback request/甲板/暂停/回退；`test_mingqi_presentation_schedule.gd:135-162` 实际场景仅测真实fire即时flush。尚无该新调度下实际Mingqi real hit→皮肤转移→入水水花→campaign人数→回收的一条完整断言。此前 `tools/capture-reference-events.gd:49-61` 是 Visual QA真实炮击capture，不能等同 Mingqi职业场景验收。

## 原作参考边界

只读原作既有学习证据：`C:/Games/Pirates-REA-Reference-20261011/naval-study/deep/battle-details/DETAIL.md:285-298`、同目录 `battle_state.py:487-603`。40槽人物/炮管/炮架/桶池独立于炮弹池：人物空中→入水→浮回水面，水面按slot奇偶选动作，严格距离<200拾救并crew+1；炮管/炮架沉降回收，桶拾取奖励50。学习译本明示未接所有伤害视觉随机调用到同一原RNG流。其原坐标和时钟不能直接当Godot米/秒；也不构成原作 ragdoll或本作救援已实现的证明。本作保留18骨真实3D水手，原作23骨水中人物/KFM和billboard未迁移。

## 保留测试证据与建议

保留JSON（上轮，未本轮复跑）：`Temp/crew-impacts-performance-regression.json:179-195` 578断言/0失败（包括真实Jolt位移、暂停、90帧甲板/约束、入水支持）；`Temp/reference-crew-lifecycle-performance-regression.json:179-195` 13/0（单次入水事件、去重、回退）；`Temp/presentation-impact-schedule-green-v1.json:179-215` crew schedule33/0、Mingqi schedule37/0。这些证据可佐证已有实现，不能证明当前GPU观感或救援玩法。

主线程按独占运行安排复跑，输出保留本轮文件：

```powershell
rtk proxy node tools/verify-godot.mjs --filter test_crew --output Temp/audit-crew-current.json
rtk proxy node tools/verify-godot.mjs --filter test_reference_crew_lifecycle --output Temp/audit-crew-lifecycle-current.json
rtk proxy node tools/verify-godot.mjs --filter test_mingqi_presentation_schedule --output Temp/audit-mingqi-schedule-current.json
```

单次 actual Mingqi capture建议记录：同一个真实crew damage hit的id/time；naval crew变化；campaign able/wounded/dead receipt；impact source event/slot、18骨/17pin和实际位移；一次crew-entry水花；paused phase冻结；7秒或wet1.2秒后池回收。近景镜头应看清皮肤和海面。没有可救援实体时不应注入假救起成功数据；盘点阶段无需立即扩充玩法。
