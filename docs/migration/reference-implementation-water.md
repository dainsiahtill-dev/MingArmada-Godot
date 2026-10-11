# 立体落水与船浪实现

2026-10-11，目标 `C:/Users/dains/Documents/Git/ming-armada`。原网页 `MingArmada` 和 `C:/Games/Pirates-REA-Reference-20261011` 只读；无 stage、commit、push，无 GUI 或浏览器运行。完整产品路径集成、GPU 截图和整套验证由主线程统一完成。

## 改动与用途

- `game/presentation/water/water_splashes.gd`：保持原 `configure`、`apply_snapshot(float)`、`add_event`、`diagnostics`、`dispose` API；按真实 event.time 和 event.position 生成独立水环、全方位实体水柱、伞状壳、世界空间飞滴、弱雾。独立 presenter 也按 event.id 去重；暂停冻结，倒退清理，过期事件不复播。保留旧第二子节点 `WaterSpray` 作为隐藏的旧遮罩兼容节点，默认可见雾节点 `WeakMist` 使用本轮确认的原 mist 依赖。
- `game/presentation/water/splash_volume.gd`：解析式体积/径向泡沫几何和解析式飞滴轨迹。飞滴是沿当前速度方向朝向的交叉薄 strip，位置在世界空间；不使用相机朝向决定轨迹。不调用 `_process`、Timer、粒子模拟时钟或积分器。
- `game/presentation/water/splash_volume.gdshader`：按原纹理 alpha 渲染体积和飞滴，保留深度测试；RGB 接近常量的白底不作遮罩。明确调节 alpha 响应，未改原 PNG 字节。
- `game/presentation/water/wake_trails.gd`：保持原 `apply_snapshot(Dictionary)` API 和历史五横截面网格。默认历史遮罩改为原 `wake3unique`。记录真实向前速度变化和船向角速度，历史尾迹保留局部加速度浪涌、转弯扩大及年龄渐隐；仍按观测船尾连线、断段、端点/边缘渐隐，倒车和纯侧滑不发新尾迹。
- `game/presentation/water/ship_wave_geometry.gd`：独立船首弧形浪和两侧泡沫网格，强度由真实向前速度、正向加速度、转弯决定。转弯使两侧强度不同，停止/倒车立即停止附着浪，旧历史继续渐隐。每个顶点采样同一 accepted time 的注入波高，最多附加 0.20m 表现性浪峰。
- `tests/test_reference_water_volume.gd`：直接验证实际几何、世界坐标、有限预算、时间、边界、来源依赖、水手比例及沉船表面模式。
- 新增四张 PNG 及对应 `.import`：只复制明确使用的四张已解码原资源，保留源 PNG 字节，mipmap/alpha import 沿既有模板。没有加载整套 96 张候选。

## API 与集成

两个 presenter 均增加可选 `configure_surface_filter(sea_at: Callable)`。Callable 接收 `(world_x, world_z)`，返回该处是否允许水效。主线程可以注入 `terrain(x,z) < 0`。未配置时保留旧行为。水柱起点在陆地时拒绝；水环、柱壳、侧浪、船首和历史网格删除有陆地顶点的三角形；飞滴到达陆地后从可见池隐藏。`configure`/`dispose` 会清理该回调，集成方应先 configure 水高，再 configure_surface_filter。

`add_event` 可选 `scale`，默认 1，有限数限制在 0.2–2；水手可用 0.45。几何、喷射速度/寿命和雾尺寸随比例变化，飞滴重力仍为 9.81m/s²。可选 `surface_only: true` 用于已经结算的沉船泡沫事件：只保留扩散环和径向 `SurfaceFroth`；水柱、伞壳、飞滴、旧 spray 和弱雾均隐藏。主线程沉船建议 `scale: 1.8, surface_only: true`，普通炮弹默认 1。此层不会再结算命中、船壳损伤或船员减员。

`diagnostics` 保留旧字段，新增 splash `droplets`、`droplet_capacity` 和 `droplet_positions`；新增 wake `attached_waves` 和 `wave_budget`。`droplet_positions` 是每次提交给 MultiMesh 的同一 CPU 世界坐标清单，适用于 headless dummy renderer 无法读回实际 GPU instance transform 时的诊断；不是另一个运动状态。

时间只来自 `apply_snapshot` 的 accepted time。飞滴以 event.time 推导 birth 和 age，迟到事件重建相同轨迹；同相位请求不读新船位、不更新几何。倒退立即释放原节点、样本与去重表；新场景 configure/dispose 均可重复调用。无新增模拟时钟或物理积分。

预算：最多 32 个落水事件，每个 24 个飞滴槽，最多 768 槽；体积段 32×8，0.95s 后体积隐藏，整个落水事件 2.8s 后释放。最多 32 条历史尾迹，各 64 样本、6.5s 寿命，每船三个附着浪网格，共最多 96 个附着浪。近/远镜头均守同一硬预算；本任务没有另设远景模拟或事件来源。GPU 成本及远景可读性待主线程真实镜头验收。

