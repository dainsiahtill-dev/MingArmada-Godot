# 新生涯与其他入口的当前性能对比

2026-10-13；源码基准 `756392e`。本轮只增加私人诊断工具与证据，不改生产玩法、画质、模型、船员数量、用户存档。CodeGraph 项目未索引，采用 RTK 源码检索和实际 Godot 运行。

## 已复现的现象

原生 Godot 4.7.2 / Vulkan Forward+ / Intel Arc 130T；每个入口使用独立新进程、实际公开菜单和 Router，窗口保持前台、可见、未暂停。先预热至少 2 秒，再记录至少 8 秒真实引擎帧。采样期间不手动调用物理/呈现方法、不限帧、不截图读回 GPU。

| 实际公开入口 | 船 / 可见船员 | 有效采样秒 | 观测平均 FPS | 帧间隔中位 ms | 墙钟期间权威时间推进秒 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 海上明旗新生涯 | 5 / 84 | 8.076 | 12.88 | 78.318 | 8.067 |
| 海岛与航海实景 | 1 / 2 | 8.023 | 33.53 | 29.402 | 8.022（展示时钟） |
| 自由试航 | 3 / 35 | 8.210 | 2.44 | 410.179 | 2.667 |

新生涯相对于海岛展示的卡顿已经复现。自由试航也有严重卡顿，不能把所有其他入口都视为流畅基线。岛屿展示没有完整战役与航行模拟，而且只有一艘远处的船。

这是相同机器、同版代码、相同窗口尺寸下的产品默认入口对比，**不是相同内容的纯效率实验**：新生涯主视口 1600×900、balanced、反射 768×432；海岛实际 3D 子视口 1600×838、high、反射 768×402；相机、船数和可见船员也不同。三轮生产代码散列稳定，实际焦点、窗口与负载检查都通过；未验证长期性能。

采样后才暂停并截取真实窗口图片。图片中的“已暂停”不代表采样期间暂停。

## 当前主要原因

### 每步战役同步与完整业务包

`MingqiRuntime.advance` 每个接受的 1/60 秒物理步都调用原生模拟、`bridge.reconcile`、`campaign.advance` 和战役快照。`NearFieldBridge.reconcile` 继续验证并回写全部近场船只；`Encounter.reconcile_ships` 对五艘船每次创建五个 Physics probe，并进行十次属性遍历复制。这是源码确认的调用数量，未单独给 probe 估算毫秒占比。

`MingqiRuntime.snapshot` 每次呈现还生成完整业务包：战役深复制、全部港口停泊条件、保存安全、故事投影及操作资格。新生涯 UI 深复制包，并更新包括隐藏面板在内的所有 watcher。当前 CPU 方法诊断中，新生涯推进中位 5.043ms，试航 1.123ms；业务 snapshot 1.373ms / 0.037ms；UI 2.136ms / 0.406ms。它们是单次同步方法成本，不能当 FPS，也不能忽略物理每秒执行 60 次。

源码入口：`game/runtime/mingqi_runtime.gd:208`、`:314`；`game/runtime/near_field_bridge.gd:180`；`modules/naval_simulation/encounter.gd:1091`；`game/ui/mingqi/mingqi_interface.gd:44`。

### 新时间的云雾和岸浪呈现

生产世界共有 30 个云克隆、161 个云 mesh、3 组地面雾 / 60 个雾 mesh，以及 3 岛共 698 个岸浪 patch / 349 对。云 cache key 包含旋转和相机基向量；新时间的云旋转、雾控制器仍需计算和提交。岸浪只有严格同时间重入才跳过，新时间需要采样全部 patch 并提交 shader 参数。

本轮增加首次新时间分项工具，先推进真实 runtime，再计生产组件的首次新时间调用；随后同时间重入另列，最后完成正常呈现。不把原先完整呈现之后的缓存命中时间当首次更新时间。初版记录保留；复核后的完整 phase 同步记录见下文证据。

复核修正后，8 个严格推进的 1/60 秒样本全部通过 world、ocean、shore、atmosphere 与 4 个地形 material 的时间一致检查：

| 首次新时间生产方法 | CPU 中位 ms |
| --- | ---: |
| 云与地面雾 `atmosphere.apply_snapshot` | 10.423 |
| 岸浪与森林 `natural_world.apply_snapshot` | 5.274 |
| 海水时间提交 | 0.109 |
| 海水投影更新 | 0.062 |
| 地形与岸浪 surface 状态同步 | 0.304 |

这是 headless 分项方法成本，相机沿用前次正常呈现，未关闭内容；不是原生帧的完整分解，也没有覆盖一个绘制帧内累计 4～5 个物理步的全部成本。不能与各视口 GPU 或其他方法中位数直接拼成帧时间。

海水时间提交和投影自身的 CPU 时间很小，不能因此认定海水 shader 的 GPU 成本也小。当前优先方向是云雾控制器、岸浪采样和参数提交的 CPU 工作。

源码入口：`modules/scene_engine/fidelity_fx/atmosphere.gd:201`；`modules/scene_engine/terrain/natural_shore_surf.gd:206`；`modules/scene_engine/world/world_view.gd:287`。

