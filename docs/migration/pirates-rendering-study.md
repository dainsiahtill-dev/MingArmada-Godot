# Pirates! 渲染与资源学习记录

日期：2026-10-11。范围：学习现成研究，再抽查其原始 shader、NIF/KF/KFM 解析证据与完整导出几何。本轮不修改游戏、源资产或原报告，不启动原游戏，也不重新反编译。

**结论：最值得采用的是分层和分时组织。** 海面流水纹、白浪、风向亮斑、船首破水、船侧泡沫、历史尾流、炮弹落水各有职责；一张透明图片不能替代这些不同的几何、挂点和事件。先补齐落水的立体结构、船首/船侧泡沫，再调强度，比继续增加随机纹理更直接。

## 证据标记与边界

- **Observed / 已观察**：本轮直接读到的原始文本、解析字段、顶点/索引或动画键；仅指静态文件证据。
- **Inferred / 推断**：基于多个文件得到的用途解释，尚未经原游戏 draw call 或 GPU 画面确认。
- **Unknown / 未知**：运行分支选择、世界单位、额外引擎状态或采样时序仍缺证据。
- **Proposed / 本作方案**：Godot 适配与验收建议，不是原作源码或已经完成的功能。

入口：[Shader 专项](C:/Games/Pirates-REA-Reference-20261011/naval-study/SHADERS.md)、[资源专项](C:/Games/Pirates-REA-Reference-20261011/naval-study/ASSETS.md)、[资源对象图](C:/Games/Pirates-REA-Reference-20261011/naval-study/asset-evidence.json)、[资源事实](C:/Games/Pirates-REA-Reference-20261011/naval-study/asset-facts.json)、[完整精选几何](C:/Games/Pirates-REA-Reference-20261011/naval-study/selected-geometry.json)。JSON 定位采用文件名、数组名和 block id，不依赖巨大 JSON 的行号。

## 海面：以实际绑定区分层，不以文件名猜能力

**Observed：PC NSF 声明的像素程序是无反射版本。** [OceanWaterEMBM_ps11.nsf](C:/Games/Pirates-REA-Reference-20261011/naval-study/original-shaders/Assets/Shaders/FX/WaterShader/OceanWaterEMBM_ps11.nsf:96) 的 DX9 `VSProgram` 为 `VSOceanWaterEMBM.vsh`，`PSProgram` 为 `PSOceanWaterEMBM_NR.psh`（L108–112）。Stage 2/3 均绑定 `NTM_Base`，输出坐标为 oT2/oT3。[NR 像素程序](C:/Games/Pirates-REA-Reference-20261011/naval-study/original-shaders/Assets/Shaders/FX/DX9/PSOceanWaterEMBM_NR.psh:4) 只读取 t2/t3，相乘后按环境色混合，alpha 固定为 0.40。

原 [海面顶点程序](C:/Games/Pirates-REA-Reference-20261011/naval-study/original-shaders/Assets/Shaders/FX/DX9/VSOceanWaterEMBM.vsh:60) 与原 FX 的摘要相符。正时间下，记 `U = 45 * scale * inputUV`、`phase = (time % 45) / 45`：

```text
waterUV0 = (U.x + phase, U.y)
waterUV1 = (1 - U.x, 1 - U.y - phase)
A = saturate(1.5 * ambient.rgb)
P = Water(waterUV0).rgb * Water(waterUV1).rgb
output.rgb = A * P + (1 - A) * A
output.a = 0.40
```

这是颜色纹理的交错流动，不能写成“两层流动法线”。该 VS 的 position 只做矩阵变换，没有时间波高位移；这不能排除未读到的 CPU 网格变化。完整 EMBM 反射资产存在，使用 `texbem` 的二维 signed du/dv 寻址扰动；不能将任意蓝色/灰色 PNG 当成合法 DUDV 或 XYZ 法线。**Unknown：磁盘声明是否就是某次实际运行的绑定，反射 RT 如何生成，`time` 的运行单位及其他材质分支。**

