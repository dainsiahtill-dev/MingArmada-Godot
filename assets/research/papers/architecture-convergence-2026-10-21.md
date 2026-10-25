# 架构基础收敛：海面采样、固定步与显示

2026-10-26续作：[帧预算诊断](../../../docs/research/frame-budget-2026-10-26.md)、[调用内复用记录](../../../docs/research/cloud-billboard-reuse-2026-10-26.md)。静态云层矩阵复用经独立CPU与同载体GPU提交数据验证后接入；局部批次均值下降18.31%，正式入口仍约14.16FPS。全量回归进行中，已发现阴影实验代理输入遗留不一致；不宣称整场显著提速、全套回归通过或游戏目标完成。

- 课题 ID：`architecture-convergence-2026-10-21`。
- 日期：2026-10-21。类型：前瞻工程研究。状态：研究中，数值CPU和独立Demo的本机GPU捕获/状态合同已验证，完整游戏帧率及最终全套接受项待验。
- Demo：`res://game/research/demos/architecture_convergence_experiment.gd`，主菜单“实验室”的同名课题。
- 摘要：保持真实船体、五波海面、吃水和休闲助航，减少被丢弃的法线与快照工作；用两套同条件生产模拟和可切换显示验证边界。本论文不宣称完整游戏达到60FPS或绝对性能最优。
- 详细CPU报告：[物理子包研究记录](../../../docs/research/physics-convergence-2026-10-21.md)。主设计：[架构收敛](../../../docs/architecture/convergence-2026-10-21.md)。原始证据：`docs/research/evidence/architecture-convergence-2026-10-21/physics/`。

## 问题与假设

船体仅取水位，旧调用仍计算gradient/normal；浅水每次完整波面查询需要中心和四个地形差分。船体每tick采四个浮点及一个中心回退点，所以完整tick为25次地形查询，四浮点子组为20次。旧内部调用还丢弃每步构造的完整snapshot。固定步模拟、输入意图与渲染插值的责任需要清楚，不能为显示平滑改变权威时间或重复推进。

H1：复用既有scalar高度等式，四浮点查询可20→4、完整tick25→5，保持所有double标量状态。H2：无返回快照的内部步进与公开step数值等价。H3：选择基线/候选、切换固定姿态/生产插值、暂停观察和转镜头只改变显示；同初态重置恢复同一权威序列和计数。

长度m、时间s、质量kg、角度rad；naval权威保持60Hz。Demo固定seed1661、风(-0.8,-0.6)14m/s、初始航向0.45rad、速度2m/s，休闲助航的帆量意图0.85。六种原船型逐一可选，默认4m浅水，可切24m深水。没有生涯、存档、设置、联网或新物理规则。

## 方案比较

基线：生产Coastal sampler通过sample-only包裹，保留完整height/gradient/normal工作。候选：同一Coastal sampler增加已有scalar接口，通过同一OceanAdapter只取水位。两套真实Encounter/SailingSimulation接收相同输入，屏幕仅显示选择的一套；切换不重置或推进任何一套。

固定姿态与插值均消费生产SailingSimulation；插值直接调用既有render_snapshot，不复制另一套插值公式。未采用降频、减少浮点数、刚体改写、GPU海水物理或删除3D人物来声称游戏提速。此隔离Demo本身不包含crew、尾迹和完整世界，成本结论只适用于明确计时的数值子实验。

## 算法与实现

共享`modules/physics_engine/ocean/ocean_adapter.gd`拥有accepted_time及sea_level；height接口优先scalar，旧sampler回退完整sample。ShipDynamics仅改变取水位的入口，并提取step_in_place；公开step及snapshot的脱离引用合同保留。波面相位和累加顺序、中心回退、浮力与吃水公式均不调整。

Demo不自动_process或_physics_process。实验室宿主唯一调用advance，生产Simulation的frame适配器接受dt并执行60Hz固定tick。两套模拟互不共享可变船体。读计数的地形采样器只包裹Coastal内部查询，岸碰撞和渲染不混入。计数在配置完成后清零，重复展示不采样物理；重置销毁自己的世界/船模/海面/镜像与模拟后重建，保留观察镜头。

显示使用真实ShipView和生产projected ocean shader/normal texture。固定水深经生产ShoreField纹理注入shader，CPU和显示共用相同五波与8m浅水衰减。观察采用固定侧面/俯视镜头，也支持环绕、缩放；Shader时间来自选择的显示snapshot，禁止读墙钟推进水位。

## 实验设计

先保存237份基线源码hash和旧solver/adapter文本。合同测试计数真实调用、逐步比较六船在浅深水中的全snapshot与buoyancy debug，另覆盖动态cargo/draft、nonzero sea_level、sample-only sampler、共享Dictionary、非法/重复/回退时间和公开snapshot隔离。独立工具在内存编译冻结旧GDScript，避免仅用新实现产生自己的oracle。

