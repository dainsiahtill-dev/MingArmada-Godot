# 参考水花与现有效果融合

2026-10-11：正式炮弹落水路径已增加可运行的参考水花层，现有强柱体、伞形水壳、24 颗弹道水滴、随波主涟漪和沉船表面泡沫保留。水花不是另建的独立演示，真实 `Encounter` 炮弹水面碰撞产生的 `splash` 事件经原 `CombatEffects` API 创建此层。

## 源证据与资源

入口是 `C:/Games/Pirates-REA-Reference-20261011/naval-study/deep/demo/webgl.mjs` 的 `splashScene`、`naval-study/selected-geometry.json`，以及 `deep/asset-details/DETAIL.md`、`complete-assets.json`、`particle-systems.json`。

源资产 `cannon_ball_splash.nif` 的 SHA256 为 `6190bd0d9e7c82f3e92c842ee81ff77c632f60250fa3c0b110c482ed01d8db76`。新增 [reference_cannon_splash.json](../../assets/data/reference_cannon_splash.json) 包含：

- 2 个真实 `Cylinder01/02` 网格，各 78 顶点、126 三角；5 张真实水平水环，各 4 顶点、2 三角。合计 **176 顶点、262 三角**，保留原局部坐标、三角、UV 和 mesh-local 变换。
- 5 层水环的原始线性平移、旋转、缩放键与两组 alpha 控制器；两个柱体各自的 alpha 和 V translation 控制器。
- 8 套粒子系统的 emitter、gravity、grow、颜色、启用窗口、birth rate、父级转换及 modifier 顺序证据。原始容量为 **[15, 4, 16, 12, 8, 20, 4, 3]，合计 82 槽**。

实际绑定的是已经导入的 `fx_water_splash_004.dds.png`、`fx_water_splash_rings_01.dds.png`、`fx_streakin_001.dds.png` 与 `fx_mist_01.dds.png` 四张原预览贴图；导入器逐张验证本项目 PNG 与参考树中对应 PNG 的散列相同。原来的水花补充贴图、泡沫和尾迹贴图仍使用各自的现有路径。

生成器是 [import-reference-splash.py](../../tools/import-reference-splash.py)，仅写本项目，不修改参考树；[reference-cannon-splash.json](../../assets/provenance/reference-cannon-splash.json) 记录输入、源 NIF、输出数据与四张贴图散列。

## 正式接线

[water_splashes.gd](../../game/presentation/water/water_splashes.gd) 为普通炮弹和船员入水事件创建 `ReferenceSplash` 子层，按同一个已接受的 `now - event.time` 更新。`surface_only` 沉船事件只使用原随波表面泡沫，不会额外发射炮弹水柱或喷雾。

[reference_splash.gd](../../game/presentation/water/reference_splash.gd) 重建七个真实网格并创建八个独立 `MultiMesh` 槽池。水环按原 TRS/alpha 曲线求值，四个角的高度使用当前已接受水面相位；柱体使用原局部形状及原 alpha/V 曲线。源飞沫和喷雾按事件绝对年龄解析求值，不使用 Timer、粒子 process、shader TIME 或逐帧 Euler 积分。迟到事件、暂停和回退仍由原拥有者管理；整个层随原水花对象释放。

海域 callable 从 `WaterSplashes.configure_surface_filter` 传给已经活跃的源层；下一个接受相位中，源网格与源颗粒同步剔除落到陆地的部分。子层的顶点仍是世界坐标，外层原 `top_level` 合同使移动调用者不改变落水点。

[reference_splash.gdshader](../../game/presentation/water/reference_splash.gdshader) 读取原 alpha 遮罩；喷雾使用带周边羽化的椭圆载体，飞沫使用交叉细条，不引入白色矩形载体。已有 `pirates_foam` 和 `splash_volume` shader 均未改动。

## 保留好效果与游戏适配

原柱体 alpha 峰值仅约 **0.0250185 / 0.0436260**。直接替换现有清晰柱体会削弱炮弹反馈，因此采用叠层融合：原强反馈不动，新增真实几何与分层细节。源柱 alpha 使用明确的 18 倍可读性增益，源环为 0.35，新增颗粒为 0.40。原 controller 的相对时序、曲线和独立 alpha 值仍完整求值，不把两柱合成同一条曲线。

源 NIF 单位没有被证明为米。这里选择 **0.01 米 / 源单位** 的展示转换，Z-up 映射为 Godot `(x, z, -y)`；原 emitter speed、radius 和 gravity 随此转换，新层重力约 9.891 米/秒²，原层的 9.81 米/秒²保留。事件 scale 缩放形状及颗粒半径，速度使用其平方根，以保持大小与喷溅高度关系。

原随机分布、分配取整和原粒子 draw 展开没有被恢复。当前明确使用稳定种子的均匀速度/角度 variation、半开启用窗口的即时首槽及 `1/rate` 出生网格，受原容量限制；未猜测 `life_span_variation` 分布，使用原基础寿命和颜色尾部。Spawn modifier 的原参数/顺序属于证据，未知的粒子后代生成机制没有被伪装为已经还原。该模块是可运行的游戏融合实现，并非逐指令等价的原引擎恢复。

## 新鲜验证

两个 RED 都已实际观察：缺失源层时 2 assertions / 1 failure；新增层尚未跟随热替换海域 callable 时 71 assertions / 2 failures。对应生产改动后，最新五个 headless 进程均退出 0，无 SCRIPT ERROR、ERROR、Parse Error 或 Compile Error：

| 测试 | 结果 |
| --- | --- |
| `test_reference_splash_fusion.gd` | 71 assertions，0 failures |
| `test_pirates_water_effects.gd` | 127 assertions，0 failures |
| `test_reference_water_volume.gd` | 133 assertions，0 failures |
| `test_reference_event_time.gd` | 31 assertions，0 failures |
| `test_reference_presentation_integration.gd` | 7 assertions，0 failures |

合计 **369 assertions，0 failures**。新增测试直接执行正式 `Encounter.command(fire)` 和每个物理 tick，观察真实炮弹水碰撞，证实其事件到达新层；另外核对独立源 alpha 峰值、V 位移、不同环的启用时间、真实池容量、共享波面、暂停、迟到、动态海域过滤、回退、寿命和旧体积保留。源数据对照还逐项确认七个原导出网格的坐标、三角、UV 和局部变换未改写。

日志为 [local-verification.json](evidence/reference-splash-fusion/local-verification.json)。本轮按任务边界未开 GPU 窗口，真实喷溅的透明排序、镜像中呈现和画面可读性由主 Agent 在统一海战中截图验收；全量项目回归同样交给主 Agent 的冻结批次。这些 headless 结果没有被称为 GPU 画面已经验收。Windows 导出须继续包含 `assets/data/reference_cannon_splash.json`（当前 JSON include filter 应覆盖它），并核对新脚本与 shader 的打包依赖。
