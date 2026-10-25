# 阴影轮廓边索引：保序奇偶抵消与 CPU 热点修复

## 2026-10-26：实验使用生产实际选定的投影网格

原创福船R6保留高精可见网格，通过`target_shadow_geometry`元数据选择独立代理。生产Adapter已消费该合同，实验的Prepared输入仍读取`mesh.mesh`，导致两条路径在比较不同输入。全量首轮中原实验10断言/2失败；独立夹具逐个证明deck/hull/三桅准备输入错误，7断言/5预期失败，记录保存在`architecture-convergence-2026-10-21/billboard-reuse-20261026/shadow-proxy-red-01-process.json`。

修复仅使实验按与生产Adapter相同的元数据/回退规则选网格，保留actor、姿态、投影与所有原算法。原120帧配对实验修后10/0，五代理夹具7/0，见同目录`shadow-proxy-green-01.json`。新增`tests/test_laboratory_shadow_proxy.gd`保留合同。这里是CPU与实验接线复验，不宣称此次另做了阴影GPU观感或完整游戏性能验证；既有GPU记录保持原范围。最终全套回归重跑仍进行中。

## 2026-10-14 最新补充：通用 target 有向边重数修复

以下为后续新增证据，不把前文历史“尚未GPU”阶段改写为当时已验证。root 的单caster候选已通过真实GPU：同24s远线像素158→0，近船阴影29→22；actual backend回读targetCalls=alteredCalls=8、rejectedCalls=0，仅补2片侧面，原positions/indices前缀及direction保持不变。[原始对照](../../../docs/research/evidence/shadow-edges/DIRECTED_BOUNDARY_GPU_COMPARE.json)。随后root运行未注入候选的正式通用路径：[production DIAGNOSIS](../../../docs/research/evidence/shadow-edges/directed-boundary-production-20261014-r1/DIAGNOSIS.json) valid=true，同24s四张原帧，activeCasters44、addedSides4、errors空；同ROI远线0、近船22，与隔离候选一致。

后续[普通自由试航六帧](../../../docs/research/evidence/wake-flow/interactive-production-1/final/GPU_VERIFY.json)同样valid=true、failures空，时间0/4/12/20/30/30s，每帧activeCasters及volumeCount均81；addedSides为30/30/34/26/30/30，各层shadow errors均空。root亲看cruise/turn/stop原图确认长线消失、双尾保留；30s暂停画质重建前后classification与boundaryBuilds不变。该运行无候选shadow backend注入。六张状态截图与固定诊断场景都不是完整游戏帧时间或全场景像素等价证明。

H9：以原caps的有向边整数重数减去原侧面已有贡献，把非零余额作为缺失侧面追加到原volume末尾。新 `game/presentation/world/target_shadow_boundary.gd` 继承原PreparedRigid，target adapter统一实例化该子类，无caster ID、模型名称或类型过滤。保留所有源vertices/indices原前缀和方向；已有apex直接采用原结果。原side数量为0而caps非空时，在全部原cap顶点之后追加apex，不改变原index0。超过65535顶点的修复不展开，不截断/丢caster：继续显示原完整geometry，并由boundaryError明确报告未修补限制。

原Math、RD shader与Prepared源代码不变。SourceShadowRenderer及PreparedShadowFrame通过既有具体基类、输入identity与输出ownership合同接收该子类，仍共享递归冻结的当前geometry。换mutable holder继续回原Math。仅原immutable indices对象随精确face-sign拓扑变化时扫描caps/edges；同符号微小light变化复用修补indices，仅更新原f32 apex及冻结的顶层位置列表，不新增逐帧全局边扫描。

预先反例与验收：零side非空caps、同向两/三/四重边、反向抵消、正常闭合边界不变；原prefix逐元素保持、旧publication不变、缓存计数不随同拓扑light增长、无名字过滤、uint16上限不丢caster。实际行为RED51断言/14失败→GREEN57/0（构造出新增几何后多执行6个检查），shadow10文件全通过。首次完整回归中旧target“完整Math相等”断言36项失败，属于本次明确追加修补与旧目标等价合同的差异；最终保留generic Prepared完整oracle，target无补边要求完整相等、有补边要求原positions/indices/direction前缀精确相等。失败回执均保留，不掩盖为原Math视觉等价优化。

