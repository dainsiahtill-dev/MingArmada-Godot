# 2026-10-26 GPU 路径只读审计

- 归属：既有 `architecture-convergence-2026-10-21`，继续其未关闭的正式帧预算接受项；不另建课题。
- 类型：源码审计与既有回执复核。本文未运行 Godot、GPU、游戏或 benchmark，未修改生产源码。
- 保留合同：r6 hero 福船、35 名可见 3D 船员、海水、岸浪、云、倒影、尾迹、光学和特效全部保留。候选仅消除可证明无贡献或重复的工作，不降低画质、数量、采样率或目标分辨率。
- CodeGraph：父任务已确认本项目无索引，本审计按指示使用 RTK 源码读取；没有自行建立索引。

当前证据只足以安排受控实验，不能确定 main GPU 27.4ms 的具体 pass 归因，也不能宣称任何候选已提速。

## 当前实测边界

权威输入是 [r6-c 普通菜单自由试航回执](../../../../production/hero-fuchuan-2026-10-26-art/perf-r6-c/live-observation.json)：Intel Arc130T / Godot Forward+，1600×900，主视图 `msaa3d=2`，3 船、35 名可见船员，暖机 10.059s 后保留 412 个样本、30.054s 观察区间。

| 指标 | mean | p95 | 含义 |
| --- | ---: | ---: | --- |
| 实际 callback interval | 72.945806ms | 80.101ms | 观察帧间隔，13.708807FPS |
| 主 viewport GPU | 27.403286ms | 30.393ms | 主 viewport 聚合 GPU 查询；尚无 pass 拆分 |
| 反射 viewport GPU | 2.778704ms | 4.055ms | 768×432，无 MSAA 的独立反射目标 |
| 主 viewport render CPU | 4.847410ms | 6.543ms | 渲染 CPU 查询，不能称 GPU draw 时间 |
| 反射 viewport render CPU | 1.529323ms | 2.277ms | 同上 |
| render setup CPU | 1.476078ms | 1.930ms | 独立记录，不与父计时重复相加 |
| process monitor | 68.533602ms | 74.803ms | 重复读取的一秒窗口最大值，不是 412 次脚本 `_process` 直接计时 |

[既有口径说明](../PERFORMANCE_INTERPRETATION.md) 已按相同引擎 commit 追踪 `main.cpp`：process monitor 包含 SceneTree、消息队列、RenderingServer sync/draw；CPU/GPU 交叠或等待。不能把 68.53+27.40 作为总帧时，不能通过 viewport 聚合数反推出 stencil 或 ocean 各耗时。

独立主 GPU 均值已高于 16.67ms，故即便 CPU 改善，仍需继续 GPU 研究。该判断不等于 GPU 当前支配 72.95ms 的整个帧间隔。

## 最小可行动实验：不提交必被 alpha 阈值丢弃的岸浪 patch

源码链：

- `modules/scene_engine/terrain/natural_shore_surf.gd:178-215`：每个原始细分网格拥有独立 MeshInstance3D 和 ShaderMaterial；`cast_shadow=OFF`，保留完整 STEP=1.25m 网格。几何不随相机重建。
- 同文件 `249-284`：原 source clock 每 patch 求出 `visible_alpha=clamp(native_alpha,0,1)*envelope*0.78`，然后上传 `controller_alpha`；当前不按 alpha 取消 draw。
- `modules/scene_engine/terrain/natural_shore_surf.gdshader:2,45-69`：`blend_mix, depth_draw_never`，最终 `ALPHA=texture_alpha*controller_alpha*feather*thin_wash*shore_zone`，最后才执行 `ALPHA<source_alpha_threshold` 的 discard。
- `assets/data/fidelity_island/shore-scene.json`：8 个 source mesh 的阈值均为 20/255；原 `surf_bart3.dds` 为 DXT3、128×128、8 级原 authored mip。不能换成普通 PNG 自动生成 mip。

可证伪 H-G1：生产存在足够多当前 `controller_alpha=0` 的可见 patch；省去这些必无片元贡献的 draw，可降低渲染提交/顶点与片元工作，同时保留同刻主/反射像素。

