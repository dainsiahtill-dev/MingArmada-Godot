# REA 最新效果交接：原证据、Godot 适配和下一批工作

核查日期：2026-10-12。仅新增本文；参考目录、游戏代码、资产、测试与 QA 未改动。未启动原游戏、浏览器、编辑器、GPU 或 benchmark。CodeGraph 的本项目无索引状态由主线程已确认，本任务按指示使用 RTK 定向读取，不重复查询。

参考根 **R**：`C:/Games/Pirates-REA-Reference-20261011`；目标根 **G**：`C:/Users/dains/Documents/Git/ming-armada`。以下相对路径分别以 R/G 为根。

## 当前权威与纠正

先读 [REPORT](C:/Games/Pirates-REA-Reference-20261011/REPORT.md)、[2026-10-12 修正报告](C:/Games/Pirates-REA-Reference-20261011/FIDELITY_REBUILD_REPORT.md)、[交接合同](C:/Games/Pirates-REA-Reference-20261011/AGENT_HANDOFF_FIDELITY.md)，再读各 `fidelity-rebuild` 模块最新报告。旧 `naval-study` 的原件/完整解析仍可用，旧 `deep/demo`、`island-water/demo`、`shore-surf`、`atmosphere-fx/demo` 的行为属于教学实现。

本项目 [master plan](reference-effects-master-plan.md)、[atmosphere study](reference-atmosphere-integration-study.md)、[asset bindings](reference-effect-asset-bindings.md) 的原始资源导入记录保留价值，但以下旧判断已经被新证据推进：

- 原粒子出生窗口、调度、pool、球/平面重力、四角与 packed RGBA 已在 **4 资源/35 系统**范围恢复；旧“完整调度全部未知”不能继续套用。其余 518 个解析系统或本作导入的 276 系统没有因此全部可运行。
- `sparkle_surface.nif` → `water_spaarkle.dds` 已有真实材质指针和原 `0x4E2700` 装配/选 shader 证据；原几何为 289 顶点/512 三角形。`02_sparkle_b`、`foam0016/0024` 仍属候选/本作美术选择。
- Cat 地形原参数和植被控制表已恢复。旧索引 128、`.35`、0.035、平方岛、随机云或通用镜像相机都不能作为原作常量。
- 本作可保留已接受的五波海面、现代反射/折射、本作船和 3D 水手；这些属于产品适配，原版完整画面、反射 draw、海战全生命周期仍未验收。

## 可复用的最新来源

**岸浪**：[shore/README](C:/Games/Pirates-REA-Reference-20261011/fidelity-rebuild/shore/README.md)。`source-data.mjs` 读取 `naval-study/island-water/source-study/geometry/cat_island_s.nif.json` 与 `shore-source/island-authored-evidence.json`；原 `Pak5/cat_island_s.nif` 共 8 meshes/600 顶点/300 三角形，75 独立短片复制两层。`Pak2/surf_bart3.dds` 为 8 个原 DXT3 mip，V 两端透明；不桥接成连续白圈。

**海水/微光**：[water/README](C:/Games/Pirates-REA-Reference-20261011/fidelity-rebuild/water/README.md)、[SHADER_PROVENANCE](C:/Games/Pirates-REA-Reference-20261011/fidelity-rebuild/water/SHADER_PROVENANCE.md)。`source-water.json` 保存完整原四类 NIF；`source-water.mjs` 保留原 VS/PS 的 UV 和双采样乘积。`0x4E2920` 是画质/设备分支；FX factory `0x5DE520` 与 loose PS/NSF 的分支身份不能混合。NR alpha=.40、FX=.45、loose 完整 PS=.60，最终原帧分支未知。`WavesDUDV.tga` 是 ReflectiveWater 真实 detail 槽；NIF 的 tiling33 不自动乘入禁用 texture-transform 的原海水 VS。

