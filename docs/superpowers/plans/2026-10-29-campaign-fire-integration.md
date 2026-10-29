# 生涯火攻与逐 tick 工时 Implementation Plan

> 使用 executing-plans / TDD。自主继续现有dirty工作区，不提交、推送或重置。并行仅分配互不写同文件的测试、纯核和只读审查；主线程顺序运行Godot与GPU。

**Goal:** 将已可玩的火攻接入生涯，物资/存档/近远场与登船实际人员预算一致。
**Architecture:** 原课题ship-fire-control扩展H4；纯整数人tick核和同一独立Demo先验。Native产生不可变起点工时，Bridge闭包验真，Campaign用持久cursor和60tick carry一次提交。火控可选字段沿原v2 codec与业务事务接入。
**Tech Stack:** Godot4.7.2、原Encounter/Sailing/Campaign/Bridge/SaveCodec、既有生成UI素材。
**Spec:** docs/design/2026-10-29-naval-world/30-mingqi-fire-authority.md、32-crew-work-accounting.md。

## 全局约束

- 原无扩展Native快照、三弹药与旧局分支保留oracle；新状态不免费赠送库存，availableCrew不存盘或写回人口。
- 既有课题扩展，不新造重复实验。独立真实GPU与CPU接受后才应用正式Native/Campaign算法。
- AI仅辅助火控/投送延至右边界受理；原舵帆、炮击和RNG顺序不改。
- 所有shell使用rtk；CodeGraph实际返回无索引，RTK精确回退。新目录新证据，保留失败。
- 旧active boarding任意remainder保留至结束/割缆；期间不接受新辅助岗位，不能静默补造历史工时。

## 任务

1. [ ] **纯核与独立验证。** tests/test_crew_work_accounting.gd缺模块有效RED后实现modules/naval_simulation/combat/crew_work.gd。sample/finish_row/batch与严格carry按32号十字段/五字段；launcher末120、转岗120/121、返回末120、右边界伤亡均用字面期望。扩展同一ship_fire_control_experiment，比较期末估计与真实人tick，不改原默认lane/oracle。CPU与真实Lab GPU后冻结。
2. [ ] **原生生产者。** 新tests/test_native_crew_work.gd有效缺方法RED；在研究candidate中实现crewWorkAccounting:true、crew_work_receipt不可变peek、起点几何、期末人口、同tickreconcile保留和辅助AI右边界。Candidate CPU与同一Demo GPU通过后应用精确diff至Encounter，跑旧native/gunnery/fixed-tick及既有火攻回归。
3. [ ] **严格持久化与真实采购。** tests/test_mingqi_fire_persistence.gd已有效RED(29检查1失败)，候选codec仅暂存。独立门槛后应用可选FireControl/Launcher与热量/岗位关系，Campaign setup/_sync完整转发，所有人口变更裁岗。tests/test_mingqi_fire_supplies.gd验证54两、receipt幂等、失败原子性；buy-fire-supplies固定旗舰、safeport、item/qty、2/12/24两与600/60上限。
4. [ ] **工时消费、远场与安全。** Bridge附crewWork+validateCrewWork，Campaign预检早于任何时钟提交，持久crewWorkCursor拒重放/缺步；新boarding用60tick carry与起点几何，磨损/奖船只用当前余员。SaveCodec严格carry/cursor关系。Runtime每step消费同一账；活火/岗位/操作/剩余launcher冷却pin，自动到港/保存/修船等真实权威守卫一致。
5. [ ] **生涯操作与验收。** Mingqi港内补给与航行火攻/损管使用既有生成素材；命令走真实queue/fence，默认静音。真实主菜单/生涯入口采购、离港火攻/登船、暂停、save/load、重建/远船、输入与释放GPU；独立审查与定向回归、论文和交付更新。

## Review Focus

- tick120端点人数不能回补整个过去一秒；AI初次受理不能倒算一个tick。
- 端点伤亡只改下一段人口；过去贡献不能使当前在岗人又被磨损/调拨。
- 重复context、重建epoch、丢步、篡改receipt不得推进时钟、cursor或货物。
- Reconcile改变controlsSequence/近场成员时不能清除或补造真实起点roster。
- 旧档正fire、任意半秒legacy boarding与新火控之间不静默赠送/清零/迁移。

## 执行账

- 上一目标轮为实质进展：公开火攻入口，32项相关文件与gpu-04验收已实跑；整体目标仍active。
- 本轮CodeGraph实际返回无索引，未自行建索引。现有源码与31号证据已复查；不将之前的GPU当作本轮新工时的证明。
- crew-work-kernel-red-01：缺纯模块，1检查1失败，exit1；许可纯核实现。
- mingqi-persistence-red-01：29检查1失败，缺可选codec；生产源尚未应用暂存patch。
- Ruling: 使用整数人tick与不可变起点见证，放弃秒末估计/浮点累计；代价是新consumer一次仅接受真实1/60秒，不支持用单张末端快照批量补时。
- Ruling: 旧active boarding保留原算法至结束/割缆，新辅助岗位被禁；代价是旧局需结束/割缆后使用新岗位，换取保存任意旧remainder而不伪造过去劳动。
