# 原生船体物理：实施及验收证据

日期：2026-10-11。只读来源：`C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada`，HEAD `9ad6a44daecd4ec36a8172d83ff27493feffe5dd`。目标：`C:/Users/dains/Documents/Git/ming-armada`。这是船体数值层验收，不是完整游戏迁移验收。

## 结构与来源

- `modules/contracts/physics_types.gd`：原六船 SI 参数、`NormPhysicsConfig` 默认值、有限数与吃水校验。参数来自原 `packages/naval-core/src/encounter.ts` 的 SPECS，保留物理质量、实际火炮数量与 crew metadata 的区别。
- `modules/contracts/simulation_contract.gd`：120Hz 物理步、60Hz naval 步、原 50ms 单次 delta 上限、单位。Runtime 提供已接受的时间；solver 不含 `_process`、`_physics_process` 或 accumulator。
- `modules/contracts/wave_descriptor.gd`：五个原波分量、descriptor 转换、7m crest-to-trough envelope 与最多八波校验。CPU/GPU 可以共享这份合同。
- `modules/physics_engine/ships/ship_dynamics.gd`：原 `NormPhysicsEngine` 的船体力学、四点浮力、姿态、cargo/draft 更新与水平接触 impulse。依赖 contracts 与数值 manual budget；不 import scene、UI、naval 或 game。
- `modules/physics_engine/ships/manual_handling.gd`：原 `physics-core/src/manualHandling.ts` 的完整有界请求及 torque；原 `naval-core/src/manualHandling.ts` 的六船速度/健康/船员预算。权限、自动回风、导航取消、fresh-forward 等政策仍由 naval/runtime 层拥有。
- `tools/migration/export-ship-reference.mjs`：直接在内存 transpile/evaluate 冻结 TypeScript 原实现，读取原 authored wave 模块与 SPECS，导出 detached JSON。没有构建或写入原工程，没有从新 GDScript 生成 expected 值。导出器检查 HEAD，并检查参与 oracle 的原文件没有相对 HEAD 的工作树改动。

水平面使用 XZ，heading 连续累积，0 指 +X、π/2 指 +Z。`wind.direction` 是来向；气流取负。正 heel 表示右舷下沉，正 pitch 表示船艏上仰。数值状态只用 64-bit scalar float 与 Dictionary；Vector2/Vector3 转换留在显示/接触 adapter。

保留更新顺序：drive → sail pressure/lift/drag → air/water drag/brake → keel lift/induced drag → lateral damping → legacy hard no-go → hydraulic rudder/crew stern force/manual torque → heave/pitch/heel → heading/position。船体数值层没有 Godot 默认重力或默认浮力参与，不会双重积分。

## 冻结 API

```gdscript
var ShipDynamics = preload("res://modules/physics_engine/ships/ship_dynamics.gd")
var ManualHandling = preload("res://modules/physics_engine/ships/manual_handling.gd")
var ship = ShipDynamics.new()
ship.configure(spec: Dictionary, terrain: Callable = Callable(), waves: RefCounted = null) -> bool
ship.step(delta: float, controls: Dictionary = {}) -> Dictionary
ship.step_buoyancy(delta: float, accepted_time: Variant = null) -> Dictionary
ship.get_snapshot() -> Dictionary
```

`spec` 字段：`kind`、`position:{x,z}`、`heading`、`speed`、`time`、可选 `baseY`、`wind:{direction:{x,z},speed}`、`cargoMass`、`draft`、`sailAngle`、`sailDeployment`、`sailCondition`、`sailPowerScale`、`config`。`params` 是可选低层原 ShipLikeParams 覆盖，普通游戏初始化使用六船 kind。没有 `baseY` 时采用当前时间四支点平均水高，采样顺序/算术保留原初始化行为。

`waves` 提供 `sample(x:float,z:float,time:float)->Dictionary`，其中 `height` 为米。solver 只读注入采样器。terrain Callable 预留给上层接触适配；普通船体积分不直接查询地形或自行结算浅滩/损伤。

`controls` 字段：`throttle`（[-1,1]）、`rudderAngleDeg`、`crewSteeringForce`（N，cap40000）、可选 `manualAssist`，以及可选 rig/wind 更新。`time` 是已接受区间结束时刻，Runtime 可每个 120Hz 步显式传入；缺省使用先前 time 加本次实际接受的 capped delta。无效/非正 delta 不改变时间、controls 或 body。

Snapshot 每次返回 detached dict：

```text
kind, time, position{x,y,z}, heading, velocity{x,y,z}, yawRate,
heave, heaveRate, pitch, pitchRate, heel, heelRate, baseY, buoyancyOffsetY,
mass, dimensions{length,width,draft},
rig{sailAngle,sailDeployment,sailCondition,sailPowerScale},
sailDebug{valid,apparentWindSpeed,trueWindSpeed,relativeWindDirDotForward,
          sailAngleRad,aoaRad,runBlend,cl,cd,forwardForce}
```