**岛/材质/树林**：[island/README](C:/Games/Pirates-REA-Reference-20261011/fidelity-rebuild/island/README.md)、[TREE_CANOPY](C:/Games/Pirates-REA-Reference-20261011/fidelity-rebuild/island/TREE_CANOPY.md)。`data/cat-island-original.json` 保存 H/N/B/BHI、landscape 参数与纹理 SHA；`terrain-native.mjs` 保留矩形 120×140 和截短 cell。`data/vegetation-original.json`、`vegetation-native.mjs`、`vegetation-pass.mjs` 保存原固定棕榈网格、CH/CC/CS 和 TCanopy；原棕榈 1612 顶点/1046 三角形，Canopy 每块 3312/3519。已证 CXD 构建/打包；原相机/LOD/pool 和棕榈完整 FFP 未闭合。

**云/雾**：[atmosphere/README](C:/Games/Pirates-REA-Reference-20261011/fidelity-rebuild/atmosphere/README.md)。五个 `domecloud1..5.nif` 原型共 28 个 mode0 billboard；`0x4D8060` 每实例四次 CRT rand，角间隔决定数量，不能固定 30。`0x4D8300` 严格 `accumulator > 0.03333333507180214` 才更新，只减一次阈值；名字参与原角速度，不是风向线性位移。调用时间单位、天空相机更新与现场随机历史未知。地雾是 20 实例的原加载链，一个原型有 20 meshes，两者不可混算。

**粒子**：[particles/README](C:/Games/Pirates-REA-Reference-20261011/fidelity-rebuild/particles/README.md)、`source-provenance.json`、`assets-json/*.nif.json`、`FREEZE.json`。原炮烟 `fx_cannon_fire_01` 11 系统，水花 `_01/_02/_03` 各 8 系统，普通环/柱分别 7/5/7 meshes。`runtime.mjs`、`scheduler.mjs`、`emission-window.mjs` 是新入口，优先于 atmosphere 报告中早期“未移植调度”段落。本次逐项重算 **FREEZE 165 个文件 SHA，0 缺失/漂移**；这只证明当前磁盘冻结一致。

**船件/损伤/crew**：[naval/MATERIAL](C:/Games/Pirates-REA-Reference-20261011/fidelity-rebuild/naval/MATERIAL.md)、[SKIN_NATIVE_VERIFY](C:/Games/Pirates-REA-Reference-20261011/fidelity-rebuild/naval/SKIN_NATIVE_VERIFY.md)。ShipHull 按 `ship_playercolor_*` Base 指针匹配，损伤夹 0..100、20 一档，Decal1 要 UV1；12 个 battle 炮门缺 UV1 时非零 damage 停止，不能复制 UV0。12 crew 是两个平行 quad/8 顶点/4 三角形，mode2 和 UV 图集链已证。静态 skin 仅原 rest，动态 wind/cloth/Sail shader/GPU palette 未闭合；本作保留 3D 人物和本作船。

## 具体导入/调用契约

### 单位、轴与父变换

原数据使用 NIF Z-up；当前本作粒子适配为 `(x,z,-y)`，即 `RAW_TO_GAME`，正交转换应对位置、速度、法线、相机 basis 和矩阵一致应用。原单位不能直接称米。当前 `reference_particle_model.gd` 明确选 `metres_per_unit=.01`，旧 demo `.035` 是另一选择。

建议资产清单显式保存 `source_sha256/source_block/metres_per_unit/time_scale/source_origin/parent_TRS/coordinate_space`。只在边界做一次轴和尺度转换。若 `sourceTime=q*acceptedSeconds`，位置/半径转换乘 s，速度乘 s*q，物理加速度乘 s*q²，寿命除 q；若直接执行原积分器，则在原坐标/原时间计算，最后只转换结果，不能再给速度重复乘尺度。q=1 可作为本作选择，不能声称原游戏钟已恢复。

