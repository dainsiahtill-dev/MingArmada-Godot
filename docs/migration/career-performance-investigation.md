# 新生涯主线程卡顿排查

2026-10-12～13，实际 Godot 项目 `ming-armada`。本轮由普通主菜单路由进入场景，使用实际生产方法计时；不修改用户存档。基线源版本 `800a688`，相关文件散列位于 `Temp/career-performance-baseline-source-hashes.json`。

## 已复现的瓶颈

原生 Vulkan / Intel Arc 130T、1600×900 的分段对照见 `Temp/career-cost-native-baseline-v3.json`。新生涯初始为五艘船；暂停时一次 `_physics_process` 的 CPU 方法中位耗时为 **69.255ms**，推进时为 **79.281ms**。16.67ms 方法预算检查实际失败两项。该数值是同步方法耗时，不是实测 FPS、GPU 帧耗时或长期稳定性指标。

进一步用同一场景、相同 accepted snapshot 分解生产呈现方法，见 `Temp/career-cost-world-stages-v3.json`（headless CPU 诊断）。初始五艘船和 84 名可见船员全部保留；没有关闭效果、反射或海岛。推进组中位数：

| 方法 | CPU 毫秒 |
| --- | ---: |
| 岸浪 controller / state 更新 | 29.534 |
| 云雾 source state / bounds 更新 | 27.160 |
| 森林更新 | 0.070 |
| 海水时间更新 | 0.128 |
| 海水投影更新 | 0.046 |
| 战役与物理 runtime advance | 5.186 |
| 完整业务 snapshot | 1.462 |
| 生涯界面更新 | 2.188 |

暂停时岸浪及云雾成本依然存在。各子方法为相同时间下的独立重入计时；不能直接相加冒充完整新帧时间。

云雾每次重建源 block 索引、遍历完整源节点、控制器、顶点和 UV；部分结果仅在配置网格时需要。岸浪每个 packet 重复创建并深拷贝多个 controller clock、执行 binary32 编码及原曲线采样，同时间没有复用。这两项是优先修复范围。

其他正式模式也使用共享 World 路径，当前实测并不支持“问题仅存在于新生涯”。新生涯另外具有战役同步和较重的 UI；启动还有海图重复构建，但它们不是本轮稳定更新的主要耗时。

## 修复约束及验证

保留全部云、雾、岸浪 patch、模型、贴图及原 mip；保留 accepted time、原 controller 插值与 float32 存储、海浪与浮力数据。优化静态准备、重复对象分配和严格相同输入重入，不量化时间，不减少效果数量，不改画质。

云雾与岸浪由不同 Agent 实现，另有独立只读审查；原生测试均由 root 串行运行。回归比较原数学 oracle、循环边界、回退、同时间、相机切换、重配置和释放。下文记录本轮结果，未将初始预算失败记录当作成功证据。

## 真实帧确认的放大机制

`Temp/career-live-kernel-v2/live-observation.json` 是缓存优化之后、场景更新尚未拆分时的真实引擎观测。由普通主菜单进入新生涯，保持原生窗口前台、可见、未暂停，整个计时区间没有手动调用物理方法、限帧或 GPU 截图读回。12.144 秒共绘制 36 帧；游戏权威时间只推进 4.8 秒。去掉前两秒预热，30 个间隔的中位数为 339.169ms，所有间隔都执行了 8 个物理补步。

根因调用链为 `MingqiScene._physics_process → runtime.advance → _present → NavalWorldView.apply_snapshot → World.apply_snapshot`。固定物理补步同时更新船模、船员显示、海面、岸浪、云雾及全部生涯 UI。一帧变慢之后，引擎补更多物理步，每补一步又执行全套呈现，导致积压。单项缓存改善不能单独消除这条放大链。

结构修复要求：

- 固定物理步只推进权威模拟、观察炮弹速度、记录船舶出生姿态，并保持船员受击 Jolt 逐物理步推进。
- 每个正常绘制帧汇总 accepted time，呈现一次最新快照。事件保留原顺序、出生时间和位置；不因延后绘制丢弃事件。
- 立即命令、暂停、重载和手动截图仍能明确刷新画面；刷新后清空已消费的累计时间。
- 先验证延后炮口姿态、事件和船员物理合同，再重跑同一 12 秒原生观测，区分改善幅度与尚未达到的目标帧率。

## 已落地及最终观测

`game/scenes/mingqi/mingqi_scene.gd` 将日常完整呈现从 `_physics_process` 移到 `_process`，累计的时间来自 runtime 实际接受的模拟步，刷新时消费并清空。命令和手动捕获继续使用原 `_present` 接口。新生涯特有的战役同步与 UI 成本仍存在，不通过删掉它们隐藏问题。

`ShipView` 逐物理步轻量记录精确模型姿态，保留炮口出生位置；`CrewView.advance_impacts` 保留原 Jolt 步进、相邻甲板帧与物理请求，同 phase 的绘制不会再次覆盖请求。稀少 fire／造成船员伤害的 hit 仍即时完整呈现，保证受击皮肤移交、出生与生命周期。跨 battleId 未初始化的新演员使用权威原生位置回退，避免旧沉船根节点污染新船。

