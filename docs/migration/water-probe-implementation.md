# 原生海面模块实现与验证

本次仅实现 Godot 海面验证模块。完整迁移计划保持；船舶浮力、战斗、经营、存档和性能验收没有由本次 CPU 测试证明。实际 GPU 渲染、截图和视觉对照由验证场景另行记录。

## 来源及语义

参考网页工作树 HEAD `9ad6a44daecd4ec36a8172d83ff27493feffe5dd` 的 `packages/scene-engine/src/engine/water/ProjectedWaterShader.js`、`ProjectedWaterSurface.js`、`oceanWaves.js`，以及 `src/config/constants.js` 和 `engine/world/World.js`。参考模式是网页默认的 projected 海面。

`wave_field.gd` 保留五个世界坐标正弦波，振幅 `1, 1, 1, .25, .25`，波数向量 `(.02,.015), (.02,-.015), (.05,0), (.1,.11), (.1,-.11)`，时间系数 `.9, .1, -.6, 2.05, -.05`。这是原 vertex shader 的 sin(a)cos(b) 展开；没有调节波幅或水线。波相位用 GDScript 标量 double 计算，避免先存入默认单精度 Vector2 使长时间相位偏移。公共梯度和法线仍使用 Godot 的 Vector2/Vector3 精度。

Shader 使用相同五波公式。原三层 `waternormals.jpg` 滚动及 `1/.8/.3` 权重、固定向上偏移 `3.5`、Fresnel 三次幂、250 次幂高光及 `1.5` 倍强度、碎屑、峰顶噪声泡沫、100–1500m 水平距离雾、透明度公式均保留。原 shader 没有实际 planar 镜像反射，岸线泡沫逻辑被删除且 shore mask 为零；本实现不添加或宣称这些效果。

原输入颜色由实际 `THREE.Color.toArray()` 读取：

| 输入 | Three 已转 linear 的值 |
| --- | --- |
| `#008991` 深水 | `(0, 0.2501582847191642, 0.28314874041918053)` |
| `#00b6ad` 浅水 | `(0, 0.46778379610254284, 0.4178850708380236)` |
| `#ffffff` 泡沫 | `(1, 1, 1)` |

以上数值直接作为 Godot vec3 uniform，刻意不使用 `source_color`。片元保留原 `pow(color, 2.2)` 第二次转换；雾的 `(0.53, .81, .92)` 同样按原公式做 pow。纹理作为非颜色 sampler，重复采样并使用线性 mipmap 过滤。默认太阳输入是原 World 初始位置 `(300,150,100)`；网页后续会让太阳 X/Z 跟随 target，场景装配可写入 `sun_position` uniform 保留同样语义。

原生首次 GPU 场景由主任务在 D3D12/Forward+ 成功渲染并查看 9 张截图，发现比网页水色更蓝、更亮。输出链审计见 `physics-rendering-inventory.md` 第9.3节：网页 balanced/low 最终 RenderPass 直接写 screen，自定义水片元没有 tone/colorspace chunks；原 shader 数字没有被自动执行 linear→sRGB。首次 Godot ALBEDO 同数值则被输出编码，场景另用了 ACES，因而不等于原 balanced 画面。

新增显式 `direct_screen_output` uniform，默认 true。在全部原 RGB 和 alpha 数学完成后，仅把 final RGB 用标准分段 sRGB→linear 传递函数转换，再交给 Godot Forward+ 输出；调用场景须使用 `Environment.TONE_MAPPER_LINEAR`、不添加 glow，才能抵消 native 的 linear→sRGB 编码。转换为 `c/12.92`（`c < .04045`），否则 `((c+.055)/1.055)^2.4`，不提前 clamp 超过1的高光。设 false 保留首次 native-linear baseline；这不是 high/legacy 的完整 Three bloom/Copy pass 仿真。

该输出适配保留 original shader 的 raw RGB 语义，不改输入颜色、波、船高或片元中的 fog/foam。它只能抵消水片元的输出编码；透明混合仍在 Godot 的 linear framebuffer 中进行，原 direct-screen 水混合则用原输出数字。因此 background/terrain/船材质和 alpha 的完整 frame 仍需独立 GPU 对照，不能由此宣称完整像素一致；high/legacy 另有不同 pass 链，本次没有模拟它。第一次截图 baseline 应保留，转换后的同镜头证据由主任务单独记录。