**Observed：白浪层与风向亮斑职责不同。** [OceanWaterSparkle 顶点程序](C:/Games/Pirates-REA-Reference-20261011/naval-study/original-shaders/Assets/Shaders/FX/DX9/VSOceanWaterSparkle.vsh:53) 为双层 `NTM_Base` 提供 75/45 两种周期。与底层不同，这里没有额外平铺倍率 ×45，翻转 UV 为 `scale * (1 - inputUV)`。[像素程序](C:/Games/Pirates-REA-Reference-20261011/naval-study/original-shaders/Assets/Shaders/FX/DX9/PSOceanWaterSparkle.psh:3) 输出 `T0.rgb * T1.rgb * saturate(3.5 * ambient.rgb)`，alpha 为 `T0.a * T1.a`。对应 NSF 声明标准 alpha blend、Z-test 开启、Z-write 关闭，不是加法混合。

[WaterSparkle.nsf](C:/Games/Pirates-REA-Reference-20261011/naval-study/original-shaders/Assets/Shaders/FX/SparkleShader/WaterSparkle.nsf:18) 则明确写有“指示风向”的用途；Stage 0 是 Base，Stage 1 是 Detail。[VS](C:/Games/Pirates-REA-Reference-20261011/naval-study/original-shaders/Assets/Shaders/FX/DX9/VSWaterSparkle.vsh:50) 保持 Base UV、滚动 Detail 的 V；[PS](C:/Games/Pirates-REA-Reference-20261011/naval-study/original-shaders/Assets/Shaders/FX/DX9/PSWaterSparkle.psh:9) 将两张图的 RGBA 与顶点 RGBA 相乘。**Unknown：风向向量如何转换为对象朝向，原作实际展示密度和亮度。**

**Proposed：** 本作保留已有海面几何、浮力和法线，学习双颜色层的低强度流动；把白浪与风向提示单独控制。岸边浪花继续使用真实岸线距离与湿润区域，不能把 OceanSparkle 的全海白浪误作岸浪。暂停应固定所有这些层的模拟时间。原 D3D9 公式可做离线理解和小样，不直接代替本作完整 shader。

## 炮弹落水：立体水柱、水环、喷滴和水雾是不同组件

**Observed：** `asset-facts.json.facts[name="cannon_ball_splash.nif"]` 对应 [原 NIF](C:/Games/Pirates-REA-Reference-20261011/raw/fpk/Pak6/cannon_ball_splash.nif)。其 `block_types` 含 7 个 NiTriShape、8 个 NiParticleSystem，0 个 NiBillboardNode、0 个 NiMeshParticleSystem。没有 billboard 节点不等于粒子最终不会朝向相机。

| 原始对象 / block | 直接证据 | 用途与边界 |
| --- | --- | --- |
| Cylinder01 #3、Cylinder02 #130 | 各 78 顶点、126 三角；局部 Z 高度约 144/150；纹理 `fx_water_splash_004.dds` | 立体柱状壳体，不是一个竖直面片。单位和场景缩放未知。 |
| INITIAL ring001 #91、ring02 #103 | 子网格 #95/#107 各 4 顶点、2 三角；局部 Z=0；贴图 `fx_water_splash_rings_01.dds` | 起始水平水环，带节点关键帧。 |
| 2NDARY ring03/04/05 #109/#118/#124 | 子网格 #113/#122/#128 同为水平面；独立父节点、变换及部分共享材质 | 后续水环可以不同尺度、朝向和透明曲线；并非五张都必须同时显著可见。 |
| Gravity INITIALSPLASH #16 | 含 SSpray INITIAL01、INITIAL02、INITIAL 与 2NDARYcenter-lighter | 初始喷滴与延迟中心滴，粒子使用 `fx_streakin_001.dds`。 |
| Gravity 4MIST #139 | SSpray mist / mist01，粒子 #143/#163 | `fx_mist_01.dds` 水雾组。 |
| Gravity 2ndary splash #178 | SSpray 2NDARYcenter01/02，粒子 #182/#199 | 延迟高速度喷滴，与初始滴不同时间段。 |

纹理依赖来自真实材质槽，不是按名字挑选：水柱 `fx_water_splash_004.dds`，水环 `fx_water_splash_rings_01.dds`，喷滴 `fx_streakin_001.dds`，水雾 `fx_mist_01.dds`。此前提供的 `fx_water_splash_02.dds.png` 不能仅凭近似名称代替原水柱材质。

从 `asset-facts.json.facts[…].particles[].emitters[].enabled_keys` 可读到分时启用：