原父树先组合 TRS；world_space 清 world rotation/translation，**保留 world scale**。Emitter/Gravity 相对 TRS=`inverse(systemWorld)*objectWorld`。新生烟取出生时炮口 pose；旧烟不随移动船拖走。一次性事件传出生世界 pose，持续发射器保存接受时间下的 pose 历史。不得在渲染层改船速、伤害、人员或存档。

Cat 原地形：`effectiveXY=.266302*250≈66.5755`；`effectiveZ=1.989325*2.5≈4.9733125`；local=`(column*XY,-row*XY,Hbyte*Z)`。rootZ=`(127.5-WaterLevel)*2.5-effectiveZ*127.5`，SurfLocalZ=`WaterLevel*effectiveZ`，WaterLevel=127，Surf worldZ≈−1.23669。127.5 来自 PE `00 00 FF 42`，不再使用误算的 312.874。Godot 现有 profile 另有缩放、旋转、海陆阈值和港口平台；原 Surf 不可未经同一转换直接覆盖本作海岸。

Canopy 三图 26×31：`CXD.x=(CH-128)/3*effectiveZ`，y=CC/255，z=CS/255；索引 `column*8+(7-row)`。块中任一 y>.5 才复制；scale3、XY 间隔2400，Z=`effectiveZ*127.9000015258789`，再加岛根。这里 CH−128 与地形 H×Z 是不同路径。新岛重生成树位/岸片必须记录为本作几何适配，并遵守真实干地、坡度、房屋 footprint 和航道。

### 时间、UV 与 mip

岸浪直接调用 `evaluateFloatController(controller,keyGroup,applicationTime)`；连续播放每控制器保留 `ControllerClock.advance()` 状态，seek 明确重建。原 cubic outgoing/incoming 是段系数，不额外乘键间 dt。`textureTransform(desc,{translationU,scaleU})` 返回 column-major mat3；type1、rotation0：`u'=scaleU*(u-centerU-translationU)+centerU`。原 U translation stop30，scale/alpha stop29.96666717529297，不能统一周期。原 UV 每片重启，不归一化拼环；Godot 纹理/viewport Y 翻转须逐 pass 记录，避免重复翻转。

原微光函数 `sparkleCoordinates(uv,time,scale)` 保留周期75/45和字面常量 `.0133333/.0222222`；原 double sample 是 RGBA 相乘。当前 Godot `reference_original_micro_sparkle(world_xz,normal,accepted_seconds,wind_direction,wind_speed,footprint,view_distance,light_alignment)` 是本作风移/阈值/距离控制，原 alpha 形状复用，不能标为原 VS 完整移植。`ProjectedOcean.set_simulation_time(seconds)` 和 `set_surface_wind(direction,speed)` 是正式接线点；不另开 shader TIME。

原 DDS 导入清单须保留每级 width/height/fourcc/byteSHA、mip count、TexDesc clamp/filter。岸浪 Clamp/Clamp、filter_mode2，alpha test20/255、SRC_ALPHA/INV_SRC_ALPHA、Z-test/no-write；原海水采样遵守对应 NSF/FX。Godot 现存 PNG 是 base 图 RGBA 转换，生成 mip 不等于原 authored compressed mip；若使用 PNG，应标记 Godot 重建 mip 的适配并验透明边缘，不冒称字节等价。

原 DDS 色通道先保存不变的 straight RGBA；不预乘、不加白、不暗化。alpha、DUDV、法线、CXD 编码通道作为数据。向 Godot HDR/linear 的显示 RGB 转换必须显式，避免 `source_color` 与手工转换重复。当前正式水色在显示空间组合后经 `reference_to_linear` 写 ALBEDO；微光 helper 仅取原 alpha，返回限定显示 RGB 增量。粒子 packed RGBA 要按原 float×255→binary32 store→FISTP 打包；最新 fixture 用 FPCW037F 最近偶数，现场原 control word 未观测。Canopy GREATER70/255、棕榈 GREATER75/255 是不同阈值，不能统一。