[完整基线、候选源码及RED/GREEN/回归](../../../docs/research/evidence/shadow-edges/target-directed-boundary-20261014/manifest.json)；[生产接缝与诊断报告](../../../docs/superpowers/plans/playable-voyage-work/t2-target-shadow-boundary-report.md)。公开 `scene.sea.source_shadow_status().casterAdapter` 新增boundaryBuilds与addedSides，errors包含上限限制；计数应在实际volume提交后读取。通用生产GPU固定场景证据见上文；未测性能，不用缓存断言宣称整场加速。原cap绕序问题不混入本次修复。

[独立只读审阅](../../../docs/superpowers/plans/playable-voyage-work/shadow-directed-boundary-review.md)无阻断发现：独立复跑boundary57/0、preparation546/0，冻结源码及未改的Prepared/Math/RD哈希一致；审阅原图后确认正式all-retained/stencil-off与隔离候选对应图文件哈希相同。rigging-hidden实际匹配0节点，因此不作为有效消融；超uint16回原输出仅保留功能与诊断，不宣称该输入已修复。

## 2026-10-14 后续实验预注册：刚性数据准备与不可变提交

状态：研究中，以下为修改前假设与接受标准。独立实验拟用 `game/research/demos/shadow_edges_experiment.gd`，仍归属原 `shadow-edges` 课题。

root 新测 `Temp/playable-voyage-cpu-baseline.json` 是 headless CPU 分段：sourceShadows p50约21.18ms（compose约8.04、submit约12.82）、world约29.20ms。不是 GPU draw 或完整帧FPS。五个现有shadow测试本轮基线全通过（`Temp/research/t2-shadow-baseline.json`）。

H3：每帧仍做相同 `face.normal.dot(local_light)` 精确分类，但只在全部面的朝向位模式改变时重建保序edges/caps，可减少稳定silhouette重复工作，不用光向阈值、不跳帧。

H4：目标刚性geometry只在准备时校验和f32化固定源点。相同topology的输出点/indices可冻结复用，逐帧仍按原Math的两次f32与1e9运算求direction及apex。顶层输出和apex每次新建并冻结，不修改旧frame。

H5：保留公开compositor.submit默认deepcopy；仅专门prepared frame凭证可在render thread共享已递归冻结的geometry。generic mutable caster继续原Math及deepcopy，不以声称只读的bool省略验证。

预先接受：ordered edges/caps和Math完整输出精确相等；同侧微小light变化不重建拓扑但direction/apex必须改变；跨面符号变化重建，包含零点边界；旧frame在下次更新、输入holder修改、epoch/reset/dispose后逐字节不变；伪造/被替换positions或edges不能进入prepared快路；默认submit仍隔离mutable输入。固定同三船姿态、seed9713、1/60s，比较120帧成对纯CPU compose+volume原始样本与p50/p95（nearest rank）。任何性能结论只限该范围。GPU/lifecycle由root另测，未测项保持未测。

替代方案：原Math每次完整验证/重建是oracle；量化光向或降频会改精确输出，拒绝；跨线程共享mutable数组有竞态，拒绝。新方案增加明确的准备对象及冻结frame类型，释放跟随adapter/renderer/compositor原生命周期。

H6（独立GPU候选，未接生产）：root四图 `docs/research/evidence/playable-voyage-2026-10-14/ship-line-baseline` 中船上极细黑线仅在stencil打开时出现，mesh最大extent约24m，关闭stencil后消失。怀疑1e9有限apex进入clip运算引起精度/裁剪不稳定，尚未确诊。`tools/verify-shadow-clip-gpu.gd` 仅在独立driver替换backend subclass的volume vertex shader；正scale=max(1,abs(x),abs(y),abs(z))，改用vec4(position/scale,1/scale)。其投影在实数算术下仍为同一个有限点，保持原geometry、双面顺序、depth/stencil规则。先比较同一24s/相机原帧、保留真实船下阴影；若黑线未消失或正常阴影改变则拒绝，不修改生产RD。