| 粒子 block | 启用区间（资产键时间） | 纹理 / 容量字段 | 观察 |
| --- | --- | --- | --- |
| #20/#59/#76 | 约 0.03333–0.1 | streakin / 15、16、12 | 初始短促喷滴。 |
| #41 | 约 0.33333–0.5 | streakin / 4 | 较晚的轻中心喷滴。 |
| #182/#199 | 约 0.33333–0.5 / 0.46667 | streakin / 4、3 | 延迟二次滴，重力强度字段与初始组不同。 |
| #143/#163 | 约 0.43333–0.5 | mist / 8、20 | 水雾稍晚；寿命变化字段较大。 |

容量是 `NiPSysData.num_vertices` 字段，不是实测同时可见滴数。例 #20 发射率键为 225、速度约 444.37、寿命 0.5、重力强度约 989.1，重力轴局部为 (0,0,1)。父节点还带旋转；不能直接当 Godot 的 m/s、m/s² 或世界向下方向。

水柱也不是从零时刻持续高亮。`asset-evidence.json.assets[name="cannon_ball_splash.nif"].blocks` 中：

- #13/#136 `NiAlphaController` 分别指向水柱材质 #12/#135；#14/#137 曲线在约 0.400625 仍为 0，0.425208 附近峰值仅约 **0.0250 / 0.0436**，0.725 归零。
- #7/#133 `NiTextureTransformController` 操作 V 平移，区间约 0.42625–0.9；#8 第一柱 V 从约 -0.7010 到 0.5716，#134 第二柱则回到接近初始 V。
- 多个 `UserPropBuffer` 含 `zMode10`；本轮没有恢复其原引擎解释。上述材质 alpha 不能独立预测最终像素亮度。

**Inferred：** 有价值的是“短促喷滴、延迟低强度柱状细节、水雾、水面扩散”组成的事件时间线。**Unknown：** 本文件变体是否为当前运行所用、各组的最终混合和粒子朝向、所有父变换组合后的效果尺度、同帧启用数量。

**当前差距：** 集成任务记录显示，本作已试绑 27 张源图，落水目前采用稀疏 2D sprite 与水环；本研究未重审 Godot 产品源码。这样的实现能提供事件与轮廓，但仍缺真实柱状体、空间喷滴以及清晰的分时组件，不能宣称已复现原作 3D 水花。二维软遮罩可解决白色方块，却不能解决所有角度下的立体感。

