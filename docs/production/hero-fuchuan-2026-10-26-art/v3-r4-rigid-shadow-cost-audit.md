# v3-r4 正式试航刚性阴影数据成本审查

2026-10-26。只读审查；未启动游戏、运行 GPU 测试、修改模型或代码。主线程已通过实际 `--print-fps` 日志发现正式自由试航约 4–6 FPS；本报告不独立认证该测时，也不把静态三角形数量转换成 FPS 结论。

**确认：高细节可见 hull、deck、mast_timber 网格目前被直接作为自定义模板阴影几何输入。最小风险改动点是 Blender 原创资产与 HeroProvider 的 caster 资格/代理接线；无需删可见模型、角色、帆或效果，也无需改变 Prepared/Boundary 的通用几何算法。**

## 原生调用路径

主菜单的当前自由试航使用 `game/scenes/naval_practice/naval_practice.gd`，不是旧 `sailing_trial`：

1. `naval_practice.gd:79` `_process()` 每渲染帧调用 `_present(0)`；`:101` 调用 `sea.apply_snapshot()`。
2. `naval_world_view.gd:363` `apply_snapshot()` 更新船/船员/世界；`:406` 进入 `_apply_source_shadows()`。
3. `naval_world_view.gd:417` 调用 `_rigid_casters.compose(native,ships,-_sun.global_basis.z,stencilActive,quality.shadows)`；`:419` 将 packet 送给 `source_shadows.apply_snapshot()`。
4. `target_rigid_shadow_caster.gd:50–54` 扫描当前 `ShipView.get_model()` 的 MeshInstance3D，仅凭 `target_rigid_shadow_caster`、`is_visible_in_tree()` 和非空 mesh 接纳；直接 `_mesh_geometry(mesh.mesh)`。
5. 同文件 `:64–70` 配置 `TargetShadowBoundary` 并选择 topology；`:73` 提交源 positions、caps、edges、prepared owner 和真实 worldTransform。
6. `source_shadow_renderer.gd:48–60` 判定重建、`prepared.build_volume()` 并记录 geometryRevision；`:66` 通过 PreparedShadowFrame 发布不可变数组。
7. `source_shadow_compositor.gd:26–49` 每次 POST_TRANSPARENT 回调逐 eye 调用 RD backend；`source_shadow_rd.gd:185–192` 对每个 retained volume 分别绘制 increment/decrement 两面，最后一张全屏阴影混合 quad。

旧 `sailing_trial.gd:156–157` 也调用同一 compose/renderer，但不是本次主线程实际操作的入口。

## 资格来自两层，全部细节都被纳入

- `hero_ship_provider.gd:44–45` 为可见 `hull`、`deck` 和 `mast_timber_*` 设置 target_rigid_shadow_caster。
- `build_hero_fuchuan_v3.py:114/140/316` 也直接把同名标记写入 Blender 对象的 glTF extras。**仅停止 Provider 的 set_meta 不足以清除旧标记**；新资产应不导出该标记，或 Provider 明确置 false/remove_meta，再只给代理启用。
- `hull()` 先把壳板、细嵌缝曲线、护舷材、外侧骨架、实心舷墙、炮口框、艏柱、龙骨、尾封板全部 join 成 hull。因此 `_mesh_geometry()` 不会只取光顺主壳，而会处理每根曲线转换出的实体三角面。
- deck 包括逐条窄板及上层甲板；mast_timber 包括绳箍。三者的可见细节都成为模板体积的一部分。
- `_mesh_geometry` 按 Mesh instance_id 缓存并精确位置焊接，所以不应声称它每帧重新从 mesh 拷贝所有面；但该缓存不削减 caster 的面数或轮廓边数。

## 对 r4 原始 GLB 的只读静态计数

| LOD | 整船三角形 | hull 面 / 精确焊接点 | deck 面 / 精确焊接点 | 每根 mast_timber 面 |
| --- | --- | --- | --- | --- |
| 0 | 101,299 | 35,820 / 18,034 | 5,144 / 4,938 | 720 |
| 1 | 48,051 | 13,520 / 6,844 | 2,248 / 2,158 | 696 |
| 2 | 27,291 | 6,304 / 3,264 | 888 / 834 | 696 |

近景 LOD0 的五个目标 caster 合计 **43,124 个源三角形**。整船 101,299 并非全部进入此刚性路径，不能混为一谈。

LOD0 hull 焊接后边的相邻面次数：degree1=878、degree2=51,599、degree3=112、degree4=762。它不是单一闭合双流形：开口/重叠/拼装细构件使 parity 轮廓复杂。deck 有 4,644 条 degree1 边，逐板结构同样会制造多余边界。

照源码的三角形翻序、面向判定和奇偶边切换，对三个**示例局部光向量**做静态计算：

| 示例 local light | 被选 caps | parity edges | 原始 volume 顶点 | volume 三角形 |
| --- | --- | --- | --- | --- |
| (.7,.6,.3) | 17,332 | 6,520 | 65,037 | 23,852 |
| (-.3,-.8,.5) | 19,264 | 6,826 | 71,445 | 26,090 |
| (.3,.8,-.4) | 16,550 | 6,602 | 62,855 | 23,152 |

