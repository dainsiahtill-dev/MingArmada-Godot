# 世界云生命周期：出镜回收与连续漂移（2026-10-15）

- 课题沿用 weather-shadow；修复目标为独立世界云的可见生命周期，不新增首页演示。
- 已有云/海合成顺序修复继续保留。

## 问题与假设
60秒固定初态扫描发现7次约1.28~2.50km的世界云位置跳变；第0朵风暴云的正alpha零件数与alpha总量不变（10/10），支持“逻辑中心回收被直接提交为可见物体瞬移”是主要根因。默认32源调用/s、10单位/m、movementSpeed500属于目标适配；不是原版实测每秒速度。
原始重置条件为玩家西侧、加权距离>16000源单位，不含视锥判定。现相机允许远距离旋转，不能将该条件当“云已经离开玩家视野”。

## 方案与接受标准
采用有界的三实例显示适配，保留原算法/RNG/逻辑天气轨迹：
1. Producer为每个重置发布generation，并发布由源步进换算的连续漂移速度；不改变原整数结果或RNG调用。
2. 显示层按接受时间推进世界位置，平滑离散风向/速度；逻辑重置后，旧实例保持原轨迹，不能在可见范围内瞬移。
3. 回收前检查涵盖完整云片及云影的保守球，且扩大视锥48m；同时保护主相机及海面镜像视锥。
4. 仅当旧实例整个出镜后，才安置新generation。若逻辑新位置在视野内，沿漂移的反方向寻找视野外出生位置，再随风进入；找不到时继续等待，不强制删除或屏内重生。
5. 保持固定三个实例，不复制无界离场云。原controller仍按接受时刻运行；这是目标显示策略，不宣称原版算法。
6. 同刻相机刷新不推进显示位置、回收或RNG；epoch/rewind/reset清状态；同画质重建保存现显示状态或复用owner。
7. CPU验证generation/RNG、完整边缘出镜、镜像保护、连续步进、暂停/恢复、并行重置和有界资源；GPU固定机位在原跳变前后连续捕获，证明原云保留并移动、屏外回收/入镜；相关回归和既有实验室A/B。

## 限制
三中心逻辑风场保持原权威位置，显示云在等待回收期间可有位置偏差；后续降雨等若依赖可见云必须消费显示位置合同。透明alpha/源形状不在本次重新设计。独立GPU实验不代表整场FPS。遇相机快速转向，持续保留旧物体比强制换新优先。

## 实测交付（最终生产源码）

- 最终独立 GPU：[lab-3/LAB_VERIFY.json](evidence/world-cloud-lifecycle-2026-10-15/lab-3/LAB_VERIFY.json)，seed1、固定初态与镜头，每组129个32Hz接受时刻。50张原帧覆盖0–2秒连续移动、2.5秒离场，以及3.5–3.625秒回收前后；实际完整边界允许回收时间为3.5625秒。基线首跳2951.203857m，候选首步3m。A/B每个时刻的完整源packet散列相同。
- 正式入口 GPU：[production-2/LIFECYCLE_VERIFY.json](evidence/world-cloud-lifecycle-2026-10-15/production-2/LIFECYCLE_VERIFY.json)，真实自由试航、原海水/岛/船员/物理/交互水场/平面倒影。唯一改变是明确的近重置初态；正常modelScale10，两个121样本的60Hz接受时间序列。原重置帧基线跳2951.203857m，生产只移动1.599976m。20组主/镜像捕获共40张PNG，包括普通入口、两秒轨迹、同刻高画质、低机位和出镜后回收。
- [PIXEL_VERIFY.json](evidence/world-cloud-lifecycle-2026-10-15/PIXEL_VERIFY.json)对七个时刻的主/镜像原帧作有方向的暗云差分；云像素在重置后持续存在，质心连续向左移动，证明不是只保持一个内部坐标或一张不动的图。root实际查看了重置前后、两秒、低机位、倒影及回收前后原帧。
- CPU真实Camera3D六面、非零潮位额外相机、整球边界、原生代数/无效reset保持状态、精确指数积分分步一致等36断言通过；生产renderer独立夹具11断言通过，实验室112断言通过。冻结60秒后恢复动态，同刻无补偿位移，随后一帧小于2米。
- 原天气与滚动保留两份回归通过；正式大气573断言通过。早期60秒保护窗的正式大气测试超时保留，180秒独立复验正常退出，完整套件后续也在33.2秒完成此项。
- 小范围成本实测仅为暂停同packet CPU presentation：80个热身后样本，整套Atmosphere基线中位1.772ms、候选1.884ms；p95为1.872/2.801ms。该数不是正常游戏FPS，不含全程GPU/多船多炮压力。始终只有三个世界天气实例，不保留无限离场副本。