独立CPU计时固定每批六船各600步=3600 solver step，每船接受10s；预构造输入，2对暖机、12对交替先后顺序样本，全样本保留，nearest-rank p50/p95。Godot4.7.2 stable ed1daf0bf，Windows/Intel Core Ultra5 225H，headless无GPU；电源策略、温度和后台负载未知。计时范围不含AI、岸碰撞、炮战、campaign、Jolt、绘制或configure。

独立Demo接受判据：预挂载配置不冒充ready；宿主单步只接受一个1/60s tick；暂停/同刻切换/转镜头不动权威及计数；浅水每tick25/5计数；六船相同输入的两状态严格相等；重置重放确定；dispose释放自己的世界和镜像。Headless可证明这些合同，GPU连续画面、遮挡、水线和真实正常入口frame interval须另留原帧与回执，未测不能判通过。

## 结果与证据

物理子包实测：四浮点20→4次地形调用，完整tick25→5，中心回退未删除。新合同7285断言/0失败；冻结旧solver与候选六船×浅深水×600步=7200对完整状态/浮力逐步严格相等，工具7464断言/0失败。原轨迹oracle16557/0、吃水浮力68/0、海水集成4457/0、逆风助航183/0、实际控制78/0；这些回执分别登记在目录来源中。

最终隔离CPU批次：基线mean238.414ms、p50 235.897ms、p95 264.313ms；scalar+step_in_place候选mean162.951ms、p50 163.053ms、p95 173.180ms，12对样本平均局部下降31.65%。每批地形查询90000→18000。这是3600次数值步的批次成本，不能当作单帧毫秒或整场FPS。

原始结果：`physics/green-02.json`、`physics/cpu-pairs-03.json`、`physics/cpu-pairs-03-process.json`，均位于课题证据目录；process回执记录退出0、唯一完成marker和无Godot ERROR。较早CPU01/02分别30.30%/32.98%的平均下降原样保留；最终03对应最终fallback源码hash。RED01保留了首次把完整tick误认20次的错误；RED02纠正调用域后仍失败；共享Dictionary反例RED03失败后才补原sample fallback。

新独立Demo的headless合同已实跑：[lab-green-03](../../../docs/research/evidence/architecture-convergence-2026-10-21/physics/lab-green-03.json) 46断言/0失败，退出0、唯一marker、无Godot ERROR，stdout保留部分帧双权威原始snapshot、接受时间/显示时间、shader时钟、六船计数和资源数。覆盖既有首页实验室启动、单步、六船重置、暂停观察、插值切换、共享生产scalar seam与释放。[目录回归](../../../docs/research/evidence/architecture-convergence-2026-10-21/physics/catalog-green-01.json) 99/0，[通用参数合同](../../../docs/research/evidence/architecture-convergence-2026-10-21/physics/parameters-green-01.json) 11/0。

Demo初次运行的`lab-green-01.json`实际是失败尝试，45断言/1失败：重置时把观察镜头double保存到Vector3导致精度变化；随后改为标量Dictionary，`lab-green-02.json`通过45/0。最终03增加scalar seam断言与原始状态输出，通过46/0。文件名中的green不替代真实结论，失败保留。

主任务随后串行运行了真实GPU：[GPU_VERIFY](../../../docs/research/evidence/architecture-convergence-2026-10-21/lab-gpu/GPU_VERIFY.json) valid=true、1754断言/0失败、50张原始PNG；[严格进程回执](../../../docs/research/evidence/architecture-convergence-2026-10-21/lab-gpu/PROCESS_VALIDATION.json) 确认退出0、无ERROR和唯一完成marker。实际普通首页进入实验室，六船×4m/24m×侧面/俯视×full/scalar同刻捕获48张，另首页/论文2张；每组有120个接受tick及半tick余数，逐步比较两套状态，还验暂停、重置重放、shader时钟、释放和存档/设置字节不变。硬件Intel Arc130T GPU(16GB)，Godot4.7.2 Forward+，窗口1600×1000，独立Demo balanced。主任务亲看福船4m侧面scalar原帧，确认显示正常；不把这一审阅扩大为所有长时动态和全游戏观感接受。

时间顺序如实记录：本轮先冻结基线与执行独立CPU对照，随后数值seam接线；此可视Demo在同轮后补，GPU实跑在其后，不能声称它在接线前已经取得GPU验证。原始GPU证据及sourcehash不改写；实跑后的HUD/论文确认属于新文案版本，另有`physics/lab-gpu-postcapture-note.json`记录新旧散列。完整产品的架构守卫、入口/资源/FX接线和帧率验证属于同一主课题的独立接受项，不由本数值表代替。

## 局限与失败