### 调度放大问题：新生涯已拆分，试航仍存在

当前新生涯日常 `_physics_process` 只推进权威、记录出生姿态、推进 Jolt；完整呈现在 `_process`，开炮和船员受击保留稀少即时刷新。旧版本新生涯的每补步全场景更新已修复，不能继续说当前版本仍有该旧调用链。

当前 Practice `_physics_process` 仍直接 `_present(runtime.advance(delta))`。真实自由试航 20 个有效帧间隔全部执行了 8 个物理补步，每步重做船模、船员、云雾、岸浪和界面；8.210 秒墙钟只推进 2.667 秒原生时间。该入口仍有补步负载放大和游戏时间变慢。

源码入口：`game/scenes/mingqi/mingqi_scene.gd:133`；`game/scenes/naval_practice/naval_practice.gd:49`。

### GPU 并非全部差距的解释

新生涯主视口 GPU 中位 24.920ms、反射 3.189ms；海岛 3D 子视口 24.547ms、反射 3.146ms。二者接近，不能解释 12.88 / 33.53 FPS 的全部差距。结合直接 CPU 方法成本和权威物理调用链，可定位新生涯额外的 CPU 负载；不能由视口计时给某个 shader 或 84 名船员分配精确占比。

GPU 计时使用 Godot [RenderingServer 视口测量 API](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu)。视口渲染 CPU 不包含脚本 `_process`；不能直接将 GPU、脚本方法和其他 monitor 的数据相加为帧总耗时。

`Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS` 保留作原始 monitor 数据，不作逐帧独占 CPU 时间：Godot 4.7 `main/main.cpp` 按约一秒发布窗口峰值，process 区域包含渲染同步/绘制。见 [Godot 4.7 主循环源码](https://github.com/godotengine/godot/blob/4.7/main/main.cpp#L4678-L4762) 和 [Performance 文档](https://docs.godotengine.org/en/stable/classes/class_performance.html)。

## 入场等待与持续低帧率要分开处理

本轮新进程实际入场：新生涯 6.229 秒、海岛 7.570 秒、自由试航 8.796 秒；未清空 Godot 或系统缓存，不称完全冷启动。新生涯不是本轮入场最慢的模式。

源码确认新生涯 Interface 初次空包建 UI、配置海图后，第一次 campaign packet 改变 signature 再重建 UI；`_build_convoy` 会再次采样海图地形。该重复工作影响入场等待，但没有单独测时，不能用它解释全部运行卡顿或声明省下多少秒。

## 后续修复优先级

1. 保留现有效果与数量，优化云雾和岸浪的新时间计算：预编译静态资源/曲线、减少重复分配和参数提交；按相同相位比较输出，避免用同时间缓存命中冒充改善。
2. 优化新生涯每物理步近场同步的静态规格、验证器和复制，保持原权威同步和交易检查；不通过丢弃物理步隐藏成本。
3. UI 根据实际变化刷新；隐藏面板延迟刷新，海图采样独立于 UI 重建。船模/船员避免重复处理隐藏 LOD 和同相位的动画采样。
4. 将已验证的新生涯物理/呈现分离合同应用到 Practice，保留开炮出生姿态、事件顺序和受击 Jolt 逐物理步推进。
5. CPU 改进后继续分别隔离主视口 GPU 的水面、透明层和地形成本。本轮未做 shader 对象级 GPU 归因，未宣称性能已经修复。

## 本轮证据

- `Temp/entry-live-mingqi-current-20261013-v1/live-observation.json` 与 `mingqi-after-observation.png`。
- `Temp/entry-live-island-current-20261013-v1/live-observation.json` 与 `fidelity-island-after-observation.png`。
- `Temp/entry-live-sail-current-20261013-v1/live-observation.json` 与 `sail-after-observation.png`。
- `Temp/career-entry-cost-current-20261013.json`：当前同步 CPU 方法对比，failures=0。海岛分支旧工具仍把 shipCount 写死 0，真实数量应以新的 live 工具为准（1 船）。
- `Temp/world-fresh-time-20261013-v1.json`：初版分项记录，terrain 同步尚用上一 world phase；岸浪和 atmosphere 新时间断言通过。保留作诊断修正证据，不作为完整世界新 phase 同步的通过记录。
- `Temp/world-fresh-time-20261013-v2.json`：修正诊断同步顺序后的 8 个新时间样本，failures=0；每个地形 shader phase 也与 native 对齐。
- `Temp/career-entry-performance-verification-20261013.json`：三份真实帧报告与当前 191 份生产代码 hash 一致，间隔总和/FPS、全程焦点/负载、截图后读回与 SHA256、v2 所有组件 phase 核验通过。
- 私人工具：`tools/diagnose-entry-live.gd`、`tools/diagnose-world-fresh-time.gd`。没有新增玩家菜单或独立游戏示例。

当前交付为诊断与可复现证据，尚未改动生产性能代码。原用户 Godot editor 保留，诊断进程退出；未提交或推送。
