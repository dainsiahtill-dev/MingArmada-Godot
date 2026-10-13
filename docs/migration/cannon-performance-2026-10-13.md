# 开炮后卡顿：诊断与验收

本轮目标是修复自由试航中开炮后的严重降帧。正式修复保留原始贴图、完整粒子容量、控制器、随机数算法、炮弹和落水事件；隐藏特效、冻结特效更新只用于独立诊断。

## 已确认的根因

1. 正式 SourceEffect 使用了学习观察器的 120 Hz `seek()`：每个画面帧补算多次粒子状态并 fork 完整池。原游戏的 variable appTime 更新接口已存在，正式游戏应显式选择 `advance_native()`。研究观察器仍保留原接口和默认行为。
2. 每个粒子重复计算系统相机上下文和 UV 矩阵；正式绘制还创建未使用的 detached snapshot，并对新几何记录再做一次完整深复制。
3. 每个粒子每帧创建 ArrayMesh。稳定布局和索引可以原位更新，保留逐载体节点及透明排序；headless dummy 的 region update 是空操作，需要保留真实重建回退。
4. 每次特效出生都再次校验、转换完整源数据，初始化用不到的 canonical observer，再分配 native replay。正式 native 模式现在共享已校验的只读 blueprint，各实例独立拥有完整 pool、controller 和 RNG。
5. 水花海陆裁剪逐三角形重复查询同一坐标。实际单个水花 age 0.8 的 owner 有 1803 次 predicate 查询，约 7.7 ms；海水高度的 151 次采样约 0.9 ms。查询缓存正按一次同步绘制/更新的作用域落地，禁止跨帧保留。

原生诊断先排除了纯炮弹模拟和 GPU 填充率：纯 Runtime 每 tick 从约 1.0 ms 增至 1.36 ms；隐藏源特效绘制后仍约 2.3 FPS；保留已绘制网格而暂停其 CPU 更新后，帧时间中位数约 74 ms。

## 过程测量

同一真实菜单/router 自由试航，1600×900、balanced、4× MSAA、正常反射、实际左舷四炮齐射。Godot 编辑器保留，只有一个测量游戏进程。FPS 是相应墙钟阶段的平均读数，帧时间另列中位数。诊断截图在计时结束之后读取。

| 阶段 | 开炮前 FPS | 开炮后 FPS | 开炮后帧时间中位数 | 严重降帧判据 |
|---|---:|---:|---:|---|
| 原始复现 | 14.87 | 2.27 | 456.49 ms | 失败 |
| native 时钟及基础几何清理 | 14.68 | 6.15 | 151.04 ms | 失败 |
| binary32 热转换 | 14.74 | 6.83 | 134.27 ms | 失败 |
| 真实 GPU 网格资源复用 | 14.74 | 7.40 | 120.25 ms | 失败 |
| blueprint、绘制记录借用及 point 整理 | 14.83 | 7.92 | 114.48 ms | 失败 |
| 原版工作单元：系统批次、局部发炮 | 14.77 | 10.93 | 85.985 ms | 严重退化判据通过；整体仍慢 |
| 岸浪、云雾、投影和尾迹热点清理：左舷 | 16.26 | 12.15 | 77.172 ms | 严重退化判据通过；仍未达到流畅 |
| 同一最终源码：右舷 | 15.96 | 12.22 | 77.233 ms | 严重退化判据通过；仍未达到流畅 |

当前继续按原版的工作单元接入系统批次和局部发炮，并定位剩余基础场景热点，以上过程数据不能当作完成证明。原始卡顿窗口推进的 native 时间很少，后续优化能实际执行更多落水事件；不得将不同 payload 的整段 FPS 差额全部归给某一项修改。

## 状态与图形验证

- native API 的完整容量、原 CRT、世界变换及 bounds 对照；保留公开 `seek`、`meshes`、snapshot 的默认独立所有权。
- 新生 effect 保留唯一 age 0 visibility 锚；同年龄暂停、相机和海面重投影不再次执行 native modifier/bounds 更新。
- 真实 GPU 对照旧 renderer：8026 断言通过，2701 个稳定载体、148 次拓扑变化；完整解码 surface arrays、材质、有效 AABB 和排序一致。
- 当前 native work 完整 factory、seed/池隔离、lazy observer、公开深拷贝与内部借用回归 420 断言通过。
- 暂停后相机旋转通过真实 WaterSplashes owner 更新水花 billboard，generic 水花状态保持冻结。