当前Demo的full baseline是保留完整海面采样工作的生产路径，并非完整旧游戏；两套authority同屏运行也不是产品性能测试。屏幕计数不包括渲染采样、地形缓存、岸碰撞或其他模块。深水完整sample只有一次中心地形查询，因而地形计数收益会小于浅水；仍可能节省法线运算，但需各自测量。

12对p95仅描述这组小样本。本机独立GPU捕获/状态合同已经实跑，仍缺完整场景演员预算、连续动态观感接受及原生frame interval，不能宣称60FPS。公开API兼容不能由代码阅读替代运行；未验证长期热稳定性。旧full-only sampler保留完整工作，不保证从其内部省掉normal成本。历史证据和失败不覆盖，缺少安装包内仓库证据时由论文保留实测结论和限制。

## 集成与复现

普通主菜单进入“实验室”，选择“架构基础收敛：采样与固定步”，运行。默认观察scalar/生产插值；切换完整基线或关闭插值看同时间姿态，暂停后用宿主单步，六船/水深参数按原宿主reset_required重建。截图功能由宿主保存原帧与inspection：权威tick/time、seed、实际输入、双方原始snapshot、计数、镜头矩阵、Shader时间和资源数。截图不是连续动态验证。

源码入口：`game/research/demos/architecture_convergence_experiment.gd`；CPU/host测试：`tests/test_laboratory_architecture.gd`；成本工具：`tools/measure-physics-convergence.gd`。在配置GODOT_EXE后，以新输出名运行：

```powershell
rtk proxy node tools/verify-godot.mjs --filter laboratory_architecture --output Temp/research/architecture-lab-new-run.json
rtk proxy node tools/verify-godot.mjs --filter physics_sampling_contract --output Temp/research/physics-contract-new-run.json
rtk proxy $env:GODOT_EXE --headless --path . --script res://tools/measure-physics-convergence.gd -- --output=res://Temp/research/physics-cpu-new-run.json
```

正式接线维持唯一frame时间owner、无accumulator单tick、公开detached快照和Jolt视觉12体预算。本机独立GPU已留证，完整游戏帧率和主课题最终接受项完成前保持研究中。回退恢复该课题seam及目录状态，不删除存档、用户设置、原始证据或其他未提交工作；不将本Demo的省略项用于产品提速宣称。

## 主课题后续验收补充（2026-10-21）

本节为上述独立数值Demo及其GPU截图之后的主课题结果，不改写早期实验时间线或其source hashes。更正预算措辞：Jolt限制为最多12个角色碰撞实例，每实例可包含多个骨骼刚体/关节，不能理解为12个RigidBody。

主课题两批已完成物理/固定tick、FX动态缓冲及资源、settings与AssetLibrary、ShipView/3Dcrew、cloud曲线和保守岸浪裁剪的生产收敛。新版官方全套286/286、0失败/超时/Godot ERROR；1098份源码/测试/配置/runner文件执行前后完全相同，耗时22分50.818秒。实验室课题和本独立Demo代码保持原验收版本。

实际公开自由试航，Intel Arc130T/Godot4.7.2 Forward+，1600×900 balanced，seed1661，每一行3船35名可见3D人物，正常有焦点未暂停：两轮正序/反序mean分别94.242→72.700ms、93.702→72.606ms。两次进程mean等权93.972→72.653ms，缩短22.69%，约10.64→13.76FPS；分位数不平均，慢帧不修剪。此为整个收敛变更集相对最初生产的收益，不是本数值Demo或culling-only的单独归因。**16.67ms/60FPS尚未达到**，因此主课题仍保留研究中/性能门槛开放。

岸浪实际GPU06为1940/0，三个非空案例主/反射pure-redraw、hold、candidate均零字节差；其scope明确排除Crew/UI/forest，保留地形/海面/光照/船体/compositor。GPU05另保留forest的两个有效案例，重入树叶噪声导致该整组1907/2，原件保留。candidate01一条异常GPU query使其原GPU均值不可用，未删数据或据此解释wall收益。资源直读测试85条导出WARNING与真实发布验收分开；离线模型烘焙、导出一致性及连续炮火/大舰队长时压力尚需后续关闭。

完整当前状态：[架构验收记录](../../../docs/architecture/convergence-acceptance-2026-10-21.md)、[双配对原始性能](../../../docs/research/evidence/architecture-convergence-2026-10-21/live-second/COMPARISON.json)、[最终完整回归](../../../docs/research/evidence/architecture-convergence-2026-10-21/full-suite-second-summary.json)、[图文证据](../../../docs/research/evidence/architecture-convergence-2026-10-21/review-final.html)。论文更新只补证据与范围，未改变算法、参数或Demo行为；另存`physics/lab-paper-final-note.json`记录新旧hash。
