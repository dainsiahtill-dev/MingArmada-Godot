# 低速导航操舵恢复：独立 Spec / Standards 审查

2026-10-12；只读审查，不修改生产、不重跑作者相同测试、不启动GPU/性能工作。Spec由本审完成，Standards由独立子审查员另核；CodeGraph无索引，RTK定向读取。

**结论：当前冻结范围未发现可操作的新代码问题。** 此结论只批准控制器改动范围，不等于正式地形、多人泊位、敌船压港或整条剧情循环验收完成。

## 来源与范围

- [报告](task-autopilot-report.md)、[scoped patch](autopilot-scoped.patch)、[来源身份](autopilot-source-hashes.json)。patch SHA256 `08875f203740f07279eff468658eb1f074c6ee27f17809be4b07deb290c47012`。
- 生产仅 [Encounter](../../../../modules/naval_simulation/encounter.gd)，SHA256 `efa4a5e072b6b542eb872bd1cc3f6cf56e84290cc8bd7a1be01f7637dc9cfc5d`；[新定向测试](../../../../tests/test_autopilot_port_approach.gd)，SHA256 `e4c853d522fe5670e3cd6894f13f3470575c93043e4cb3a759130b6dbb95216a`；两项与实际文件一致。
- [编辑前快照](encounter.gd.autopilot-before)SHA `f6edeadb5a6c74223b25b943f9d2c35dc9c12c2320fd7a55f9d36bd977bdd1fb`恰为上一导航交接冻结身份。本审由快照和live源码重新生成 production unified diff，逐字与交付patch的生产段一致。没有把其他dirty修改纳入此范围。

## 规格与边界

- 默认 `referenceHandling=false`不产生新assist，旧 `_autopilot` 控制计算保留，原无规划30m/有规划18m停止圈仍一致；最后停止圈不恢复操舵。参考增强只在speed<1.2、误差>5°、实际crew/hull有效、非captured且未blocked时参与。
- `_fixed_tick`仍先排除sunk/locked/disabled，assist存在本tick局部Dictionary，经原controls.manualAssist送入物理，没有持久化字段或遗留手操权限。原手操request优先；navigate原入口清除旧manualHandling。
- 按≤10°步长检查目标转向的船体方向与15/30/45m出去方向 `_wet_hull`；原wet Planner、tack、ship avoidance及实际 `_shore`扫掠碰撞约束继续执行。不会因控制恢复而取得穿越陆地许可。这是有限采样安全门禁，不宣称所有多船泊位/风况均已证明。
- 使用现有 [Manual.build](../../../../modules/physics_engine/ships/manual_handling.gd) 船型、真实crew/maxCrew、hull/maxHull、sail/maxSail预算；braking=false，throttle仍0。原扭矩clamp/condition scaling/responsive rate预算不变，没有新yaw求解器、pose/速度回写、健康/货物/胜利注入。merchant定向断言覆盖yaw≤6°/s、acceleration≤8°/s²、power≤20/30、brake0。
- 原 `_ai`、敌舰武器、弹道与伤害公式未改；reference开时该辅助面向所有符合导航条件的船，不据此承诺敌舰与友船的所有航行轨迹仍和旧版一致。

## 证据限度

本审独立读取 [存储的十脚本运行结果](autopilot-green.json)：全部exit0，无SCRIPT/PARSE/ERROR诊断；24条新断言、51559原naval断言/72源case、16557物理断言、handling33、gunnery42、bridge13、waypoint64、storysave122均为0失败，另两旧oracle PASS(0)。合计68414断言；这是作者保存的实际结果，本审未重复执行。

[before/after metrics](autopilot-metrics.json)三初始朝向与报告一致：-1.4386原557.05秒→179.30秒；0/PI原600秒未到→226.73/206.27秒。新测试退出条件仍是真实distance≤25、speed≤0.75；健康、帆、crew不变。fixture明确是单船、平底、固定风、无海浪，与完整现场速度/波浪/邻船不等价。

独立Standards复核同样未发现新增质量缺陷：默认关闭、权限门禁、共享预算、tick局部消费和原物理接口成立。**后续仍由Root跑正式地形真实旅程及手动接战/靠港；首航交20损20已发生的部分成功，也不能替代本轮正式地形或第二委托恢复循环。** 运力恢复死路及优先建议另见 [loop review](task-replay-loop-review.md)。
