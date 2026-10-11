# 海水光学与地形材质独立审核

日期：2026-10-11。范围为本轮 `projected_ocean.gd`、`original_water*.gdshader*`、`surface_optics*`、`terrain_chunk.gd`、`terrain_surface.gdshader`、`world_view.gd` 接线与新 focused 测试。实现只读；仅写本报告。未启动 GUI、完整 runner、性能测试；CodeGraph 本会话目标未索引，按主任务要求停止查询，全部源码读取使用 RTK fallback。

## 当前结论

本轮发现的 1 项 P2 已修复并独立复验；当前未发现未解决的 P1/P2。已审接线和数学合同未发现其他阻断项。GPU 编译、实际反射/折射图像及性能不在本审核的 headless 证据范围内。

### 已修 P2：相机 detach 后未切回安全 shader，并在 null viewport 上调用方法

修复前位置：`modules/scene_engine/ocean/projected_ocean.gd:163–166`。当时生命周期退路仅检查 `is_instance_valid(_camera)`，但 camera 仍是有效 Node、已经不在树内时，其 `get_viewport()` 返回 null。helper 的 diagnostics 已识别 camera 无效，projection 函数却继续读 viewport，且未刷新光学材质，造成日志错误与“诊断关闭、uniform仍开”的状态不一致。

修复前独立复现：正常配置 Ocean + Camera，`configure_reflection(camera)`、`enable_surface_optics()` 后执行 `root.remove_child(camera); ocean.update_projection()`。

```text
DETACHED_ENABLED=false
SCRIPT ERROR: Cannot call method 'get_visible_rect' on a null value.
at: update_projection (.../projected_ocean.gd:166)
FALLBACK=true
```

脚本：`C:/Users/dains/AppData/Local/Temp/reference_review_optics_detach.gd`。修复前进程 exit 0 不代表通过；以上 SCRIPT ERROR 是历史失败证据。

最新源码在 `update_projection()` 访问 viewport 前检查 camera 是否在树内，并验证 viewport；失效时同步关闭光学材质、清 projection 初始化缓存。相同 camera 重新挂载后，按保留的请求状态恢复光学 shader。已独立重跑正式 optics 测试（122 assertions / 0 failures）及上述脚本，并扩展脚本核对 detach/reattach 的实际 shader 资源，得到：

```text
DETACHED_ENABLED=false
FALLBACK=false
DETACHED_SHADER=res://modules/scene_engine/ocean/original_water.gdshader
REATTACHED_ENABLED=true
REATTACHED_UNIFORM=true
REATTACHED_SHADER=res://modules/scene_engine/ocean/original_water_optics.gdshader
```

最新独立复现 exit 0，无 SCRIPT ERROR；正式测试同时覆盖 accepted time 与既有 mesh 保持。因此本项关闭。

对照：free相机已通过独立复现：`enabled=true/uniform=true` 变为 `false/false`，shader回到 `original_water.gdshader`。重新configure到其他camera时清旧attachment也已在最新源码读到。

## 审核结论与证据范围

- Reverse-Z：Forward+/Mobile 的 raw depth 保持 `[0,1]`，Compatibility 分支映射至 `[-1,1]`，均通过实际 inverse projection 重建 view position；没有固定 near/far 假设。测试独立构造 reverse-Z 矩阵，覆盖3组aspect、3组near、3组far及3个深度位置。
- 反射使用 view-space reflect ray、projection回屏幕、scene depth重建和view-depth差检测；上限24步，low=0，balanced=16，high=24。出屏/近相机/无hit返回confidence0；水下scene geometry通过世界Y门槛排除，返回已有water颜色。透明对象和屏外对象不在opaque screen-copy里，diagnostics明确此限制，不能宣称完整平面镜反射。
- 折射使用同viewport opaque color/depth；偏移UV限制在有效屏幕区，若偏移命中前景则退回原SCREEN_UV。厚度按view-depth差计算并夹到非负，吸收指数最多80米，红光吸收快于蓝光。此处是有界艺术表现；未把当前headless数学测试当作真实GPU遮挡验收。
- 原海水shader拆为两个入口共享同一个body；optics关闭或style0使用无screen/depth采样入口。body保留相同五波vertex displacement、原normal纹理采样与accepted simulation_time。optics启用时不再二次alpha混合opaque背景；仍走透明水面渲染队列以避免screen-copy自反馈。
- Terrain使用不含ALPHA写入的opaque shader；world-space程序细节由原高度/坡度生成UV权重。新材质不改顶点、法线、索引、原色或实际碰撞网格。湿沙/焦散调用与海水相同的wave/coastal include。
- `sync_surface_state` 先校验finite time、wave count/components、shore bounds后再写；缓存按字段值比较，不仅按time。wave数组复制，Texture2D作为只读共享资源；同time改变wave/bounds仍更新，重配置清cache，dispose清mesh/material/body与cache。
- World在配置实际camera后启用style1 optics；near和distant terrain明确传detailed选项，tile创建即同步已有海水state；每次snapshot先设置accepted time、更新window，再同步所有terrain。暂停重复time不累积，rewind直接seek；新streamed tile得到当前time。style0保留原material与非screen shader。
- 未新增Timer、墙钟、第二camera、SubViewport反射世界或物理积分。共享opaque/depth buffer是屏幕空间方案，不能显示原screen-copy不包含的透明/屏外目标。

