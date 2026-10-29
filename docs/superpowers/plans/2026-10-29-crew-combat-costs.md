# 船员成本、换岗与真实炮战 Implementation Plan

> **For agentic workers:** use superpowers:executing-plans; shared dirty checkout preserved, no commits/push. Prior user autonomy permits execution without another design approval cycle.

**Goal:** 把已有船员课题放进真实海战引擎，在同预算下验证抢修、人力与火力取舍。
**Architecture:** 保留32Hz船上作业基线；新增同课题60Hz双舰炮战模式，复用正式Encounter与NavalWorldView，独立合同账本负责招聘/工资；实验不读写生涯存档。
**Tech Stack:** Godot4.7.2/GDScript，既有实验室宿主与绘制UI，Node严格runner。
**Spec:** `assets/research/papers/crew-role-effects.md` 本次追加；`docs/design/2026-10-29-naval-world/balance-principles-and-validation.md`。

## 冻结的输入合同

- 两个模式：workshop旧32Hz；battle新60Hz。入口仍crew-role-effects，同一论文/目录，不重复建课题。旧模式保留并回归。
- 预算144实验币，四游戏日合同；普通招聘8+日薪1，专家招聘16+日薪2。12普通、8普通+2专家、6专家三组均承诺144；未雇者绝不补免费人手。
- 独立`crew_contract.gd`：configure({roster,budget=144,days=4})、snapshot、settle(phase_id,day)。整组原子招聘，招聘即时扣款、工资预留；显式单调日数/阶段ID结算，重复同票据幂等、冲突重放拒绝。战斗tick从不推进合同日。训练暂未实现，不冒称成本包含培养系统。
- 稳定人员池沿用crew01—12。普通组全12，无专家；mixed组crew01—10，专家crew03/04；elite组crew01—06，六人都是各自本职专家。纯规则配置可选hired_ids/qualified_ids/tick_hz(32或60)/transfer_seconds(默认0，新战斗2)。未给新字段时保留原行为。
- 换岗接令立刻离开原岗，进入transit，2秒结束后才进入目标岗位；重发同目标不重置计时，途中改为另一个目标拒绝。过渡期间无作业/进食/休息收益。step先结算当前步劳动，再完成到位，恰好2秒的快照已到位但未提前产出。
- 真实炮战：两艘固定阵位福船，110m，heading0，空波/无风，双方由公开command控制，hostileTargets明确敌对，保留原生弹道/碰撞/齐射/弹药。初始玩家船体54，敌船100；相同船/弹药/库存，仅改变已付费人员或分工。先固定单一seed1661，后续跨种子机动另验。
- Encounter是船体和损伤唯一权威。每步先发允许的开炮指令、推进原生1/60秒，读实际状态损失并交给crew，再算有材料的修复，提交update_ship_stats。禁止用旧快照盖掉新伤害；沉船或无人船不能恢复作业/复活。
- 聚合有效船员映射到已雇稳定人员：固定seed生成独立且可记录的受伤顺序；实际crew损失依次扣0—1健康，不用名义hit.damage超额扣人。健康权重影响岗位劳动；未提供战斗观察时旧实验全健康。这是实验中的伤亡分配假设，非正式具名角色死亡规则。
- 装填只在下一次开火时接受新的倍率；按现有合同保留已启动的冷却。使用岗位实际劳力确定目标7/efficiency秒，扣除引擎已有全船crew比例因子避免重复惩罚；倍率超原生合法上限10或效率为0时明示无法作业，不用无穷倍率。已有齐射不在中途变更炮数。
- 案例最大60战斗秒；一方失去作战能力后停止新发射、继续原生在途弹至清空或时限，避免提前抹去同归于尽；记录截止仍在途炮弹。场景结论不等于真实机动海战胜率。

## 文件职责

- 修改 `crew_role_rules.gd`：逐人招聘/资格、2秒转岗、健康、原生损伤观察与守恒账本，可选60Hz。
- 新增 `crew_contract.gd` / `tests/test_crew_contract.gd`：独立预算与显式工资阶段结算。
- 新增 `crew_battle_trial.gd` / `tests/test_crew_battle_trial.gd`：真实Encounter协调器，公开configure/step/assign/snapshot/drain_events。
- 新增 `crew_battle_experiment.gd`：Node3D实验视图，复用NavalWorldView，参数与实数值面板；不自带时钟。
- 旧展示保留 `crew_workshop_experiment.gd`，`crew_role_experiment.gd`作为两个模式的生命周期路由，catalog身份不变。
- 新增针对该轮的扫描和GPU捕获工具；旧32Hz工具/证据保留语义，不能用旧结果证明新模式。

## 实施清单

- [x] 先写失败合同测试，再实现招聘/工资；预算/阶段重放、非法类型、与战斗秒独立共135断言通过。
- [x] 先写规则失败测试，再实现转岗/健康/60Hz；原133断言通过，新增36规则断言。
- [x] 原生炮战协调器42断言，实际fire/hit/损失/材料/伤亡/重新调活人/冷却合同通过；未按赢家编断言。
- [x] 同课题模式、3D视图与宿主重绑/缓存迁移，22断言及GPU入口通过；原用户数据未改。
- [x] 36场同预算对照已留原始事件/初终态/每秒轨迹，全部败局保留；单seed/固定位置/带伤不对称边界已说明。
- [x] battle-gpu-02：142原图、138采样、546原生步，通常4步/图；两次实际调岗回执，首帧投影红绿复验及窄屏检查。第一支援受伤未到位，未冒称此次GPU证明支援产出。
- [x] 独立审查并修死者锁岗、typed-int工资日、模式缓存、首帧投影；原生相关回归通过，论文与来源更新。

## 延续工作与验收边界

正式生涯和工资迁移未接。培养、医治、甲板行走、长期经济、自然机动与人工操作未验。当前队伍不同人数采用同seed但伤亡排列不同；下一步先做三配置×两种敌舰初态，再分离伤亡seed，随后加入真实原生脱离命令。尚无全局平衡或整个游戏完成结论，总目标保持active。

## Review Focus

损伤只有一个权威；名义伤害不等于实际扣值。工资预留不能重复支付。转岗到位不能提前一tick生效。舰炮全船crew因子与岗位效率不能重复扣。沉船不能被每tick修复拉回存活。固定阵位/脚本控制与人工实战必须分别表述。
