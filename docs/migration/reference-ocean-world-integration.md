# 正式世界海面融合

本轮把参考学习台的真实镜像反射、深度折射和精确岸线采样接入现有 `ProjectedOcean`。用户随后明确要求保留旧海面优点，因此正式材质采用融合实现：五波、风向纹理流动、青蓝色调、细碎闪点及碎波来自现有游戏；真实镜像、光学深度与实际地形三角采样来自参考示例。参考学习台的独立四组 Gerstner 展示仍保留原行为。

## 正式实现

| 文件 | 职责 |
| --- | --- |
| `modules/scene_engine/ocean/projected_ocean.gd` | 保留 MeshInstance3D、投影网格和原公共 API；配置材质、反射、风向、近岸 RF 与接受时钟。 |
| `modules/scene_engine/ocean/reference_game_water.gdshader` | 正式融合材质。旧纹理细节与色彩，加上真实镜像、深度折射与岸线白沫。 |
| `modules/scene_engine/ocean/integration_wave_functions.gdshaderinc` | 原五波的高度、法线、8 米 coastal attenuation；全域 RF 端点双线性采样和近岸 RF 实际三角插值。 |
| `modules/scene_engine/reference_island_water/ocean_renderer.gd` | 同 World3D 的镜像摄像机及 SubViewport。`attach_surface()` 借用正式网格；`configure()` 继续独立生成示例网格。 |

参考代码：`C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/demo/shaders.mjs`、`renderer.mjs` 与 `model.mjs`。既有细节代码：`original_water_body.gdshaderinc`、`surface_layers.gdshaderinc` 和 `coastal_visuals.gdshaderinc`。

## 融合取舍

初版直接保留参考 fragment 中的正弦细纹，在正式五波与低角度摄像机下形成明显规则网纹。主线程实拍的 `mingqi-shore-low.png` 与 `sail-captain.png` 显示了问题，海面专家也亲自查看了原图；没有把初版作为合格交付。

现改为旧 `waternormals.jpg` 三层纹理：世界基准频率 `.008`，另外两层倍率 `1.6` 与 `4.0`，相互旋转并分别滚动。纹理 tangent XY 转为世界 XZ；风向定义流动坐标，风速影响细纹流动。片元层保持原五波位移，只有表面反光细节改变。

深海吸收的显示基色使用既有青蓝 `(.12,.48,.66)`，浅海使用 `(.18,.73,.73)`，按实际底部深度在 `1.5–17` 米之间渐变。深度折射仍采样当前 viewport 的实际 opaque color/depth，浅滩可透出地形、湿沙和焦散。两个原有水色纹理只贡献小幅非周期变化。

旧 alpha 闪点与白浪仍从原纹理真实通道取样；碎波由风速、表面法线和可见距离控制。单一强烈的 `110` 次幂大高光改为轻量宽瓣与纹理打散的细瓣。岸边既保留新三角 RF 定位的白沫，也调用旧 `coastal_breaker_foam()`，继续使用 `foam0008/foam0009` 的 alpha、移动浪头、浪后尾沫和侵蚀。全域真实岸线距离场不会给孤立水下沙洲加上假岸线。

这些参数是游戏美术选择，不能声明为参考示例的逐像素或原作 GPU 复原。融合画面是否自然由主线程新一轮真实截图验收决定。

## 物理、采样与时钟合同

- 正式位移仍读取 `WaveUniforms.components()` 的五组接受参数；不接入参考示例四组 Gerstner，不抬高船舶隐藏错误。
- 离岸五波公式与 `CoastalWaveField` 一致；近岸使用 `smoothstep(0,8,-groundHeight)`，法线保留其 `.5` 米两侧有限差分。
- 全域 RF 用 `uv*(size-1)` 对齐真正端点，再双线性混合四角；不能用普通归一化纹理过滤造成半个 texel 偏移。
- 近岸 RF 来自 WorldView 实际绘制的 Float32 顶点。泡沫/光学按 `(a,c,b)/(b,c,d)` 的相同对角线三角插值；物理 attenuation 继续使用全域 canonical field，避免把渲染块拓扑冒充物理规则。
- `simulation_time` 与 `u_time` 由调用者提供同一接受值。没有 `_process()` 或 shader `TIME`。重复接受值、暂停和倒退不自行推进海面。
- `set_reference_surface_state()` 只允许可验证的光学参数；非零 tide、关闭物理 waves、非数值/非法宽度等更新原子拒绝。`strength` 调整表面纹理细节，不调整物理波高。