### 粒子调度与事件

可移植原 API：`new OriginalParticleReplay(asset,{seed,parent})` → 按明确时间步历史逐次 `advance(sourceTime)` → `systems[*].pool.active/world/bounds`。asset 是新 `assets-json` 的完整 blocks/roots；不要将本作 compact `systems.json` 直接传入。`seed`/CRT state、父 TRS、camera basis 均显式输入。原 `rand` 为 MSVCR71 32bit 状态；每成功出生7次，池满停止采样；历史线程 seed/调用消耗未知。

`num_vertices` 是原 pool capacity，`num_active` 是实际活动数；炮烟初始全0，不是固定发射 num_vertices 个。首次 Emitter update 只记录 time/visibility；窗口内取 current rate、跨完整窗口取 midpoint rate，`5AD920` 用端点出生序号差及 ages，不做任意曲线精确积分。保留 ResetOnLoop→Emitter→Update 链和 modifier stable order：AgeDeath→Box/Spawn no-op→GrowFade/Color→Gravity→Position→BoundUpdate。

AgeDeath strict `age>life`，删除后 index 继续递增；GrowFade 改 size，Color 用 age/life 键并夹 RGBA；Gravity 先改 velocity，Position 用每粒子 lastUpdate。不能追加一次解析抛物线造成双位移。变量步长到同终点不保证一致；本作暂停提供同接受时间，回退/载入明确清旧事件并重建当前状态。新 `canonical-observer.mjs` 的 f32(k/120) 和隔离终点副本是可重复 seek 的观察策略，不能称原游戏120Hz。

当前 G 的教学 model 可用 API 为 `configure(path,options)`、`spawn(effect,event_id,born,world_position,world_basis,seed,options)`、`set_emitter_transform(...,at_time)`、`set_time(accepted_time,wind)`、`stop(event_id)`、`snapshot()`；它明确 `native_runtime_equivalent=false`。若保留其积分/随机/容量作为本作策略，继续注明；若替换局部原语义，先转新 schema 和独立原 fixtures，不暗改整个276系统为“原等价”。

未来桥 API 延续既有计划：`configure(definitions,camera,water_sampler)`、`apply_snapshot(native)`、`apply_events(events)`、`diagnostics()`、`dispose()`。消费真实 event id/time/position/velocity/shipId/side；迟到按出生 age，未来事件拒绝，重复不重生。持续伤烟取当前伤情，载入不补播历史爆炸。soft depth 与水面遮挡需实际 Godot 验证；原反射完整 draw 未恢复，现共享 World3D 镜像仍作为本作适配。

## 当前 Godot 接口和缺口（源码核查）

- 正式 `modules/scene_engine/ocean/reference_game_water.gdshader` 已 include 岸线羽化和微光，只有一次 `reference_original_micro_sparkle` 调用，使用 u_time。羽化为深度0.3..3.2米/岸距3..14米，浅蓝混色最多12%；保持五波和已接受水色。`ProjectedOcean` 已绑定真实 `water_spaarkle.dds.png`。
- `assets/data/reference_atmosphere/definitions/systems.json` 已保留276系统，`assets/provenance/reference-atmosphere.json` 为完整导入来源；85 PNG 及五个 domecloud 原型已有。资源导入的旧 unknown 列表不是最新原函数恢复结论；原始字段和已验证图像身份无需重导入。
- `modules/scene_engine/fx/reference_particle_model.gd` 存在，仍线性键/连续 rate 积分、Godot RNG、默认128粒子/层与512出生/周期、解析位移和本作 wind_drag；未发现生产 consumer。`reference_particle_view.gd`、`reference_combat_fx.gd`、`reference_weather_view.gd` 均未存在。`CombatEffects` 仍六灰球炮烟、棕球受击和灰球毁船。
- Godot 原 Cat CH/CC/CS、CXD/TCanopy、原短岸片控制器没有找到生产适配入口；`surf_bart3.dds.png` 已存在。`ReferenceIslandProfile` 是原轮廓加本作美术/港口适配，不等于最新 native terrain。当前业务 mapping：厦门 coastal2、金门 cat_island、补给 virgin_islands；旧 dressing 文档的厦门/Cat 对照已过时。
- `IslandDetails` 支持成功旧房的 `existing_buildings=[{position:Vector2(x,z),radius:metres}]`；保留地形脚点/坡度/航道合同。森林密度和屋脚观感仍需主线程真实验收，不能把原 Canopy 整块直接盖到明朝港区。

