# 海水光学：学习示例到 Godot 的实施记录

2026-10-11，实施于 `C:/Users/dains/Documents/Git/ming-armada`。参考目录只读，未修改或复制原 shader。此处是本作新增的 Godot 实现，不是原游戏 DX9 渲染路径的恢复。

学习入口：[island-water README](C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/README.md)、[AGENT_HANDOFF](C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/AGENT_HANDOFF.md)、`demo/renderer.mjs` 与 `demo/shaders.mjs`；同时阅读项目已有比较报告 `reference-implementation-demo-study.md`。

## 已实现与选型

学习示例先绘制正常场景颜色/深度，再绘制裁剪后的镜像场景，最后绘制海水。本作保留正常 viewport 的不透明颜色和深度读取，新增折射、按厚度吸收及有预算的屏幕空间反射；**未创建镜像 SubViewport，未声称接入 512×512 原游戏反射目标**。

Godot 官方合同规定深度只可从当前 viewport 读取；Camera3D 没有任意斜裁剪平面接口。共享 World 的镜像视图若缺少各材质的海平面裁剪，会把水下地形一起反射。按主线程明确批准的回退，采用屏幕空间反射，避免引入第二个模拟世界或不可验证的裁剪假象。

官方依据：[逆投影与 reverse-Z](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html)、[屏幕读取时机](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html)、[Camera3D 接口](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)，本轮已打开核对。

- **折射**：从当前 viewport 的 `hint_depth_texture` 用实际 `INV_PROJECTION_MATRIX` 重建 view position；Forward+/Mobile 直接使用 `[0,1]` 原深度，Compatibility 转换到 `[-1,1]` NDC。没有沿用学习示例固定 near=.3/far=1200 的 WebGL 公式。
- **吸收**：视图方向水层厚度取不透明表面深度与水面深度之差；`exp(-vec3(.16,.065,.028)*thickness)` 使红光比蓝光衰减更快。深水保留已批准的蓝色海面；浅水最多混合 .42/.54 的可见底色。
- **前景保护**：受法线扰动的折射 UV 若落到水面前的船体/岸线，退回原 UV，避免将前景船壳拉成水面裂边。
- **反射**：在 view space 镜像入射方向，向实际不透明场景深度查询交点；拒绝水面以下的候选，按屏幕边缘及射线距离淡出。Fresnel 调整反射混合，保留小船在俯视镜头下的可读性。
- **颜色**：原海面显示空间色转换先完成，再在线性工作空间与 Godot 屏幕源混合；不对屏幕源重复做 gamma。
- **性能与生命周期**：低档 0、均衡 16、高档最多 24 次反射深度查询；没有额外 viewport、texture、camera、World 或自主 `_process`。禁用光学或切到原风格时切回不含屏幕采样的原 shader，取消相关背缓冲复制需求。
- **稳定合同**：原五波高度、法线、CPU 波查询、世界 XZ 和 `simulation_time` 没有更改。光学没有 `TIME`；反射与折射独立开关，不修改浮力、炮弹和尾迹。

## 接口与集成

`projected_ocean.gd` 新增：

| 接口 | 行为 |
|---|---|
| `configure_reflection(camera)` | 只接受已配置的同一投影相机；空或无关相机回退原 shader |
| `enable_surface_optics(enabled=true)` | 显式启用；默认关闭，原风格始终关闭 |
| `set_reflection_enabled(enabled)` | 独立反射开关；低档仍不执行射线查询 |
| `set_refraction_enabled(enabled)` | 独立折射/吸收开关 |
| `get_surface_optics_diagnostics()` | 方法、步骤预算、档位、相机状态、屏幕/深度来源、0 离屏目标与 0 私有世界 |

`set_surface_quality` 已同时控制原表面细节与新查询预算。主线程负责 GenericWorld 的产品启用及选项转发，专家没有编辑 World/场景/UI。`original_water_body.gdshaderinc` 是原 shader 实体共用体；原 shader 与光学 shader 共享同一波函数及颜色代码，避免维护两套水面。

`surface_optics.gd` 另提供诊断数学：投影/逆投影、吸收、镜像方向和有预算的反射深度追踪。诊断追踪不修改场景，用于对照 GPU 接受的投影与交点；实际逐像素绘制在 `.gdshaderinc` 内运行。

## 本轮验证

Godot `4.7.2.stable.official.ed1daf0bf`，专家仅运行 headless 聚焦测试；没有开启游戏窗口或替主线程宣称 GPU 画面通过。

| 测试 | 结果 |
|---|---|
| `test_reference_surface_optics.gd` | 初始 RED 4 断言 / 3 失败；审查修复后 122 断言 / 0 失败 |
| `test_reference_ocean_layers.gd` | 15 / 0 |
| `test_wave_uniforms.gd` | 8 / 0 |
| `test_coastal_waves.gd` | 1,090 / 0 |
| `test_naval_world_view.gd` | 20 / 0 |
| `test_world_lifecycle.gd` | 1,710 / 0 |
| 改动文件 `git diff --check` | 通过 |

新测试覆盖 3 个宽高比 × 3 个 near × 3 个 far × 3 个 view position 的独立 reverse-Z 矩阵重建，以及一条镜像射线与已知深度、不透明水上墙面的正向交点、查询上限、无效深度、零预算、反射/折射开关、相机失效/无关相机、resize、原风格回退、暂停时间与五波不变、释放。

完整项目 runner 和实际 GPU 编译/截图由主线程统一执行，避免多个游戏窗口和共享证据被相互覆盖。应比较同一 accepted time、同一相机的反射开/关及整体光学开/关画面，拍近船、岸线和远海；反射开关差异必须落在预期反射区域，不能仅用“shader 存在”代替像素证据。

独立审查发现并修复 P2：Camera3D 从场景树移除但尚未释放时仍是有效实例，原更新路径直接读取空 viewport，且诊断显示禁用而材质仍启用。新增 detach/re-attach 用例先复现 `get_visible_rect` 空调用及 1 项失败，再验证 122/0：离树立即回退原 shader，清除投影缓存；重新挂回同一相机后自动恢复请求的光学，保持 accepted time 和既有网格。更新前分别检查树内状态及 viewport 有效性；shader 参数仅在状态转换时刷新。

## 已知限制

屏幕空间反射只能反射当前视野内、已写入不透明屏幕源的物体；离屏物体和透明水柱、尾迹等不在该源中。缺失交点沿用海面已有天空/Fresnel 颜色。本方法不等同学习示例的镜像相机反射，不提供水下相机、物理光线折射、完整透明排序或每个浪峰的真实反射曲面；变形法线与粗采样会有常见 SSR 丢失/跳变，距离与边缘淡出降低其可见性。

源文件 SHA256（本轮实际读取与核对）：

| 源 | SHA256 |
|---|---|
| `AGENT_HANDOFF.md` | `2bc57242534a0da4b1f78b9590adf1925b099f002112d301eea54477be951ae9` |
| `demo/renderer.mjs` | `82f2afde7bd0699dff66a5a532bbf33f4cb941e3d25090a084097b81565f2c7f` |
| `demo/shaders.mjs` | `652df55dae5f76b8d50dba72413b42462ee06d6a475caa0a715f471775608d12` |