## 本审核实际执行

Godot `4.7.2.stable.official.ed1daf0bf`，直接 `--headless --path C:/Users/dains/Documents/Git/ming-armada --script ...`。

| focused 运行 | 当前结果 |
|---|---|
| `test_reference_surface_optics.gd` | 122 assertions / 0 failures |
| `test_reference_island_materials.gd` | 155 assertions / 0 failures |
| `test_reference_surface_integration.gd` | 32 assertions / 0 failures |
| `test_wave_uniforms.gd` | 8 assertions / 0 failures |
| `test_coastal_waves.gd` | 1090 assertions / 0 failures |
| 相机free独立复现 | uniform关闭、原shader退路成功 |
| 相机detach/reattach独立复现 | diagnostics、uniform、实际shader共同关闭并恢复，无Godot错误 |

上面五个仓库测试均exit0且无Godot错误；最新detach/reattach独立复现也无错误。主线程的GPU验收应记录实际光学开/关对照、reverse-Z遮挡边界、透明船体/海面排序；性能未在本审核测量。本报告不宣称这些GPU验收完成。

## 补充：scalar height 功能等价只读复审

按最新指令停止性能方向。本节仅审查已完成的 `WaveField.sample_height`、`CoastalWaveField.sample_height` 及 sailing、legacy、mingqi、naval_practice、visual_qa 五个 runtime 路由。未修改产品代码，未启动 Godot、GPU、完整 runner 或性能测量。

结论：未发现未解决的 P1/P2 功能问题。WaveField 新接口逐项使用相同 ORIGINAL_COMPONENTS 五波、相同 double scalar 相位表达式和累计顺序；完整 `sample()` 的 height/gradient/normal 实现未改。Coastal 新接口保留中心地形无效时回原波、depth>=8 原波、depth<=0 零高度及其间 `t*t*(3-2*t)` 衰减，完整 `sample()` 的四个邻点梯度探测及法线计算仍保留。`ocean_adapter.gd:10` 仍调用完整 `sample(..., accepted_time)`，船体物理梯度路径未切为仅高度接口。

五个 runtime 仅把 `.sample(...).height` 替换为 `.sample_height(...)`；参数签名、显式 seconds 转发、缺少 wave 实例时的原返回值保持原样。Legacy 的默认 `seconds=NAN` 仍取 simulation snapshot time，无 simulation 时仍取0；其他四个接口仍要求显式 seconds。新采样函数无时钟、累计器或状态写入，暂停、重复时间和 rewind 仍由原 accepted time 决定。

独立逐项核对 `tests/test_wave_height_fast_path.gd`，并读取 fixture 数量，确认成功路径确实包含 **17,845 assertions**：48条冻结原始海面 fixture 各2项=96；9种地形高度×164组坐标×6个时间×2项=17,712；其余37项覆盖方法存在、地形配置、中心/完整采样调用数、非finite地形、失效Callable、完整结果不被采样改写及五 runtime 各3项路由断言。坐标包含10亿级值与极小值，时间包含负值、零、微步和百万级值；8米边界与近零浅水、陆地均覆盖。

证据边界：本补充为源码与测试覆盖独立审核，没有重新执行该测试，不把17,845当作本审核新增运行成绩。新测试的五 runtime 检查使用 probe，覆盖显式8.25秒路由；未直接执行 Legacy 默认时间、真实暂停/rewind 或倾斜海床梯度。默认时间与暂停结论来自变更前后表达式及无状态源码比对；完整倾斜海床 gradient/normal 的既有 `test_coastal_waves.gd:21–28` 在本报告此前运行中已覆盖，新改动没有修改该计算路径。
