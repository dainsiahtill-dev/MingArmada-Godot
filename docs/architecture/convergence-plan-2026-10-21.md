# Architecture Convergence Implementation Plan

**Goal:** 收敛正式入口、数值调度、物理采样、通用渲染能力和资源所有权，并保存实际等价/成本证据。
**Architecture:** 见[设计](convergence-2026-10-21.md)；复用已有Godot引擎模块，不新增万能总管。
**Tech Stack:** Godot4.7 GDScript/Vulkan/Node.js/RTK。

## Global Constraints
- 已有dirty云与project配置保留；不提交/推送/重置。
- 船体60Hz数值权威、3Dcrew/Jolt最多12个角色碰撞实例、交互水3船、接受水光学和易操作手感保留。
- 每个变更先执行能捕捉问题的合同或独立成本基线，再修改；公开snapshot保持detached。
- 原始失败、源码hash、输入和PNG不覆盖；不通过删除表现层获得等价提速。

## Review Focus
暂停/同刻刷新不推进；一次固定tick不能吞输入/事件；coverage失效可立即回退；场景重入无旧Node/RID；高/低质量首构建与后续重建都正确。

## Tasks
- [x] 核对真实工程、已有改动、官方最佳惯例和三个独立源码审计。
- [x] 记录基线：原源码hash/选定测试/相同正式入口性能。
- [x] 物理包：OceanAdapter scalar seam + ShipDynamics只取高度；计数/轨迹/fallback回归。
- [x] FX包：通用阴影下沉、公开动态表面和纹理能力；coverage隐藏尾迹不做无效上传；等价/生命周期回归。
- [x] App包：唯一settings读盘、首构建质量、资源provenance及释放；imported首选因27模型vertex order和动画不等价未接受，保留证据。
- [x] 调度包：无accumulator固定tick接口和primitive读数；原frame适配预算保留，state/events逐步等价。
- [x] 实验室与文档：系统owner/频率/预算矩阵、独立基线候选、正式入口CPU/GPU基准、架构守卫。
- [x] 第一批候选冻结：并行只读审查、定向回归、完整套件、正式GPU视觉/重入/性能，记录边界及剩余预算。

## Additional accepted work
- 配置期缓存ShipView角色，保留全部LOD/帆morph/损伤顺序，冻结旧pose oracle通过。
- Cloud curve预编译，冻结旧compiler1584帧逐字节相等，空curve兼容经独立review修正。
- 未接受岸浪palette：跳过5112 shader setter未证明显著CPU均值收益，避免新增分支。
- 既有几何测试修复：源解析地形与渲染triangle权威分开，保留原阈值，用独立三角形/footing oracle验证，无生产岛算法改动。

## Second measured pass
- [x] 第一批quiet full-game pair98.238→93.466ms，16.67ms预算未达。
- [x] 第一批284/284全套，1094文件全程不变。
- [x] Crew两setter独立旧源码oracle，3233/0，原work-red6预期失败。
- [x] Shore frustum独立原输出/packet oracle243848/0，真实camera union1704→264计算。
- [x] Crew生产两setter RED236/18→GREEN236/0，相关Crew/Jolt/终局/local-fire共10个不同测试通过；[接线与新源码hash](../research/evidence/architecture-convergence-2026-10-21/crew/PRODUCTION_ADOPTION.md)。此前284/284仅覆盖第一批旧源码，新版本仍需最终冻结全套。
- [x] Shore生产culling接线、独立逐源审查及边界回归：目标117/0，最终shore4/4、实际NaturalGameWorld和surface optics通过；[生产源码/回执hash](../research/evidence/architecture-convergence-2026-10-21/shore/production-source-hashes-01.json)。
- [x] Shore原生GPU06实际1940/0：close-up、near-plane、同刻重入的main/reflection均有原shader非空贡献，纯redraw/同刻baseline与candidate零字节差异；[原始回执](../research/evidence/architecture-convergence-2026-10-21/shore/culling-gpu-06/receipt.json)。范围为shore-environment-no-foliage，保留ground/ocean/depth/灯光/船体/compositor，排除Crew/UI/foliage，不代表被排除owner的全世界像素等价或GPU耗时收益。
- [x] 实际GPU workload census03完成1904/0，5 epochs / 80 samples / 12 captures；[工作量与恢复证据](../research/evidence/architecture-convergence-2026-10-21/workload-README.md)。节点库存、draw计数与各epoch耗时不能相互替代，不从非同刻epoch相减推断单组件收益。
- [x] 实际公开入口两轮有效quiet paired整场：94.242→72.700ms、93.702→72.606ms。失焦/暂停的无效记录保留且不纳入；该结果仍未达到16.67ms目标。
- [x] 最终集成候选完整回归与证据收口：286/286通过，0失败/超时/Godot ERROR，22分50.818秒；1098份冻结文件新增/移除/变化均0。[最终摘要](../research/evidence/architecture-convergence-2026-10-21/full-suite-second-summary.json)。第一批284/284作为独立历史检查点保留。
- [ ] 性能门槛：16.67ms/60FPS未达到。当前两轮整场均值约72.65ms；剩余CPU/GPU归因、连续炮火/大舰队长时压力、canonical模型烘焙和导出一致性仍为后续门槛，不能写成已优化完毕。
