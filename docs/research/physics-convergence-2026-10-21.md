# 物理采样与无快照步进：架构收敛 CPU 子实验

- 主课题：`architecture-convergence-2026-10-21`，本文件是其物理子包记录。独立Demo及包内七段论文登记在同一主课题，不另建重复课题。
- 日期：2026-10-21。状态：独立 CPU 合同和微基准已测，主任务已实跑独立实验室GPU捕获/状态合同；完整游戏帧率及最终接受项由主课题另验。
- 设计：[convergence](../architecture/convergence-2026-10-21.md)。证据：[physics](evidence/architecture-convergence-2026-10-21/physics/)。
- 冻结旧源码：[ship_dynamics](evidence/architecture-convergence-2026-10-21/baseline/source/modules/physics_engine/ships/ship_dynamics.gd.txt)、[ocean_adapter](evidence/architecture-convergence-2026-10-21/baseline/source/modules/naval_simulation/ocean_adapter.gd.txt)。未改写这些基线。

## 问题与假设

船体仅需水位，却通过 `OceanAdapter.sample` 计算 gradient/normal。浅水每个完整波面调用需要中心加四个地形差分。船体每次水相对浮力步实际采四浮点及一个中心回退点；原完整 tick 是 25 次地形调用，不是最初审计预测的 20 次。四浮点子组才是 20 次。首次 RED 保留了这一预测误差，第二次 RED 按实测调用域纠正断言，没有删除中心采样或改变求解器。

H1：已有 `CoastalWaveField.sample_height` 可替代被丢弃法线的调用，保持 double 标量运算顺序、accepted_time、sea_level、旧 sample-only sampler 合同；四浮点地形调用 20→4，完整 tick 25→5。H2：`step_in_place` 仅去除调用者丢弃的公开快照，数值状态和拒绝输入行为不变。保持 m、s、kg、rad，60Hz 船体步与原浮力、吃水、助航均不调整。

## 方案比较

基线使用冻结的完整波面采样与公开 `step`，每步返回完整 detached snapshot。候选复用既有 scalar height 等式，在 physics 下沉共享 OceanAdapter，并增加无返回值内部步进。未采用新波面公式、降低采样点数、降频、改刚体求解、去掉3D船员、替换公开快照为可变引用。候选的状态变化点少，能直接与冻结源码逐步比较。

## 算法与实现

- [physics OceanAdapter](../../modules/physics_engine/ocean/ocean_adapter.gd)：`sample` 保留原完整合同；`sample_height(x,z,_time)` 始终使用 adapter 的 `accepted_time`。支持 scalar 接口时返回同高度加 sea_level；旧 sampler 通过完整 `sample` fallback，连共享 Dictionary 的既有结果处理也保留。descriptor-only 高度用共同标量函数，保持原 phase/累加顺序。
- [ShipDynamics](../../modules/physics_engine/ships/ship_dynamics.gd)：`_water_height` 优先 scalar，仍用 `Types.finite_or` 拒绝非有限值；无 scalar 时保留原 full fallback。`step_in_place(delta,controls)->void` 保留原 guards、控制接受、积分顺序和赋值；公开 `step` 调它后返回 detached `get_snapshot`。
- 原 naval adapter 的兼容 shim 及 Encounter 改用内部 API，由主课题负责。本子包不改 runtime/tick/naval。无新增墙钟状态；计时工具中的墙钟仅测成本。

## 实验设计

[合同测试](../../tests/test_physics_sampling_contract.gd) 对真实 Coastal sampler 计数；六船各在4m/24m地形深度跑600个60Hz tick，逐步精确比较全 snapshot 与 buoyancy debug，tick180改 cargo、tick300改 draft，使用相同风与有界助航输入。另测 nonzero sea_level、显式 accepted clock、旧 sampler、非法/重复/回退时间、非法水位、公开 snapshot 隔离及内部步不调用完整快照。

[独立工具](../../tools/measure-physics-convergence.gd) 在内存编译未改动的冻结旧 GDScript，与候选逐步比较；非零 sea_level=1.25m，六船×两种深度×600步=7200对状态。性能部分固定4m深度，每批六船各600步，共3600 solver step/批；预构造相同命令，计时不含 configure、输入构建或事后 snapshot 比较。旧调用丢弃 `step` 返回值，候选调用 `step_in_place`；测量涵盖 scalar 与无返回快照两个声明因素的组合，不能分别给它们归因。

Godot 4.7.2 stable `ed1daf0bf`，Windows，Intel Core Ultra5 225H、14逻辑处理器，headless无GPU。2对暖机、12对样本；奇偶对交替运行顺序。接受时间每船10s，解析波面无 RNG；无 viewport/画质因素。记录全部样本；quantile=`ceil(q*n)-1` nearest-rank。电源策略、温度、后台负载未知，不声称长期稳定性能。

## 结果与证据

