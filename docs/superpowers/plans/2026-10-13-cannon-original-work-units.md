# 原版工作单元接入计划

> **For agentic workers:** Use superpowers:subagent-driven-development for the two independent implementation tasks. Root runs all Godot verification. Steps below use checkbox syntax to track completion.

**Goal:** 消除真实自由试航四炮齐射后的严重降帧，并据实定位剩余基础展示成本。

**Architecture:** 正式游戏粒子按系统生成和提交，保留独立系统的容量、随机流、材质与原始粒子顺序。physics 发炮只处理真实出生事件及必要局部展示；整场船、人物、世界、HUD在正常呈现帧统一更新。已接入的同帧 worker 在渲染前完成，所有 Node/GPU/水面回调继续在主线程。

**Tech Stack:** Godot 4.7.2 / GDScript / ArrayMesh / WorkerThreadPool，Windows 原生 Forward+。

**Spec:** `C:/Games/Pirates-REA-Reference-20261011/performance-study-20261013/AGENT_HANDOFF.md` 及同目录 `PERFORMANCE_IMPLEMENTATION_REPORT.md`。

## Global Constraints

- 实际项目为带连字符的 `ming-armada`；旧 `MingArmada`、原游戏和研究交付只读。
- 不减少粒子、隐藏特效或改动伤害/弹道来获得通过。
- 本轮保留当前游戏玩法时钟；原版 60/32/25 ms 及完整 clone 初值边界另行记录，不能把现有 clock adapter 宣称为原版。
- 用户明确要求甲板人物继续使用3D模型、骨骼和动画；采用原版调度结构时保留此表现，不替换成图集billboard。
- 默认学习 `meshes()`、observer 及公开所有权接口保留；正式系统路径明确选择 `render_unit=system`。
- 只有 Root 启动引擎；编辑器保留，每次只运行一个测试/游戏；测试游戏退出后再启动下一次。
- 每条 shell 命令以 RTK 开头；不提交、推送、重置或创建新工作树。

## Review Focus

- 同帧多次不同出生 stamp：保留 id/order、准确 muzzle/impact pose 和 native 输入顺序。
- 相机刷新/暂停/回退：不重复消费 RNG，也不跳过新的出生事件。
- 系统缓冲有效前缀及多实例：保持4N顶点/2N三角形，延迟 worker 不持有被下一次 fill 覆盖的描述。
- 原 blend/UV/mips 与 authored 水柱/环：独立保留，不随烟粒子跨系统合并。
- 销毁、重配和 detached owner：每个 worker 恰好等待一次，随后释放资源。

## Task 1: 每系统粒子绘制

**Files:** `modules/scene_engine/fidelity_fx/` 中的 batch helper、Runtime 与 Presentation；新 `tests/test_fidelity_fx_system_batch.gd`。Root 在 builder 冻结后接线游戏 owner。

**Interfaces:** Runtime 提供 `batch_meshes(camera: Dictionary) -> Array`；Source configure 接受 `render_unit: particle|system`，默认 particle；worker 与同步呈现均按该选项选择纯CPU输出。

- [x] 写真实源 RED：完整容量及 native state 不变；顶点/ARGB/UV/索引原顺序；每系统载体、零active跳过、相机/生命周期/缓冲所有权。
- [x] Root 用 `rtk proxy node tools/verify-godot.mjs --filter test_fidelity_fx_system_batch --output Temp/cannon-system-batch-red.json` 验证失败。
- [x] 实现系统批量路径；活粒子数改变时保持实际draw前缀，稳定布局复用 GPU 资源；原默认接口保持。
- [x] Root 验证 GREEN、相关回归和原生GPU系统流；再将正式炮火/水花选项接到 system。

## Task 2: physics 局部出生

**Files:** 两个实际海战 Scene、`naval_world_view.gd`、`combat_effects.gd`；新 `tests/test_local_fire_presentation.gd`。

**Interfaces:** Sea 提供独立的局部发炮呈现入口；仍消费准确 ordered events/native snapshot，使用已有 authoritative pose history。normal `_present()` 保持整场入口。具体签名以 RED 确定并记录 builder 交接。

- [x] 写真实 physics fire RED，计数全部scene/world/HUD重复调用，并比较出生pose/time/id/order、recoil/audio、重复/迟到事件。
- [x] Root 运行 RED 后授权窄实现；crew hit/terminal immediate 路径保留。
- [x] 修正 Combat detached Water 显式 dispose 生命周期，并加入真实 teardown 覆盖。
- [x] Root 检查局部出生、reference event time、deferred pose/Jolt、两个Scene、terminal/aftermath回归。

## Task 3: 正式接线与验收

- [x] 冻结生产源码后，以真实router/UI左右舷四炮及后续落水复测；保持1600×900 balanced/4×MSAA与现有判据。
- [x] 记录每系统/粒子载体、CPU调用数量、frame median/p95/恢复和 native 时间推进；截图在计时后获取。
- [x] 根据独立Scene成本探针确认剩余基础开销；仅在有直接耗时证据后修改隐藏模型树/普通crew等路径。
- [x] 整合适当回归和独立审查；更新性能报告，明确多船大齐射尚未覆盖的边界。
- [x] 重新打开实际自由试航并检查启动日志/画面；只有真实原生复现通过才解除开炮性能失败。

## 当前验收记录

- 系统粒子：Root真实原生GPU 32865断言/0失败；完整x86字节、源状态、多实例、暂停相机恢复、flash载体复用通过。
- 局部发炮：99/0；两个场景调度与formal game clock system接线249/0通过。
- 原生真实四炮：v8 valid=true、4发炮/4落水、无存档写入；before14.765 FPS、post10.925 FPS，post median85.985ms，原有严重退化判据通过，但仍不流畅，不能据此声称整体性能完成。
- 世界成本探针：world31.50ms中 atmosphere13.65ms、forest/surf13.64ms、projection3.06ms；尾迹另11.44至18.31ms。甲板3D crew1.51ms，不是基础性能主因。
- 投影局部ray缓存已通过48断言，118676个实际Camera3D oracle顶点全部精确相等；网格/反射质量保留。正在处理主要world/wake热点，最终左右舷测量待新版冻结。

- 尾迹provider-owned单次scope缓存已通过462断言，85次实际Wake完整网格/材质/回调顺序一致；精确float64坐标、near/NAN/nested/configure-revision/RAII/cap边界通过。
- 云雾scalar6974、float1339、render28485、sky220通过；独立审查未见重要问题。
- 岸浪stateReuse/new+既有hotpath/surf三组通过；default sample仍保持独立输出。当前生产冻结，Root正在左右舷native最终测量。

- 最终左/右舷v9均valid=true、0fail、4fire+4splash；before16.26/15.96FPS、post12.15/12.22FPS、median77.172/77.233ms。严重退化判据通过，整体性能未完成。
- 当前source-final CPU探针确认：dynamicSurf仍约12ms、cloud/fog compile仍各5ms、wakes约9.7至13.1ms、FXfinish/post约10.2ms。3Dcrew1.5至2.1ms。优先级遵从实测，不把float-buffer通过外推为cloud瓶颈解决。

- 最终视觉v4：6张实际GPU截图、4fire+4splash、正确有限生命周期、0fail/源码冻结/存档写入0，Root实看muzzle与rings。
- 最新投影native54/0，138359个Camera3D oracle顶点精确一致；最终local fire99/0及两个场景调度重新通过。
- 实际release/main已重开自由试航：PID7892，startup.ok=true，1600×900，截图Temp/cannon-structure-final-game-20261013.png；编辑器PID9236保留，两进程Responding=true。