H6结果：root实跑 `normalized-clip-candidate-20261014` 退出0/无错误，亲看all-retained黑细线仍在；拒绝此候选，生产shader保持原版。下一步两个分开的单因素诊断：`tools/verify-shadow-receiver-gpu.gd`仅拒绝reverse-Z空receiver=0，1e9几何不变；`tools/verify-shadow-finite-apex-gpu.gd`仅在独立GPU upload将apex改为距首点10000世界米，原Math与所有source数组不变。不把后者称精确同像素优化，先检验巨大挤出是否因果，再决定有界表示是否合法。

诊断有效性补充：root随后两候选均正常退出，但黑线仍可见；因为首轮driver没有记录实际shader/upload处理路径，这只能证明观察图未改善，不能判定各算法已被有效反证。远海ROI `[250,0,470,390]` 相对各自stencil-off，RGB每通道均变暗>10的像素：baseline158、normalized158、receiver158、finite156。driver现经 `shadow_candidate_probe.gd` 在render thread回读实际backend id/script、shader SHA/compile命中、draw/upload/candidate调用数；有限apex还记录修改计数及前后世界米长度。先取得非零处理回执再继续推论，生产RD仍未改。

背景资料仅用于制定下一假设：[NVIDIA GPU Gems 3第11章](https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows/chapter-11-efficient-and-robust-shadow-volumes-using)说明z-pass对相机所在体积、面定向和近远裁剪有约束；其推荐的无限齐次点/深度钳制与当前Godot私有stencil实现并非同一已验证合同。不能从读到这些技术直接宣称本项目故障根因或更换算法完成。

CPU结构诊断（不是GPU修复结论）：真实福船44个caster，将原Math output按精确位置焊接，逐个累计每条无向边的有向出现符号，43件存在非零有向边余额。原Math侧面为`[b,a,apex]`、封口为`[c,b,a]`，target adapter向两者传相同原face方向，near boundary因此同向出现两次。独立仅反转cap输入后41/44完整有向闭合；`native_hull_56_component_00/09/10`仍有局部同向/非流形边。原始 `followup/t2-shadow-closure-diagnostic.json`与复现脚本保留在本轮证据目录。此诊断揭示现有精确Math oracle没有覆盖目标几何合法性；是否对应长线仍需已证明执行路径的GPU单因素对照，生产输入/Math尚未据此改变。

H7预注册：root新的 `finite-apex-readback-20261014/DIAGNOSIS.json` 已证明finite候选实际生效（all-retained meshCalls336、alteredApices336，原最大世界长度约1e9、候选10000，draw680/upload42），但线仍在。因此下一单因素是near cap绕序：只交换原Math output中cap三角形的第1/3索引，所有side indices、positions、direction、1e9 apex、组件与stencil政策不变；不剔除非流形组件。通过字面单三角夹具及真实船输出证明旧输入未改变和有向闭合改善，再用已带render-thread回执的相同24s四图比较。预先接受：远海ROI黑线指标显著减少/消失、船体正常阴影保留、candidate cap修改计数非零；若失败不接target adapter。生产RD/Math保持原版。

H7结果：独立CPU95断言通过（44caster、933cap三角，43件方向不闭合降到3件），但root `cap-winding-candidate-20261014` 实测alteredCalls336后远线仍在，未接生产。这与cap仅覆盖船体投影附近、无法直接改变远处side triangle像素相符。后续定位工具 `tools/diagnose-shadow-casters-gpu.gd` 只向真实compositor提交按原顺序二分的caster子集，所有mesh/船保持显示；每组保存同24s原帧、与stencil-off的固定远海ROI/近船ROI像素差、GPU实际cachedMeshes与源码hash。只递归产生远线的组；若组合有线但两个子组单独无线，明确记录interaction，不误判单个caster。最后恢复全部casters并要求原ROI结果复现。此过滤仅诊断，不是生产删影。