生产默认已启用新生命周期，既有天气实验室提供同一实现的开关与“可见云离场回收对照”预设。没有新增首页演示。当前源码与原始GPU/CPU日志保存在同一evidence目录，旧失败不覆盖。

## 失败记录与明确边界

1. 第一版renderer接线的条件表达式返回了无类型空Array，导致Array[Plane]运行时错误；改为显式类型数组加assign，失败与超时日志保留。
2. 第一版GPU验收工具有GDScript推断错误，未启动验证，保留原日志。
3. production-1无效夹具保留：工具改Weather初态但漏掉simulation.refresh_snapshot，0秒缓存仍是旧x=800m，镜头却对着x=-1598m。该轮画面没有目标云，且连续性断言失败，不能算视觉证据。工具经正常刷新合同安装初态，增加初态断言后重跑production-2通过。
4. code review发现减弱动态恢复会把冻结时段积成大步；补先红后绿反例与rebase_time，保持物体位置，仅恢复后续正常步进。
5. 同一遇敌/航行期的普通前进、暂停和相机变换保持连续。显式时间倒退/新epoch会清显示历史并按源状态重建；本轮没有保存每个旧相机下的完整显示轨迹，不能声称任意rewind画面无跳变。减弱动态中的回退也会丢弃未来display packet。
6. 原资源alpha/KF形态与天空云环原旋转不在本轮重设计；新显示云与源天气场在待回收阶段可能不同位。forceCenterZero是原件诊断覆盖项，显示漂移不承诺逐调用追踪其强制放置。后续降雨/雷声若依赖可见云，需显式接入显示位置合同。
7. 最终目标是修复可见瞬移/回收与离散漂移顿挫，保留当前源速度单位标定；不声称本轮完成原版整片天气系统、云造型或整场性能验收。全套项目回归另列真实失败，不能由这组云GPU通过推断为全绿。

## 可复现命令

在项目根运行，输出目录须是新的路径：

```powershell
rtk proxy node tools/verify-godot.mjs --filter cloud_lifecycle --output Temp/cloud-lifecycle-new.json
rtk proxy node tools/verify-godot.mjs --filter laboratory_weather --output Temp/weather-lab-new.json
rtk proxy node tools/run-research-proof.mjs Temp/cloud-lab-new.json '["--path",".","--script","res://tools/verify-cloud-lifecycle-lab-gpu.gd","--","--output=res://Temp/cloud-lab-new"]'
rtk proxy node tools/run-research-proof.mjs Temp/cloud-production-new.json '["--path",".","--script","res://tools/verify-cloud-lifecycle-production-gpu.gd","--","--output=res://Temp/cloud-production-new"]'
rtk proxy node tools/verify-cloud-lifecycle-evidence.mjs
```

## 算法与实施合同

所有输入使用接受时间秒与Godot世界米；render callback、墙钟和额外相机刷新不产生新时间。每个源worldClouds项新增generation（源复位计数）及driftVelocity（三维米/秒）；原位置、controllerState、sourceCallIndex、RNG与外部操作继续原样。generation指最近观察到的逻辑代数，不能用它判断旧云是否已被替换，应看retiring/recycles及实际position。

独立引擎helper为[world_cloud_lifecycle.gd](../../modules/scene_engine/fidelity_fx/world_cloud_lifecycle.gd)，只有advance(index,packet,time,radius,visible)、clear、snapshot/restore、rebase_time。它不持有节点、纹理、输入或独立process。index来自固定3个生产slot；snapshot是分离副本。仅在目标time大于已接受time时前进，同刻调用不能触发源换代、回收或重生。

