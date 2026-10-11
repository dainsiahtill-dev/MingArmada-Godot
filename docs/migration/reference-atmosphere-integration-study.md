# 云雾、炮火与烟：Godot 整合研究

日期：2026-10-11。阶段：只读研究完成，等待正式海岛/海面整合冻结后实施。此次只新增本文；未修改游戏代码、原参考文件，也未启动 GPU 窗口。

## 结论与现状

参考学习页已有可直接移植的确定性发射、粒子轨迹、尺寸/颜色曲线、透明混合、云层风移和雾片代码。正式 Godot 游戏已有真实 fire/hit/splash 事件、炮口挂点、accepted time、受损阶段及共享 World3D 镜像反射，可以连接这些实现。缺口主要是有纹理的烟火、持续伤情烟、云/地雾及正确的透明深度合成，不需要重写船舶物理或炮弹伤害。

当前 [CombatEffects](C:/Users/dains/Documents/Git/ming-armada/game/presentation/combat/combat_effects.gd:40) 使用 SphereMesh 和纯色 StandardMaterial3D：fire 是短闪光加六个灰球，hit/mast-break 是棕球，destruction 是闪光加灰球。它已按事件原始时间重建迟到效果、去重、回退清理并调用独立 WaterSplashes；这些行为应保留，由新烟火渲染器替换灰球表现。

已有 [ShipView](C:/Users/dains/Documents/Git/ming-armada/game/presentation/ships/ship_view.gd:129) 在 GLB 中查找 `socket_smoke_port_*` / `socket_smoke_starboard_*`，按真实发炮点选最近炮管，驱动 0.6m 后坐。现有 native [fire 事件](C:/Users/dains/Documents/Git/ming-armada/modules/naval_simulation/encounter.gd:437) 保存 shipId、side、ammo、projectileId、position、velocity；应使用事件世界位置和方向，不能重新用当前船位置生成过去的炮烟。

在当前源码和 `assets/textures/pirates_reference` 的实际目录检查中，没有专门的云层、地雾、持续船火渲染模块；31 张参考纹理主要是水、泡沫、水花。下文 demo 所需 11 张 PNG 均尚未进入该目录。

## 已读的一手入口

参考根目录：`C:/Games/Pirates-REA-Reference-20261011/naval-study/atmosphere-fx`。

| 文件 | 实际职责与可复用内容 |
|---|---|
| [README.md](C:/Games/Pirates-REA-Reference-20261011/naval-study/atmosphere-fx/README.md) / [AGENT_HANDOFF.md](C:/Games/Pirates-REA-Reference-20261011/naval-study/atmosphere-fx/AGENT_HANDOFF.md) | 来源、单位、已恢复与教学近似边界、事件和资源字段。 |
| [demo/model.mjs](C:/Games/Pirates-REA-Reference-20261011/naval-study/atmosphere-fx/demo/model.mjs:12) | emissionSchedule、growFade、父 TRS、确定性 LCG 随机、ParticleWorld、authoredConfig、透明排序。 |
| [demo/clouds.mjs](C:/Games/Pirates-REA-Reference-20261011/naval-study/atmosphere-fx/demo/clouds.mjs:2) | 天气位移积分、三层云速、30 片云、560 单位循环空间、220..280 边缘渐隐。 |
| [demo/renderer.mjs](C:/Games/Pirates-REA-Reference-20261011/naval-study/atmosphere-fx/demo/renderer.mjs:46) | alpha/additive 独立绘制、无深度写入、opaque+water 深度取样、主/镜像共享云帧、地雾片。 |
| [demo/shaders.mjs](C:/Games/Pirates-REA-Reference-20261011/naval-study/atmosphere-fx/demo/shaders.mjs:1) | 世界贴片、纹理原 alpha、遮挡、软交界、加法层雾衰减、全屏距离雾。 |
| [CLOUD_REFLECTION.md](C:/Games/Pirates-REA-Reference-20261011/naval-study/atmosphere-fx/CLOUD_REFLECTION.md) | 每帧云位置/朝向只算一次、镜像绘制、连续时钟和边界淡出合同。 |
| [完整 particle-contract.json](C:/Games/Pirates-REA-Reference-20261011/naval-study/atmosphere-fx/source-study/particle-contract.json) | 276 个真实系统；原 block、SHA、父变换、控制器、modifier 和属性继承。 |
| [compact-demo.json](C:/Games/Pirates-REA-Reference-20261011/naval-study/atmosphere-fx/source-study/compact-demo.json) | 浏览器实际使用的 10 个代表层，已规范为便于 demo 消费的字段。 |
| [SOURCE_REPORT.md](C:/Games/Pirates-REA-Reference-20261011/naval-study/atmosphere-fx/source-study/SOURCE_REPORT.md:72) | 云/雾网格、纹理原 RGBA、完整几何与控制器证据。 |
| [SHADER_REPORT.md](C:/Games/Pirates-REA-Reference-20261011/naval-study/atmosphere-fx/shader-study/SHADER_REPORT.md:26) | alpha、depth、不同雾指标和 UV 旋转/缩放控制器。 |