主要原始测量与分段回执在 `Temp/cannon-native-*-20261013-*`、`Temp/cannon-actual-water-cpu-baseline-20261013-v1.json`。新 regression tests 位于 `tests/test_fidelity_fx_*work.gd`、`test_fidelity_fx_fork_cache.gd`、`test_fidelity_fx_mesh_reuse.gd`、`test_game_effect_clock.gd`。

## 最终验收

已完成本轮冻结源码的左右舷实际四炮复测与原生图形对照，详见下面的最终测量。严重开炮退化判据通过，整体自由试航仍未达到30/60FPS。正式游戏重新打开和最终截图记录在后续回执。

## 原版工作单元与3D人物约束

新版接入每系统连续4N顶点/2N三角形、原始ARGB/UV字节及系统级排序，保持独立池、材质、容量与随机流。稳定拓扑复用实际GPU网格；变化拓扑按真实活粒子前缀重建。四炮截图667个活粒子仍全部绘制，但炮火owner共52个系统/flash载体。甲板人物保持3D模型、骨骼和动画，未改为billboard。

真实齐射v8 (Temp/cannon-native-system-local-20261013-v8/live-observation.json) valid=true、失败0、4次发炮+4次实际落水，native推进与源文件冻结通过，无存档写入。严重退化原判据未改变；post10.93FPS仍不可称流畅。原生GPU系统批次32865断言通过；局部发炮99、game-clock249、两个场景呈现调度通过。

进一步实际CPU归因：world31.5ms中动态岸浪约14.1ms、云雾约13ms(其中cloud编译5.276ms、fog编译5.542ms)、投影海面约3ms；3Dcrew约1.5ms。森林材质仅0.138ms，故未采用其缓存候选。尾迹微探针确认每个顶点向同一terrain provider重复两次精确双精度XZ查询，保持每个网格顶点/水面采样的前提下正在减少重复terrain工作。

新增投影ray缓存的原生48断言、118676个实际Camera3D顶点全部精确相等；独立审查补充fixed size_2d_override/nonstretch resize边界，RED实际发现18.6m错误后已修复并GREEN。岸浪状态复用和云雾owner-local Float32采样通过完整现有source oracle；总体native效果与FPS须最终新版冻结后再次验证。

边界：本轮保留当前gameplay appTime及零出生锚，原报告60ms烟/32ms水花计数与完整clone/controller初值未全部接入；Godot全局透明排序和DX9像素逐位等价仍未证明。不得将本轮离线对照或四炮场景外推为十几船、上百炮性能验收。

## 当前最终测量与剩余瓶颈

左右舷v9均valid=true、failures=0、performanceRed=false；3船、35可见3D船员、1600×900 balanced/4×MSAA、正常反射、每轮4次实际发炮及4次实际落水。左舷post p95=111.571ms，右舷post p95=115.295ms；恢复平均15.10/15.48FPS。全程源码冻结、窗口有效、native时间正常推进、存档写入0。记录：Temp/cannon-native-final-port-20261013-v9/live-observation.json、Temp/cannon-native-final-starboard-20261013-v9/live-observation.json。

新的真实CPU归因Temp/scene-cpu-final-20261013-v2/live-observation.json也valid=true/failures=0。before/post：投影3.06→约1.34/1.32ms；岸浪14.11→约11.96/11.33ms；尾迹原11.44/15.67→9.72/12.60ms。云雾cloud仍5.41/5.34ms、fog仍5.20/5.10ms，scalar-buffer收益有限，不能宣称云雾热点已解决。post源特效finish/wait/upload仍约10.19ms；3D人物约1.54/2.14ms。父子inclusive成本不能重复相加；observer约0.13ms。

结论：按原版组织粒子与发炮结构已接入，严重齐射退化复现判据通过；整体自由试航约16FPS、开炮约12FPS，基础岸浪/云雾/尾迹和特效更新仍有实测成本，未达到30/60FPS，不能写“全部性能问题解决”。3D甲板人物保持原模型/骨骼/Jolt动画路径。

最终画面/启动：Temp/cannon-native-visual-final-20261013-v4的6张GPU截图与生命周期记录通过，Root已检查muzzle和rings。投影最新native54/0，138359个实际Camera3D顶点全精确相等；local fire及两个正式场景调度最终回归通过。实际main/router已重新打开自由试航(PID7892、startup.ok=true、1600×900、无脚本错误)，编辑器PID9236保留。真实活动游戏画面：Temp/cannon-structure-final-game-20261013.png及同名.json。
