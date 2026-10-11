# Reference demo: Godot 海岛与地形材质移植

本模块直接移植 `C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/demo/model.mjs` 的高度场、地形网格、三角面查询与背景海底，以及 `shaders.mjs` 的 `terrainVS/terrainFS/common`。参考目录和原 Three.js 项目保持只读；当前代码位于 Godot 项目 `C:/Users/dains/Documents/Git/ming-armada`。

## 交付与接线

| 文件 | 职责 |
|---|---|
| `modules/scene_engine/reference_island_water/reference_island_model.gd` | 加载原索引高度数据、生成地形/海底 ArrayMesh、R32F 海岸查询纹理 |
| `modules/scene_engine/reference_island_water/reference_terrain.gdshader` | 沙、湿沙、草、岩、程序焦散、原 demo 太阳照明与距离雾 |
| `modules/scene_engine/reference_island_water/reference_terrain_common.gdshaderinc` | 原 `sky/noise/valueNoise` 公式及显示色到线性色转换 |
| `assets/data/reference_cat_island_h.json` | 原 JSON 的逐字节复制 |
| `assets/provenance/reference-cat-island.json` | 数据来源、字节数与 SHA-256 |
| `tests/fixtures/reference-demo-terrain.json` | 执行原 JavaScript 得到的独立数值和完整载荷哈希 |
| `tests/fixtures/generate-reference-demo-terrain.mjs` | 重建独立对照数据的 Node 脚本 |
| `tests/test_reference_demo_terrain.gd` | Godot 数学、网格、数据、LUT 与 shader 输入验证 |

模型为静态方法的 `RefCounted` 脚本，可由独立预览场景和海面 renderer 共同使用：

```gdscript
const Model = preload("res://modules/scene_engine/reference_island_water/reference_island_model.gd")
var field: Dictionary = Model.load_field()
var island: ArrayMesh = Model.terrain_mesh(field, 160)
var seabed: ArrayMesh = Model.seabed_mesh(field, 160)
field.heightTexture = Model.height_texture(field, 160)
# field.terrainResolution = 160 已由 load_field 写入。
```

公开采样方法为 `height_at(field,x,z)` 和 `mesh_height_at(field,x,z,resolution=160)`。前者保留原索引的双线性插值，负责生成网格；后者以 Float32 绘制顶点为基础，按 `(a,c,b)/(b,c,d)` 的实际对角线做三角插值，供岸线与海面查询。源数据范围之外统一为 `-20`，不把新增背景海底冒充原高度数据。

`terrain_arrays/terrain_mesh/height_texture` 的 resolution 接受原函数范围 `1..254`；无效分辨率或无效数据返回空字典/null。`seabed_arrays/seabed_mesh` 使用原五圈比例 `[.5,.65,.9,1.5,3]`，背景外圈高度分别为 `-16/-30/-60/-80`。原 renderer 实际使用 `segments=160`，尽管原 model 函数默认值是 64；预览需显式传 160，得到 3,200 个海底顶点。

## 保留的数值和资源合同

- 原数据为 120×140 的 uint8 调色板**索引**，共 16,800 个值；没有把调色板 RGB 转成亮度。
- JSON 56,923 字节，SHA-256：`d1b4f3b42347916ef7f85262e1ac16a65234c4981a374039b55ab0b417d30a1c`，源与目标逐字节一致。
- `extent=160`、`heightScale=.35`、`seaIndex=128` 是已有学习 demo 的显示选择，保持一致；不称为恢复的原游戏常量。
- 地形 res160 为 25,921 顶点、153,600 索引；完整 Float32 位置/法线/UV 与原 JavaScript TypedArray 字节一致。
- 索引从源 Uint16 无损扩展到 Godot PackedInt32Array；顺序、绕向和对角线全部保留，完整载荷对照无差异。
- 高度纹理为 161×161 `Image.FORMAT_RF`，不生成 mipmap；全部 R32F 数据直接取实际绘制顶点 Y，整个纹理载荷与原 renderer 相同。
- 使用 cull_disabled，保留原 WebGL renderer 关闭背面剔除的行为；无需改变源索引绕向。

## 地形 shader 与镜像反射

shader 逐表达式保留 `terrainFS` 的沙/湿沙颜色、两层 noise、草地高度和坡度权重、岩石混合、太阳漫反射、程序焦散与距离雾。`unshaded` 禁止额外 PBR 灯光叠加，`fog_disabled` 防止引擎雾与源公式重复。

输入保留 `u_time/u_tide/u_eye/u_sun/u_sun_color/u_clip/u_caustics`。时间由预览接受的时钟驱动，暂停时冻结、回退时重新求值；潮位同时改变湿沙和焦散的水上/水下判定。颜色公式先在原 demo 的显示色空间计算，最终显示色先 clamp 到 `[0,1]`，模拟源 RGBA8 场景/反射目标的写入边界，再以标准 sRGB 分段函数转到 Godot 线性帧缓冲；不额外 round/量化滤波后的采样。预览应使用 Linear tonemapper。

镜像 SubViewport 与主视图共享 World3D/material，不能每次写一个全局 `u_clip` 切换 pass。当前 `u_clip` 默认 true，仅 `CAMERA_POSITION_WORLD.y < u_tide-.02` 的镜像相机裁掉 `worldY < u_tide-.02` 的片元。主预览相机限定水上。距离雾和 sky 视线也使用 `CAMERA_POSITION_WORLD`，确保镜像 pass 自己的相机参与运算；`u_eye` 保留原合同但不用于覆盖每个 pass 的相机。

## 验证

先写测试并运行：模块尚不存在时，输出 `REFERENCE_DEMO_TERRAIN_TESTS assertions=1 failures=1`，退出码 1；失败原因为待移植模块缺失。

完成实现后的最新 focused headless 输出：

```text
Godot Engine v4.7.2.stable.official.ed1daf0bf
REFERENCE_DEMO_TERRAIN_TESTS assertions=591 failures=0
```

运行命令：

```powershell
rtk proxy node tests/fixtures/generate-reference-demo-terrain.mjs
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_reference_demo_terrain.gd
```

覆盖 128 组原 JavaScript 独立高度/三角面样本、三种地形分辨率、两种海底分段数、完整载荷哈希、LUT 全数据、跨三角对角线的手算鞍形单元、无效输入/分辨率和缺失文件。双线性高度误差阈值 `1e-10`；三角面与原 JS 双精度 helper 的差异允许 `2e-6`，原因是实际绘制/查询采用原 renderer 的 Float32 顶点。完整 Float32 网格与 LUT 采用零差异字节哈希核验。shader 资源解析及原状态输入检查通过。目标 `git diff --check` 无输出。

该结果是数据、数学、网格与 shader 输入验收，**不是实际 GPU 画面验收**。实际 Forward+ 截图、镜像水面组合、浅水焦散可见性和与浏览器 demo 对照，由主 Agent 在完成预览接线后执行。本分工未启动 GPU、性能测试、完整测试或改变旧 World/TerrainChunk。
