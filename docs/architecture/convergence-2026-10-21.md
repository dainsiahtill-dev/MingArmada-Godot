# 全游戏架构收敛设计（2026-10-21）

状态：两批生产实现、独立审查、实验室与GPU验证已落地；新版完整回归286/286通过，1098份冻结文件全程无变化。实际两轮整场帧间隔93.972→72.653ms，缩短22.69%，60FPS预算未达到。[当前验收记录](convergence-acceptance-2026-10-21.md)记录结果、失败和剩余门槛。用户目标：正式开发前建立一致的引擎/游戏层职责、资源和时间合同，优先削减真实重复工作；坚持游戏行业惯例，以测量证明性能，不以重写/ECS/多线程标签推断最优。

## 已确认的现状

真实工程为 ming-armada Godot4.7 Forward+。旧MingArmada网页仓库不属于本轮。已有未提交云生命周期和project.godot配置保留。正式主菜单已有release/dev入口隔离；历史参考与实验室保留。正式炮火已走原资源粒子池+系统批处理，水面已有最多3船局部GPU场，船体CPU数值权威与Jolt船员表现有合理分工。

## 取舍及目标架构

比较：A全量推倒改ECS/全GPU求解，无法保持手感/源算法且风险大；B仅移动目录，无法解决重复采样/调度/初始化；C保持有效模块，收敛实际调用合同与成本，采用C。

- game/domain：航程、经济、任务和存档业务；不创建Node/GPU或读取输入/墙钟。
- game/runtime：命令/暂停/时间倍率、近远场协调和公开detached快照。只有frame入口接受可变dt，单次固定tick接口由上层预算驱动，naval权威保持60Hz。
- modules/naval_simulation：AI/操船/炮弹/碰撞/伤害及天气步进，依赖contracts、physics、environment，不依赖game/presentation。
- modules/physics_engine：船体纯数值与统一海面高度采样；impacts为显式Jolt视觉adapter，最多12个角色碰撞实例（每实例包含多刚体和关节），不反写业务伤害。
- modules/environment_engine：源天气/RNG/光照权威；显示云生命周期属于scene。
- modules/scene_engine：海面/地形/岸浪/天气/特效/动态表面/阴影/资产加载；仅消费接受时间与数据。主线程拥有SceneTree/GPU提交，worker独占可变计算数据。
- game/presentation：事件到表现配方、真实船体/3D人物/挂点和镜头适配；共享引擎不得反向引用游戏具体类型。
- app/Main/Router：唯一设置与存档事务owner、候选场景成功后交换；构建首帧即使用确认质量，不先balanced再重建。

## 本轮实施包及接受标准

1. 物理采样：height-only走已有scalar等式；保留accepted_time/sea_level/sample-only fallback。同输入轨迹/事件等价，浅水四浮点地形调用20变4由独立计数确认。
2. 固定步与快照：提取不含accumulator的单tick入口；frame入口保留各自原有预算/暂停语义。公开snapshot仍隔离引用，内部tick/time/status读取不复制整世界。单tick与原frame路径同命令序列逐项等价，输入/航向/逆风助航保持。
3. 引擎通用能力：将PreparedRigidShadow实现下沉引擎，消除modules=>game；保留typed immutable receipt与零拷贝证明。抽取动态mesh upload/bounds公开能力和公开纹理查询，消除跨文件私有方法依赖。不得加无真实变化点的总管包装。
4. 水表现：coverage抑制的尾迹保持历史/controller，但跳过不可见几何和上传；coverage丢失同接受时刻能恢复。船体残沫和原3Dcrew维持，配方重叠不随意删层。
5. 入口/资源：唯一settings load，首次构建使用存储质量；缓存immutable资源、每个实例独立Node/骨骼。只有验证导入模型等价后采用ResourceLoader首选，原件authoring fallback显式可诊断。
6. 架构守卫：层依赖/引擎无隐藏时钟/纯数值无Node、正式入口和实验室合同、资源释放以及有界队列持续可测试；记录系统owner/输入/输出/预算。
7. 独立实验与性能：使用现有实验室新增系统调度/预算课题（唯一新研究，而非多个player demo）；固定seed/初态/60Hz/viewport/quality。测量CPU分段/采样调用、原帧和正式frame interval。目标机器1600x900 balanced，60FPS目标16.67ms；不达标如实报告，不能用微基准反推。

## 研究依据（官方/第一手）

- Godot CPU optimization：https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html（profiler、局部计时、缓存与Node成本）
- Godot physics interpolation：https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html（固定tick与显示分离；本项目不叠加第二套自动插值）
- Godot MultiMesh：https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html（批处理有整体裁剪代价，不能全场合成一个大batch）
- Godot thread-safe APIs：https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html（SceneTree/GPU资源主线程、worker可变数据独占）
- Game Programming Patterns object pool / data locality：https://gameprogrammingpatterns.com/object-pool.html 、https://gameprogrammingpatterns.com/data-locality.html（热路径复用与连续数据；池有容量和重置要求）

## 验证与回退

已有cloud/ocean/buoyancy/wake/3Dcrew等观感接受项为约束。先保存基线文件与hash、定向red、独立CPU/GPU，候选冻结后正式入口对照。回退仅恢复本轮明确seam，不重置用户工作/个人存档。各实施包记录具体文件、命令、原始结果与失败。全套回归保留原始日志并分辨既有错误；不通过放宽接受阈值制造全绿。

绝对“性能最优”不作为可证明结论。本轮交付是架构有约束、已测改进、明确剩余瓶颈和后续性能预算。整体帧时间与局部算法分别报告。