岸浪静态 controller 与 clock 编译一次，严格相同时间复用，海面 uniform 仅变化时提交，PackedArray 按值快照防别名。云雾静态资源与 billboard 状态复用，动态 fog 保留原控制器；最低高度只计算原顶点 Z 分量。Float32 存储点及原 Float64 表达式结合顺序保持一致，没有减少任何 patch、船员、模型、贴图、反射或效果数量。

全部为 Intel Arc 130T / Vulkan / 1600×900，前台、可见、未暂停的实际引擎帧。下表去掉两秒预热后的帧间隔用于典型值；约 FPS 是中位间隔倒数，不能当长期性能保证。

| 实际观测 | 拆分前 v2 | 拆分后 v3 | 最终 v4（开启渲染计时） |
| --- | ---: | ---: | ---: |
| 观察墙钟秒 | 12.144 | 12.059 | 12.060 |
| 总绘制帧数 | 36 | 175 | 182 |
| 游戏权威推进秒 | 4.800 | 12.083 | 12.083 |
| 预热后中位帧间隔 ms | 339.169 | 68.563 | 66.106 |
| 典型约 FPS | 2.95 | 14.59 | 15.13 |
| 预热后每绘制帧物理补步 | 全部 8 | 4～5 | 3～5 |

v3、v4 均保留 5 艘船和 84 名可见船员。v4 日志完成标记 `CAREER_LIVE_OBSERVATION frames=182 valid=true nativeSeconds=12.0833333333333`；原生截图捕获 failures=0。截图在观测结束后才暂停、读回 GPU 图像，截图 UI 的“已暂停”不表示计时区间暂停。

证据：`Temp/career-live-kernel-v2/live-observation.json`、`Temp/career-live-scheduled-v3/live-observation.json`、`Temp/career-live-render-metrics-v4/live-observation.json`，画面在各目录 `career-after-live-observation.png`。

## 剩余成本与边界

本轮消除了最严重的补步积压，**尚未达到流畅的 30／60 FPS 目标**。最新独立 CPU 方法诊断 `Temp/career-cost-scheduled-v7.json` 的推进组中位数：固定物理回调 5.909ms，单次画面呈现 30.006ms，完整业务 snapshot 1.457ms、UI 2.264ms。这些是受控方法调用的 headless CPU 成本，不是 GPU 帧时间；同时间重入缓存成本也不能冒充首次新时间成本。

v4 启用 Godot 官方 RenderingServer 计时：主视口 GPU 中位 28.925ms、平面反射视口 3.780ms；相应渲染 CPU 为 0.731ms 和 0.779ms，frame setup CPU 2.269ms。引擎 process monitor 为 47.352ms、physics monitor 为 7.530ms。不同计时覆盖的阶段与并行关系不同，不能直接相加作为帧总耗时，也不能凭整个视口的 GPU 数据断言某个物体或 shader 独占这些时间。方法依据见 [RenderingServer 文档](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-set-measure-render-time)。

新进程进入新生涯观测为 5.70～5.94 秒，操作系统与 Godot import 缓存未清空；这项加载等待没有宣称完成优化。后续成本已缩小到新时间的云／岸浪呈现、战役逐步同步、界面与主视口绘制，应分别测量，不再将海水、船员或岛屿笼统当作唯一原因。

只读源码还确认每次五船 reconciliation 新建五个数值 Physics probe，并进行十次属性反射与复制。这是调用数量，不是单独耗时；本轮保留整批验证和提交，未用跳过交易或校验的方式换取速度。

## 验证结果

当前实现通过延后炮口姿态、真实逐 Jolt 步进与呈现调度、原开炮出生姿态、crew impacts／生命周期、Mingqi runtime／场景／存档／新开与继续、岸浪原曲线与云雾 Float32／缓存回归。独立审查关闭了 PackedArray 别名、Bezier 结合顺序、跨 epoch 旧沉船偏移与受击出生延后问题，无未关闭 P1／P2。

关键新 RED→GREEN 记录：`Temp/mingqi-presentation-schedule-red.json`、`Temp/crew-impact-schedule-red.json`、`Temp/deferred-ship-birth-pose-red.json`；最终 GREEN 与原用例回归索引见 `Temp/career-performance-final-verification.json`。新增云 Float32 store A/B 的 45,222 项原版逐位对照全部通过，仅观察到约 0～6% 单项提速；不将其夸大为整体 FPS 收益。

未运行整个历史测试套件或长期战役／大型交战性能验收。代码未提交或推送，临时生产计时标记已移除；保留诊断工具与证据，不新增玩家可见的独立示例入口。

可复现命令（输出必须使用新文件名，不能覆盖旧证据）：

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --path C:/Users/dains/Documents/Git/ming-armada --script res://tools/diagnose-career-cost.gd -- --order=fidelity-island,sail,mingqi --budget-ms=16.67 --output=res://Temp/career-cost-fresh-name.json
```

诊断脚本手动重入生产方法并在每次采样间绘制真实原生帧，**不作为 FPS benchmark**。首轮 `career-cost-baseline-v1.json` 的自定义 pause reason 被产品拒绝，不能用于暂停组结论；之后版本改用真实 `player` pause 并记录实际 paused 状态。所有旧记录保留。