H8定位与候选（2026-10-14，尚未GPU验收）：[实际caster二分](../../../docs/research/evidence/shadow-edges/caster-isolation-20261014/CASTER_ISOLATION.json) valid=true，12组中唯一阳性为 `player:native_hull_56_component_03`；单mesh保留全部158远线像素，其他组0，无组合interaction。它属于fuchuan当前映射的barque源外观，`barque-lowend.nif` 的源mesh56 `hull:2`。只读工具 `tools/inspect-shadow-caster-topology.gd` 重建同一Main/fidelity-island的24s状态，提取40焊接点、44源面、26轮廓边、16caps；实际光方向下源面15与508（组件面7与33）均选中，同向共享焊接边 `4→12`。第三个关联源面18反向、未选中。现有无向奇偶toggle错误地把两条同向共享边一起抵消，导致轮廓顶点4/12有向度数为-2/+2，挤出后两条apex边无法相消。

边端点局部坐标为 `[-0.0986835361,3.6276154518,10.6442127228]` 与 `[0.1036706865,3.6276154518,10.6442127228]`，屏幕投影约 `[476.6685,426.3837]` 与 `[476.3328,426.5207]`。延伸到apex的两条直线在y=0交于x=286.625/286.225，在y=390交于x=460.452/460.055；不足0.4像素宽的裂缝位置与实际远线bbox `[286,0,459,388]` 对应。这是实际源边及数学缺口证据，仍不能代替候选GPU像素验证。

H8单因素候选 `game/research/shadow_directed_boundary_candidate.gd` 从既有caps的源顶点次序计算有向边整数余额，扣除原侧面已提供的边；仅追加缺失侧面。对实际culprit只追加同向边4→12的两片side三角，保留全部42原三角、全部原顶点/1e9 apex/方向、cap绕序与shader；不混入H7、不删任何caster。原Math及正式target adapter完全未改。CPU反例先运行旧输出12断言/4失败，再运行候选16断言/0失败，实际apex有向不平衡总量4降到0。初次测试另有convert内建函数名冲突和整数字面数组与f32数组比较错误，均保留失败回执，不算算法RED。

[只读拓扑、RED/GREEN、源快照清单](../../../docs/research/evidence/shadow-edges/directed-boundary-cpu-20261014/manifest.json) 已保存。最终 `shadow` 相关9个测试脚本全部通过；生产adapter/Math/RD的SHA256与caster二分GPU时完全一致。GPU候选仅通过Godot headless `--check-only`，没有执行图形后端。

后续GPU由 `tools/verify-shadow-directed-boundary-gpu.gd` 仅对上述caster应用候选；保留同24s四图及render-thread `meshCalls/targetCalls/alteredCalls`、新增边及重数、原positions/indices前缀完全不变、shader/source SHA256回执。接受条件：处理计数非零且缺边恰好两片，远线158像素归零、其他正常阴影保留。用户当前优先尾迹研究，本候选仅准备并解析检查，未运行GPU、未接生产。

未来生产修复边界应在 **target adapter/prepared target geometry** 的轮廓构造：反向边可抵消，同向边保留整数重数；源 `SourceShadowMath.toggle_edge/build_volume_component` 保持既有有限oracle合同。不得直接替换通用Math或把本诊断append补片按caster名字硬编码入游戏。正式实现需一般有向边不变量、所有船型/姿态与实际GPU验收；cap绕序为独立问题。参考 [GPU Gems 3 §11.3.1](https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows/chapter-11-efficient-and-robust-shadow-volumes-using) 对开口/非流形及不一致绕序的讨论：它支持先核查网格前提和保持有向闭合，不证明本候选已完整实现其鲁棒算法。

### 本轮 CPU 执行结果

[2026-10-14T105017Z-prepared manifest](../../../docs/research/evidence/shadow-edges/2026-10-14T105017Z-prepared/manifest.json) 保存源码SHA256、基线原件、RED/GREEN、成对原始samples与压缩的完整世界profile。原Math及生产RD shader的SHA与基线相同。状态：CPU精确等价验证通过，性能候选已接原adapter/renderer seam；GPU及黑线candidate尚待root验收。

