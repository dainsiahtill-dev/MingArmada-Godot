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

当前仍在验收最后的海陆查询重复工作，以上过程数据不能当作完成证明。原始卡顿窗口推进的 native 时间很少，后续优化能实际执行更多落水事件；不得将不同 payload 的整段 FPS 差额全部归给某一项修改。

## 状态与图形验证

- native API 的完整容量、原 CRT、世界变换及 bounds 对照；保留公开 `seek`、`meshes`、snapshot 的默认独立所有权。
- 新生 effect 保留唯一 age 0 visibility 锚；同年龄暂停、相机和海面重投影不再次执行 native modifier/bounds 更新。
- 真实 GPU 对照旧 renderer：8026 断言通过，2701 个稳定载体、148 次拓扑变化；完整解码 surface arrays、材质、有效 AABB 和排序一致。
- 当前 native work 完整 factory、seed/池隔离、lazy observer、公开深拷贝与内部借用回归 420 断言通过。
- 暂停后相机旋转通过真实 WaterSplashes owner 更新水花 billboard，generic 水花状态保持冻结。

主要原始测量与分段回执在 `Temp/cannon-native-*-20261013-*`、`Temp/cannon-actual-water-cpu-baseline-20261013-v1.json`。新 regression tests 位于 `tests/test_fidelity_fx_*work.gd`、`test_fidelity_fx_fork_cache.gd`、`test_fidelity_fx_mesh_reuse.gd`、`test_game_effect_clock.gd`。

## 最终验收

待最后修改冻结后，记录真实左右舷开炮测量、原生图形对照、实际炮烟/落水截图、相关回归和正式游戏重新打开的结果。整体自由试航原本约 14–15 FPS，不能仅因本轮开炮尖峰下降而宣称已经达到 30/60 FPS。