## 玩法闭环完成后的第一批小任务

1. **冻结并复拍现有近岸羽化**：不换水体系。针对正式航海/港区同相机同接受时间，查湿沙→浅蓝→深海连续性、薄断续浪沫和绿色海底窗口硬边；保留 shader/纹理/RF/相机/时间 SHA 与元数据。CPU 公式通过不替代观感。
2. **微光只做同帧 0/1 对照**：用现有 strength 开关，检查近/远尺寸、低风覆盖与水色；先验已有 helper，不添加第二层。若吸收原 UV75/45，只作为独立可控策略与现 helper 比较，避免立即改物理五波。
3. **岛细节局部试点**：一处厦门坡肩/沙滩/旧房附近，使用实际干地和房屋 footprint，吸收原棕榈/Canopy 的层次与 alpha 组织；保留本作树种/建筑布局。单独记录新生成位置与原网格/纹理来源，再验港口进出通道。不要全岛批量替换。
4. **一门炮的原11层烟试点**：先独立 Godot view+真实 fire 桥，接出生 pose、accepted clock、容量和纹理 alpha/add；验证移动船留下烟、短窗关闭后旧烟寿命、暂停/迟到/重复/回退。覆盖原4资源 schema 后再扩连续伤烟和三种水花，保留当前强反馈水柱/波面过滤。
5. **天气后续批次**：五原型/原 CRT/原角更新与本作风移分别标记，可择优混合；共享主/镜像同接受帧，逐项验 billboard、透明排序和一次雾化。船体动态 skin、完整原反射 draw、原运行视频仍作为外部未知，不阻塞本作可验收增强。

## 本次重新计算的 SHA256

以下均为当前磁盘字节重新计算；原 EXE 身份引用权威报告，未重新分析 EXE。所有原件路径以 R 为根，最后四条以 G 为根。