## 稳定公共接口

```gdscript
# RefCounted; pure CPU, no scene, clock or game dependency.
sample(x: float, z: float, time: float) -> Dictionary
# {height: float, gradient: Vector2(dHeight/dX, dHeight/dZ), normal: Vector3}

# MeshInstance3D; preload projected_ocean.gd from the composing scene.
configure(camera: Camera3D, normal_texture: Texture2D,
          resolution: int = 80, max_distance: float = 3000.0) -> void
set_simulation_time(seconds: float) -> void
update_projection() -> void
```

`configure` 创建并投影网格。最低分段数 16，默认 80 对应 6561 个顶点、12800 个三角形。网格遍历保留原 JS clipY 从 -1 到 +1，使用 `screenY = (1 - v) * height` 转换为 Godot 从上向下的屏幕坐标。每顶点使用当前 Camera3D 的 `project_ray_normal`，与 world y=0 求交；无有效向前交点或方向近乎平行时使用原 fallback。正 max_distance 限制射线距离；非正或非有限参数是原无上限模式，其 horizon fallback 为 `250 * 10 = 2500m`。

CPU 投影先算世界坐标，再通过 `to_local` 写 mesh，因此 MeshInstance3D 自身有平移时仍保留世界海平面和世界波相位。Shader 开启 `world_vertex_coords`，基准网格 y=0；波位移在 vertex 阶段进行。`cull_disabled`、`depth_draw_never`、`blend_mix` 保留原 DoubleSide、depthWrite=false 和透明混合意图。海面不投影阴影，禁用自身遮挡剔除；波位移由额外 8m cull margin 覆盖。Godot 的 mesh 可见性由更新后的真实包围盒和该边距保障，原 Three 对该 mesh 完全禁用 frustum culling。

时间只从 `set_simulation_time` 接收，重配置保留最近有效值；NaN/Inf 不覆盖有效时间。模块没有 `_process`、墙钟或 shader `TIME`。调用方在镜头变化后显式 `update_projection`，在已消耗游戏时间变化时显式 `set_simulation_time`。ShaderMaterial 的可配置 uniform 为 `simulation_time`、`camera_position`、`normal_texture`、`sun_position`、`color_deep`、`color_shallow`、`color_foam`、`direct_screen_output`。场景引擎只依赖该 shader 和原生渲染类型，不引用 physics_engine 或 game；CPU 波场不引用 scene_engine 或 game。

## 直接测试证据

命令：

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_water_probe.gd
```

引擎实际输出 `Godot Engine v4.7.2.stable.official.ed1daf0bf`。先创建可加载的 RefCounted/MeshInstance3D stub，再运行测试。首次测试字符串使用 Godot 不支持的 `%.12g`，先改为 `%.12f` 后取得无运行时错误的行为 RED：exit 1，54 assertions，4 failures；波高 45/48 不符，梯度/法线各 48/48 不符，configure 未建立网格。这不是 missing file、解析或环境失败。

实现后 GREEN 使用原 JS 导出的 48 个 `tests/fixtures/original-ocean-reference.json` 样本，对照包括负坐标、远坐标及 0/24.7/80/600 秒。最大波高误差约 `1e-14`，梯度误差 `0`，法线误差 `1.1932565e-7`；阈值为波高 `1e-10`、向量 `1e-6`。另用中心差分独立核验梯度，实 Camera3D/SubViewport 验证中心交点、网格 Y 方向、世界坐标变换、相机移动、地平线 fallback、距离上限、最低/默认网格密度、纹理注入、显式时间更新、暂停跨帧不推进、无效时间保留和重配置时间保持。

末次 headless GREEN 输出 `WATER_PROBE_TESTS assertions=76 failures=0`，exit 0。Headless 测试证明 CPU 数值和 mesh/参数行为，不证明 GPU shader 编译、纹理导入后的实际颜色、透明排序、地平线画面或网页像素匹配。输出转换改动的 RED 来自主任务实际查看到的过亮 baseline；该 GPU 颜色回归必须通过同镜头 capture 验证，headless 数值通过不能冒充它已修好。当前投影每次重建 ArrayMesh surface；这是验证阶段的直接实现，持续游戏的性能预算和 GPU 更新优化待独立验收。
