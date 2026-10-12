# 战斗反馈与参考效果接入审计（2026-10-13）

只读检查当前 `ming-armada` 源码；未改生产文件，未启动 Godot、REA 或测试。CodeGraph 当前工程未索引，本次使用 RTK fallback。下列“已接线”证明调用路径存在，不能替代当前 GPU/音频验收。旧 capture 仅证明曾取得样本，不能代签当前脏工作树。

正式入口路径：`mingqi_scene.gd:45-57` 开启参考操纵/炮术、创建 NavalWorldView 和 SeaServices；`mingqi_scene.gd:164-167` 将实际 snapshot/events 交给海景、音频和 UI。`naval_world_view.gd:223-232` 将同一 events 分发给船、船员和 CombatEffects，推进尾迹和云雾。

| 细节 | 当前状态 | 当前源证据与具体剩余项 |
| --- | --- | --- |
| 炮口闪光、烟、后坐 | 已正式接线，部分本作适配 | `combat_effects.gd:110-119` 使用真实 drawn muzzle 的 `fx_cannon_fire_01.nif`；`ship_view.gd:187-206` 按出生姿态找源炮口，`:208-234` 驱动 0.6m 后坐。`:57-59` 弹丸仍从物理位置绘制，烟源位置与物理炮口分开；需要实画确认两者衔接。`presentation.gd:239-241` 明示额外暖色闪光为本作显示适配。fire02/03 无生产调用。 |
| 三弹种 | 规则已接入，视觉区分未做 | `cannon_system.gd:5-11` 有实心/链/葡萄不同速度、射程、伤害和5粒散射；`mingqi_interface.gd:560-568` 可选择并显示库存。`combat_effects.gd:54-59` 每种弹丸都画同一0.18m球；没有链弹链条/旋转或葡萄弹专属视觉。 |
| 实际飞行、碰撞、伤害 | 已接入，局部命中未做 | `encounter.gd:455-488` 重力、移动旋转盒扫掠、水面先后比较、真实伤害和事件。`:464-475` 仅船壳盒/帆盒，选中后不保留命中部件，均按弹种扣 hull/sail/crew；未见独立桅杆/炮位碰撞、命中处持久木板破洞。 |
| 普通受击火花/吹出烟/碎屑 | 仍简化 | `combat_effects.gd:121-122` 仅6个棕色 BoxMesh 碎片；未接原 impact01..03 / blowout01..03，多层受击火烟尚不能算完成。 |
| 持续伤情烟、火、沉船烟 | 资源存在，生产未接 | `reference_atmosphere/definitions/assets` 有 low/medium/high/sinking smoke；生产 game 和 scene_engine 中无这些效果调用。`ship_damage.gd:99-167` 仅阶段材质、断桅/沉船动画和3种离散事件，未按伤情驱动持续 emitter。 |
| 毁船爆炸、甲板爆炸、沉船泡沫 | 局部实现 | `combat_effects.gd:127-133` 自制短闪光+8烟贴片、1.8倍 surface-only 泡沫。原 ship_destruction_explosion / explosion_on_deck / sinking_froth 的完整效果没有生产调用；当前不等同原完整源效果。 |
| 炮弹/船员落水3D splash | 已正式接线，需复核当前画面 | `water_splashes.gd:62-101` 涟漪、柱体、伞壳、世界水滴并叠加3种原 splash 回放；`:174-198` 表面泡沫与3D喷溅区分。`naval_world_view.gd:168-171` 船员入水为0.45倍水花。不要列为“没做”；低角度/俯视/海面深度交界仍需当前 capture。 |
| 云、地雾与天气覆盖 | 云雾已接，天气范围局部 | `world_view.gd:114-138,326` 正式调用 Fidelity Atmosphere。`atmosphere.gd:74,114` 5云原型+groundfog、显式种子和目标世界摆放；`world_view.gd:129` camera-follow 云高、云径、薄雾0.035为本作适配。storm/day-night/lightning 未见生产调用，不应把资源存在当完整天气已完成。 |
| 尾迹、船首/船舷浪 | 已接线，源几何覆盖局部 | `wake_trails.gd:25-37,82-115,148-159` 使用原 wake/froth 纹理，自家随波 ribbon 与船首/两舷曲面；加速/转弯会改变强度。未接按船型 authored sidefroth/bowfroth 原网格/控制器；不要把已有尾迹列为缺失。 |
| 声音与战果UI | 基础声音和练习终局已有；正式战果反馈缺口 | `sea_services.gd:40-44` 播放实际事件。`sound_palette.gd:13-20` fire/hit/splash 为合成噪声PCM；`game_audio.gd:146-157` AudioStreamPlayer仅距离衰减，`:210` audibleVerified=false。`naval_practice.gd:78-85` 有胜/败/投降标题，无战果汇总。正式 Mingqi `campaign.gd:695-705` 写 battle-ended 回执；`opening_story.gd:165-169` 历史仅筛 story-choice，`mingqi_interface.gd:510-518` 仅读此 history，无专门战果UI接线。 |

