# 正式海域整合独立审查

日期：2026-10-11。审查对象：当前 WorldView/NavalWorldView 接线、近岸 RF、共享 wave descriptor/CPU Coastal、真实高度 profile 与岸线布景、验收脚本存档隔离。Ocean 融合生产已冻结并完成最终静态复审；最终真实画面与 GPU 验收仍由主线程执行。本文不以 headless 通过代替画面验收。

## 当前结论

正式接线保留原地理与物理责任边界，海/船/尾迹/落水人员仍消费同一 accepted time。近岸场明确服务真实地形泡沫/折射，物理衰减仍使用全局 RF；两种场没有被混成两套浮力。共享世界镜像、天空材质和 owned-node 清理路径成立。

审查发现的共享 descriptor Float32 溢出、换画质后风丢失及新岛 profile 非法字段错误均已修复并清洁复跑。最终 Ocean 静态复审没有新的阻塞问题。旧版 probe 已取得实际 GPU 数学证据，但最新补强 probe 的源 SHA 与旧记录不同，需主线程重跑后绑定完整 gate；截图与新 EXE/PCK 也由主线程验收。不能以本文声称整合阶段全部交付已经完成。

## 具体发现与状态

### 已关闭：共享 CPU/GPU descriptor 接受集合不一致

位置：[wave_descriptor.gd](C:/Users/dains/Documents/Git/ming-armada/modules/contracts/wave_descriptor.gd:45)。原 validator 仅检查 double 有限性，CPU WaveField/Coastal 接受 amplitude/speed=`1e60` 或 wavelength=`1e-60`，真实 WaveUniforms 转成 Vector4 后为 INF，拒绝上传。默认五波无此问题，但新共享 configure 的公开合同不一致。

按主线程授权新增 [Float32 回归](C:/Users/dains/Documents/Git/ming-armada/tests/test_wave_descriptor_float32.gd)，实跑 RED：32 断言、12 失败、exit 1。最小修复仅在 validator 中以与 GPU 相同的方向归一化/波数构造实际 Vector4 并检查有限；未改五波常量、速度、相位、CPU double 累加、场景或玩法。GREEN：32/0；同时 WaveUniforms 8/0、SeaPhysicsIntegration 4457/0，均 exit 0 且无 ERROR。默认五波 12 个位置/时间组合仍与原 scalar 顺序逐值完全相等。

### 已补接线：画质重建后的风丢失

位置：[NavalWorldView.apply_settings](C:/Users/dains/Documents/Git/ming-armada/game/presentation/world/naval_world_view.gd:111)。原质量重建后的 world.apply_snapshot 只传 time/focus，暂停时新材质会保持默认风，细水纹与碎波短暂不跟当前天气。主线程已补 `_snapshot.wind`。独立复跑新 NavalWorldView 测试为 25/0，exit 0、无 ERROR，新增断言验证暂停换画质后 0.6/0.8 方向、6.5 风速与 7.25 accepted time 保留，旧 mirror WeakRef 失效，Environment 绑定新 Ocean 同一 SkyMaterial。

### 已关闭：新高度 profile 非法输入触发脚本错误

位置：[HeightField.configure_ports](C:/Users/dains/Documents/Git/ming-armada/modules/scene_engine/terrain/height_field.gd:20)。独立运行 test_reference_island_profiles.gd 时，第 75 行非法字段用例触发 `Invalid call. Nonexistent 'float' constructor.`。输出虽打印 4846 断言/0 失败并 exit 0，仍是严格验证失败，不能算通过。

主线程已在 reference profile 输入路径先判断 int/float，再转换并检查 finite；整个新 profile 列表构造成功前不提交 `_ports` / `_reference_profiles`，默认旧 ridge oracle 保留。审查者没有修改该文件。独立清洁复跑为 4846/0，exit 0，整个输出无 SCRIPT ERROR；此前假绿输出作为发现记录保留，不能沿用。

## 源码合同核实