- [red-01](evidence/architecture-convergence-2026-10-21/physics/red-01.json)：5失败；捕捉缺 scalar、adapter、in-place 接口，同时揭示原25次地形查询而非预测20。
- [red-02](evidence/architecture-convergence-2026-10-21/physics/red-02.json)：修正调用域后仍5失败；四浮点与完整tick分别计数。
- [green-01](evidence/architecture-convergence-2026-10-21/physics/green-01.json)：7284断言、0失败，四浮点20→4；完整tick25→5，候选full调用0。
- [red-03-fallback](evidence/architecture-convergence-2026-10-21/physics/red-03-fallback.json)：新增共享Dictionary旧sampler兼容反例，1失败。[green-02](evidence/architecture-convergence-2026-10-21/physics/green-02.json)：复用原sample结果处理后7285断言、0失败。
- [最终CPU原始样本](evidence/architecture-convergence-2026-10-21/physics/cpu-pairs-03.json)、[进程回执](evidence/architecture-convergence-2026-10-21/physics/cpu-pairs-03-process.json)：7464断言、0失败，退出0，唯一完成marker，无Godot ERROR。7200对冻结旧源码状态/浮力逐步严格相等。每批地形调用90000→18000；未少采任何水位。

| 最终候选隔离 CPU 批次 | n | mean ms | p50 ms | p95 ms | min/max ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 冻结旧源码 | 12 | 238.414 | 235.897 | 264.313 | 229.902 / 264.313 |
| scalar + step_in_place | 12 | 162.951 | 163.053 | 173.180 | 155.659 / 173.180 |

本批次平均局部CPU时间下降31.65%。较早的 [01](evidence/architecture-convergence-2026-10-21/physics/cpu-pairs-01.json)、[02](evidence/architecture-convergence-2026-10-21/physics/cpu-pairs-02.json) 原样保留，平均下降分别30.30%、32.98%；03对应最终fallback源码hash，未挑选或排除单个样本。这些毫秒是3600次数值步的批次时间，不是帧时间。

原有定向回归： [ship physics](evidence/architecture-convergence-2026-10-21/physics/ship-physics-green-01.json) 16557/0、[buoyancy contact](evidence/architecture-convergence-2026-10-21/physics/buoyancy-green-01.json) 68/0、[sea physics integration](evidence/architecture-convergence-2026-10-21/physics/sea-integration-green-01.json) 4457/0、[casual sailing](evidence/architecture-convergence-2026-10-21/physics/casual-sailing-green-01.json) 183/0及78/0。对应测试包括吃水/水位、同刻/暂停、原轨迹oracle、逆风助航及实际控件意图。与本包最终合同合计6份脚本28628断言、0失败；不把工具断言另重复计入测试合计。

## 局限与失败

纯CPU数值范围不包含AI、岸碰撞、炮战、campaign、Jolt船员或渲染；不产生完整游戏FPS、60FPS达标或视觉通过结论。合同测试的full/scalar对照共享当前积分器，因此独立工具额外加载冻结旧积分器避免自行生成自己的oracle。旧 full-only sampler fallback保持完整工作，不承诺省掉其 gradient 成本。未实现 compact motion snapshot、scratch buffer池、GPU或完整套件。

## 集成与复现

同一课题现已登记主菜单实验室入口：`game/research/demos/architecture_convergence_experiment.gd`，包内论文 `assets/research/papers/architecture-convergence-2026-10-21.md`。两套真实Encounter/Simulation同步对照full/scalar，六船型可选，复用生产render_snapshot、ShipView及五波海面。 [lab-green-03](evidence/architecture-convergence-2026-10-21/physics/lab-green-03.json) headless 46/0；目录99/0、通用参数11/0。主任务另串行实跑 [GPU_VERIFY](evidence/architecture-convergence-2026-10-21/lab-gpu/GPU_VERIFY.json)：valid=true、1754/0、50PNG，严格进程回执确认退出0/无ERROR/唯一marker；Intel Arc130T Forward+。主任务亲看福船浅水侧面scalar图正常。可视Demo与GPU验证为数值接线后同轮补充，不补造先验历史；完整游戏FPS另验。原GPU证据不修改，文案确认的新旧hash追加在`physics/lab-gpu-postcapture-note.json`。

主课题将旧 naval adapter 改兼容shim／引用新physics adapter，并把 Encounter 调用改为 `step_in_place`；继续验证原 fixed-tick、事件、暂停、鼠标航向、助航和船员表现时序。仅完成这些接线及正式入口验证后才标主课题集成完成。

```powershell
rtk proxy node tools/verify-godot.mjs --filter physics_sampling_contract --output Temp/research/physics-contract-new-run.json
rtk proxy node tools/verify-godot.mjs --filter ship_physics --output Temp/research/physics-oracle-new-run.json
rtk proxy node tools/verify-godot.mjs --filter buoyancy_contact --output Temp/research/physics-buoyancy-new-run.json
rtk proxy node tools/verify-godot.mjs --filter sea_physics_integration --output Temp/research/physics-integration-new-run.json
rtk proxy node tools/verify-godot.mjs --filter casual_sailing --output Temp/research/physics-handling-new-run.json
rtk proxy $env:GODOT_EXE --headless --path . --script res://tools/measure-physics-convergence.gd -- --output=res://Temp/research/physics-cpu-new-run.json
```

配置本机 `GODOT_EXE`；每次换新输出名。独立工具拒绝覆盖已有输出。保留SOURCE_HASHES与原始失败，回退只恢复这两个数值seam及主课题的兼容接线，不重置其他工作、模型、设置或存档。