覆盖边界：`assets/data/fidelity_fx/manifest.json:4-44` 当前原生回放包只有 fire01 与 splash01/02/03（35系统）；`:799-859` 为5云+地雾（48原网格）。完整 `reference_atmosphere/coverage.json:21-32` 保存276系统合同并明确资源导入不等于运行恢复。旧 WIP `reference_particle_model.gd` 没有生产 view 调用，不能用它的完整解析数量填正式画面覆盖。

优先补齐：普通受击层、持续伤情火烟、三弹种视觉、正式战斗结束/损失汇总。命中部件与局部破损应先确定要做到哪级；现有阶段受损/断桅/击飞由其他审计覆盖。

正式终局还需实查：`mingqi_runtime.gd:229` 在旗舰 hull<=0 当 tick 立即加入 result pause；船的4.125秒沉没片段依赖 accepted time，须验证败亡时是否有完整可观看窗口，不能用敌船/QA沉没代签。Continuous胜利只产生 `battle-ended`（`encounter.gd:1063-1067`），`game_audio.gd:134` 不接受该类型，因此正式胜利提示音没有当前接线；defeat另有独立事件。

现有验证入口（本审计未执行；独占 GPU 由主线程运行）：

```powershell
rtk proxy node tools/verify-godot.mjs --filter reference_gunnery --output docs/migration/evidence/combat-audit-gunnery.json
rtk proxy node tools/verify-godot.mjs --filter fidelity_fx --output docs/migration/evidence/combat-audit-fx.json
rtk proxy node tools/verify-godot.mjs --filter reference_water_volume --output docs/migration/evidence/combat-audit-water.json
rtk proxy node tools/verify-godot.mjs --filter combat_particle_visuals --output docs/migration/evidence/combat-audit-destruction.json
rtk proxy "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --path "C:/Users/dains/Documents/Git/ming-armada" --script res://tools/capture-reference-events.gd
rtk proxy "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --path "C:/Users/dains/Documents/Git/ming-armada" --script res://tools/capture-reference-implementation.gd
rtk proxy "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --path "C:/Users/dains/Documents/Git/ming-armada" --script res://tools/capture-reference-world-integration.gd
```

`capture-reference-events.gd` 是实际 QA 入口/炮击/船员/断桅/沉船样本，`capture-reference-implementation.gd` 继承实际 Legacy 产品炮弹水碰撞并增加低角度/俯视样本；它们不能代替 Mingqi 正式战斗。`capture-reference-world-integration.gd` 证明五个正式菜单入口组合和退出清理，但未触发 Mingqi fire/hit/战斗结束。正式 Mingqi 还需从真实开局/存档推进，记录左右炮烟、三弹种命中、落水、破损、沉船和episode结束对应截图/accepted time；无需给 REA 再安排任务。