- [WorldView.configure](C:/Users/dains/Documents/Git/ming-armada/modules/scene_engine/world/world_view.gd:35) 将同一 injected height sampler 用于近/远 terrain、RF、spray、港口和植被。共享 descriptor 默认为原五波，Ocean 和 ShoreSpray 从同一 detached 描述上传。
- [WorldView.apply_snapshot](C:/Users/dains/Documents/Git/ming-armada/modules/scene_engine/world/world_view.gd:105) 用 snapshot.time 更新 Ocean/spray，再同步近/远 TerrainChunk；无墙钟或独立 shader TIME。
- [NavalWorldView](C:/Users/dains/Documents/Git/ming-armada/game/presentation/world/naval_world_view.gd:155) 按同一 native.time 应用船姿态、Crew、Effects、Wakes 与 WorldView，水花/尾迹/落水 pool 注入同一 `_water`。不修改 canonical pose 或业务状态。
- [近岸 RF](C:/Users/dains/Documents/Git/ming-armada/modules/scene_engine/world/world_view.gd:173) 从实际 near chunk 的 Float32 顶点格点读数，缓存只按 tile window；同 tile 更新 accepted time 不重建静态场。两三角沿 `[a,a+1,b] / [b,a+1,b+1]` 对角线插值，未用平滑双线性伪装实际 terrain。越界边缘退回 injected sampler 后仍写 Float32。
- [TerrainChunk.sample_mesh_height](C:/Users/dains/Documents/Git/ming-armada/modules/scene_engine/terrain/terrain_chunk.gd:208) 与 shader near RF 三角规则一致。方法显式假设当前 chunk 为水平平移；正式世界满足此条件。此证据不能推成任意旋转/缩放 terrain 的查询支持。
- [ReferenceOceanRenderer](C:/Users/dains/Documents/Git/ming-armada/modules/scene_engine/reference_island_water/ocean_renderer.gd:114) 使用 main camera World3D、镜像主 camera 实际变换、相同 lens/environment/attributes，排除水专用层；没有镜像水面反馈。外部 attached surface 不由 helper 释放，helper 只释放自己镜像，WorldView owned ocean 的释放再释放 helper 子节点。
- 主/镜像共用 SkyMaterial，正式 Environment 使用 LINEAR/exposure 1；船模/植被仍用同向 native sun。新 Ocean 状态 preset 允许 sunset 时，Sky/sea/terrain 会随源 sun 改动，native sun 仍为日光；正式产品当前仅默认晴天，不把 sunset preview 扩展成完整产品天气验收。
- [IslandDetails._contour](C:/Users/dains/Documents/Git/ming-armada/modules/scene_engine/world/island_details.gd:210) 现从海侧向内扫描，定位首个水陆 bracket 后二分，支持中心在水中的双肩/湾岸；空方向返回 INF，不虚构布景。独立新 coastal dressing 11/0，覆盖非单峰且 submerged center，exit 0 无 ERROR。

Ocean 最终复审读了完整 `reference_game_water.gdshader`、ProjectedOcean、integration include、ocean_renderer 及共享 `surface_layers/coastal_visuals`：五波位移/物理法线仅由 integration 函数负责；新三层 wind-oriented normal、原 alpha 碎波/闪点只改 fragment 细节，不抬船或改变波高。真正镜像和主 viewport 深度折射分别绑定独立 sampler；reverse-Z 深度使用当前 INV_PROJECTION_MATRIX。旧海色与浅海吸收、真实 near triangle 岸线及原移动 breaker foam 混合路径成立。没有新增独立时钟或渲染层反向 import 物理。独立 final ocean 87/0、exit 0、无 ERROR；这只验证接口/生命周期，不冒充视觉验收。

## RF 与原解析高度误差：有界近似，不是零误差

GPU 的 physical attenuation 读取全局 RF endpoint 双线性；CPU Coastal 仍读真实解析/索引高度 sampler。`near RF` 精确贴合可见三角，仅影响 height_at 的泡沫/折射，不替换 canonical attenuation。近岸 RF 测试通过不能证明五波 GPU 位移和 CPU 水高已经逐值相等。

新增 [真实 GPU 数学 probe](C:/Users/dains/Documents/Git/ming-armada/tools/probe-reference-world-gpu.gd) 将 production `integration_wave_functions.gdshaderinc` 及它引用的 `wave_functions.gdshaderinc` 原函数文本嵌入 compute GLSL；使用实际 WorldView 材质 wave_components、flags、shore/near bounds 和真实 RF 图。只适配 uniform binding，不改 GPU 的波浪公式。GPU 返回 reference_game_height、global RF height、near triangle height 及 normal.y。CPU 对照调用现有 Coastal，一份读 canonical height，一份读实际 RF，分离浮点数学与地图近似。

