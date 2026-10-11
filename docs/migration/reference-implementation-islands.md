# 海岛分层材质落地

2026-10-11。只修改 Godot 项目地形模块；原参考目录只读。此记录是本项目实现与当前测试结果，不能替代原作 GPU 帧或本项目的截图验收。

## 实现和接入合同

- `modules/scene_engine/terrain/terrain_chunk.gd` 保留原高度 Callable、顶点坐标、法线、三角形索引和线性顶点 COLOR。物理仍使用同一个 ArrayMesh 创建的三角形形状。
- 原五参数 `configure` 保留默认 StandardMaterial3D。新增可选第六参数 `{ "detailed": true }`，为每个地块创建独立 ShaderMaterial，避免时间与其他可变材质参数串地块。
- 新 `terrain_surface.gdshader` 使用世界坐标产生多尺度地表纹理。低缓海底与沙滩以沙为主；平缓内陆渐变为草；陡坡及高山露岩。UV 保存沙／草权重，第三层由总和恢复，材质混合仍包含原顶点 COLOR。没有将 UV 当重复贴图坐标，也没有改变现有港口、岛屿高度或地理数据。
- `get_surface_weights(height, normal)` 是实际建网格使用的分层函数，返回归一化的沙、草、岩权重。颗粒、沙纹、草地色块和岩石细缝在片元中补充；细节按屏幕导数衰减，避免远景高频闪烁。
- `sync_surface_state(ocean_material: ShaderMaterial) -> bool` 只复制接受时间、波分量、波数量、岸线高度纹理、范围及沿岸衰减配置。所有字段先校验，再更新；无 `_process` 或 shader `TIME`，不持有 ocean 节点或材质引用。高度 Texture2D 是共享只读输入。本地复制状态缓存避免逐帧重复上传静态波与岸线数据，同一接受时间也不重复写入；创建新材质与释放时清空缓存。无岸线场的海面使用明确的离岸回退。
- 湿沙使用地表与当前波面高度差，降低沙地亮度和粗糙度；浅水底部增加随同一接受时间移动的焦散光网，随深度及坡度衰减。地形保持不透明，无 ALPHA 输出。
- `dispose` 释放本地网格、材质和碰撞，并可再次配置；碰撞由开启改为关闭时不留下已释放的 body 引用。

主线程负责 WorldView 中近景／远景地块的第六参数与状态同步：地块创建后同步一次，每次更新实际海面的接受时间后再同步。原水面风场、五波高度和法线算法未在本任务修改。

## 学习依据与边界

已学习：`naval-study/island-water/README.md`、`AGENT_HANDOFF.md`、`SOURCE_REPORT.md`、`ORIGINAL_SHADERS.md`、`demo/shaders.mjs`，以及本项目 `reference-implementation-demo-study.md`。

采用的是学习台“按高度与坡度混合地表、接受时间驱动湿岸和浅水焦散”的原则。本任务新 shader 属于本项目学习后重写；不是原作 shader 直接移植。原作地形声明提供沙、湿沙、ocean3 及额外基础层的证据，原 B/T/BHI 编码与运行分支仍未确认，因此未猜测这些通道。未导入 Cat Island 高度图，也未替换现有地图。

新增外部图片依赖 **0**，没有复制、改写或重新编码原参考纹理；本轮表面颗粒和焦散使用程序公式。原作焦散 NIF 没有明确源纹理引用，`dg_caustic.dds` 仍只是未建立绑定的候选，本实现没有冒称恢复该绑定。

当前岸线 RF 场仍是现有连续近似，并非每一个近／远景地形三角面的精确 LUT。湿沙跟随实际注入的近岸波面，不另加潮位或四组 Gerstner 波。本项目没有潮汐玩法，本任务未新增潮位模拟。焦散是有界的视觉光网，不是光线追踪或真实光学聚焦。

## 当前验证

所有命令通过 RTK，在 Godot 4.7.2 headless 执行；没有启动 GUI，也没有运行整套 runner。

```powershell
rtk proxy "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --headless --path . --script tests/test_reference_island_materials.gd
rtk proxy "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --headless --path . --script tests/test_world_lifecycle.gd
rtk proxy "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --headless --path . --script tests/test_distant_island_support.gd
rtk proxy "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --headless --path . --script tests/test_water_probe.gd
```

- 新分层测试：先得到正确 RED `assertions=4 failures=2`，缺失实际材质分层及共享水面接口；最终 GREEN `assertions=155 failures=0`。覆盖高度／坡度分层、真实网格权重、默认兼容、原几何／碰撞不变、材质私有化、自定义波描述与岸线纹理同步、暂停／回退／无效时间拒绝、同时间静态波与岸线变更、离岸回退、效果开关、释放与再次配置。新增离岸测试发现并修复未设置 shader 默认参数返回 null 时的转换错误。
- 场景生命周期：`assertions=1710 failures=0`。
- 远景岛屿支持：`assertions=31 failures=0`。
- 原水面基准：`assertions=77 failures=0`，48 组原 JS 高度最大误差约 `1e-14`，梯度 `0`，法线约 `1.1932565e-7`。

真实 D3D12 shader 编译、地表外观与性能验收由主线程统一完成；上述 headless 结果不构成 GPU 图像证据。