漂移目标速度为v，上一速度为v0，响应时间T=0.2s，接受步长dt。令d=exp(-dt/T)，则：

```text
new_velocity = v + (v0-v)*d
new_position = old_position + v*dt + (v0-v)*T*(1-d)
```

这是同一恒定目标速度下的指数响应精确积分。不能以帧末速度乘整段dt代替位移，否则恢复长步、30/60Hz之间会出现不同轨迹；相关粗/细步反例已先红后绿。暂停期间不推进；减弱动态关闭时只将helper时钟rebase到最新接受时间，保留position/velocity/retiring，不积分被有意冻结的60秒。

Atmo针对每个完整源hierarchy求root中心包围球。普通mesh使用world.translation及静态局部顶点最大半径×abs(world.scale×modelScale)；billboard使用parent中心，加(relative位移长度+局部半径×abs(relative.scale))×abs(parent.scale×modelScale)，覆盖任意观察角度；被压到海面的烘焙影使用实际receiver高度差。透明度为0的部件也参与，并在同一actor期只增不减，避免controller收缩时过早回收。

可见性由真正Camera3D六面视锥提供：World先更新海面镜像，再将启用的实际反射相机传给Atmo。主、镜任一视锥与半径+48m的球相交，都继续保留。没有假定镜面永远y=0。每次复位只让当前slot进入retiring，连续多次源复位不创建额外slot。

旧球完全出镜后，优先尝试最新逻辑位置；若仍可见，沿速度反向搜索新出生点，步距max(128m,2×(radius+48m))、最多64步。失败则保持等待，不强制屏内放置。原controller接受时钟不因换位而重置。质量设置相同则复用Atmosphere及显示helper；dispose/new epoch/显式rewind清理它，不留未拥有节点。

CPU小范围计时与其他headless项目回归并行发生，桌面负载未隔离；仅记录当前观测值，不将中位差解释为精确的算法纯开销或性能上限。

## 完整回归与旁支失败

官方完整headless回归实际运行24分41秒，272个文件中265通过、7失败，原[完整回执](evidence/world-cloud-lifecycle-2026-10-15/full-headless.json)原样保留。云专项、正式大气、world、全部天气消费者与实验室合同通过。不能将本轮云GPU通过称为全项目全绿。

| 文件 | 全套原始结果 | 独立核对 / 后续 |
| --- | --- | --- |
| test_autopilot_port_approach.gd | 60.459秒保护超时，无完成标记 | 180秒保护串行复验：37.923秒，24断言0失败、唯一标记、exit0、无诊断 |
| test_career_startup.gd | 60.196秒触发保护；已输出53/0仍按超时失败 | 180秒保护串行复验：29.603秒，53断言0失败、唯一标记、exit0、无诊断 |
| test_fidelity_vegetation_population.gd | cat_island增长阈值未达 | 实际90棵，要求至少91；测试/直接依赖与HEAD逐字节相同，源资源目录未修改 |
| test_layer_boundaries.gd | 两条scene_engine反向加载game的阴影依赖 | prepared_shadow_frame与source_shadow_renderer加载prepared_rigid_shadow；三文件及测试与HEAD相同 |
| test_local_fire_presentation.gd | WorldTrace缺get_interactive_water_mask_revision，8次SCRIPT ERROR | 即使打印99/0也不能通过；夹具与调用点均未改，独立复跑相同错误；该scene仍会经过本轮云路径 |
| test_reference_peak_orientation.gd | cat_island码头落点高度断言 | 实际2.069470678m，要求2.1±0.0001m；独立复跑50断言1失败，测试/直接地形依赖与HEAD相同 |
| test_tack_route_replan.gd | 测试line13使用未声明的Layout，解析失败 | 该测试与HEAD逐字节相同 |

[两个超时项的独立复验审查](evidence/world-cloud-lifecycle-2026-10-15/contracts/extended-headless-assessment.json)保存原始散列、标记与诊断；它们的通过不改写原始全套回执。其余五处失败已定位直接原因，本轮没有扩展范围去修旁支；检查源码与HEAD相同不等于重新运行过历史commit。详见[失败明细](evidence/world-cloud-lifecycle-2026-10-15/REGRESSION_NOTES.json)。
