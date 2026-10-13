# 开炮性能：REA 交接与暂停记录

2026-10-13，用户要求 Godot 侧暂停，先等待原版逆向的明确做法，再恢复接入和验收。本记录不是完成报告。

接收任务：REA-席德梅尔的海盗游戏，thread `01a12a4e-c382-72a2-b117-4632a05961de`，host `local`。

## 交接请求

+用户明确要求我把反复难以解决的开炮卡顿交给你逆向原版做法，Godot 侧现在暂停，等你交付成功再接手。请优先研究 Pirates!.exe 的粒子批量绘制与海战帧循环；复用已有报告、数据库，不重复大范围资源抽取。

实际项目 C:/Users/dains/Documents/Git/ming-armada（带连字符，无连字符MingArmada是旧Three.js）。本侧代码只读，请不改项目、不启动Godot。原件 C:/Games/Pirates.Green.Edition-ALI213/Pirates!.exe。

直接复现：实际菜单/router自由试航1600×900 balanced、4×MSAA，真实左舷四炮。原始开炮前14.87FPS/67.27ms、后2.27FPS/456.49ms；隐藏FX绘制仍2.31FPS；保留已画出网格而冻结FX CPU约74ms，主要CPU更新。纯炮弹Runtime1.0→1.36ms/tick。已修掉误用120Hz学习observer seek/fork，正式改advance_native(appTime)，保留完整容量/CRT/原DDS+mips/控制器和出生0锚；新增同龄memo、四蓝图七DDS预热、精确海陆memo、GPU mesh复用与同帧纯RefRuntime并行。仍未通过：Temp/cannon-native-worker-20261013-v7/live-observation.json valid=true failures=0，4fire和后续splash，前15.04FPS/66.60ms、后9.43FPS/101.92ms、p95=180.70ms、恢复13.76FPS/72.11ms，performanceRed=true。报告docs/migration/cannon-performance-2026-10-13.md仍是未完成草稿。全部过程证据Temp/cannon-*-20261013-*。

请闭合以下缺口：
1. 原版NiParticles/NiPSys究竟每粒子还是每系统/材质批量提交？追真实DrawPrimitive/DrawIndexedPrimitive或引擎提交链，恢复动态vertex/index buffer容量、原地更新、RGBA/UV布局、CPU/GPU billboard。Godot现在一粒子一MeshInstance，这只是迁移方案，并非原版已确认行为。
2. 原版透明排序粒度是系统/效果/粒子？是否在系统内排序？alphaFlags additive/mix怎样允许batch保持视觉？请给原代码/运行证据，不能根据学习demo renderer猜原版。
3. modifier/发射/寿命/矩阵/UV的真实更新时钟、调用次数、cache/LOD是什么？variable appTime还是fixed/catch-up，是否重复update？学习observer120Hz不等于原帧率。
4. 分批发炮/落水出生是否强制更新整场船/crew/world/HUD？目前每次fire在physics full_present，process又full_present，出生阶段重复完整Scene。请追原版fire/event/muzzle挂点/recoil与update/render顺序，给保留准确birth appTime而避免重复全Scene的合同。
5. 有证据的CPU批量生成/packed buffer/按系统提交/条件更新实现是什么？优先恢复正确高效结构，不能用减粒子、隐藏烟、停更状态代替修复。

本侧代码入口 modules/scene_engine/fidelity_fx/{presentation,particle_runtime,native_particle_replay,native_particle_math}.gd；game/presentation/combat/combat_effects.gd；water/water_splashes.gd；world/naval_world_view.gd；game/scenes/naval_practice/naval_practice.gd。四源 fx_cannon_fire_01及cannon_ball_splash_01/02/03完整容量435/82/85/79，系统11/8/8/8。actualGPU cannon age0.8单源9.72ms=native3.70+meshes3.19+render2.52。已通过GPU旧renderer对照8026断言、worker与sync/fullNative state/mesh/material/AABB/order对照349断言；一致性通过，性能未通过。

请保存专项报告、原函数/汇编/伪码、验证与未知项、Godot batch建议和接入合同到 C:/Games/Pirates-REA-Reference-20261011/performance-study-20261013/，或直接指明既有完整证据。完成后在你的最终答复写清完整入口和哪些缺口已/未确认，本线程会读取交付后继续。若已有报告已回答这些问题，先指出准确证据与可复用实现，不重复逆向。Godot侧已暂停进一步实现/验收；目前仅保留编辑器，未启动测试游戏。

## 暂停时的验证和后续边界

- 最新实际原生四炮复现仍为性能失败，禁止降低原判据或把一致性测试通过当作卡顿解决。
- `Temp/cannon-parallel-green-20261013-v1.json`：349 断言、0 失败，完整四源 worker/sync/native 状态及几何一致。
- `Temp/cannon-game-clock-worker-20261013-v4.json`：正式游戏时钟回归通过。
- `Temp/cannon-fidelity-fx-regression-20261013-v5.json`：worker 修改之前的 11 项特效组通过；worker 后完整组尚未重跑。
- `Temp/cannon-native-mesh-quad-20261013-v2.stdout.log`：worker 修改之前真实 GPU 网格对照 8026 断言通过。
- `Temp/cannon-native-visual-prewarm-20261013-v2/`：真实游戏 4 次发炮、4 次落水的 6 张生命周期截图，已观察水柱及水环。worker 后尚未重新截图。
- 新增生命周期测试继续工作已停止；`tests/test_fidelity_fx_parallel_work.gd` 保持已通过的 270 行，SHA256 `7f2e3f2ccfa3a93db6793354174322e97a728dbc198d6f72406966cd32bb44c1`。
- 独立审查已发现一个待处理的 detached owner 边界：CombatEffects 释放 `_water_splashes` 目前仅 `free()`，脱离 SceneTree 后若 Water 尚有 pending 任务，不能依赖 `_exit_tree` 收回；恢复后应加真实 teardown 测试并显式 dispose。正式 SceneTree 内的路径安全。本次按用户暂停要求未继续修改。
- 原项目所有未提交改动保留；不提交、推送、清理或回滚。编辑器 PID 9236 保留。当前没有测试游戏在运行，未重新启动正常自由试航。

恢复条件：读取 REA 针对此交接的完整证据，明确 batch、透明排序和帧循环合同后再实施；随后补全生命周期、实际 GPU 对照、左右舷齐射和正式游戏重开验收。