既有迁移文档中未发现完整的 atmosphere 接入报告；[reference-implementation-event-time.md](C:/Users/dains/Documents/Git/ming-armada/docs/migration/reference-implementation-event-time.md) 已记录当前灰球的事件年龄规则，不能重复退回墙钟动画。

## 可直接移植的算法

1. **短窗发射**：分割 rate key 与 active key 的时间区间，对线性速率积分；每跨一个整数质量阈值算出生时间。active 关闭瞬间不生成新粒子，已经出生的烟继续活到 lifespan。不要把发射窗延长到烟的寿命。
2. **确定性轨迹**：事件 ID 派生稳定 seed；LCG 的状态和溢出按 `uint32` 处理。出生时保存炮口世界变换，后续以 `age = acceptedTime - birthTime` 求值。相机变化、重复事件与渲染帧数不影响轨迹。
3. **原父变换**：按 child 到 parent 顺序应用 TRS，位置包含平移、方向排除平移。demo 统一使用 `(x,z,-y) * 0.035` 做 Z-up 到 Y-up 转换；0.035 是示例选择，原单位未知。游戏船尺度不同，应该给定义一个明确的统一倍率，不能分别随意缩放速度和半径。
4. **GrowFade**：匹配 generation 时，尺寸乘 `max(1e-4, min(age/growTime, remaining/fadeTime, 1))`。它调尺寸，不调 alpha；color keys 的 alpha 独立求值。
5. **烟色与透明**：纹理保持 straight RGBA，颜色曲线与材质 alpha 独立相乘。正常烟用 alpha blend；火光用独立 additive 定义，不能从 `Additive.nsf` 文件名推断 framebuffer 状态。
6. **云连续位移**：对风向/风速逐段积分 offset；改风只影响之后的增量。不能每帧用“累计时间 × 新风速”，也不能用短烟火循环时间驱动云。暂停依赖 accepted time，不依赖 shader 内置 TIME。
7. **主视角/倒影一致**：云 world positions 和 right/up 从主相机算一次；镜像相机只改变 view/projection，不能在镜像 pass 再让贴片面向镜像相机。正式海面已有 [共享世界镜像](C:/Users/dains/Documents/Git/ming-armada/modules/scene_engine/reference_island_water/ocean_renderer.gd:113)，无需创建第二个天气世界。

以上数学可移植，但 demo 的颜色 age 映射、随机分布、容量、云布局和风速属于明确教学选择。完整 Gravity、Spawn 代际调度、原 controller 循环及原运行时 shader 选择尚未全部恢复；这是参考证据的边界，不妨碍先将现有可运行表现接入游戏。

## 资源范围：代表层与全量定义应分开

当前 demo 10 层：fire01 的 block 9/92/114；低损伤 block 7；高损伤 block 7/140；沉船 block 7；毁船 block 7/684/795。所需 PNG 如下，可原字节复制并记录源 SHA；参考目录保持只读。

| 文件名 | 用途 | PNG SHA-256 |
|---|---|---|
| fx_cannon_smoke_01.dds.png | 炮烟 | f82129f7e3894081579e090246918899736d41d0b77970b508a2ee824f6c9814 |
| fx_cannon_smoke_03.dds.png | 炮烟第二层 | 26d402de1e9bf74eb782feb2a2cbafe0d89889f00cdff67b4fa9860310f605c9 |
| fx_underlit_smoke02.dds.png | 伤情烟 | 49e65b173f52120e8987d9695224f26a894cddf3fca343184e87a0aca9e4aa08 |
| fx_underlit_smoke02_mortran.dds.png | 伤情烟变体 | 724442b44bfa8c397df8821b30fe15c10b4817c6810ade52e5c1d8da3b657ec3 |
| fx_underlit_smoke03.dds.png | 沉船烟 | 056b04c93e5364a7b75871a2f1fad2b62cdf8be79736daab2dcf4badeb69d3d9 |
| fx_ember_001.dds.png | 余烬 | 82c1b6d4fb05fdd3e7dae04b179c2b22814a146189573068eaebcd174fa7c1f7 |
| fx_explosionplasma_002a.dds.png | 爆炸火光 | 282777a0ab6e33e8238ec8be4743ce47ab662a8323f967cf3885c318b7142ca4 |
| fx_explosionsmoke_002a.dds.png | 毁船烟 | c82322c4a616fd997e74b0e7d6137d526f44b54c834bd174691b6c82dd02c69b |
| fx_splinter_02.dds.png | 木碎屑 | 3dc11d3511c2ad728cfd6d2ec9115f472721aebad3bafa80b8b711278f860cb7 |
| cloud_bw.dds.png | 云 | e2830c7c5de01723f157d8c685b7807feb8261bed023d5a485646506d6b61f93 |
| fx_groundfog_crop01.dds.png | 地雾片 | 63d54e28032d4a2491166f44c92272ef1f3392ec879688adab8c3d55285f8ce2 |