## 原证据与本作选择

读取本轮新增的 `naval-study/deep/README.md`、`deep/asset-details/DETAIL.md`、过滤后的 `particle-systems.json`、`sample-input.json` 和 `selected-geometry.json`；没有把旧报告当作可直接移植的数值。

原 `cannon_ball_splash.nif` 有 `Cylinder01` 和 `Cylinder02`，各 78 顶点、126 三角形，及五个水平水环平面；首套粒子 world_space=true，15 槽，原始 speed≈444.37、gravity≈989.10、life≈0.5（variation≈0.8），发射窗约 0.0333–0.1s。原水环 scale/alpha 由独立控制器驱动；alpha 结束与完整 prefab stop_time 不等同。本作保留分层结构与短爆发，但自行选择最大约 4m 的柱、0.95s 体积衰减、24 槽 deterministic 飞滴、5.1–6.75m/s 上抛、1.7–3.02m/s 水平散射及 9.81m/s² 重力。这是本作米秒尺度的表现设计，不声明恢复原引擎粒子随机分布。

原 bowfroth 四套系统各 10 槽、world_space=true、speed≈153.50、life=0.625；原侧泡沫有真实网格且无粒子。本作按当前船长/宽建立小型弧形/侧面波峰，按 accepted 快照差值选强度，不复制原始发射速度或 25s 控制器关闭键。原 `selected-geometry.json` 的 sidefroth 导出 150 顶点、214 个三角形，而 DETAIL 表述 284；本任务未导入其索引，未把两者说成一致，也未以报告文字覆盖直接读取的 JSON。

### 来源摘要（供统一 provenance）

以下路径均相对 `C:/Games/Pirates-REA-Reference-20261011`：

| 来源 | SHA256 |
|---|---|
| `naval-study/deep/README.md` | `a85e22b00a7b5a2358d78261186c9b09d8cc51ac62e1928e2f6e18d8728ba07b` |
| `naval-study/deep/asset-details/DETAIL.md` | `70484c5c2beac3707221f5b60b95a98e278a5dfb93bb7aa3b10a28707ad89c58` |
| `naval-study/deep/asset-details/particle-systems.json` | `94b8fbf2d7ffd6561ed718b9432d974c8fb59e8dd34842a5ac51e470fd3ad4ba` |
| `naval-study/deep/asset-details/sample-input.json` | `4609061753ec30f695d7471ea31067af3959bf18cf669b8fb324d69161aad5d6` |
| `naval-study/selected-geometry.json` | `948b6057dbccb4c48f820f6d1648bb18a1061aca9e8d54a24e6a8df9a47feef4` |
| `raw/fpk/Pak6/cannon_ball_splash.nif` | `6190bd0d9e7c82f3e92c842ee81ff77c632f60250fa3c0b110c482ed01d8db76` |
| `raw/fpk/Pak1/fx_ship_bowfroth.nif` (particle JSON 来源标记) | `372314be98c71f8a536c85a23cffea23c880dce3165d0af8fa92634ba7a63a4f` |
| `raw/fpk/Pak7/fx_ship_sidefroth_sloop.nif` | `5ac8174bdc711c24c28b12de68f0c9c9675c4c5f0b10296716436b65b4a551a1` |

新增目标全部在 `assets/textures/pirates_reference/`；源 PNG 位于 `preview/images/fpk/<Pak>/<filename>.png`，源 DDS 位于 `raw/fpk/<Pak>/<filename>`。以下原 DDS 与源/目标 PNG hash 分别计算，复制前确认目标不存在，复制后字节相同。

| 用途 / Pak / 文件 | 原 DDS SHA256 | 原 PNG = 目标 PNG SHA256 |
|---|---|---|
| 柱/伞壳 / Pak6 / `fx_water_splash_004.dds` | `36c2cc0dabc3d7a6f5677226e1915087ce0901f9b8925efe876972fe3c29505e` | `573c902a6eb16daaa7d90d6b2077c3590c3ed12df0bc75c36ac5bc67adfdb25d` |
| 空间飞滴 / Pak1 / `fx_streakin_001.dds` | `bdc9931efb752334bc77cbaf6dac588621afd5a5f10021717b4d94616202b580` | `661e4ebdd9085a4c3216e478f1b7a0be32dbe943303bc27ed5b1d47c0f93a067` |
| 弱雾 / Pak5 / `fx_mist_01.dds` | `97a62745f1dc05e6a2331a0a1b420d7da6d0cd05182b82d5cda794720789f98d` | `84e853537ebd6e4f7188f5131a0ba09e36f8c1aab09babbec1ef085b54b29089` |
| 历史尾迹 / Pak4 / `wake3unique.dds` | `255d1020d8a74e1a3390b47ae805da72bfb9d3f26496032fda3d658759c9a6ae` | `77f467af2ea61bd0fa07bf22cf8e956334b63f6edeb5347bedb1c145ae314ad5` |

