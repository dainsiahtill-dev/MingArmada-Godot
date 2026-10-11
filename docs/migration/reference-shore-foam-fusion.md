# 正式海域的沙滩与浅水柔和过渡

本轮按用户最新纠正实施：海岛与海面的边缘应像参考图一样，从沙滩、湿沙过渡到浅蓝海水，并保留薄、不规则、动态的浪沫；不做粗白描边。海岛森林、地形与码头细节由独立海岛任务实施，本文件只记录正式水面的局部光学接线。

## 实现与边界

- [reference_shore_foam.gdshaderinc](../../modules/scene_engine/ocean/reference_shore_foam.gdshaderinc) 提供浅水过渡、海底可见度和不透明场景深度重建函数。
- [reference_game_water.gdshader](../../modules/scene_engine/ocean/reference_game_water.gdshader) 接入上述函数，保留原有五组波浪、法线、纹理、镜像反射、动态岸边泡沫与主配色。
- [test_reference_shore_feather.gd](../../tests/test_reference_shore_feather.gd) 执行实际生产 shader 中的三个标量函数，检查连续性、边界及真实岸线门控。

浅水过渡同时受海水深度与真实海岸距离约束。垂直深度从 0.3 到 3.2 米渐隐；距真实海岸从 3 到 14 米渐隐。浅蓝散射色最多混入 12%，因此浅滩可读性增加，但不会在离岛很远的浅水处形成一圈亮色，也不会覆盖原有海水层次。

原动态泡沫段完整保留，包括透明纹理、不规则采样、随接受的模拟时间变化的亮带及现有 breaker 层。本轮没有增粗泡沫、增加白色圆环，也没有新增粒子。沙滩与湿沙本身仍由地形材质负责，本轮不改地形网格或地形物理。

## 海底硬边排查与最小处理

主 Agent 实际运行后保存的 [sailing-turn.png](evidence/reference-splash-fusion/native/sailing-turn.png) 中，前景可见绿色水下区域在直线处突然结束。该图来自当前正式 Legacy 场景；[对应运行元数据](evidence/reference-splash-fusion/native/sailing-turn.json) 记录了真实场景、相机和接受的模拟时间。此问题应与已解决的旧白色尾迹方块区分。

从渲染链路判断，有限海底网格或覆盖窗口的颜色通过场景折射贡献给海水，而窗口之外不再有同样的不透明海底贡献，会产生这种直线色差。本轮只在水面 shader 内渐隐海底贡献，不移动海底，不改波高和浮力：

1. 使用实际 `u_depth` 和当前相机逆矩阵重建被折射的不透明像素位置。
2. 与真实高度场比较，仅在像素位于水下、接近海底时使用海底可见度；普通吃水范围内的船壳保留折射贡献。
3. 水深从 8 到 22 米逐渐减少海底颜色。近岸 RF 窗口边缘向内 48 米采用连续渐隐，抑制有限覆盖的硬直边。
4. 更深的水下像素也会淡出，避免窗口边缘高度不连续时分类失效。

这是代码与现有截图支持的原因判断；绿色硬边是否在当前镜头中彻底消失，必须由主 Agent 对本轮最终 shader 实际运行并截图确认。CPU 测试不能证明像素效果。本轮没有增加屏幕空间性能优化或质量降级。

## 参考资料与迁移取舍

研究来源为只读参考包中的 [海岛与水面实现](C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/README.md)、[Surf 资源研究](C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/source-study/SOURCE_REPORT.md) 与 [原 demo shader](C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/demo/shaders.mjs)。

原 Surf 资源由平面沿岸条带组成，使用纹理变换、透明度控制器及错开的相位表现推进、停留和消退，而非固定的不透明白色描边。原始曲线与阶段可作为后续独立波浪带的依据，本轮保留正式水面已迁移的动态泡沫，不宣称已复现全部原始控制器。

用户最新 [视觉参考](C:/Users/dains/AppData/Local/Temp/codex-clipboard-1af49d9e-6b6d-4113-ad6b-3ca77828193b.png) 的重点为密集森林、沙滩及柔和浅蓝水色过渡。本轮不会把此前“清晰白边”的要求误解为粗白色轮廓。

## 已执行验证

| 检查 | 实际结果 | 证明范围 |
| --- | --- | --- |
| 新标量测试，实施前 | 1 项断言，1 项失败，退出码 1 | 缺少正式柔和过渡实现时测试失败 |
| 新标量测试，实施后 | 29 项断言，0 失败，退出码 0 | 实际 shader 标量函数的深度、距离及边缘窗口公式 |
| 正式 Ocean 集成测试 | 87 项断言，0 失败，退出码 0 | shader 资源解析、现有纹理与材质接线、生命周期合同 |

标量测试从生产 include 中提取并执行实际函数体，期望值采用独立手工推导的数值，不另写一份 CPU 公式来伪称 GPU 等价。向量深度重建、实际光栅化、边缘羽化观感与船壳遮挡属于主 Agent 的最终 GPU 截图验收。

## 冻结与后续接线

本轮生产 shader 与 include 已通知主 Agent source-ready，随后冻结；仅补充报告。Ocean 专家后续原作细闪点 helper 的 include 与单行调用由主 Agent 统一接线，避免并发修改同一正式 shader 或在最终截图期间漂移源码。

无本地用户存档读写，无新增窗口、服务器、墙钟时间、物理参数变化。本轮不声称完成后续云雾、炮火、烟或整款游戏目标。