probe 默认**强制** `reference_islands:true` 和所有 port 的 source profile；源未 ready 时明确失败。没有 CPU 公式复制冒充 GPU，`--offline` 明确返回 gpuExecuted=false。它验证源函数 GPU 数学，不证明最后投影网格顶点间的 raster 插值或整幅海面画质。

本次只运行 check-only 与 headless `--offline`，未启动 GPU。当前真实 Cat Island/Coastal2/Virgin profile 的 1445 点（含四个时刻、真实近岸网格及 global field 边界）结果：

| 项目 | 本次离线值 |
|---|---:|
| 最终补强后的断言 / 失败 | 2904 / 0 |
| RF 对 canonical 水高最大近似差 | 0.0275619409840714m，约 2.76cm |
| 最差水高位置 | x=-3.997143，z=435.9223，t=17.25 |
| RF 域内地面高度最大近似差 | 1.33838817202537m，含陡岸 |
| RF 域外 point 数 | 151；-20m fallback 与 -24m actual ground 分开计，均 offshore 全衰减 1 |
| 真 GPU 数学误差 | 尚未执行，不能填零作为通过证据 |

此前同 probe 的旧圆丘高度基线水高近似差为 0.00363094649105999m；它已经不代表新实际岛 profile。两次结果不可混用。

原五波绝对振幅和为 3.5m，smoothstep 在 depth/8 上的最大导数为 0.1875/m，所以同点水高近似差满足 `|delta water| <= 0.65625 * |delta ground|`，另加 GPU 浮点误差。离线每个点已检查此界。该界不保证所有未采样坐标均低于 2.76cm；当前数字只适用于上述采样集。最新 GPU probe 单独声明 RF-backed CPU 数学 gate 0.002m、GPU/canonical 总高度 gate 0.05m；global endpoint/near triangle fetch 也要求 <=0.002m，normal.y 有限且朝上。5cm 是本阶段采样验收界，不是零差或完整世界最大值证明。

已核读旧版真正 GPU JSON：gpuExecuted=true，Intel Arc 130T，1445 samples，5791 report assertions/0 failure（完成标记另有文件写入断言），GPU/RF CPU 最大差 0.0000299146548861096m，GPU/canonical 最大差 0.027585528092713m。旧版尚无防空图/完整 upload/5cm gate，且 recorded probe SHA `828f631...` 与当前 `fe5e27e...` 不同，必须重跑当前冻结脚本后才作为最新交付记录。

最新记录解析字段：`gpuExecuted==true`、`waveCount==5`、`readbackFloatCount==samples*4`、`failures==0`、非空 `rfSizes`、各最大误差不超过各自 tolerance，以及 actual include/shader/probe SHA 与当前源一致。最终唯一 `REFERENCE_WORLD_GPU_MATH_PROBE ... failures=0` 标记、exit 0 和整个输出无 ERROR 同样必需。只看空 GPU image、空 readback、默认零误差或单个 exit 0 都不能通过；当前脚本在 dispatch 前检查两张实际 RF 非空且为 Float32 格点、完整 8-vector/5-wave upload、真实 attenuation flags，零缓冲也会在非零 canonical 样本中失败。

由主线程运行（默认 Forward+，不加 --offline/--headless）：

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --path C:/Users/dains/Documents/Git/ming-armada --script res://tools/probe-reference-world-gpu.gd
```

成功读回后写 `docs/migration/evidence/reference-world-integration/gpu-math-probe.json`，包含实际 include SHA、probe SHA、GPU/engine、profile 来源、误差和 scope；RD 不可用或 GLSL 编译失败即失败。使用 local RenderingDevice compute 并读回 storage buffer，所有 RID 在结尾释放；API依据 [Godot 官方 compute 文档](https://docs.godotengine.org/en/stable/tutorials/shaders/compute_shaders.html)。

## 截图脚本与用户存档隔离

[capture-reference-world-integration.gd](C:/Users/dains/Documents/Git/ming-armada/tools/capture-reference-world-integration.gd:80) 在 MainScene 加树前注入 Router 的三个 dependency：mingqi、legacy、settings 都是 `user://tests/reference-world-capture-<PID>-*.json`。真实菜单、scene.storage、scene.settings_storage 都由此 Router 注入；没有写 `user://saves/*` 或用户 settings.json 的接线路径。它不使用默认 continue 槽。

