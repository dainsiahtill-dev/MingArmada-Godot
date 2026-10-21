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
- [ ] 候选冻结：并行只读审查、定向回归、完整套件、正式GPU视觉/重入/性能，记录边界及剩余预算。

## Additional accepted work
- 配置期缓存ShipView角色，保留全部LOD/帆morph/损伤顺序，冻结旧pose oracle通过。
- Cloud curve预编译，冻结旧compiler1584帧逐字节相等，空curve兼容经独立review修正。
- 未接受岸浪palette：跳过5112 shader setter未证明显著CPU均值收益，避免新增分支。
- 既有几何测试修复：源解析地形与渲染triangle权威分开，保留原阈值，用独立三角形/footing oracle验证，无生产岛算法改动。
