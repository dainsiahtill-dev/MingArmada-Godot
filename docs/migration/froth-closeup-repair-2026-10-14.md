# 首侧白沫近景修复记录 · 2026-10-14

本轮针对自由试航近景中船侧白沫呈大片白云、长时间不流动的表现，修正了原 UV 动画被全局时间夹停、侧沫承载范围超过实际船壳，以及透明水面遮掉白沫的问题。交付范围为首／侧白沫的持续播放、贴壳范围和近景合成；其他海面、岸浪、历史尾迹与战斗效果仍按各自范围验收。

## 已确认的问题与实现

原侧沫与首沫 authored mesh 的 UV 控制器保留 `flags=44` 和 `0..25s` 关键帧。原编译器按 CLAMP 采样，而调用者传入整场航行的 `controllerAppTime`，导致 25 秒以后一直取最后一帧。真实源网格通过 Compiler、SourceFroth、SourceSurface 进入 ArrayMesh 时，0／0.25／0.5／1／2／3／4／8 秒 UV 确实变化，25／26／40 秒则相同；因此属于播放时间适配问题。

[source_froth.gd](../../modules/scene_engine/water/source_froth.gd) 缓存实际源 UV 区间，只为 configure 验证过的 UV-only authored graph 使用本作持续循环的局部相位与显式 seek。原 flags、keys 和共享 Compiler 没有改成 loop。粒子 owner 继续接收单调的原 appTime；局部纹理周期不会回卷粒子寿命、pool、RNG 或 emitter。不同的替换 graph 保留绝对时间路径，避免循环其 alpha／TRS。暂停或重复时间不推进，停船关闭首／侧 authored 沫及新出生门控，存活水滴继续老化；后方历史尾迹有独立 owner。

实际 fuchuan 船壳宽约 **5.123m**，原 barque 侧沫承载网格宽约 **11.284m**。原 alpha=1 的部分落在壳外约 **1.68–2.05m**，原先只有速度门槛，超过门槛就全强度显示，使近景呈宽而连续的白带。这是本作比例／覆盖适配问题；不能凭原资源存在就假定当前船体与泡沫尺寸已经匹配。

[hull_waterline_profile.gd](../../game/presentation/ships/hull_waterline_profile.gd) 从真实模型船壳生成 **97 个横截面**，过滤帆、索具、旗和甲板部件；通过 [source_water_packet.gd](../../game/presentation/world/source_water_packet.gd) 发布实际轮廓与独立速度强度。[target_froth_fit.gd](../../modules/scene_engine/water/target_froth_fit.gd) 将侧沫载体贴到相应壳缘，并保留源 RGBA、UV、纹理和控制器。目标 fuchuan 水线宽 **4.9727m**；精确 6 节输入对应壳外带约 **0.7459m**、独立强度 **0.65**。GPU固定姿态夹具的实测速度略低于精确6节，记录值为外带 `0.7447426m`、强度 `0.6480857`；两者没有混写。

[source_attached_froth.gdshader](../../modules/scene_engine/water/source_attached_froth.gdshader) 复用同一原 alpha 纹理，在船体局部的米尺度空间增加持续流动的 alpha 细节，打散压缩后连续的亮边。这属于本作视觉改良；原 UV／顶点 RGBA 仍完整保留。透明水面与不透明船壳的遮挡由 [source_surface.gd](../../modules/scene_engine/water/source_surface.gd) 的实际侧沫材质路径分别处理，并有单帧 GPU 读回验收。没有把该适配写成原 DX9 材质或 GPU 绑定链的完整恢复。

载体缓存还验证了接口提供的有效 `sideScale`，避免在显式尺度覆盖改变时复用旧形状。对应真实接口回归的红样本为213断言／1失败，修正后的最终检查为213／0。这是缓存接口防护；当前游戏没有调用该覆盖，不能将它列为本次白云外观的根因。

## 验证与画面证据

五个最终定向批次共 **17 个选择测试，17 个通过**；独立复核此前再次运行首侧沫 **6 个测试，6 个通过**。独审记录包含211断言版本的载体测试，发生在最后两行有效 `sideScale` 缓存防护修正之前；最终主检查包含213断言版本，不能称独审已覆盖最后两行。没有运行整项目完整 suite。逐项退出码、超时、completion marker 和实际运行输出保存在 [checks](evidence/froth-closeup-2026-10-14/checks/)；验收汇总和文件散列见 [DELIVERY_VERIFY.json](evidence/froth-closeup-2026-10-14/DELIVERY_VERIFY.json)。