实际菜单点击/返回依赖原 token/router 生命周期。脚本将 scene 自动 process/physics 关闭，仅显式按 accepted tick 推进；截图 paired reflection 开关前后比较 canonical snapshot，返回 WeakRef 检查 mirror 释放。直接设置 capture camera 是观察行为，不改变 authority 位置。

非阻塞补强：capture prefix 加时间 nonce 可以避免 Windows 复用 PID 时读取同名旧测试槽；当前前缀即使复用仍在 tests 独立路径，不会碰用户正式存档。现已核读 Mingqi、Legacy 和 NavalPractice 正式 scene 均启用 reference_islands；仍需真实 menu 截图证明该来源确实出现在最终画面。

## 全部开局舰船检查

新增只读 [probe-reference-spawns.gd](C:/Users/dains/Documents/Git/ming-armada/tools/probe-reference-spawns.gd) 实例化实际 Mingqi Runtime 和新 reference HeightField，读取真正初始 native snapshot；检查全部 5 船中心及每船 9 个船体长/宽采样点，不用 dock point 代替船只。结果 ships=5、failures=0、exit 0、无 ERROR：

| 实际船只 | 中心水底高度 | 9 点最小水深 | 实际 draft |
|---|---:|---:|---:|
| mingqi-1650-flagship | -8m | 8m | 3.2m |
| mingqi-1650-grain-a | -24m | 22.089006m | 1.2m |
| mingqi-1650-grain-b | -24m | 24m | 1.2m |
| mingqi-1650-fast | -2.4m | 2.4m | 1m |
| mingqi-1650-background-grain-01 | -24m | 24m | 1.4m |

没有船舶中心或船体采样点位于陆地，水深均大于 draft+0.3m。该证据覆盖实际开局舰队，不扩张为整条运输路线或完整战役已经验收。

## 当前运行证据与未完成门槛

以下均本次直接运行 Godot 4.7.2（ed1daf0bf），非沿用旧报告：

| 检查 | 输出 / 判定 |
|---|---|
| test_reference_world_integration.gd | 668/0，exit 0，无 ERROR |
| test_naval_world_view.gd | 最新 25/0，exit 0，无 ERROR |
| test_sea_physics_integration.gd | 4457/0，exit 0，无 ERROR |
| test_wave_uniforms.gd | 8/0，exit 0，无 ERROR |
| test_coastal_waves.gd | 1090/0，exit 0，无 ERROR |
| test_wave_height_fast_path.gd | 17845/0，exit 0，无 ERROR |
| 新 test_wave_descriptor_float32.gd | RED 32/12、exit 1；修复后 GREEN 32/0、exit 0 |
| 新 test_reference_coastal_dressing.gd | 11/0，exit 0，无 ERROR |
| test_reference_island_profiles.gd | 最初假绿 4846/0、exit 0 但有 SCRIPT ERROR；修复后独立清洁 4846/0、exit 0 |
| test_reference_ocean_integration.gd | 冻结后独立 87/0，exit 0，无 ERROR |
| probe --check-only | exit 0，语法检查通过；不证明 GLSL/GPU |
| probe --offline 新 reference profile | 最新补强 2904/0、exit 0，gpuExecuted=false |
| probe-reference-spawns.gd | 全 5 船/0 失败，9 点每船，exit 0，无 ERROR |

本审查范围已完成：接线、物理合同修复、profile 非法类型清洁复跑、质量重建、最后 Ocean 静态复审与开局全部舰船。主线程交付门槛仍含：当前冻结 probe 的 GPU 再执行、实际新参考海岛菜单截图亲自验收、全套 frozen-source 回归和最新 EXE/PCK 证明。本文不给这些代签通过，也不重做已关闭的旧白色方块问题或进行性能优化。
