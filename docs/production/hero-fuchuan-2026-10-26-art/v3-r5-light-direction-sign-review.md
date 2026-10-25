# r5 健康帆暗斑：光线方向符号独立核对

2026-10-26。只读核对代码及 `native-shadow-isolation-r5-a/manifest.json`，直接查看 `native-play/08-r5-healthy-shadow-failure.png` 与 `native-play/01-full-sail.png`。未改生产文件、未启动 GPU 或游戏。本结论取代此前依据固定 fallback 太阳所作的“当前光线必向下”假设；实际 WeatherState 会覆盖该 fallback，必须以隔离包为准。

**确认主线程的新推导成立：WeatherState 将源光线传播方向当成了 towardSun，原生 DirectionalLight 和自定义体积因而都向上投影。应修正 target 坐标/语义适配这一处，保留原始 sourceLightFields；不应再给 RD 或 TargetBoundary 增加一次方向反转。**

## 实际符号链

1. `fidelity_island/daylight.gd:98` 的 `light_direction(position,target)` 明确计算归一化 `target-position`。这是从光源位置到目标的传播方向，不是从受光点指向太阳。
2. `weather_state.gd:309–313` 读取这一 `lightDirection`，原转换 `R(x,y,z)=(x,z,-y)` 只旋转坐标系，保持了传播语义。
3. `world/world_view.gd:67–72` 却将 target.direction 当 towardSun `S`，用 `Basis.looking_at(-S)` 配置 DirectionalLight；同一个向量还送给 ocean/sky 的 `u_sun` 与 `sun_position`，同样具有指向太阳的语义。
4. `naval_world_view.gd:417` 用 `-_sun.global_basis.z` 给 caster。DirectionalLight 沿局部 -Z 传播，所以它继续消费实际传播方向，没有额外符号错误。

隔离包六行的向量一致：

| 含义 | 向量 |
| --- | --- |
| 源 `d_s=lightDirection` | `(-.502183676,+.510248899,-.698181629)` |
| 正确 Godot 传播 `D=R(d_s)` | `(-.502183676,-.698181629,-.510248899)` |
| 旧 target.direction（误当 S） | `(-.502183676,-.698181629,-.510248899)` |
| 旧实际传播/caster worldLight | `(+.502184,+.698182,+.510249)` |
| 应有 target towardSun `S=-R(d_s)` | `(+.502183676,+.698181629,+.510248899)` |
| 修正后实际传播/caster worldLight `-S` | `(-.502183676,-.698181629,-.510248899)` |

Weather 的目标公式应为 `[-source.x, -source.z, +source.y]`。WorldView 的 `looking_at(-direction)`、caster 的 `-basis.z` 均保持原样。源地形/植被 shader 使用 `dot(-source_light_direction,normal)`，也印证源字段本来就是传播方向；不能将源字段一起反转。

## 对暗斑机制的含义

实际 r5 `worldLight.y≈+.698`，1e9 apex 因而在船体上方；下船壳和分段墙体向上形成体积，能够投到健康帆上。可见模型和代理的轮廓差异会使同一错误表现成大块斜影或碎斑。隔离中 native maps 也有船底遮帆，说明共同的太阳输入比 RD 独有的 receiver、near clip 或模板 winding 假设更直接。

`source_shadow_rd` 的 reverse-Z receiver 保留 `volumeDepth>=sceneDepth`，单看比较方向没有推翻依据。`RenderSceneDataRD.get_view_projection()` 在官方实现中已带 depth correction/flipY，不能因为暗斑再盲加一次投影翻转。见 [官方 RenderSceneDataRD 源码](https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/storage_rd/render_scene_data_rd.cpp)。这是上游源码佐证，不冒充本机 GPU 验证。

## 最小可证伪判别

- 数值先锁定：对本包记录的相同时刻，验证 `target.direction == -R(sourceLightFields.lightDirection)`，并验证真实 `-sun.global_basis.z == R(sourceLightFields.lightDirection)`。只在这条适配中修正符号，sourceLightFields、颜色、太阳能量、时间、船姿态和所有 caster 保持相同。
- 相同接受时间和相机对比 legacy sign 与 corrected sign，保留完整可见帆、角色与所有实际投影。两张画面的唯一声明因子是目标方向符号；若健康帆的船底向上投影消失，支持共同输入根因。
- 至少在 corrected sign 下分别看 native maps 和 authored stencil。若两种都恢复“上表面受日光、船底不向上遮高帆”的关系，才进入代理的剩余独立视觉验收；若仍有碎斑，再保留这次符号修正并重新隔离具体 caster/RD，不能把当前闭合检查当视觉通过。

跨昼夜的数值合同应检查 `S=-R(d_s)` 而非无条件 `S.y>0`：夜间源路径可能在地平线下。白昼已知样本可额外检查太阳在上、传播向下。

本报告确认符号推导与建议的最窄修正层；不宣称健康帆问题已经在修正后的 GPU 中消失。