| 最终检查批次 | 选择／通过 | 内容 |
| --- | ---: | --- |
| 首侧沫 | 6／6 | 原顶点色、跨25秒播放、接缝、停止门控、载体、完整粒子 owner 对照 |
| 实际船壳水线轮廓 | 1／1 | 六类真实模型、97横截面、姿态／比例、源几何保护 |
| 正式水面 packet | 1／1 | 源挂点、钟域、轮廓与航行／海战输入合同 |
| 船模型合同 | 4／4 | 模型 provider、正式游戏、甲板安全、受损状态 |
| 历史尾迹回归 | 5／5 | 原有限几何、renderer、terminal descriptor、timeline |
| 独立首侧沫复核 | 6／6，重复检查 | 不与17个不同选择测试相加 |

持续播放测试在跨 `24.99/25.01s` 的 repeat 接缝，以及 `26/40/60s`、全局100秒后新实例处均检查实际 ArrayMesh UV。每步粒子 pool／RNG／controller／clock 与独立、未改的 native replay oracle 的完整状态字节一致。原首侧沫 source flags／keys 保持；目标载体适配的检查也确认源 RGBA 与 UV 不变。

固定真实 fuchuan 模型与正式 packet 的 GPU 红／绿对照保留在 [before/VERIFICATION.json](evidence/froth-closeup-2026-10-14/before/VERIFICATION.json) 和 [after/VERIFICATION.json](evidence/froth-closeup-2026-10-14/after/VERIFICATION.json)。冻结前测记录 `changedPixels=0`，有预期失败项，执行退出码1；修复后 `changedPixels=1171`，无失败，执行退出码0。变化统计比较30／31秒的固定姿态渲染，每隔2像素采样，RGB绝对差之和大于0.03才计入；它验证持续可见变化，不是FPS。

同一24秒原贴图相位的泡沫单独画面保留为 [before/t24-foam-only.png](evidence/froth-closeup-2026-10-14/before/t24-foam-only.png) 与 [after/t24-foam-only.png](evidence/froth-closeup-2026-10-14/after/t24-foam-only.png)。记录中的旧字段 `footprintPixels` 实际是**亮像素采样计数**：每隔2像素检查 `R>0.6、G>0.7、B>0.75`，前4367、后65。它不是总白沫面积、网格面积或所有可见泡沫覆盖面积，不能据此换算面积改善比例。

侧沫遮挡 GPU 对照在 [occlusion-gpu/current/VERIFICATION.json](evidence/froth-closeup-2026-10-14/occlusion-gpu/current/VERIFICATION.json) 中通过三项：透明水面不吞沫、后方不透明物不错误吞沫、前方不透明船壳正常遮挡。对应 [red/VERIFICATION.json](evidence/froth-closeup-2026-10-14/occlusion-gpu/red/VERIFICATION.json) 保留前两项失败与前方船壳通过的红样本。测试是实际 SourceSurface 材质的诊断场景，不能扩大为全部透明排序或原版 GPU 画面的验收。

普通运行的实际验证由主菜单进入自由试航，保存 [high-close-01.jpg](evidence/froth-closeup-2026-10-14/native/high-close-01.jpg)、[high-close-02.jpg](evidence/froth-closeup-2026-10-14/native/high-close-02.jpg) 和 [stopped.jpg](evidence/froth-closeup-2026-10-14/native/stopped.jpg)，观察条目在 [OBSERVATIONS.json](evidence/froth-closeup-2026-10-14/native/OBSERVATIONS.json)。这些证明本作普通入口的视觉行为，未测量FPS，也未作原版运行帧像素比对。3D甲板人物仍使用当前实现。

## 复验入口与边界

稳定 GPU 工具为 [verify-source-froth-closeup-gpu.gd](../../tools/verify-source-froth-closeup-gpu.gd) 和 [verify-source-wake-occlusion-gpu.gd](../../tools/verify-source-wake-occlusion-gpu.gd)。冻结前消费者保留在 [baseline/source_froth.gd](evidence/froth-closeup-2026-10-14/baseline/source_froth.gd)，只供 QA 红样本使用。以下命令需要有图形环境；文档汇总阶段没有重跑 GPU。

```powershell
rtk proxy 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe' --path 'C:/Users/dains/Documents/Git/ming-armada' --script res://tools/verify-source-froth-closeup-gpu.gd -- --phase=after
rtk proxy 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe' --path 'C:/Users/dains/Documents/Git/ming-armada' --script res://tools/verify-source-wake-occlusion-gpu.gd -- --role=side
```

本次完成的是首侧白沫近景问题及相关合同的定向修复。原 `475550` 完整生命周期、原船型尺度表、原 DX9 材质／渲染时序和GPU像素等价仍有研究边界。局部UV循环、船壳外带、速度强度、米尺度alpha细节与合成适配均明确属于本作方案；没有宣称所有海面／天气／粒子效果已全部完成。