- `PreparedRigidShadow` 在configure时复制并f32化源点、复制face indices；向外发布的source/edges/caps/volume所有嵌套Array与Dictionary均read-only。每帧原Vector3 dot逐面分类；仅bit-pattern变化重建ordered拓扑。light变化仍按原Math两次f32构造direction和有限apex，旧output顶层数组不修改。
- `SourceShadowRenderer` 仅接受具体prepared类型且positions/edges/caps为同一对象、light匹配、非skinned时走准备路径。替换mutable位置holder后立即回原Math。`PreparedShadowFrame` 仅共享prepared owner所证明拥有的当前不可变输出；其它容器递归复制冻结，拒绝Object/Callable/Signal引用。公开`submit()`仍deepcopy；新`submit_prepared()`只接该凭证，render callback/RD算法没有改动。
- 有意义RED：新准备组件缺失；隔离helper基础测试通过后，实际compositor准备接口缺失仍红。最终 `t2-shadow-final-contracts.json` 七文件全部通过；新增准备546断言，独立demo9，原ordered edge5498、原Math177 checks、gates27；renderer/lifecycle各failures=0（原脚本未打印断言数）。最初新测试check返回类型错误单独保留，不能作产品RED。
- 独立真实福船44caster、120帧，前12帧按预注册规则排除；本轮最终108个样本：原Math volume p50 4.767ms、p95 6.096ms；prepared（包括精确classifier）p50 0.593ms、p95 0.886ms。5324次分类仅50次拓扑重建，完整geometry mismatch=0。原始文件 `t2-shadow-volume-paired-11444.json`。早期临时固定名raw文件曾被全套复跑覆盖，不能追认为首次独立性能数据；测试现使用进程ID唯一输出，并保留已存在文件。
- 正式自由试航生产组件headless profile12样本：shadow wrapper p50 21.178→5.663ms，p95 22.684→7.940ms；compose8.036→2.364ms、submit12.815→2.533ms。这是CPU分段；该轮world p50反而29.198→38.863ms，其它stage、并发工作和源文件存在变化，不能报告整场加速百分比或60FPS。
- 本轮GPU黑线候选只通过脚本check-only，尚无本agent执行的图像结论；root已保留独立stencil开/关原帧。其结果与CPU等价优化分别验收。

独立Demo `game/research/demos/shadow_edges_experiment.gd` 已实现统一host合同与control_spec：真实船型、prepared/oracle开关、固定镜头、暂停/重置/释放；固定tick推进原船姿态、局部光变化、准备路径和原Math逐项对照。平面接收面是明确的诊断场景，未加海面/船员，不代表完整游戏负载。root负责统一目录登记和GPU/PCK。

- 课题：`shadow-edges`；整理日期：2026-10-14；报告类型：既有优化的事后工程整理。
- 历史状态：目标刚性 hull/mast adapter 已有历史集成与 oracle 回执；首次事后整理没有独立 Demo。本轮追加实验与当前状态见前文。
- 摘要：用无向整数边到 slot 的索引替代线性扫描，同时逐元素保留原方向、奇偶取消和 swap-last/pop 顺序。
- 主要来源：[动态与性能修复报告](../../../docs/migration/hull-dynamics-2026-10-14.md)、[adapter 源码](../../../game/presentation/world/target_rigid_shadow_caster.gd)、[原 Math](../../../modules/scene_engine/fidelity_fx/source_shadow_math.gd)。

## 问题与假设

真实自由试航分段发现阴影 CPU 链均值约 83ms。目标 adapter 在 dirty silhouette 构建时，对每条面边调用原 Math 的线性查找取消；大量不抵消边导致最坏 O(E²)。

假设 H1：索引只替代查找位置，保留边数组的原始更新顺序，可以获得期望 O(E) 构建，同时保持提交到原 volume Math 的输入完全相同。

假设 H2：验证必须比较 ordered edges、caps、positions、indices、direction 与 counts；仅比较无向集合或最终阴影轮廓图会漏掉影响原输出的次序变化。

单位：CPU 调用耗时与 wall frame interval 为毫秒；位置为目标模型单位经世界 transform 映射到米；边 ID 为整数。Math 的 `1e9` 挤出常量是有限源构造合同，不解释为物理阴影距离。