最小第一候选只针对**实际已发布的有限 `controller_alpha==0` 且实际阈值>0**。它与纹理采样、LOD、视图和阈值附近舍入无关：所有片元原本均被 discard，shader 不写深度，且该 Node 不投射 shadow map。未知值、被替换 shader/纹理合同、非正阈值均保守保留原 draw。

第二候选才扩大至 `float32(controller_alpha)<float32(source_alpha_threshold)`。需要先证明其余 alpha 因子都在 [0,1]、原纹理所有 mip alpha 也在 [0,1]，并按实际上传后的 float32 比较，保持严格 `<`，不可误用 `<=`。不要把 CPU double 值与 shader float32 阈值直接比较。此扩大范围不是第一实验的隐含一部分。

实现与接受限制：

1. 保留全部 Node/mesh/material/packet、source sampler、随机序列和时间。只取消已证明透明的 draw；不可删 patch、冻结 controller、减少波面网格或改变阈值。
2. 显隐必须跟随**实际材质发布**，而非诊断求值。现有 `apply_snapshot:218-237` 与 `_write_material:242-247` 支持离屏 staging、同刻重入补交；`diagnostics` 可更新数值但不应改可见状态。显示和提交 alpha 若脱节，会造成漏浪。
3. 新 accepted time、同刻 diagnostics 后重入、暂停转镜、rewind、epoch、configure/dispose 与原 frustum union 都要覆盖。不能只更新从隐藏变可见的单方向状态。
4. 先统计每帧 owner/patch 总数、真实视图可见数、alpha 零值数、阈值以下数、显隐写入次数，证明该 predicate 在当前 r6 场景有实际机会。
5. 冻结相同 accepted tick、相机、seed、wave/tide 和全部 r6 资源，连续跨越零 alpha 与阈值边界。原 shader/controller 值和所有 mesh arrays 相同；主/真实反射同刻 PNG 应零字节差，并有正贡献控制，防止在空海/无岸画面上获得空洞通过。
6. 先记录 draw/primitive 减量，再串行交替 quiet A/B 记录 CPU 提交、主/反射 GPU 和正式 interval 全样本；截图读回放计时后。若显隐 setter 成本抵消 draw 节省，也如实保留结果。

这比直接合并透明网格更适合作为第一单因素实验：它不改变任何仍贡献颜色的 patch 排序。当前只读尚未统计 r6 每帧符合条件的 patch，不能预测节省毫秒。

## stencil compositor：已有 cache 与剩余重复工作

源码链：`source_shadow_renderer.gd:23-32,35-67` 挂到**主相机** compositor；`source_shadow_compositor.gd:11-13,26-52` 在 POST_TRANSPARENT 使用 resolved color/depth；`source_shadow_rd.gd:137-159` 已按 caster id+geometryRevision 缓存 vertex/index buffers。不要把它误判为每帧全量重建每个体积 GPU mesh。

可独立检验的 H-G2：`source_shadow_rd.gd:172-175,194` 每次 render 新建 depth sampler uniform set，draw 后立即释放，即使 depth RID/尺寸稳定。按 render device、shader、sampler、depth RID 缓存有效 uniform set，可减少 render-thread CPU/driver 资源操作；这首先是 **CPU 提交假设**，没有证据可称其降低 GPU stencil raster 毫秒。

最小候选须保留 per-eye/pass 的 depth identity；resize、内部 render target 换代、依赖删除、dispose 都要有效失效。缓存必须检查 `uniform_set_is_valid`，不能把仍非零的失效 RID 当活资源。现有 `_device_owns` 注释已指出依赖删除风险。

当前 GPU draw 为每 caster increment/decrement 两遍，末尾一个全屏合成 quad（`source_shadow_rd.gd:182-192`）。有明确源顺序合同：先完成同一 caster 双面，再处理下一 caster，使用 clamped stencil decrement。**不能直接把所有 front draws 合成一组、所有 back draws 合成一组**；源码 `183-184` 已说明结果会变。也不能任意改 wrap stencil、z-fail、剔除或 receiver 条件。

已存在的 backend 私有全尺寸 D24S8（不支持则 D32S8）attachment、每 render depth/stencil clear 与 fullscreen quad 都需要 pass 级计时。scissor/conservative projected bounds 是后续候选，但相机进入体积、near-plane clipping、无限/大范围 extrusion、多 caster 相交必须 fail-open；不能按船 hull 屏幕 bounds 裁阴影体积。