完整参考有 53 张 PNG，纹理合同 `unresolved=[]`。其中三档炮火各 11 个系统；三档 impact 为 25/25/32；三档 blowout 为 14/15/16；低/中/高/沉船烟为 7/6/17/6；deck explosion 为 35；ship destruction 为 44；smoketrail 为 1，共 276。全部现代系统在合同中为 world-space BoxEmitter，另外天空/云/地雾/风暴及旧 NiParticles 保存在 assets-json，不能强塞同一现代系统字段。

**完整合同与 compact 合同不是同一 schema。** 完整数据使用 `property_chains`、`emitters[*].emission_controllers`、`emitters[*].emitter_transform_chains`；compact 使用 `render_properties`、`emission`、`parent_transform_chains`。不能让 authoredConfig 直接遍历完整合同。完整数据中有 6 个负 start time 控制器，且保留 LOOP/CLAMP 等 flags。需要显式 converter 和 coverage manifest，记录每个 source block 是否已转换、每种 modifier/controller 是否实现或明确近似；不能静默丢 266 层后声称全量。

## Godot 接线中必须解决的画面问题

**透明深度**：浏览器的 soft particles 读取独立 opaque+water depth。Godot 文档明确透明材质不进入 `hint_depth_texture`；当前海面写 ALPHA，单凭 `depth_draw_always` 不能证明烟 shader 取到包含水面的深度。需做真实像素探针，再选择独立包含水面的深度目标或经验证的解析波面深度。先使用硬件 depth test 保证船/岛遮挡，再补软交界，不能声称普通 hint depth 已完整复刻浏览器。[Godot Spatial shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)

**深度公式**：示例固定 near=.3/far=1200 且 OpenGL depth；实际游戏 near=.5/far=4000。移植时用当前 pass 的 INV_PROJECTION_MATRIX 重建 view Z，不照抄示例公式。Godot 4.3+ 使用 reverse Z；Forward+ 与 Compatibility 的 NDC Z 范围不同。深度采样必须属于当前 viewport，不能直接借镜像 viewport 的 hint depth。[Godot Advanced post-processing](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html)

