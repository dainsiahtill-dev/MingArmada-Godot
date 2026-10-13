# 毁船烟与表面泡沫：可见性及源接入边界

2026-10-13。专家核对生产源码、已导入资源、测试和学习 demo；主线程完成本地产品修复、Godot 回归及原生 GPU 捕获。原程序与逆向工作区未修改。CodeGraph 未索引，采用 RTK 阅读。

## 已确认的生产与资源事实

[ShipDamage](../../game/presentation/ships/ship_damage.gd) 的死亡时间键经 [ShipView](../../game/presentation/ships/ship_view.gd#L119) 发出 `destruction-explosion`／`sinking-froth`，再由共享 Sea 接到 [CombatEffects](../../game/presentation/combat/combat_effects.gd#L132)。当前毁船仍为1个 flash 和8个手写 smoke puff，复用原 cannon smoke DDS及其 authored mip；它不是原44层毁船效果。沉船 `scale=1.8、surface_only=true` 只保留波面 RippleRing／SurfaceFroth，不生成炮弹柱、喷雾、droplets或 source cannon emitter。

[精确 replay manifest](../../assets/data/fidelity_fx/manifest.json) 只有 `fx_cannon_fire_01.nif` 与 `cannon_ball_splash_01/02/03.nif` 四个 effects。[完整参考定义](../../assets/data/reference_atmosphere/definitions/systems.json) 已有 impact 25／25／32层、blowout 14／15／16层、甲板爆炸35层、毁船44层及 low／medium／high／sinking smoke；[绑定索引](../../assets/data/reference_atmosphere/binding-index.json)及解码PNG也已导入。缺口是接线与精确 replay 覆盖，不是资源不存在。

`fx_ship_destruction_explosion` 的22个DDS依赖中，仅 `fx_water_splash_rings_01.dds` 已在精确压缩mip manifest，其余21个 explosion／plasma／smoke／sparks／splinter／圆水花／OrangeStreak依赖没有该入口。完整 [Pak5 asset JSON](../../assets/data/reference_atmosphere/definitions/assets/Pak5/fx_ship_destruction_explosion.nif.json) 含 block451 `NiPSysRotationModifier`，target为PCloud431、order3000、random_initial_axis=true；[particle_runtime](../../modules/scene_engine/fidelity_fx/particle_runtime.gd#L168) 不支持此modifier并会拒绝。因此不能只替换 effect 名称或补 manifest 就声称完整44层已接。

## 可复用 API 与出生挂点合同

[ReferenceParticleModel](../../modules/scene_engine/fx/reference_particle_model.gd#L206) 已有 `configure`、`spawn(effect_name,event_id,born,world_position,world_basis,seed,options)`、`set_time(accepted_time,wind)`、`set_emitter_transform`、`stop`、`snapshot`、`dispose`。它是纯 `RefCounted` 状态／数学模型，当前没有生产 view／shader调用，并明确 `native_runtime_equivalent=false`。其variation、色键年龄、cycle与gravity规则是游戏adapter选择，不能代签精确原运行时。

已有直接渲染入口是 [SourceEffect](../../modules/scene_engine/fidelity_fx/presentation.gd#L67)：`configure("fx_cannon_fire_01.nif", {origin,direction,scale,seed,camera,render_profile:"game_smoke"})`，随后 `apply_snapshot(age,absolute_time)`。它复用11层炮烟和原DDS/mip、没有额外 game flash；当前毁船分支未使用，且不能称原毁船44层。

这两条adapter默认原坐标 `[x,y,z]` 转 `[x,z,-y]`，采用 `.01` 米／原单位的显式缩放；速度、发射盒尺寸和radius随空间尺度变化，时间／life不缩放。纯模型另支持 `source_origin`、`radius_gain`、`alpha_gain`。学习台 `naval-study/atmosphere-fx/demo` 已有 `authoredConfig → ParticleWorld.emit/sample → FxRenderer.cards/renderFX`，但compact demo只选3个毁船代表层，`.035` scale、4米出生高度与12秒循环属于教学配置，不能直接套成原游戏合同。

本次修复在保留原 `position` 的同时，为毁船增加独立 `source_effect_position`：配置时缓存实际甲板中心支撑点，加局部UP `.35m`，经出生时船frame和解析沉没模型矩阵变换。4秒／256条历史另存不含下沉模型的 `ship_transform`，避免重复计算下沉；缺历史时保留原位置。烟发出后留在世界位置，froth仍用原位置贴合当前海面。`.35m` 是新游戏的表现偏移，不宣称恢复原dummy。炮口沿用原 `source_muzzle_position`，命中、断桅及业务字段没有通用移位。

## 当前修复与验收边界

textured puff 新增 `billboard_keep_scale=true`，恢复既有尺寸和growth，保留透明度、寿命及深度测试。[尺寸RED](../../Temp/destruction-billboard-red-20261013.json) 为91项／9失败，GREEN为91／0。[出生挂点RED](../../Temp/destruction-anchor-red-20261013.json) 为193／39；最终[GREEN v2](../../Temp/destruction-anchor-green-20261013-v2.json) 为258／0，覆盖六个实际源船型、迟到事件、非均匀变换、纯查询、重载及过期历史。独立审查发现的optional-position默认参数兼容问题也完成RED／GREEN修复。

[combat particle test](../../tests/test_combat_particle_visuals.gd) 现在覆盖keep-scale、实际size/growth、同时间transform冻结、DDS mip、透明／深度策略及释放，但事件位置仍人为 `y=2`，没有海面和最终视口像素检查。[reference ship damage](../../tests/test_reference_ship_damage.gd)及[terminal scene](../../tests/test_terminal_scene_presentation.gd)覆盖时间键、事件一次、下沉／隐藏及权威冻结；[water volume](../../tests/test_reference_water_volume.gd)和[splash fusion](../../tests/test_reference_splash_fusion.gd)覆盖SurfaceFroth几何存在及surface-only分支。它们没有烟／沉船froth的实际相机距离、出生高度与可见像素覆盖门槛；读取纹理图像或节点数不等于渲染图像验收。

本轮[汇总回执](../../Temp/destruction-visibility-verification-20261013.json) 验证14个独立相关脚本、9张真实新生涯GPU截图及当前三份产品源码哈希，零失败。最终出生烟源由原根位置y≈.202m改为独立甲板表现点y≈1.556m；事件原position／time仍保持原样。健康帧为.133333秒，从死亡开始到有限尾段完成，native／campaign始终.15秒。爆炸和froth各一次，4.5秒模型已隐藏，10秒不再推进。

同相位烟可见／隐藏两图的最大RGB通道差值>8区域，.4秒为1,611像素，1.6秒为6,245像素；只记录渲染对照差异，不当美术评分。[展开烟雾](../../Temp/destruction-final-native-20261013-v1/tail-1-6.png) 已逐张检查。该捕获使用公开致命hull fixture与手动生产回调，不能当实弹、性能或原游戏像素一致验收。早期爆闪与沉船泡沫仍偏弱；完整44层源效果、持续伤烟及全量视觉验收仍未完成。