## 反射与生命周期

反射使用一张同 World3D 的 SubViewport，没有复制世界。镜像相机排除第 20 层的所有海面，保留主相机其他 cull layers、environment、projection、FOV、near/far 与 aspect；摄像机 eye 包括实际 `h_offset/v_offset`。宽度至多 768，纵横比来自主 viewport，重复帧重用节点。

`configure_reflection()` 只接受投影所配置的同一相机。切换投影相机后需要重新显式绑定。相机或海面脱树时停止镜像，且不读取脱树节点的 global transform。回树后重用资源；style 0 恢复原始 shader 和调用者 layer，并销毁镜像；style 1 重建镜像但保留投影网格与接受波参数。Ocean 被释放后整个镜像子树释放。

`get_sky_material()` 供正式场景统一天空。正式场景还须使用 Linear tone mapping / exposure 1；环境绑定由主线程在 `NavalWorldView` 完成。

诊断中的 `transparent_objects_supported` 指镜像正常 3D pass 的能力；`includes_transparent_objects/includes_offscreen_objects` 仅在实际镜像启用时为 true。它们不是可见对象数量，也不是云雾已经出现在画面上的证明；单独海水层仍排除。

## 本轮直接验证

引擎：Godot `4.7.2.stable.official.ed1daf0bf`，严格 Node runner 同时检查进程退出码、Godot 错误及唯一成功标记。

| 验证 | 当前结果 | 证据 |
| --- | --- | --- |
| 新生命周期/输入防护 RED | 34 assertions，8 failures；准确复现脱树 global transform 错误、错误 RF/state 接受和偏移 eye | `evidence/reference-world-integration/ocean-red-lifecycle.json` |
| 修复后合同 GREEN | 78 assertions，0 failures | `evidence/reference-world-integration/ocean-green.json` |
| 旧纹理资源未消费 RED | 85 assertions，7 failures | `evidence/reference-world-integration/ocean-red-native-detail.json` |
| 融合资源/合同 GREEN | 85 assertions，0 failures | `evidence/reference-world-integration/ocean-fusion-green.json` |
| 最终镜像诊断/海面分层回归 | 87 + 15 assertions，0 failures | `evidence/reference-world-integration/ocean-final-related-green.json` |
| 实际 WorldView / optics 相关 | 32 + 122 assertions，0 failures | `evidence/reference-world-integration/ocean-related-surface-green.json` |
| 独立四组示例回归 | 3249 assertions，0 failures | `evidence/reference-world-integration/standalone-ocean-retained-green.json` |

`test_reference_surface_optics.gd` 中原 SSR/0-target/ray-budget 的旧需求断言改为当前真实镜像合同；独立 inverse projection、absorption 和旧 SSR 数学测试全部保留。`test_reference_ocean_integration.gd` 检查真实镜像节点的重用、启停、相机换源、layer、释放，以及独立线性底部场上的实际接受 GPU 波 uniform 与 CPU coastal 高度/法线，误差门限 `0.000002`。

以上 headless 检查证明代码、资源接口、生命周期和 CPU/uniform 合同；不把这些说成 GPU 渲染或视觉合格证明。新融合 GPU 截图、整仓回归及最新 Windows 包由主线程统一验收。

最终冻结后的五份相关测试共 3505 assertions，0 failures。没有打开额外 GPU 窗口，没有进行性能调优或 Git stage/push；代码所有权在海面、镜像 helper 与上述测试范围内。
