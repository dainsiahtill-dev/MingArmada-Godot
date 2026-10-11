# 海岛与海面学习示例：Godot 源码移植

用户最新顺序：先完成海岛与海面效果；再迁移 atmosphere-fx 的云雾、炮火、烟；之后返回游戏任务。性能工作暂缓。

本阶段基准为 `C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/demo/`。使用实际 Cat Island 高度索引及现成 model/renderer/shaders/app 代码，逐表达式翻译为 Godot。先提供独立可运行场景与主菜单入口，不改现有游戏地理、航行存档或原五波物理路径。

## 并行所有权

- 海水专家：新增 reference ocean renderer、四组 Gerstner/解析法线/footprint 滤波、镜像相机 SubViewport、完整 waterFS 与 sky shader；数学 fixtures 和 focused 测试。
- 海岛专家：新增高度场模型、160 网格和160海底环带、实际 Float32 顶点 RF 高度纹理、terrainFS、源 JSON 与来源哈希；原 JS fixtures 和 focused 测试。
- 主线程：场景、相机/控制/UI、主菜单路径、生命周期、真实 GPU 对照与整体验收。最终审核单独委派。

## 精确适配合同

- 同一 field：extent160、heightScale0.35、seaIndex128、terrainResolution160、原120×140索引。R32F高度纹理从实际绘制Float32顶点生成；相同三角对角线查询。
- 新 ocean `configure(field,camera,state)->bool`、`render(state,camera,accepted_seconds)`、`get_sky_material()`、`diagnostics()`、`dispose()`；不持有独立时间积分。
- 相机原orbit(-0.65,0.68,185)、FOV45、near0.3/far1200；潮位-3..4、波强度0..2、泡沫0.3..4，晴天/夕阳/风浪与开关同原app。
- Godot镜像viewport共享预览World3D；水层20被镜像camera排除。反射宽min(768,viewWidth)，真实aspect。地形仅在镜像camera低于潮位时裁掉海下片元。
- 源shader显示空间公式保留。Godot屏幕纹理先linear→display，原公式结果display→linear；Environment ToneMapLinear、exposure1，不加入第二次PBR光照。
- reverse-Z、矩阵、SCREEN_UV/ViewportTexture Y翻转属于引擎接口适配，原公式参数不随意重写。
- 原参考目录及原Three.js项目只读；新源码、资源、测试及报告保存Godot仓库。

## 验收步骤

- [x] 源JS数学fixture和Godot对应函数逐项比较；岸线查询与实际网格一致。
- [x] Godot实际编译所有新shader，检查镜像纹理排水、自反馈、尺寸变化及释放。
- [x] 实际主菜单进入预览，潮位/预设/波浪/泡沫/反射/焦散/暂停/重置/截图/返回可用。
- [x] 主线程亲自查看Godot晴天、夕阳、风浪、高潮位、低角度及效果开关截图；与原demo同状态对照，记录真实差异。
- [x] 独立代码审核、相关回归；保存来源/移植映射/逐项验收报告。

本阶段截图验收通过之前，不开始 atmosphere-fx 新实现，不继续性能分析。

最终记录：地形591、海面3249、场景35项断言通过；实际主菜单15状态/30原始PNG与保存PNG已查看；分层和截图取消P2修复并经独立复验关闭。78组完整回归通过，随后截图guard相关scene/menu/router151项定向回归通过。逐项记录见 docs/migration/reference-demo-port-acceptance.md。Windows交付单独核对当前源码与PCK哈希，不沿用旧包。
