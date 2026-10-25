# v3-r5 阴影代理：独立 CPU 配对与静态审查

2026-10-26。本轮只修改 `tools/measure-hero-rigid-shadow.gd` 的候选构造为 `Hero.new("art", _proxy == "authored")`，执行 headless CPU 微基准并读取三处生产接线；没有修改生产文件或测试，没有运行 GPU 或正式游戏。此文件记录独立结果；主线程的新闭合矩阵与正式试航帧率不由本报告代为认证。

## CPU 配对方法与结果

交替顺序 visible → authored → visible → authored。每组先有一条 cold 调用、8 次暖机，再采样 40 次。固定 LOD0、单船 identity pose、相同光方向，慢转每样本 0.001rad。四轮 source hash 集合完全一致，每轮运行内也无 source 漂移；全部五 caster 有效、零错误。统计采用 nearest-rank `ceil(q*n)-1`；原始样本均保存。

| 运行目录 | 静止 compose p50 / p95 | 慢转 compose p50 / p95 | 慢转独立 volume build+inspection p50 / p95 |
| --- | --- | --- | --- |
| [cpu-proxy-pairs-01-visible](cpu-proxy-pairs-01-visible/measurement.json) | .058 / .060ms | 46.704 / 60.754ms | 24.005 / 31.145ms |
| [cpu-proxy-pairs-02-authored](cpu-proxy-pairs-02-authored/measurement.json) | .064 / .077ms | .122 / .243ms | .097 / .179ms |
| [cpu-proxy-pairs-03-visible](cpu-proxy-pairs-03-visible/measurement.json) | .059 / .063ms | 48.770 / 66.289ms | 26.235 / 35.032ms |
| [cpu-proxy-pairs-04-authored](cpu-proxy-pairs-04-authored/measurement.json) | .066 / .097ms | .127 / .155ms | .104 / .148ms |

这些结果证明本 fixture 中变光下的 **CPU 阴影准备成本显著下降**。静止路径原本已命中缓存，未观察到收益；不应宣称所有路径都等比例加速。volume build+inspection 是另一个计时区间，没有混入 compose，也不是 GPU draw 时间。微基准不包括完整游戏、GPU 上传/绘制和其他系统，不能换算游戏 FPS。

可见网格源三角形合计 43,124；代理合计 1,614（hull 1,406、deck 100、三桅各 36）。慢转最后一个样本代理 hull 的 volume 为 2,782 点/1,088 三角形，deck 207点/78三角形，三桅各79点/30三角形。49条 cold+warmup+sample 输入中，候选每 caster 仅一次 topologyBuild；原可见 hull 每次都重建，共49次。

工具在 authored fixture 中选择 meta 所指 Mesh 作为纯 CPU 几何输入，因此配对隔离了几何成本；它不能单独证明正式实例的可见 mesh 没被替换。该生产合同由以下代码审查与主线程的原生检查另行覆盖。

## 三文件接线判断

- **Builder：** `shadow_hull`、`shadow_deck` 与完整组件处于同父节点和同局部坐标；桅杆代理处于相同 mast 父节点。导出代理 Mesh，Blender `hide_render` 防止进入工作室成片；完整可见网格、角色挂点、炮口和损伤角色未被代理替代。
- **HeroProvider：** 所有 `shadow_*` MeshInstance 显式 invisible，作为资源持有者；默认 `_authored_shadows=false`。仅 art+候选开关才将同父、同 transform 的 proxy.mesh 写到完整角色 node 的 `target_shadow_geometry`。缺代理或 transform 不匹配时不附着，按完整几何回退。可见/动画身份仍由完整 node 持有。
- **TargetRigid：** 只将 `_mesh_geometry()` 输入改为 `target_shadow_geometry`，不存在时使用原 mesh；caster id、actor、worldTransform、局部光转换、native cast_shadow 保存和恢复均继续绑定完整角色 node。缓存按实际所选 Mesh ID 区分。Prepared/Boundary 算法未改变。

**此接线避开了早先 SHADOWS_ONLY 被改成 OFF 后粗代理进入颜色画面的风险。** 隐藏的是资源 node，而 eligibility、cast_shadow 切换和 frame 取自完整可见 node。模板活动时完整 node 的原生投影被关闭；fallback/dispose 恢复其原模式，粗资源 node 仍 invisible。

需要保留的运行边界：缺代理导致的完整几何回退是安全性策略，不保证性能；仅凭 `<3000面` 不足以证明闭合、绕序或整个可见合同。原生镜头、阴影接收、LOD/损伤及 fallback 仍需实际运行证据。

## 独立静态有向边与体积检查

直接读取当前 LOD0 GLB 的五个 `shadow_*` primitive，按 POSITION 精确焊接，统计索引三角形的无向 incidence、有向边余额、零面积面和有符号体积。未调用 Godot/GPU；这是导出源几何的静态审查，不能替代 Godot 导入后的 exact-weld 检查。

| 代理 | 焊接点 / 三角形 | 无向边 incidence | 非零有向边余额数 | 退化三角形 | 有符号体积 |
| --- | --- | --- | --- | --- | --- |
| shadow_hull | 559 / 1,406 | degree2=1,537；degree4=286 | **0** | 0 | **+632.986523 m³** |
| shadow_deck | 52 / 100 | degree2=150 | **0** | 0 | **+9.050955 m³** |
| shadow_mast_timber_0 | 20 / 36 | degree2=54 | **0** | 0 | **+.800645 m³** |
| shadow_mast_timber_1 | 20 / 36 | degree2=54 | **0** | 0 | **+1.868502 m³** |
| shadow_mast_timber_2 | 20 / 36 | degree2=54 | **0** | 0 | **+.760511 m³** |

**五个代理均无未平衡有向边，体积非零且正向，无退化面。** hull 的286条 degree4 边来自分段舷墙闭盒相接，必须描述为“闭实体组合”，不能称为单一双流形。Builder 的每个原始 BMesh edge.link_faces==2 断言发生在最终 adapter 精确焊接之前，不能用它替代本表的最终焊接拓扑口径。

有向平衡与正体积也不单独排除自交、内部相接面或重叠实体的模板计数问题。若合同允许闭实体组合，实质性检查应覆盖：导入后有向边平衡；多方向生成 volume 的闭合/范围；代表射线或实际模板接收结果；局部 transform 不匹配时安全回退；stencil活动/失活、质量关闭、LOD切换、dispose 后完整节点投影策略恢复；默认 Provider 和候选 Provider 的全部可见角色/mesh/AABB一致。主线程已报告扩展 exact-weld 偶数 incidence、8方向 volume 范围和可见 AABB 检查，本轮未重跑或代替其结果。

结论：**可继续进行候选的正式原生性能与画面验收；CPU 窄路径改善已有独立配对证据，闭实体组合的几何性质也已明确记录。整场目标帧率与用户最终艺术认可仍是独立门槛。**