## 方案比较

- 原线性 `toggle_edge`：顺序语义明确，适合 oracle；对每边遍历当前数组，最坏二次成本。
- 哈希集合计数后重建列表：可计算奇偶，但丢失方向和 swap-pop 顺序；不满足当前等价要求。
- 排序去重：可得到确定集合，却改变原次序，增加 O(E log E)；同样不满足。
- 无向 key 到原数组 slot 的 Dictionary：期望常数查询；删除时更新移入的 last 边索引，可原样保持数组语义。当前采用。
- 更换 shadow map/caster 数量：可能更快，却改变画面及场景政策，不是本次边查找优化。

首次索引优化发生在目标刚性 caster adapter；当时原 Math、volume 投影数量、renderer/compositor 与 caster 选择规则继续使用既有实现。本轮后续准备路径的边界与逐项验证见前文。

## 算法与实现

`_toggle_indexed_edge` 先将端点 `a/b` 按 `&65535` 归入 uint16；key 为 `(min(a,b)<<16)|max(a,b)`，存入 int64，无 float hash 精度丢失。

若 key 已存在，取得 slot，把 last 边移入该位置（当 slot 不是 last 时），更新移入边的 lookup，pop 并删旧 key；不存在则存新 slot 并 append 原方向 `[a,b]`。

```text
a = a & 65535; b = b & 65535
key = (min(a,b) << 16) | max(a,b)
若 lookup 存在 key：
    i = lookup[key]; last = edges.size - 1
    若 i != last：edges[i] = edges[last]; 更新被移入边的 slot
    pop edges；删除 lookup[key]
否则：lookup[key] = edges.size；append [a,b]
```

Dictionary 给出期望 O(1) 查询，整次构建期望 O(E)，额外空间 O(E)；不宣称哈希最坏情况的严格线性界。奇偶抵消适用于相同或反向出现，残留方向由当时 append 决定。

adapter 配置时对实际三角 mesh 做精确位置焊接，去除 authored UV seam，跳过退化面。每 caster 缓存 geometry revision 与 local light；变化时重建 edges/caps，退出清理 cache 并恢复原 shadow mode。

实际 mesh 的点数必须小于 32768，volume `1 + 2*edges + caps` 不超过 65535；非法值拒绝。对面朝向和 caps 次序的选择保留原目标规则，不通过“近似相同”放宽输出。

[SourceShadowMath](../../../modules/scene_engine/fidelity_fx/source_shadow_math.gd) 继续在 f32 存储边界构造 apex、面片与封口；[renderer](../../../modules/scene_engine/fidelity_fx/source_shadow_renderer.gd) 和 [compositor](../../../modules/scene_engine/fidelity_fx/source_shadow_compositor.gd) 保持 RD stencil 与提交合同。

## 实验设计

[ordered oracle 测试](../../../tests/test_target_rigid_shadow_edges.gd) 每步同时调用未改的 `Math.toggle_edge` 和索引版本，精确比较完整数组；独立以 `min*65536+max` 编 key，验证 lookup 的移入 slot。

输入包括取消/重现、反向、uint16 别名、负端点、跨边界端点，seed=9713 的 2048 步随机序列；实际船型姿态/LOD/移除/重现，以及 2048 个不相连三角形的大 mesh。

对每个实际 caster，用原线性 Math 重新生成 edges/caps，比较 ordered 输入与完整 volume 输出。此测试使用目标 mesh 的相同几何，不宣称原未知 classifier/skinning 已闭合。

历史真实世界 profiler 经正常 Main/router 进入自由试航，保留所有对象；诊断冻结自动回调后，按 1/60 秒推进实际 runtime，暖机 12 帧，采集 12 个 fresh 分段。源 call 为 32Hz，不能把混合 contact p50 当 fresh 成本。