`velocity.y` 保留原 visual 合同的0；实际 heave 速度独立在 `heaveRate`。position.y 是 baseY+heave；heading 不 wrap。live setters：`set_config/get_config`、`set_cargo_mass`、`set_draft_meters`、`set_wind`、四个 `set_sail_*`、`set_state`、`set_base_y`、`set_speed`。水平适配：`stop_horizontal_motion`、`correct_horizontal_motion`、`resolve_horizontal_contact`。`get_wave_debug` 返回 detached 四点与平均/倾角。装备与水平接触更新保留 heave/pitch/heel、rates 和波 reference；只有 set_state/set_base_y 与初始化按原语义重置 reference。

`ManualHandling.build(kind, turn_intent, speed, crew_fraction=1, hull_fraction=1, sail_fraction=1, braking=false, sail_deployment=1)` 返回以下 `manualAssist`：

```text
targetYawRateRad, maxYawAccelerationRad, powerFraction,
neutralYawDamping, brakeDeceleration, coastInNoGo
```

速度 blend 是 clamp((speed-.3)/1.2)，预算单位由度转弧度。moving/slow/acceleration：fisherman12/6/16；patrol10/5.5/14；fuchuan8/5/11；merchant/voc6/4/8；heavy4.5/3/6。power=`crewFraction*sqrt(hullFraction*sailFraction)`；neutral damping2.5；收帆<=.05的 brake=.20m/s²。干船 yaw inertia 定义力矩预算，实时含 cargo inertia 决定实际 acceleration。

现实模式省略 manualAssist，保留原 hydraulic/crew 舵与 active-sail hard no-go；辅助模式提交上述 request，保留 no-go 帆力抑制但允许惯性滑行。实际船员舵力由 caller 提交 `min(crew,maxCrew)*200*steeringMultiplier`；归一化 rudder 由 caller 转 `rudder*30` 度。solver 不判断玩家权限或修改业务健康值。

## 本次直接数值证据

先运行测试，观察 `native marine solver must exist and instantiate` 的预期红灯，再写实现。随后使用真实原 JS runtime fixture 检查新 port。一个后来暴露的 null heave bound 原子拒绝问题也先加入失败测试，再修正。

导出命令（Node 24.18.0；VM Modules 实验警告属于导出工具）：

```powershell
rtk proxy node --experimental-vm-modules tools/migration/export-ship-reference.mjs
```

`tests/fixtures/ship-reference.json` 包含 sourceHead、参与源文件 SHA256、原六船规格、原 descriptors、24组轨迹/215个选中 frame，以及54个直接来自原 `manualHandlingFor` 的预算。24组轨迹实际积分54,960个原 source tick，包含六船各60秒120Hz、60Hz fuchuan实时 cargo/draft/power 更新、crew±/zero、drive±、manual/cargo/少船员/neutral/contact/anchor、headwind现实与辅助coasting、brake、关闭浮力的roll、四个cardinal heading。

验收命令：

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_ship_physics.gd
```

Godot `4.7.2.stable.official.ed1daf0bf` 最新直接结果：**16,557 assertions，0 failures**。215个 frame 的 scalar 字段最大绝对误差 **1.4551915228366852e-11**。误差阈值是 `1e-7 + 1e-8*abs(expected)`，bool/null 精确比较；没有宣称浮点 bit-exact。并非每个 source tick 都在 fixture 存储/比较，长轨迹按指定 checkpoint 比较。

行为检查还涵盖：无效/非正/无穷 delta、50ms cap、detached nested snapshots、无效 throttle/rudder/crew、17种非法 assist（整个请求清空）、null/string heave bound 原子拒绝、非法 cargo/draft/config不变、合法装备不重置姿态/波 reference、crew低速舵与高速禁用、dry torque/live loaded inertia、brake不倒车、headwind不虚构推进、移动平水四点浮力、水平anchor不改变水姿态。

同期更广原生检查：water77/shore10/asset manifest910/world lifecycle1707 assertions 均0失败。`test_mingqi_rules` 当时因另一个工作中的 domain 文件缺少 save_codec 和若干函数而无法编译，已向主任务报告；不把该套件当作通过。主任务应在 domain 合并完成后重跑完整测试。

## 仍需后续验收

本层没有实现 naval 权限、AI/自动 trim/回风 recovery/fresh-forward、导航/浅滩 policy、炮弹与损伤、存档、Jolt world/contact adapter、船员rig或UI。四点 pose 数值通过，不等于真实 GLB 甲板始终不浸水的三角形/边中点/重心验收；六船实际视觉、风浪水线与帆缆表现仍由主任务接入原生场景后验证。120Hz caller 的实际输入/暂停/变速/插值同一 clock 接入，也需 runtime 集成测试。不得以本层通过宣称完整玩法/完整迁移完成。
