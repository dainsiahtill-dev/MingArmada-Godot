# island-water 海水源码的 Godot 移植

2026-10-11。仅移植独立 Godot 海岛/海水预览，不改变现有游戏 runtime、旧五波海面或浮力选择，不开始粒子和性能工作。

## 来源与范围

源文件位于只读目录 `C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/demo/`。它们是已经运行的学习实现，不能称为恢复出的原游戏完整源码。当前 Godot 海水直接移植这些文件中的数学和着色表达式，未使用此前的 SSR 近似代替平面反射。

| 源实现 | Godot 文件 |
| --- | --- |
| `model.mjs` 的 `WAVES/Q/waveVisibility/waveAt` | `modules/physics_engine/ocean/reference_gerstner_wave_field.gd` |
| `model.mjs` 的 `oceanMesh/spread/footprint` | `modules/scene_engine/reference_island_water/ocean_model.gd` |
| `shaders.mjs` 的 `common/skyFS` | `source_common.gdshaderinc`、`reference_sky.gdshader` |
| `shaders.mjs` 的 `waveCode/heightCode/waterVS/waterFS` | `reference_water.gdshader` |
| `renderer.mjs` 的镜像场景及水面绘制 | `ocean_renderer.gd` |
| `app.mjs` 的 state/accepted time | 由主预览场景传入；海水模块不自建时钟 |

四组波的方向、振幅 `.32/.18/.14/.09`、波长 `18/11/7/4.2`、速度 `1.4/1.8/2.2/2.8` 与水平陡度 `.42` 保留。海面分辨率默认 192，37,249 顶点，覆盖 `[-1000,1000]` 的原渐疏网格；网格输入和 footprint 保留源 Float32 存储边界。

微纹、波浪/细节 footprint 滤波、浅深颜色、RGB 吸收 `.19/.075/.035`、Fresnel `.02/.98`、高光指数 `110`、岸线泡沫及雾均使用原表达式和系数。海岸高度使用地形实际绘制顶点的 RF 纹理，按源 `a,c,b / b,c,d` 对角线插值。

## 对外接口

`ocean_renderer.gd` 是 `Node3D`。添加至主预览场景后调用：

```gdscript
var field = ReferenceIslandModel.load_field()
field.terrainResolution = 160
field.heightTexture = ReferenceIslandModel.height_texture(field, 160)
ocean.configure(field, camera, state)
ocean.render(state, camera, accepted_seconds)
var sky_material = ocean.get_sky_material()
```

`field` 复用源 `width/height/values/extent/heightScale/seaIndex`。`heightTexture` 可注入共享地形纹理；省略时调用岛屿模块的同名构造函数。额外 `oceanResolution` 默认 192，合法范围为 1..254。

`state` 复用 `preset/strength/tide/foamWidth/waves/reflection/foam/caustics`。默认晴天、强度 1、潮位 0、泡沫宽度 1.5。预设对应的强度由主 UI 按源 `app.mjs` 更新，海水模块不会隐式改写用户传入的强度。非有限时间或状态拒绝更新，不污染上一帧 accepted state。

还提供 `get_water_material()`、`get_reflection_viewport()`、`get_reflection_camera()`、`reflection_uv(world_point)`、`diagnostics()` 和 `dispose()`。主场景把 `get_sky_material()` 赋给 `Sky.sky_material`，使用 Linear tone mapping、曝光 1；主相机保持水上。

## 真实平面反射

创建一个 `SubViewport` 和一个镜像 `Camera3D`，绑定主相机同一个 `World3D`，不复制海岛或创建第二套物理世界。镜像 eye、target 和 up 按源 `reflectCamera()` 关于当前潮位平面映射。透视参数复制主相机，默认独立预览为源 45°、near .3、far 1200。

反射纹理宽为 `min(768, main_viewport_width)`，高度按实际整数目标保持相机比例，与源 `renderer.mjs` 一致。海面只占 layer 20，镜像 camera cull mask 排除此位；水面不会进入自己的反射纹理。主相机须包含 layer 20。关闭 reflection 会真正停止 SubViewport 更新；反复渲染和暂停复用同一对镜像节点。

共享地形材质使用镜像 camera 的水下高度识别反射 pass，再按源 `worldY < tide-.02` 丢弃水下片元。这与源片元裁剪做法一致，不声称采用斜投影裁剪。独立预览只包含已接入该合同的岛屿/海底；后续加入船只和建筑时，各自材质也必须支持该裁剪合同。

## 引擎适配边界

