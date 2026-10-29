# 战火氛围与可见货物 Implementation Plan

> 使用 executing-plans / TDD，独立事项并行；保持现有脏工作区，不提交、不推送、不删除旧候选。用户最新明确要求起火、冒烟、硝烟氛围、所有货物的3D模型及受击后漂浮，并要求细节完整打磨。本轮优先这些表现与实际状态链，对等船况/脱离实验暂未开始，保留为后续工作。

**Goal:** 实际战斗能看见炮火残烟与毁船火团；真实货单能在甲板辨识，实际损失能形成有来源的海面漂流物。
**Architecture:** 火烟为只读独立表现层；货物由权威货单/扣货回执驱动，渲染不扣货。各建独立研究课题，验证后接原入口。
**Tech Stack:** Godot4.7.2、Blender资产、内置imagegen原始透明PNG、既有ShipView/DeckSupport/NavalWorldView。
**Spec:** 用户本轮三条追加；现有世界与玩法总纲、研究流程。

## 课题与合同

1. `naval-combat-atmosphere`：真实fire驱动更长烟团，hit驱动木尘/火星，真实destruction-explosion驱动随下沉甲板移动的火团及黑烟。当前没有真实存活舰火灾权威，不能把低血永久冒火或改变伤害；持续火攻/扑救仍按既有玩法研究另行闭合。毁船火团是实际毁船演出的连续效果。
2. `cargo-deck-drift`：以正式12商品ID为全集 grain/water/wood/iron/powder/cloth/silk/porcelain/tea/sugar/salt/spices。每种至少一个独立可识别3D资源，数量大时按稳定分组展示并保留真实数量，不每帧随机摆货。现有solid hit最多扣5粮，先保留并记录基线，扩展损失政策必须同步真实账本/质量/重放测试，不能只抛装饰箱。

## 火烟首版技术合同（原创表现参数，待实测）

- 新独立Node `game/presentation/combat/combat_atmosphere.gd`，不改原fidelity源回放；自有两张生成PNG，来源见assets/textures/combat_atmosphere/r1/provenance.json。
- API configure({enabled,quality},camera,water_sampler,anchor_provider)、apply_snapshot(native)、apply_events(events)、refresh_anchors()、diagnostics()、dispose()。仅接受native.time，epoch为battleId；暂停同刻幂等，倒带/epoch变化清旧状态。不得以渲染delta累计烟。
- 真实炮口source_muzzle_position优先；真实毁船source_effect_position为出生点。风为FROM，漂移按(-direction.x,0,-direction.y)*speed缩放。烟出生世界空间固定，火点只经只读甲板anchor跟随当前绘制船体；水下停止火团且不反复复燃。
- 炮烟约6—9秒、毁船烟整次总包络≤9秒、明火≤3.5秒；最后一粒不得超过毁船event.time+9秒，适配现有10秒终局表现尾声。火光短而有力、烟体有体积与升力、外沿稀薄，保留舰船/炮位辨识。
- 容量受限（默认384个活跃sprite、低档192）；同事件固定种子/固定出生编号，重放不再发；超过容量有确定丢弃并可诊断。透明粒子测深、不写深度、不投实体方片阴影。真实投影与遮挡需GPU验证。
- ShipView只读source_destruction_anchor返回实际LOD0甲板位置/时间/shipId，包含下沉姿态一次；World在船姿态提交完后刷新附着点。原事件只复制，不新增权威damage/fire值。

## 货物首版验收合同

- 模型必须来自Blender .blend与GLB可重建脚本，不能只换方块颜色；粮袋、桶、木料、铁锭、火药桶、布匹、丝卷、瓷器箱、茶箱、糖箱、盐袋、香料陶罐各有可辨形制与装载结构。
- 真实货单更新能增减同ID模型。甲板采样通过DeckSupport；须避开炮位/船舵/主通道，检查俯视与驾驶视角。
- 每个掉落必须有唯一dropId、来源shipId、good、quantity、causeEventId、出生时刻/落点；船货减少与掉落量守恒，重播不复制；不通过节点数量反推经济状态。
- 漂落动画先弹出翻滚，再落水水花，随后按水面采样起伏并缓慢随流/风漂移；重物表现需明确包装浮力政策，不能当真实海洋工程计算。暂停、回退、离场/重建和加载都要有确定状态。

## 执行清单

- [x] 审计火烟链路、真实货单与扣货基线；生成两张原始透明纹理并保留来源。
- [x] 写两份七节研究论文并登记独立课题，先测后接线。
- [x] 火烟先写状态/去重/容量/风向/终局测试，再实现；真实GPU比较现有基线/候选，审阅连续烟火与暂停/重置。
- [x] Blender生产12货物GLB及source .blend，检查尺寸、材质、部件与导出可用性。
- [x] 货单投影、损失回执和漂流状态测试；独立GPU证明装船/击落/入水/漂浮，再接正式货单与击中链。
- [x] 接入原NativeWorld两条呈现路径；实际首页入口/真实战斗/存档相关回归；记录性能范围和未测项。
- [x] 独立审查所有实际修改、保留失败、更新文档与交付缺口。完整游戏目标继续active。

## Review Focus

表现不能偷改战斗数值；烟跟世界、火跟实际甲板且下沉只算一次；终局烟不能超尾声冻结；货物必须与库存/重量一致；大量货不能堵住船员和炮位；复读/暂停/重建不能重复掉落；透明层不能遮成整块白墙。

## 本轮收束

交付及未达标范围见 `docs/design/2026-10-29-naval-world/28-cargo-and-combat-delivery.md`。功能层已集成；完整游戏目标仍active。商船原材质质量、渔船等其它船型货物布局、完整装填动作扫掠、满货舰队性能、持续火攻/扑救及经济平衡不包含在本轮完成声明内。