- 接受标准：oracle 所有数组逐元素相等，lookup 正确；缓存失效、移除/重现、gate 与释放不回归；任何失败先阻止集成。
- 性能对照：保持船数、帆装/LOD、画质、相机、光方向、地形、操作序列；记录源码与工具 SHA256。
- 指标：dirty compose、submit、shadow wrapper、world、实际 frame interval 分别给 raw samples、均值、p50/p95；父子计时不重复求和。
- GPU 接受：实际 stencil 初始化、画质切换、清理与最终截图另测；CPU oracle 不证明 GPU 像素或 draw duration。

## 结果与证据

历史 [shadow-regressions](../../../docs/migration/evidence/hull-dynamics-2026-10-14/shadow-regressions.json) 五脚本无失败；新增 edge 测试为 5498 项，450 个真实/大 mesh caster，83,339 个 volume vertex。ordered edges/caps 与完整 positions/indices/direction/counts 精确匹配原 Math oracle。

真实世界 [修改前 CPU 分段](../../../docs/migration/evidence/hull-dynamics-2026-10-14/performance/world-cpu.json) 与 [修改后分段](../../../docs/migration/evidence/hull-dynamics-2026-10-14/performance/world-cpu-after-shadow.json) 的阴影 wrapper 12 样本均值为 82.9955→22.1387ms；后值 p50=21.755ms、p95=24.536ms。

修改后 compose 均值 7.630ms，submit 均值 14.459ms，完整 world 均值 31.034ms。submit 包含 renderer CPU volume refresh、纹理平面对账及 compositor 提交；不是 GPU draw 或 GPU readback 的测量。

历史正常入口的 240 帧 wall 间隔 p50 为 133.840→83.346ms；前后模拟区间和可见位置不同，只说明那些运行的间隔，不能算严格同画面的稳定提速比例。正式自由试航仍未达 60FPS。

硬件/后端来源：Godot 4.7.2、Vulkan Forward+、Intel Arc 130T。CPU 型号与温度/电源策略未在摘要中充分报告；重新比较要补全，不假定其他硬件复现相同数值。

以上是首次事后整理时读取的历史回执；不能将这些历史结果填入新run。新增独立实验、当前重新执行的edge/世界CPU profile与尚未闭合的GPU状态见前文补充。

## 局限与失败

- 优化只解决 adapter 的线性取消热点；剩余 submit/world 与其他 GPU/CPU 开销仍存在。
- 精确位置焊接与刚性 hull/mast 是目标政策；原 actor classifier、light producer、skinning 和全部场景资格尚无等价证据。
- uint16/signed edge scope 是有限边界，不支持任意大 mesh；不能截断过大 mesh 后称等价。
- 12 个样本不能证明长期稳定性；p95 接近极端值，重复实验需更长稳定窗口与成对原始样本。
- 不把阴影集合相等、无截图错误、微基准下降或历史 GPU 路径存在提升为整场 60FPS。

源字节 provenance 和有限 CPU oracle 散列见 [shadow manifest](../../../modules/scene_engine/fidelity_fx/source_shadow_assets/manifest.json)。外部研究目录是可选来源，当前 oracle 与实现均在仓库；不扩大源资源的使用或再分发许可。

## 集成与复现

先核对 [研究流程](../../../docs/research/README.md)，配置 `GODOT_EXE`；新回执写入独立目录：

```powershell
rtk proxy node tools/verify-godot.mjs --godot $env:GODOT_EXE --filter shadow --output Temp/research/shadow-contracts.json
rtk proxy $env:GODOT_EXE --path . --script res://tools/profile-hull-dynamics-world.gd -- --output=res://Temp/research/world-shadow-current.json
```

第二条需要真实图形后端，测的是诊断 CPU 调用，不是原生自动回调的完整帧性能。保留 raw records、源码散列和 scope；实际帧间隔另走普通菜单入口记录。

要重建前后比较，在独立副本加载保留的基线 adapter，并保持同一场景输入；不修改原 Math oracle、不覆盖历史目录，不从不同 run 的低点挑值。

未来任何边结构或 caster 政策改动先创建独立实验、注册论文/Demo，过 ordered oracle 与实际 GPU/lifecycle 验证，再集成正式 seam。失败回退 adapter，恢复原 shadow mode 与 cache 释放，保留失败回执及基线。