这些方向是离线样例，不是当前暂停船姿态。第二例超过 Prepared 的 65,535 volume 顶点上限，会走 `volume exceeds uint16 scope` 错误；**不能据此宣称当前运行中已经发生同一错误**。Boundary 增补在这三例中只有 0/4/2 三角面，不支持把大成本归咎于 Boundary 修补面；大体量已经存在于原始 hull caps/edges。

## 可能的数据成本与缓存边界

1. **CPU 面分类和 topology。** `Prepared.select_topology:60–66` 只要 localLight 发生精确值变化，就扫描所有面法线；mask 未变化时会复用拓扑。船的 pitch/heel/heading 改变会改变 inverse-basis light，不能用固定世界太阳假设 localLight 恒定。
2. **CPU/上传重建。** TargetRigid 的 dirty 使用精确 localLight 比较；SourceShadowRenderer 的 rebuild 也直接比较 localLight，因而这里的精确光变化不会受 `Math.should_rebuild()` 旋转阈值保护。即便 face mask 相同、只改远端 apex，renderer 仍递增 geometryRevision，RD `_mesh_record:137–155` 会创建新顶点/索引 buffer；`:157–159` 退役旧 revision。当前正常移动可能产生频繁重建/上传，这是待计数或剖析的成本假设，不是已测到的耗时。
3. **每帧绘制与过绘。** 即便完全静止且 geometry 复用，compositor 每帧仍对全部 volume 做两个 draw。`EXTRUSION=1e9` 形成极长侧面，复杂 hull 产生数千轮廓边；fragment 每片元采样 scene_depth 并 discard，不是普通可见船体绘制。其覆盖面积与重叠次数有可能比可见三角形数量更关键；本次未测 GPU 时间。
4. **Prepared publication 已有共享。** PreparedShadowFrame 对 owner 认证的 immutable geometry 直接共享，不递归深拷贝其巨大数组；不能把这一路径误报为必然每帧深复制。

**暂停判别有边界：** `naval_practice._process()` 暂停时仍进入 `_present`，CPU presentation、compose 和 submit 仍运行；compositor 也继续绘制。暂停 FPS 若仍低，不能单独证明全是 GPU；若稳定姿态使 classifications/rebuilds 不再增加，才可进一步把重建成本与常驻绘制分离。

## 最低风险的原创代理接入点

- 在 Blender 资产内制作独立、闭合、低面数的 **hull+deck 外轮廓代理**，保留上扬艏、船腹、尾部收束和上层尾甲板大体量。省略嵌缝、板缝、绳圈、炮框小倒角等不改变主要投影轮廓的细节；代理不是可见模型替代品。
- 三桅各提供闭合 timber-only 代理，保留桅杆真实父层级与刚性姿态，排除绳箍细曲线。帆/索具、炮、船员及效果保持原有行为。
- 仅在 HeroProvider 的 art-v3 路径启用这些代理的 target caster 资格，清除高细节 hull/deck/mast 的旧资格。Prepared/Boundary/SourceShadowRenderer 继续消费原合同，避免给通用或参考来源代码增加未经验证的自动简化。
- 原 hull 的 `damage_surface`、deck 的 `deck_support`、桅的障碍、crew/helm/socket、水线读取均保留。代理不标记 `damage_surface` 或 `deck_support`，防止它改变船壳水线和角色站立语义。

## SHADOWS_ONLY 资格与可见性陷阱

**资格上可行：** proxy 为 MeshInstance3D、visible=true、mesh 非空且 target meta=true，当前 adapter 会接纳；它不检查 cast_shadow 是否为 SHADOWS_ONLY，也不检查 render layers。

**单靠 SHADOWS_ONLY 不够：** `compose:76` 在 stencil_active 时把 caster.cast_shadow 改成 OFF。Godot 的 OFF 只关闭投影，SHADOWS_ONLY 才隐藏实际网格；被改成 OFF 后粗代理可能进入颜色画面。此语义可见 [官方 GeometryInstance3D 文档](https://docs.godotengine.org/en/stable/classes/class_geometryinstance3d.html#enum-geometryinstance3d-shadowcastingsetting)。需给代理独立的颜色不可见策略，或明确避免覆写其 shadows-only 模式；不能用 Node.visible=false，因为那会被 eligibility 排除。可选的窄接线是 proxy visible=true、layers=0，由自定义 backend 独立消费网格；当前 adapter 不读 layers，但接入后仍需实际确认颜色画面与 fallback 路径。

完整可见 hull 取消 target tag 后会继续原生 renderer 投影，代理又提供自定义模板影；这可能是保留甲板/帆等局部投影所需的组合，也可能导致同一区域重复变暗。应在同一原生场景检查与既有 stencil/fallback 意图一致，不要把资格接上等同于视觉无变化。

本报告只定位数据与最窄接入接口，不宣称代理已经恢复帧率。正式验证应复用主线程当前原生入口、同镜头/状态的实测日志，并保留全部可见艺术模型和玩法。