这四张 RGBA 图片 RGB 基本为常量；实际 alpha 范围分别 0–127、0–219、0–206、0–187。shader 使用 alpha，未把 RGB 白底提取成不透明方块。既有 ripple mask、froth、旧 splash 遮罩及原 import 文件未覆写。

## RED / GREEN 与局部验证

先运行新测试：有效 RED `assertions=91 failures=5`，失败分别为独立 splash 身份去重、实体柱/伞壳、世界飞滴、海域过滤入口、船首/双侧浪缺失。随后几何/时序 GREEN。

追加独立有效 RED：历史加速度保持 `107/1`；水手小比例 `108/1`；父节点位移下的世界空间 `109/1`；沉船仅表面模式 `111/2`；四张真实默认依赖 `128/4`。每次均先看到行为失败，再改生产实现。中间发现 dummy headless MultiMesh 无法真实回读 GPU transform，因此改为检查实际提交的 CPU 位置；来源测试首次遇到旧 StandardMaterial 缺 shader API，先修测试类型判断，再得到有效 RED，没有将解析错误作为 RED 证据。

最终直接执行（Godot `4.7.2.stable.official.ed1daf0bf`，headless）：

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --editor --import --path C:/Users/dains/Documents/Git/ming-armada --quit
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_reference_water_volume.gd
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_pirates_water_effects.gd
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_naval_world_view.gd
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_world_lifecycle.gd
```

- import：exit 0；四张纹理导入完成，Godot 自动注册新 `.uid`。扫描也导入了工作树内已有未导入截图；未更改其原 PNG。
- 新水体积测试：`REFERENCE_WATER_VOLUME_TESTS assertions=128 failures=0`，exit 0。
- 旧水效回归：`PIRATES_WATER_EFFECT_TESTS assertions=127 failures=0`，exit 0。
- 海战世界视图：`NAVAL_WORLD_VIEW_TESTS assertions=20 failures=0`，exit 0。
- 场景生命周期：`WORLD_LIFECYCLE_TESTS assertions=1710 failures=0`，exit 0。

上述最终运行没有 Godot SCRIPT ERROR、ERROR 或 WARNING。未运行会改共享验证证据的 `verify-godot.mjs`。整套测试由主线程负责，不将局部通过写成项目全套已通过。

## 剩余验收边界

headless 已证实体网格深度、事件/时间/比例/预算/清理/采波高、迟到事件的帧分割无关轨迹、9.81m/s² 重力、暂停和回退、实际源依赖、陆地顶点排除、真实向前速度/加速度/转弯船浪。没有执行真实 GPU 相机旋转、近/远镜头、多齐射、沉船及水手入水截图；透明重叠、材质可读性、体积形状和真实 GPU 性能仍由主线程统一验收。

陆地裁剪是注入 terrain 回调下的有限网格采样；三角形顶点都在海上不构成任意窄地形边界的数学精确证明。需要真实近岸镜头检查，必要时按现有海岸几何/纹理场进一步裁剪，不能用 headless 顶点断言替代画面验收。原粒子随机分布、原 prefab 回收策略和原世界单位仍未恢复；本作的几何、时序、比例与池调度均明确为本作设计。

## GPU 反馈后：显式挂点合同与船首圆弧

主线程首次 GPU 图指出船首泡沫形状是尖 V，初步怀疑整体前移来自重复挂点偏移。追实际调用合同后确认：`wake_trails` 的历史 `pose.position` 是 `ship.visual.position - forward*0.51L`，helper 原来的 `+0.51L` 只是还原船中心，之后的 local along 才是船首/舰侧挂点。因此，原公开快照路径没有所怀疑的 double-offset；直接删偏移会把全部附着浪移后半船。此次未进行这种位置修正。

现在 `ShipWave.build` 明确以船中心 `pose.position` 为合同；`wake_trails` 在单一调用边界将历史船尾 pose 复制并转换为船中心，保留所有原历史坐标。这样每一层的坐标含义可直接检查，实际附着位置保持正确。

船首沿轴曲线由 `abs(2t-1)` 的两段直线改为平滑 quadratic `(2t-1)^2`，中央峰仍为船中心前方 `0.51L`，两端位置及 tip alpha 渐隐保持。侧面泡沫沿轴范围保持 `[-0.48L,+0.40L]`。

新增五个真实几何断言：船中心 helper 的 bow apex、非零连续弧线曲率、两侧的轴向范围、旋转船向下从公开 ship snapshot 到实际网格 apex 的完整路径。测试先有效 RED `REFERENCE_WATER_VOLUME_TESTS assertions=133 failures=4`；其中公开快照路径位置在修改前已经通过，明确区分合同可读性改善和实际 V 形曲线缺陷。

修改后直接 headless 重跑：`REFERENCE_WATER_VOLUME_TESTS assertions=133 failures=0`、`PIRATES_WATER_EFFECT_TESTS assertions=127 failures=0`，均 exit 0、无 Godot 错误/警告。只修改 `ship_wave_geometry.gd`、本任务的 `wake_trails.gd` 调用边界、新测试和本报告。主线程负责重新截图核验圆弧贴合与视觉效果。