Resolved 开销：官方 [CompositorEffect](https://docs.godotengine.org/en/stable/classes/class_compositoreffect.html#class-compositoreffect-property-access-resolved-color) 明确 `access_resolved_color/depth=true` 在 MSAA 时分别触发 resolve。当前 effect 在 volumes 为空时才从回调早退；这不是已证明 engine 可以省略 resolve 的证据。可先记录 caster count 与 render graph，再实验只在确实无 caster 的帧停用该 effect，同时保留首次激活、重入、target lifecycle；有有效 caster 时不撤销必要 resolve，不降低主 MSAA。

海水本身也读 screen/depth，仍有其他 resolve/backbuffer 依赖。即使空 caster gate 成功，实际省掉几次 resolve、是否本来共享，以及收益多少，都需当前引擎 pass/资源证据。

## 海水、反射与带宽

`reference_island_water/ocean_renderer.gd:76-81,104-137` 只有一个共享 World3D 的 mirror SubViewport；宽度上限768，按主视图比例得432高，默认无 MSAA。镜面排除 WATER_LAYER，并复用实际相机投影/环境。`_sync_mirror` 不复制主 camera compositor，所以不能从主 source-shadow hook 推断它也被同样执行两遍。实际 reflection 光照/普通 shadow map 成本仍以该 viewport 查询为准。

反射本来 2.779ms；关闭它、降分辨率、低频更新或删远处 actor 会损害已接受的倒影及动态合同，且无法解释主 GPU 27.403ms。先保持原反射。

`projected_ocean.gd:332-343,169-208` 的 `set_simulation_time` 与 `update_projection` 都同步 optics，重复写多项静态/动态 uniforms、镜面 camera/viewport 属性。这是**CPU 提交重复**；`UPDATE_ALWAYS` 的同一个 viewport 不是因此每帧画两次。合并此同步须保留同刻 camera、设置、tide 和 invalid camera 分支，不能由 setter 数量推断 GPU 提升。

`projected_ocean.gd:386-427` 生产80段网格有6561个顶点/12800个三角形；相机移动时 `_upload_grid` clear/add surface。它是可能的 CPU/资源提交 seam，可用已有 DynamicSurfaceBuffer 风格保留静态 index/UV/normal 与 vertex count，仅更新原 position bytes；先测同拓扑更新成本、AABB与像素。不能把减段数当等价优化，也不能忽略 `Coverage.project` 原数值合同。

主水 shader 路径包含真实成本，但缺 pass 计时：

- `reference_game_water.gdshader:73-95` 对 scene 与 mirror 各手动取4 texel，逐 texel做原 display-domain转换再双线性过滤。换成单个 HDR-linear `texture()` 会改变过滤色彩合同。
- `:132-141` 三个 normal mip band，另有几何五波 normal 与光学过滤五波 normal；近景要保持实际波面、远景要保持既有抗闪烁，不能用顶点插值 normal 替换。
- `stochastic_alpha.gdshaderinc:13-41` 每个 stochastic mask 使用3次 textureGrad及世界稳定随机旋转；glint、flecks、原 sparkle、whitecap 和岸边残沫分别使用它。这些用于已接受的去平铺/抗闪烁，代码长不是根因证据。
- `surface_layers.gdshaderinc:9-31`、`reference_sparkle_fusion.gdshaderinc:11-34` 在读 mask 后才乘最终可见性；`coastal_visuals.gdshaderinc:42-109` 在大量计算后才乘精确为0的 coast zone。**精确零因子短路**可作为 H-G3，而非减少可见层。应先把 UV gradients/fwidth 在原控制流外计算，再传显式 gradients；否则 early branch 可能改变相邻 fragment 的导数和 mip。保持所有非零输出逐步相同，先检查编译产物是否本就消除了这项工作。

H-G3 的最低风险顺序：先做源码/编译器统计与原海水 pass 时间，再选一个精确零 gate 独立实验；不同时改水色、反射、foam 和波浪。预转换 screen/mirror 目标再硬件过滤有潜在重复计算收益，但新增全屏 pass、纹理带宽、格式/舍入和 lifecycle 风险，优先级低于证据清晰的零贡献 draw。

## 岸浪合批：第二阶段，不把1704当drawcall

既有 [shore/cloud 后续设计](../../../shore-cloud-job-contract-2026-10-21.md) 已正确提出“岛×texture×有限岸段空间 cluster 的原 indexed grids+float state table”。当前源码仍为独立 patch；此候选尚未落地，不能列为现有优化。

已有 GPU06 只作为历史计数参照：`shore/culling-gpu-06/receipt.json` 三个近景案例 baseline/candidate 都是 main46 drawCalls/177267 primitives，reflection99/164870；noShore为 main20/176431、reflection73/164034。该画面实际岸浪增加26个 draw/836 primitives，主/反射各如此。**1704是全世界 patch 对象数，不是此画面、更不是r6-c的实际drawcall数。** GPU06 另排除crew/UI/forest，与当前 r6 时刻/相机不同，且没有此处的 pass 时间。

合批应在当前 pass/draw 数据证明它值得后再做。保留全部原细分顶点/UV/index字节、mips、纹理RGB、blend_mix/depth_draw_never、priority4、source clock和源阈值。透明纹理不是纯白，混合不具交换性；主/反射排序可能不同。不能把所有岛合成一个粗大AABB，也不能用单个四角quad替代原细分grid。

## 下一次串行测量的最小清单

1. 保留 r6-c baseline 及全部 source/resource hashes；同机、相同电源/backend/driver、1600×900、MSAA、相机、seed、3船35船员。先补当前每viewport visible objects/drawCalls/primitives，已有 `tools/capture-shore-frustum-culling.gd:194-199` 可提供读取模式。
2. 记录实际 source-shadow caster/cache/upload/draw count、每patch实际上传alpha与可剔除计数、ocean/reflection开关和实际目标尺寸。不要每帧调用巨大完整 diagnostics，使用固定容量 scalar counters。
3. 用渲染器/pass级GPU计时或受控外部capture区分 opaque/shadow、ocean transparent、shore transparent、source stencil/composite、resolve/copy和post；CPU bind/submit timers另列。Render graph查看与GPU计时会干扰正式quiet interval，应分开跑。
4. 先实验 H-G1 zero-alpha取消draw，再选 H-G2 uniform cache；每组只改一个因素。H-G3和透明cluster需要各自独立冻结候选。
5. 保存同刻有贡献的主/真实反射基线与候选、零字节差检查及连续跨阈值/重入序列。GPU06已有原始失败与scope，复用方法不扩张其证明范围。
6. quiet性能A/B至少交替两轮，暖机后保存全部样本、nearest-rank p50/p95、失败/排除原因和原始行；最终仍以普通菜单正式试航 interval验收。小实验GPU改善不自动等于游戏60FPS。

结论：最先值得验证的质量保持 seam 是“原本必被 alpha 阈值 discard 的岸浪 patch 不提交 draw”。最大剩余GPU owner尚未通过pass计时确认；RD uniform cache和重复optics同步属于可独立检查的CPU提交成本，反射降质没有依据。所有候选在本记录中均为未运行。

## 本次读取的关键版本

SHA256 是本次只读审计取得的当前文件散列，不覆盖历史回执的源版本，也不代表运行验证：

```text
39e8f3a586928a8617fbc9740ebcc89c02725cbac72f3a740d5ba33573a5f915 modules/scene_engine/terrain/natural_shore_surf.gd
d8d84a4290042a885bf4c7c05ed0479f64084bea7dc60a3f1dd90b8619a0b45b modules/scene_engine/terrain/natural_shore_surf.gdshader
0ba3b42c937d531203e1c8e277143d3c61e38c0991fdc4f631681e0e2cf99402 modules/scene_engine/fidelity_fx/source_shadow_rd.gd
de5d167166d9c73225347888fc18108e33906327ec28313e7c56c07c9ab26481 modules/scene_engine/fidelity_fx/source_shadow_compositor.gd
4c84499ae82e432ec7ea845602af906ef36815cafda41ec30ea6a0322e277cae modules/scene_engine/ocean/projected_ocean.gd
e78e6fa52f11f5bfe456d0573378d04a6f009c49b6bead46a0a1bcd0331f7f1d modules/scene_engine/ocean/reference_game_water.gdshader
671c601550f4d314bb9e35a6f9b3340d47a4c6a6cc9001577c7d387d51cb250e docs/production/hero-fuchuan-2026-10-26-art/perf-r6-c/live-observation.json
```
