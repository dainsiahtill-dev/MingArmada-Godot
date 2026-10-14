# 尾迹独立实验与旧GPU工具修复

新实验 `game/research/demos/wake_flow_experiment.gd` 继承既有HullContact实验，旧Demo原文件未改。复用真实Ship、Crew、ProjectedOcean、SailingRuntime和WakeRenderer。新增控制：候选尾流、六种船型、巡航/低速/转弯/收帆/再入水、side/high/front三尾部观察镜头；默认候选关闭。

`flow_enabled`、船型与场景变化返回reset_required=true，当前历史不原地切换。暂停、单步、重置、轨道和缩放沿用原宿主合同。镜头焦点在真实stern后0.9船长；headless投影验证船尾和2船长后的两端均在960×640画面内，三镜头6项均通过。再入水仍明确标注原2m展示压力覆盖层，不冒充真实物理事件。

`_compose_packet()`在super实际packet后加`ship.sourceWake.targetTrail`：enabled、Vector3 attachment.trail（生产已有yaw-only且y=0）、native heading的cos/sin forward、实际xz速度、物理dimensions.length、hullAlive=true。`surfaceProfile.beam`由HullWaterline模型局部截面生成，乘hullToWorld.basis.x.length得到世界米；缺profile才用dimensions.width。没有改普通生产packet所有者。

inspection顶层：`topic=wake-flow`、`parameters`、`target_trail`、`renderer`整体公开诊断、`flow`为actor.get("flow").diagnostics()；若root新owner尚未存在，flow是{}。既有time为实际native接受时间，tick与presentation_time保留各自含义；首步物理时间不伪写为1/32。

`tools/verify-wake-production-gpu.gd`：ContactFroth只记录公开diagnostics；原SourceFroth/显式legacy实例保留原网格透明顶点与particle诊断；未知实现拒绝。isolate-final也分类型处理，target使用实际FlowPort/FlowStarboard/ContactSpray节点，源实现保持bow/side/ParticleSystem，保留原可见性，不伪造粒子。两个分离截图改为09-resume-local-froth-only、10-resume-spray-only，避免将目标接触水沫叫原模型。

新增`--output=<fresh-directory>`；已有目录/文件直接拒绝，默认历史目录也不能覆盖。仅PNG和对应JSON写入/flush成功才登记capture；必须严格满足7张标准截图，加feather1张，加isolate3张。0张、重复、缺标签、顺序错误均不能成功。候选owner存在时每actor附公开flow诊断。

本轮headless证据：`docs/research/evidence/wake-flow/20261014-lab/`。有效lab RED1/1后最终35/0；capture guard先两轮测试作者的静态调用错误保留，真正语义RED2/2后最终9/0。唯一成功标记分别LABORATORY_WAKE_FLOW_PASS和WAKE_GPU_CAPTURE_GUARD_PASS，exit0，无Godot错误。

没有运行GPU，没有修改catalog/宿主/普通入口/已冻结旅程。root负责候选算法与renderer；新GPU工具`tools/verify-wake-flow-gpu.gd`可用此demo进行独立对照。旧capture失败run保留。测试只验证packet、生命周期、镜头投影和capture门禁；未据此声称候选动态尾迹观感已通过。