**透明排序**：alpha 烟要按相机前向深度排序；加法层独立处理。Godot 默认按 Node3D 原点排序，不是逐顶点排序，云/烟全部挤在一个大 Mesh 中可能与岛/船/海面错序。使用独立贴片 Mesh 或有明确排序的专用 renderer；主/镜像两 pass 分别排序，但几何朝向保持一致。[Godot Transparency sorting](https://docs.godotengine.org/en/stable/tutorials/3d/3d_rendering_limitations.html#transparency-sorting)

**一次雾化**：现正式海水/地形 shader 仍有 `1-exp(-distance*.0015)` 的基底雾，Environment fog 已关闭。新的统一雾 pass 启用时，要通过可配置 uniform 禁用该基底雾，并在 smoke/cloud 中用同一距离定义；不要叠加两次。原 demo 本身用 view-Z opaque fog、欧氏距离透明 fog，是明确近似；若为游戏统一模型，应记录这是改进，不称原参数等价。

**反射中的透明天气**：云通过共享 World3D 可进镜像；shader 需避免镜像下重新 billboard，保留海面以下 clip。粒子反射/折射在原 demo 中未实现，若正式游戏加入，需要独立验证；不要以云倒影通过代替烟火倒影通过。

## 可独占的文件拆分与根 Agent 接线点

以下是拟新增文件，不代表已经实现。

| 所有权 | 独占新文件 | 接口与边界 |
|---|---|---|
| 资源/控制器专家 | `tools/import-reference-atmosphere.mjs`；`assets/data/reference_atmosphere/definitions.json`；`assets/textures/reference_atmosphere/*` | 读取参考合同，转换自家 schema、保留来源和未实现项、核 SHA/alpha。只写新目录，不动水纹理。 |
| 粒子专家 | `modules/scene_engine/fx/reference_particle_model.gd`、`reference_particle_view.gd`、`reference_particle_alpha.gdshader`、`reference_particle_add.gdshader`、共享 `.gdshaderinc` | 模型是纯资源/轨迹数学；view 消费 accepted time 和世界事件变换。无 gameplay/physics import，不修改炮弹速度/伤害。 |
| 天气专家 | `modules/scene_engine/atmosphere/reference_weather_model.gd`、`reference_weather_view.gd`、`reference_cloud.gdshader`、`reference_ground_fog.gdshader` | 消费 accepted time、风、主 camera；连续 offset，主镜像同帧几何。场景坐标很大时按明确世界锚点构造云场，不能让相机位移造成云跳跃。 |
| 游戏接桥专家 | `game/presentation/combat/reference_combat_fx.gd` | 将真实 fire/hit 和船只状态映射为 FX 定义；damage tier 属新游戏配置，沿用现有 hull stage，不伪造原 HP 阈值。只在 tier 改变时启停持续发射器。 |
| 根 Agent | `combat_effects.gd`、`naval_world_view.gd`、必要海/地形 fog uniform 接线 | 替换旧灰球，保留现有球弹、水花、事件去重与 rewind；把同一 native snapshot/wind/acceptedTime 注入桥和天气，集中生命周期/质量重建/场景切换。 |

建议新桥公共 API：`configure(definitions, camera, water_sampler)`、`apply_snapshot(native)`、`apply_events(events)`、`diagnostics()`、`dispose()`。renderer 与 bridge 的事件数据包含 eventId/seed/born/worldPosition/worldBasis；事件已出生的 world-space 烟不再绑定船节点。持续伤情烟需按当前船姿态生成每个出生点，已出生粒子脱离船体；第一帧载入受损船应显示当前持续烟，但不补播过去的爆炸。

接线顺序：海岛/海面正式验收后，先三层炮烟和真正纹理瞬闪，再命中/破损/持续烟及余烬，然后云/地雾与统一 fog，最后全部已需用的定义/控制器和风暴动画。完整参考层的迁移覆盖清单应作为后续工作保留。现有 NavalWorldView 同时服务航海/海战/历史航程，一次桥接后各实际入口都应验证。

## 验收与本次已取得证据

本次在当前参考源上直接运行 CPU 测试：

```powershell
rtk proxy node --test C:/Games/Pirates-REA-Reference-20261011/naval-study/atmosphere-fx/tests/model.test.mjs C:/Games/Pirates-REA-Reference-20261011/naval-study/atmosphere-fx/tests/clouds.test.mjs
```

结果：17 tests、17 pass、0 fail、exit 0。覆盖窄窗口发射、rate 切点、GrowFade、父 TRS、原颜色键、死亡、确定性、透明排序/混合、零雾、四向风、调速连续、粒子循环跨界、云边缘循环。这里只证明参考 CPU 实现当前可运行，不证明 Godot 接入或画面验收。

Godot 实施后至少需要：左右真实炮口截图，运动船的世界烟轨迹，active 结束后的烟寿命，迟到事件直接进入正确 age，重复/未来事件、暂停/回退/重建，真实受击和沉船持续烟，船/岛前后遮挡像素，软水交界像素，普通 alpha 与 additive 分辨，零雾无残余和一次雾化，云主视角/海面倒影同步、改风连续、镜像 clip、tactical 上视角 billboard 退化保护，以及所有实际游戏入口返回/重进不泄漏。截图由根 Agent 亲自检查；此次没有进行 GPU 或性能验收。

当前学习代码来源 SHA-256：

| 文件 | SHA-256 |
|---|---|
| demo/model.mjs | 37018104c7415270c705c211fd2e4866347a7df8c410477aecce0d378f7c98c1 |
| demo/clouds.mjs | b671cc209bade6a62c2ec67b3b9a7e199a24743aaff8a0888490e6de2c8170dd |
| demo/renderer.mjs | 173b4a343e36aa2f26740f4931645bd74912812b2d177c329424798d7eaaf191 |
| demo/shaders.mjs | f205365b79709bb44ec2b1dcf88d5ec1759b2131308f02e46a1725d86adba55c |
| source-study/compact-demo.json | 1eb9e7bc420250f9715ed994c6337682da5a20e7c3aff9b894b7e60f8f302eb3 |
| source-study/particle-contract.json | d0fb3bf093ec8405d295394040d23b6f261d939a3c627de8f70c4d9b18cd29ec |