```text
REPORT.md                                      c5cf1f831e35aacfa65772305aa4c19b880fe851180ecdf5153f2effecad68d9
FIDELITY_REBUILD_REPORT.md                      5601c21eb2f9a12c192e7e91fbae211da255df459770e64854cfb59571c794e9
AGENT_HANDOFF_FIDELITY.md                       1c45dda4120b422bf0ee07ca76f3ee70a7e3f91a3b96ccb8be05e8d778f1f9a3
raw/fpk/Pak5/cat_island_h.bmp                   c318edde392b42579a8749db353a831d7ce94cd23a27b32fe99194b159b4a217
raw/fpk/Pak5/cat_island_s.nif                   4843b4eaee86060888aad7c4462970935076a7e96b790463c16568ce5982f4e4
raw/fpk/Pak2/surf_bart3.dds                     471d4cbe0c0106b5bfde7433c3179d839fc385c27c08d7f77d53d31edc4a20df
raw/fpk/Pak1/sparkle_surface.nif                1c203b6e7afcb76f9c284735b3839ffe998a74f7d9a6671f412aaff7f75b05b1
raw/fpk/Pak0/water_spaarkle.dds                 c39470e5ee05138a31899770e6a0847a057b3503a78dc9863da27e0fb938ae66
raw/fpk/Pak2/fx_cannon_fire_01.nif              868c3a7c4ed3225c17c6c6bc0bee45c0970d5558fca03ffa8e2926b4d0c74dc7
raw/fpk/Pak1/cannon_ball_splash_01.nif          576a94f1dc9599adcf89357abb4bd6989231496c1caaa87af39062d54e35d688
raw/fpk/Pak7/cannon_ball_splash_02.nif          725c7979eff42e0dffdf8e3f496aae5182cea5d6a2f42c52983b26775a710a49
raw/fpk/Pak7/cannon_ball_splash_03.nif          cc6a915339c39730c52dc4b203fddacbeb69dd08c4459e9ab2667211ed91b0ad
fidelity-rebuild/shore/source-data.mjs         29399c0eaa1ec3862f0e5b90a183ea7cc9e601ce8d1be1d9c305acbc5aeb9278
fidelity-rebuild/shore/native-math.mjs         699617341b38d96b971c6fb3713dfa4c5154749cb2d2ed7c1b1c710113e64ddf
fidelity-rebuild/water/source-water.mjs        fd21715f606dd3a10b3001c46fcd671d60f1e3a636727ac477532b73a3a5be75
fidelity-rebuild/water/source-water.json       70eecd16357ad4d4f3b3518dad21408952d27ea834b462c3c788b113ead1b383
fidelity-rebuild/water/dds.mjs                 f9ac8b7019e1912b39b18820ff9471e1f42e23ff9bb1ae97dea5ce1150b1eb46
fidelity-rebuild/island/terrain-native.mjs     5e8d38d96506e2264e3da6d9b231e01a83a833f51d45750a07de0be919d35cba
fidelity-rebuild/island/vegetation-native.mjs  cc27feda3f912820f75d25db0da9509fd84e349e679cb3bb26a88845ba245ea3
fidelity-rebuild/island/data/vegetation-original.json cb898b13e069efef569a3652b441fce73329cb477d6fed60f5ce6db521059667
fidelity-rebuild/particles/runtime.mjs         5fa79ca4a8f5322178875c856380b65c62bb787358237881a6f313e51eb3d72c
fidelity-rebuild/particles/scheduler.mjs       52ad00a3ebe77d6ca8e01f82d097b9f38a632b1394d896b39dd78fec0f35ee8f
fidelity-rebuild/particles/emission-window.mjs b1a2f3ab2f0a6c691d03d8b4374874be45271b4b2411de891765f9c8cfda80f0
fidelity-rebuild/particles/FREEZE.json         527b33ed3dd8b0dd6bd9c4e0c8df386389b887cc7fe439ea833ddbabded48373
modules/scene_engine/ocean/reference_game_water.gdshader 412006c0afbde4d55f3a0576a0e7a87a0140b9a0abe4012f71c0306255f6b231
modules/scene_engine/ocean/reference_sparkle_fusion.gdshaderinc b216717ab8b980dbf8c0aedb7d2c3e4cc656eb049f613929a59bee1a5512b83e
modules/scene_engine/fx/reference_particle_model.gd 72e08c4dd45d4e23bf701fd0b5a2f4eec613c5295a297563ce3abde5e5a357a0
assets/data/reference_atmosphere/definitions/systems.json 66b7b7ac34d215e6206870c7d250016b9cc09568839b26b61be01f4f2b558e4a
```

原目标 PE SHA256：`0da87d60243280dea5965dbb23d099bcd0727db344de35886a5207e487a7e120`；原 MSVCR71 SHA256：`8094af5ee310714caebccaeee7769ffb08048503ba478b879edfef5f1a24fefe`。完整 raw/texture/mip 身份继续以各 source-provenance、原解析数据和 FREEZE 为准，不复制一份易漂移的大库存。

本次完成的是最新来源、接口、差异和冻结完整性的交接。原游戏运行帧、Godot 新效果的 GPU 像素、当前入口的最终动画与玩法验收均未在本任务执行；原件语义恢复、教学实现和目标游戏效果验收仍分别记录。