**Proposed：** 先用 1–2 个自建低面数柱状/伞状壳体、1–2 层水平水环和有预算的水滴/雾组验证结构；按真实落水事件设置世界位置，水环采样本作海面高度。喷滴离开船后保持世界轨迹。学习原配置的职责和相对时序，重新按本作船长视角、船型比例与性能预算定单位和曲线，不强制复制 7 网格、8 系统。Godot 可用 ArrayMesh 生成柱体/环/尾流；官方说明支持用顶点、UV、索引数组创建网格。喷滴/雾可评估 GPUParticles3D，其粒子行为材质与绘制网格分开；若难以满足本作暂停/回放时间契约，先采用受模拟时间控制的固定预算实例池。[ArrayMesh 官方文档](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html)、[GPUParticles3D 官方文档](https://docs.godotengine.org/en/stable/classes/class_gpuparticles3d.html)。

## 船首、船侧、船尾：挂点效果与历史轨迹分开

**Observed：** `asset-facts.json.facts[name="fx_ship_bowfroth.nif"]` 是 1 网格、4 粒子系统，纹理为 `FX_waterfroth_001/002/003.dds`。[原文件](C:/Games/Pirates-REA-Reference-20261011/raw/fpk/Pak1/fx_ship_bowfroth.nif) 的 `Dummy_bowfroth` #3 具有左右舷 `SuperSpray port 01/02` 与 `SuperSpray star 01/02` 子节点；这是船首左右破水的结构证据，不证明本作已有对应挂点效果。

**Observed / 报告细节修正：** [fx_ship_sidefroth_sloop.nif](C:/Games/Pirates-REA-Reference-20261011/raw/fpk/Pak7/fx_ship_sidefroth_sloop.nif) 的 #3 `sidefrothPRT` 实际是 **NiTriStrips**，0 粒子系统；#15 `NiTriStripsData` 为 150 顶点、存储 `num_triangles=284`。`selected-geometry.json.meshes[asset="fx_ship_sidefroth_sloop.nif", block_id=3]` 导出 **214 个非退化三角**。ASSETS.md 的 NiTriShape/284 三角描述需按这一区分理解，不能把节点名里的 PRT 当粒子，也不能把 strip 退化连接当实际可见面。其材质实际绑定 `FX_waterfroth_003.dds`。

[wake.ini](C:/Games/Pirates-REA-Reference-20261011/raw/fpk/Pak1/wake.ini) 直接注释 `WakeTexture` 应用于 wake geometry；配置含 50 个 waypoint、生成时间 0.025、生成距离 20、宽度 150，以及 `Wake3unique.dds`、`WakeSpreadFunc.bmp`、`WakeAlphaFunc.bmp`。后二者分别描述按点序号扩散、按点龄调整 alpha。**Unknown：** 单位、时间与距离阈值的实际组合、销毁参数准确含义；原生实现须由算法研究核对。不能用 `wake3.dds.png` 文件名推断它就是配置指定的 `Wake3unique.dds`。

**Proposed：** 船首/船侧效果挂在本作船型定义的局部水线点，随迎水速度产生；船尾保留历史世界位置并渐宽、渐淡，不能每帧整体旋转旧尾流。停船停止生成，转弯保留曲线，倒车/侧滑另设规则，传送/场景切换断开轨迹；所有水线网格随真实海面采样，alpha 使用软边而非均匀白矩形。岸浪、船首、侧泡沫与尾流各用有限强度，不能重复堆白。

## 船员：海战甲板人和飞出船外的人分级表现

**Observed：** `sloop1-battle.nif` 有 12 个 NiBillboardNode、0 个 NiSkinInstance。对象链可按 `asset-evidence.json` 查到 `crew_null` #131、`D_Crew_11` #133、NonAccum #135、`Editable Mesh@#11` #136。#133 的 billboard_mode=2；材质实际为 `ship_crewman_pir.dds`。#136 为 8 顶点的两层平行面，存储三角数 8，精选几何中为 4 个非退化三角，不能当成蒙皮人物。

[deck_crew KF](<C:/Games/Pirates-REA-Reference-20261011/raw/fpk/Pak7/sloop1-battle_dummy sloop_crew_null_deck_crew.kf>) 的 sequence `deck_crew` 含 12 个纹理变换控制器。第一个控制器目标为 `Editable Mesh@#11\nPROP\nNiTexturingProperty`，base slot 的 U 平移在 0–1 时间中由 0 到 1。材质的 `12fps` 名称是作者意图；本轮未恢复运行时采样量化，不能声称测得 12 fps。

对照 [crewman_in_water_a.nif](C:/Games/Pirates-REA-Reference-20261011/raw/fpk/Pak2/crewman_in_water_a.nif) 的 `skins[0]` 确有 23 个影响骨骼，包含 Bip01 的躯干、臂、腿；其 KFM 引用 `flying`、`floating_on_plank`、`swimming_in_place`。独立角色的骨骼动画存在，不证明 flying 是实时 ragdoll，更不证明原作炮弹逐骨骼物理击飞。

**Proposed：** 本作近处甲板保留可辨认的 3D 水手，远处采用低细节模型或原创图集；借用原作分级成本，而不是用全部 billboard 取代用户要求的 3D 船员。炮弹击飞由本作物理/战斗层产生命中、冲量和状态事件，表现层从有限池播放飞出、落水与漂浮状态。远景人物数量由真实船员状态决定；显示槽数不充当人员伤亡计算。是否用布娃娃、简化刚体或预制动作混合，应由可控性与验收结果决定。

## 受击与沉船：状态贴图加预制动画，不虚构实时切割

**Observed：** [船体像素程序](C:/Games/Pirates-REA-Reference-20261011/naval-study/original-shaders/Assets/Shaders/FX/DX9/PSShipHull_11.psh:10) 按 Damage、Improvement、Base、PlayerColor 的优先级分配颜色权重，最终 alpha 来自 VS 输出。[船体 VS](C:/Games/Pirates-REA-Reference-20261011/naval-study/original-shaders/Assets/Shaders/FX/DX9/VSShipHull_11.vsh:82) 的实际指令用世界 Z 和深度参数形成 alpha；不能把注释中的减号覆盖指令里的加号，也不能把 Z 原样套到 Godot Y-up。

[SailShader.NSF](C:/Games/Pirates-REA-Reference-20261011/naval-study/original-shaders/Assets/Shaders/FX/SailShader/SailShader.NSF:38) 的 PC 路径使用固定功能纹理合成：Hole alpha 保留为透明阈值，Sail、Emblem、Scorch 混合 RGB。原文件不提供现代布料解算；船 NIF 中帆、旗、索具的 skin 不能计作水手 skin。

`asset-facts.json.animations` 与原 KF 给出明确时间线：

- [Sloop 断桅](<C:/Games/Pirates-REA-Reference-20261011/raw/fpk/Pak4/sloop1_dummy sloop_dismasted.kf>) 含 53 个 NiKeyframeController、2 个材质颜色控制器；`Dummy MainSail` 由高处移到海平面附近并旋转。文本键约 0.041667 触发 `playeffect,fx_mast_break,fx_mast_1`，2.666667 为 end。
- [battle 毁船](<C:/Games/Pirates-REA-Reference-20261011/raw/fpk/Pak3/sloop1-battle_dummy sloop_destruction.kf>) 含 31 个节点关键帧控制器和 12 个船员 UV 控制器；0.25 触发 explosion，1.416668 触发 sinking_froth，4.125 为 end。原 KFM 的 EVENTCODE 1/2/3/13 分别为 dismasted/destruction/run_out_guns/deck_crew。

**Unknown：** 没有足够证据支持实时网格切割、全部碎片碰撞或落水人物逐骨骼解算。**Proposed：** 先让本作统一损伤状态控制补丁/焦痕、破帆遮罩、桅杆状态和可中断沉船时间线，关键事件只触发一次；保留物理层判定与表现层动画的边界，随后再选择少量需要碰撞的碎片。

## Godot 实施顺序与真实画面验收

1. **保持水面基线。** 同一船、相机、太阳和波幅拍当前基线；单独开关颜色流动/白浪/风向亮斑。通过条件是亮度符合目标、波高不淹船、没有整片纯白或暗块。
2. **立体落水小样。** 以一次真实炮弹落水为同一事件，拍起始、约 0.1、0.4、0.7、1.2 的帧；再用俯视、低视角和侧视复查体积、水环贴海与遮挡。设计时序可调整，记录每项相对原配置的变化。不得只有 billboard 正对镜头的一张漂亮图。
3. **船首/侧泡沫与历史尾流。** 实际起步、直航、持续转弯、收帆停船、倒车、重新前进；截图和短序列证明尾流曲线、渐宽渐淡、无矩形边界、不会与船同步扭转或跨断段连接。
4. **船员和受击。** 近、远镜头显示 LOD 和动作；真实命中事件造成有限数量人员飞出，不重复生成，不把未命中的人全部弹走。落水状态与后续船员数能对上。
5. **暂停、回放/重入与性能。** 暂停后水环、喷滴、雾、尾流不继续老化；重入无残留。用实际目标硬件在原生前台窗口测正常海战及连续炮击峰值，记录 CPU/GPU 帧时、透明 overdraw、池容量和销毁情况，再定质量级别。自动截图驱动不能替代有效帧率测试。

透明层需真实 GPU 检查排序和深度，防止水面遮住尾流、喷雾盖住船体或 alpha 形成硬矩形。Godot 官方说明透明物体有排序限制；提高 render priority 不是绕过所有深度问题的通用修复。[标准材质透明度说明](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html)。

本轮报告没有原作 GPU 对照，也没有声称新游戏视觉功能已完成。后续每项须保留真实事件、相机、模拟时间、截图和实际验收结果；离线公式一致仅证明其覆盖范围内的数学。

本轮独立静态复核：46 份 shader 副本 SHA-256 与清单一致；8 份本报告关键 NIF/KF 原文件与解析证据 SHA-256 一致；10 组精选几何索引均在顶点范围内；报告 24 个本地链接存在。三处 Godot 能力引用已读官方文档。未重新运行原报告的 9,000 个 shader 算术案例，未把其历史结果算成本轮新验证。
