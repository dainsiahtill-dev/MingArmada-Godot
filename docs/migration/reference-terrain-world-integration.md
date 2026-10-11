# 正式海岛材质接入与局部验收

2026-10-11：`TerrainChunk` 已具备正式世界的参考海岛材质接口；本轮核查保留现有生产实现，补充网格查询回归并冻结源码。它直接服务于正式世界的地形分块，原来的 Cat Island 独立学习场景仍保持独立入口。

## 源实现与迁移范围

参考实现是 `C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/demo/shaders.mjs` 中的 `terrainVS`、`terrainFS` 与 `common`。这是参考项目中新编写的学习实现，而非原游戏完整开发者源码。

`modules/scene_engine/terrain/terrain_surface.gdshader` 保留源 `terrainFS` 的世界坐标噪声、湿沙/沙地/草地/岩石色值、海拔及坡度混合、日光方向、浅滩焦散公式和距离雾。`reference_terrain_common.gdshaderinc` 复用源天空和噪声表达式。Godot 适配有两项明确差异：

- 源 RGBA8 目标对 display RGB 写入的范围限制通过 `clamp` 表达，再转为 Godot 线性输出；没有添加二次 8 位量化。
- 源反射绘制的 `uClip` 开关改为按每次绘制的 `CAMERA_POSITION_WORLD` 判断镜像相机，只有水面以下的镜像相机才裁去海平面以下的地形。主相机保留浅海底用于折射和焦散，雾方向同样使用各次绘制的实际相机位置。

运行相机须保持在海面以上；地形分块须保持水平、仅做平移。这符合正式世界的当前用法。任意旋转/缩放的地形高度反查不在此接口范围内。

## 保留的几何与接口

`configure(sampler, coordinate, size, resolution, collision, options)` 继续接受原有注入高度函数；详细材质不会改变顶点、法线、索引、顶点颜色、UV 权重或碰撞形状。未开启 `detailed` 时仍使用原顶点色 StandardMaterial3D。港口、植被及场景装饰仍可使用原高度采样接口。

新增的 `sample_mesh_height(world_x, world_z)` 读取实际 `PackedVector3Array` 中的 Float32 顶点高度缓存，按网格真实的 `[a,b,c] / [c,b,d]` 对角线作三角形插值，避免把非平面四角做双线性插值。查询包括当前父节点平移和世界高度；四条边为闭合边界。未配置、越界、输入非有限值或处置后返回 `NAN`。重新配置会替换顶点缓存、尺寸、分辨率和查询范围。

这为 WorldView 的近岸 RF 高度场提供真实几何高度；RF 的生成、绑定、边界覆盖和海水 shader 的读取仍属于 WorldView/Ocean 集成，不能由本文件的局部测试宣称已经完成。

## 统一材质状态

`sync_surface_state(ocean_material, state = {}) -> bool` 保留原单参数调用，并支持可选的已接受状态：`time`、`tide`、`preset`、`sun`、`sunColor`、`caustics`。校验完成后才更新材质，无效输入不污染最后接受的状态。

正式五波接口 `simulation_time`、`wave_components`、`wave_count`、`shore_height_texture`、`shore_bounds`、`has_shore_field`、`coastal_attenuation` 继续兼容；若读取独立学习场景的 `u_waves/u_speeds/u_strength` 四波合同，可转换为旧波分量 metadata。这里的转换不接管正式游戏波浪、浮力或船体位姿。

源材质 `u_time/u_tide/u_sun/u_sun_color/u_caustics` 与旧别名保持一致。太阳/潮位来自共享状态，shader 没有 `TIME` 时钟；同一时刻可重复应用或回退。单块配置的 `caustics=false` 是本地效果限制，全球开关不会将其强行启用。每块材质独立，状态不会保留外部海水材质或节点引用。

## 新鲜局部验证

命令以 RTK 启动 Godot 4.7.2 headless；三个进程均退出 0，日志无 SCRIPT ERROR、ERROR、Parse Error 或 Compile Error。完整日志保存在 [local-verification.json](evidence/reference-game-terrain/local-verification.json)。

| 测试 | 结果 | 直接覆盖 |
| --- | --- | --- |
| `tests/test_reference_game_terrain.gd` | 114 assertions，0 failures | 源状态合同、日光/潮位/焦散、原子拒绝、暂停/回退、Float32 结点、父节点再次移动、四角闭合边界、16 个非平面网格格子的上下三角及对角线、重新配置、处置 |
| `tests/test_reference_island_materials.gd` | 155 assertions，0 failures | 原 configure 兼容、顶点/法线/索引/颜色一致、UV 权重、真实海水旧接口、共享资源、配置变化、材质处置与重建 |
| `tests/test_scene_geometry.gd` | 32 triangles，0 failures | 地形正面绕序与 Godot 原生平面一致 |

GPU 画面的镜像裁剪、岸线贴合、湿沙和焦散，以及正式航海/海战中船与岛的整体观感，仍须由主 Agent 在统一场景中截图验收。本轮没有启动 GPU 窗口，未声称 headless 测试等价于真实视觉验收，也没有进行性能优化或 Git 操作。
