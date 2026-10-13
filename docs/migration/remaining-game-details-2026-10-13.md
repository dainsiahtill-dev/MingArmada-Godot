# 当前游戏细节盘点

2026-10-13。审计真实 Godot 项目 `ming-armada`，采用当前源码、生产入口、测试与原生截图。CodeGraph 未索引，使用 RTK 发现。原网页、原游戏和逆向工作区未修改；没有新增玩家可见的独立示例入口。此前完成缺口盘点和性能实测，本轮继续落地终局沉船／击飞呈现与入水交接修复，并阅读新操船交付。

## 结论

船体／船帆损伤、断桅、有限沉船、真实骨骼击飞、炮口源粒子、三维落水水花与尾迹已经接入共享游戏表现。完整火灾与进水、独立部件伤害、长期落水救援、碎木漂浮、完整战果反馈与更长的新生涯剧情仍有明确缺口。导入贴图、粒子参数或独立 demo 不等于已完成游戏接线。

| 项目 | 已有 | 尚未完成／表现不足 | 当前证据 |
| --- | --- | --- | --- |
| 船壳与船帆破损 | 原十一张损伤图的分档绑定、帆洞及边缘损伤，六船型／三LOD | 根据实际命中位置的持续破洞、局部裂口／帆布破裂 | [ShipDamage](../../game/presentation/ships/ship_damage.gd#L99)、本轮 damage 三脚本 GREEN 与损伤 PNG |
| 断桅 | 帆损失全部时全桅、帆、索具一起倒伏 | 单桅独立受损、断木分离、脱落桅杆撞击／入水／漂浮 | [ShipDamage](../../game/presentation/ships/ship_damage.gd#L114)；并非任意网格断裂 |
| 沉船 | 模型倾斜下沉、爆炸键、表面泡沫、最终隐藏；正式终局最多10秒呈现，业务冻结 | 终局冻结已修；完整毁船层次、烟雾／水花读感、浮木和全员疏散仍缺 | 原 RED `Temp/terminal-sink-audit.json`；[终局修复与验收](#正式终局缺陷与修复) |
| 船员击飞 | 原站立皮肤转18骨／17关节Jolt；随权威减员；甲板／海面接触；终局逐物理步寿命与请求 | 人体关节角约束、起身过渡、局部受伤、更清晰的击飞读感；沉船全员跳海未接 | 原真实 cannon QA capture；新增正式场景真实18骨fixture年龄／请求回归，未把它当未等待引擎的位移证据 |
| 落水及救援 | 入水事件接通用水花；物理／绘制间的水花事件排队；短暂接触后回收；非致命回站位 | 长期海上人员、游泳／漂浮木、靠船拾救、人数转移回执与存档 | 真实骨接触回归＋Pool信号到Sea/Effects交接回归；[ImpactPool](../../modules/physics_engine/impacts/impact_pool.gd#L130)、[crew 审计](audits/crew-details-2026-10-13.md) |
| 火灾与进水 | 存档 schema 有 fire／flooding／mast／炮组字段 | 实战起火、燃烧持续伤害、灭火、进水、排水、对应岗位与提示未形成链路 | [Campaign](../../game/domain/mingqi/campaign.gd#L1120)；native hit仍只处理 hull／sail／crew |
| 普通受击与爆炸 | 炮口 fire01 源粒子、短闪、简单木片、9个手写毁船 puff；billboard保留实际尺寸，毁船独立出生甲板挂点已接入并验证 | 原 impact／blowout／甲板及44层毁船效果已导入定义但未接生产；爆闪与沉船泡沫读感仍偏弱；碎木仍统一BoxMesh，没有重力／旋转／碰撞／漂浮 | [CombatEffects](../../game/presentation/combat/combat_effects.gd#L110)、[毁船可见性与接入边界](destruction-visibility-2026-10-13.md)、[combat 审计](audits/combat-details-2026-10-13.md) |
| 三种弹药 | 实心弹、链弹、葡萄弹的库存／射程／伤害／散射与实际飞行；结算后回收停止运动的显示弹体 | 仍同款球体；链条形态、旋转及更易辨认的弹种反馈未做；原共享／部分装填未接 | [CombatEffects](../../game/presentation/combat/combat_effects.gd#L54)、[新控制资料对照](control-study-integration-2026-10-13.md) |
| 修理与接舷 | 港口计价、工期、恢复；接舷据点／士气／人数与俘获结算 | 实际 dock→repair 完成后材质／桅帆连续恢复的联合视觉验收不足；接舷主要为指令及数值，没有甲板登船战斗演出 | [Campaign](../../game/domain/mingqi/campaign.gd#L825)、[修理](../../game/domain/mingqi/campaign.gd#L917) |
| 战果与声音 | 普通练习胜败标题，正式生涯回执、旗舰沉没明确提示；fire／hit／splash声音；终局末尾音频时钟合同 | 正式 Mingqi episode完整战果UI仍缺，胜利音未接；音效目前为合成PCM、距离衰减，未听感验收完整原素材／3D方向 | 正式终局190项回归；[combat 审计](audits/combat-details-2026-10-13.md) |
| 天气与剧情 | 正式云／薄雾；开局账本、引水、首航归港及第二航次选择 | 风雨／雷电／风暴及昼夜切换未完整接线；贯穿大员、澎湖、王朝更替的完整新生涯剧情未形成 | [OpeningStory](../../game/domain/mingqi/opening_story.gd#L5)、[第二航次](../../game/domain/mingqi/second_voyage_aftermath.gd#L4) |
| 美术与可玩性 | 当前临时复用原版船体／帆与人物，海上操纵、舰队、经营已有 | 本作船、旗号与服饰统一仍需推进；画面仍可见海盗旗。原 world／combat整数运动尚未接；当前性能工作仍未完成 | 本轮实图；[最新性能诊断](career-entry-performance-2026-10-13.md)、[控制资料对照](control-study-integration-2026-10-13.md) |

“救人弃船”已有，但转移的是俘获船伤员／俘虏，和水中逐人救援不同。新增救援不能直接给 native.crew 加一；[Campaign::_casualties](../../game/domain/mingqi/campaign.gd#L712) 当前会拒绝意外的 native 人数增长，必须经可信事件、转移、回执和存档协调。

## 正式终局缺陷与修复

[MingqiRuntime](../../game/runtime/mingqi_runtime.gd#L229) 旗舰船壳归零就设置 `result` pause；之后不再接受模拟时间。[ShipDamage](../../game/presentation/ships/ship_damage.gd#L117) 当次才开始沉船，要继续0.25秒爆炸、1.4167秒泡沫、4.125秒结束。独立船测试／QA继续推进时间，不能证明正式终局正常。

本轮 `Temp/audit-terminal-sink.gd` 创建实际 MingqiScene，使用公开 `Encounter.update_ship_stats` 验证通过的 hull=0 fixture，调用实际物理与呈现回调，再请求50次0.1秒更新。结果：

- lethal／final native time均为 `0.0166666666666667`；pauseReasons包含 `result`。
- `sinking_age=0`、`ended=false`、模型y前后均0、`modelVisible=true`。
- `foundFreeze=true`。这是原始正式回调的CPU缺陷复现，不是实弹射击、GPU像素或FPS证据。原 RED 保留；本轮下述修复已验证。

新增 `TerminalPresentationClock` 仅在 victory／defeat、真实沉船及 result 暂停下接收后续物理回调，最多10秒，每回调最多0.25秒。第一死亡回调不重复加权威时间；呈现复制包只改 `.time`，业务、原生弹道和UI海图仍读取权威。玩家／菜单／失焦／loading／chart／rate0 阻止呈现；完成保持最后相位，重开／载入／epoch变化清空。Mingqi 仍每正常绘制帧一次完整呈现，初次沉没额外立即锚定。

另外修复两条终局残留：船员入水事件保留原time/id/position，待下一次Effects达到时间后再交付；尾段上限10覆盖7秒body再加2.8秒晚水花。结算后的炮弹显示被回收，原 native.projectiles 不删除、不推进、不产生新命中。普通练习的实际最后敌舰胜利、玩家败北和重新开始也通过验证。

`Temp/terminal-presentation-green-20261013-v2.json`：clock 147、残余效果7、实际场景190项全部通过；`Temp/terminal-detail-verification-20261013.json` 汇总17个相关脚本和6张原生截图，failures=0。真实18骨fixture证明每物理步age／request，不将无引擎yield的回调说成位移；真实骨落水回归与信号交付回归分别覆盖接触和水花交接。

最新原生捕获位于 `Temp/terminal-presentation-native-20261013-v2`。普通新生涯菜单、公开 hull=0 validator fixture、手动生产回调加真实绘制yield，六图逐张查看。该轮 native／campaign时间始终0.15秒；沉没0秒模型偏移0、1.6秒偏移约−3.59、4.5秒偏移约−23.89且hidden、10秒保持hidden。爆炸／泡沫各一次，零增量后的Audio暂停。此捕获不当实弹命中、性能或最终美术验收；毁船烟雾和水花读感仍偏弱。

毁船烟的资源与接线边界已确认：精确 replay manifest只有fire01及三种splash；完整44层毁船定义已经导入，其22个DDS的21个仍缺精确mip入口，RotationModifier也尚不支持。纯ReferenceParticleModel未接生产view。本轮已修复billboard尺寸丢失和独立出生甲板挂点，保留原position／froth合同；六船型挂点回归258／0，14个相关脚本和9张新生涯原生截图验证通过。烟雾已能在出生甲板上方展开，但爆闪和沉船泡沫仍偏弱，完整44层源效果仍未完成。详情见[毁船可见性审计](destruction-visibility-2026-10-13.md)和[当前验收回执](../../Temp/destruction-visibility-verification-20261013.json)。

## 本轮验证与画面

原旧纹理测试在源船模型更名后仍查 `sail_01`／`hull`，实际 null访问并超时。修订 [纹理测试](../../tests/test_reference_damage_textures.gd) 按 damage_surface 角色遍历全部网格及每个材质槽，保留来源SHA、具体纹理路径、mips、档位与独立实例隔离，并同时检查legacy/source缺图fallback。生产代码未因此改动。

`Temp/damage-detail-audit-verification.json` 为原失败记录（2／3）；修订后 `Temp/damage-detail-audit-verification-fixed.json` 三脚本全过：纹理39,823／0、ShipDamage844／0、材质18／0。本轮 `Temp/crew-detail-audit-verification.json` 和 `Temp/crew-detail-lifecycle-verification.json` 也均通过。

私有 `Temp/capture-detail-audit.gd` 通过现有实际主菜单 QA、scenario selector 与 fire_starboard 控件进入共享生产表现，拍5张原生1600×900 Vulkan / Arc130T图并逐张查看，完成标记 `DETAIL_VISUAL_AUDIT captures=5 failures=0`。它只展示共享损伤与实弹击飞，不代签新生涯完整伤亡／救援结算。

- [受损玩家船](../../Temp/detail-visual-audit-2026-10-13/damaged-player.png)、[受损VOC帆](../../Temp/detail-visual-audit-2026-10-13/damaged-voc.png)：帆洞可见；没有声称局部命中纹理实现。
- [炮击之前](../../Temp/detail-visual-audit-2026-10-13/crew-before-hit.png)、[真实命中](../../Temp/detail-visual-audit-2026-10-13/crew-actual-hit.png)、[0.3秒之后](../../Temp/detail-visual-audit-2026-10-13/crew-actual-hit-plus-0-3s.png)：0.4秒target crew30→29且1具18骨rig，0.7秒crew26且4具；第一具骨位置y1.740→3.731，真实Jolt已运动。画面读感仍可增强，未把rig数当最终美术验收。
- 这组捕获尚未出现water entry，不用它证明救起或完整入水画面；入水链有源码与crew回归支持。

三份专家审计分别为 [damage](audits/damage-details-2026-10-13.md)、[crew](audits/crew-details-2026-10-13.md)、[combat](audits/combat-details-2026-10-13.md)。专家只读审查；实际Godot测试和GPU捕获由主线程串行运行。

## 下一轮顺序

1. 正式终局冻结及入水交付已修；继续提高毁船烟雾／泡沫可见性和位置层次，完善正式战果反馈。
2. 接受击木片／火花与毁船、断桅反馈，补命中部位、单桅和三弹种可读性；优先复用已导入的好资源。
3. 建立持续伤烟／火／进水的状态与操作闭环；区分纯伤情视觉与真正持续伤害。
4. 做海上人员、拾救、可信人数转移和存档，再接沉船疏散；不能只把视觉回收改名为救援。
5. 补正式战果UI／声音／接舷演出、修理联合验收和长线剧情，并继续已定位性能工作。
6. 按新操船报告区分航行／交战上下文，吸收松舵惯性、反打和装填的好部分；当前浮点模型与原整数核的差异及未闭合内容见[整合对照](control-study-integration-2026-10-13.md)。

当前仍有明确未完成和已复现缺陷，整款游戏的细节整合目标保持进行中。本盘点不宣称全量效果、全套历史测试或完整战役已验收。