- 原 WebGL 固定 `.3/1200` 深度公式替换为 Godot 当前 viewport 的 `INV_PROJECTION_MATRIX` 还原。Forward+/Mobile 使用 reverse-Z `[0,1]`；Compatibility 使用相应 NDC 范围。只读取当前主 viewport 的深度，没有跨 SubViewport 读取深度。依据 [Godot 官方深度说明](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html)。
- Godot viewport UV 的 Y 轴向下，反射投影 UV 与原纹理扰动进行同一 Y 翻转。CPU 测试已与镜像 `Camera3D.unproject_position()` 对照。
- 源 RGBA8 目标在显示 RGB 范围中渲染，Godot 3D 使用 HDR 线性光颜色。源结果先限制到 `[0,1]` 再转换至线性；水面读取场景/反射时，先分别把四个 texel 转回源显示 RGB，再按原 LINEAR 权重插值，以保留源色值过滤语义。没有把连续过滤结果 round 成八位数值。Godot HDR 与原 RGBA8 的存储精度仍不同。
- 原独立场景先绘制正常场景颜色/深度，再绘制水面；Godot 使用正常 viewport 的不透明屏幕副本/深度、随后绘制海水。镜像颜色来自真实镜像 SubViewport。透明海面不进入自身采样的屏幕副本。
- 波浪的世界 XZ 查询不能直接把参数 XZ 当作已位移世界坐标。新 wave field 保留源 `wave_at()` 参数化接口，并新增使用同一解析导数的 Newton 逆解 `sample()/sample_height()`。这项逆解用于接口和数学验证，尚未接入游戏浮力。

## 同源验证

`Temp/export_reference_demo_ocean_fixtures.mjs` 使用 Node 直接导入源 `model.mjs`，生成 `tests/fixtures/reference-demo-ocean.json`。来源散列与导出样本同时保存；参考目录未被改写。

`tests/test_reference_demo_ocean.gd` 初次 RED 为新模块缺失、3 项失败。当前 Godot 4.7.2 stable official `ed1daf0bf` headless focused 运行：**3,232 项断言、0 失败，日志没有 shader 编译错误**。

覆盖：240 组原 JS 位置/解析法线；强度边界、多潮位、多时刻和 footprint；世界 XZ 逆解高度/法线/残差；20 个原滤波样本；原 Float32 spread 顶点、footprint 和三角拓扑；真实镜像共享 World3D、排除水层、源 mirror eye/up、纹理 UV、节点复用、开关、相机 detach/re-attach、无效输入、释放。

Gerstner 位置和逆解高度以 `1e-9` 比对原 JS，双精度解析法线以 `1e-10` 比对；提供给 Godot `Vector3` 的法线以 `3e-7` 比对。选取的海面网格坐标及 footprint 为 Float32 严格相等。shader uniform 列表也参与测试，避免把 shader 编译错误与进程退出 0 误判为成功。

源 SHA-256：

| 文件 | SHA-256 |
| --- | --- |
| `model.mjs` | `39dda7dfbef6184f79975e73aa13a07899e5ebe8818cce4cdfa3f78893238d57` |
| `shaders.mjs` | `652df55dae5f76b8d50dba72413b42462ee06d6a475caa0a715f471775608d12` |
| `renderer.mjs` | `82f2afde7bd0699dff66a5a532bbf33f4cb941e3d25090a084097b81565f2c7f` |
| `app.mjs` | `ff5fb1fa98f481957e566bca800e9f706056d727f230bd82c32a32827c7a0d4e` |

## 尚待主验收的证据

以上是同源数学、Godot shader 解析及真实渲染节点合同验证。实际 GPU、天空/岸线/反射开关像素对照和完整独立场景由主验收执行。本报告不把 headless 验证称为 GPU 画面验收；未运行性能 benchmark、完整 runner、原游戏或浏览器示例。

## 分层守卫收尾

完整回归发现 `ocean_renderer.gd` 为读取 wave uniform 而直接引用 `physics_engine`，违反现有层边界。守卫未放宽；渲染器现改为读取渲染层 `ocean_model.wave_uniforms()`，源四波参数由渲染模型独立持有。物理层仍独立实现同源 CPU 算法，二者只通过测试核对源数据，不建立生产导入依赖。

新增 16 个 Float32 分量严格相等的断言，证明新的渲染 uniform 与修复前传入 GPU 的值完全相同。shader、网格、镜像相机、纹理、色彩适配与绘制时序没有改动，此修复不改变 GPU 输入或预期输出。

修复前分层测试 RED：16 项断言、61 个文件、1 个 forbidden dependency 失败；新渲染数据接口测试也以缺失接口 RED。修复后 `test_layer_boundaries.gd` 为 **16 项断言、61 个文件、0 失败**，`test_reference_demo_ocean.gd` 为 **3,249 项断言、0 失败**，两者退出 0，shader 解析日志干净。未重新启动 GPU 或完整 runner。
