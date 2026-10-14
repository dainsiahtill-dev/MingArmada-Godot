# 岸浪与浅滩：真实三角岸线、解析推进浪与源短浪对照

- 课题 ID：`shore-surf`；报告 v2.3，2026-10-14。
- 类型：既有正式算法的事后整理，加本轮独立实验夹具；不补造“先研究后集成”的历史。
- 状态：新 Demo 已完成修后 GPU、同刻因子与菜单生命周期验证。水岸羽化按用户后续反馈扩为宽度0.6／贴岸水色覆盖0.55，并接入共用正式海水材质。低机位原投影缺陷仍保留，不宣称全部视觉问题关闭。
- 摘要：复用正式厦门三角地形、生产五波海面与源岸浪，允许同一接受时刻开关解析浪、源短浪和岸边残沫。三个展示 seam 存在生产乘法耦合，不是完全独立的三套算法。
- Demo：[shore_surf_experiment.gd](../../../game/research/demos/shore_surf_experiment.gd)；测试：[test_laboratory_shore.gd](../../../tests/test_laboratory_shore.gd)。目录注册与统一宿主按环境课题计划执行。
- 历史来源：[柔和过渡](../../../docs/migration/reference-shore-foam-fusion.md)、[正式海面融合](../../../docs/migration/reference-ocean-world-integration.md)、[源场景及 provenance](../../data/fidelity_island/shore-scene.json)。原资源许可未由本研究扩大；运行不依赖外部参考包。

## 问题与假设

仅按水深生成白环会把水下沙洲当海岸；连续长 ribbon 拉伸源 alpha，可产生白垫、直线纹和折叠。正式短片/解析浪融合已经存在，但需要可同时间切换、重置和审阅的独立入口。

H1：源片读取正式257×257 Float32网格的同一 `a,b,c / c,b,d` 三角表面，沿零高度交线布置；海岸误差<0.0002m，相同输入重置得到完全相同packet、源状态和网格fingerprint。

H2：固定32Hz接受时间；暂停、镜头与展示开关保持tick、时间、源packet/状态、源调用数和geometry_builds不变。相机动作重新抽样或重新布置是直接反例。

H3：真实GPU连续时刻能够显示真实岛岸上的接岸/退场和不规则短片，各展示seam可以单独关闭或缩放。该假设不承诺三项数学独立，也不证明完整旧版本渲染或浅水物理等价。

单位：地形、岸距、深度、patch尺寸为米；世界Y向上、XZ为海平面；时间是宿主接受秒，初始0s。alpha、UV、展示强度与相位无量纲。Demo不修改地形、航道、浮力、存档或生产session。

## 方案比较

- 嵌入既有 `combined_island.gd` Control页面会引入第二viewport、UI和自动_process时钟，违反宿主单一时间所有者；拒绝。
- 空中圆环或替代水shader不受真实三角岸线约束，不能证明原效果；本轮不用。
- 直接复用整个WorldView接线完整，但森林、建筑、天气和船只扩大控制范围。
- 本轮直接组合生产HeightField、NaturalWorld、NaturalShoreSurf、ProjectedOcean和ShoreField；只取正式厦门岛，保留生产257网格、seed1661、五波、贴图和shader。独立场景没有船、船员、森林、建筑、天气或shore spray，scope明确限于岸浪展示。
- 旧64m连续ribbon的失败保留：源128px纹理拉伸、短三角梯度外推导致折叠。当前短quad保留UV/米比例；原迁移报告的反例没有删除或覆盖。

## 算法与实现

[ReferenceGeography](../../../game/scenes/common/reference_geography.gd)与[HeightField](../../../modules/scene_engine/terrain/height_field.gd)配置厦门中心`(-480,-60)`、半径`185×0.8=148m`、峰值输入58m、seed1661、257网格。[NaturalWorld](../../../modules/scene_engine/terrain/natural_world.gd)使用同一Float32三角权威与实际terrain mesh，不生成港口切水航道。

[NaturalShoreSurf](../../../modules/scene_engine/terrain/natural_shore_surf.gd)按无向顶点ID连接实际跨零高度三角边，沿累计弧长放源短quad。配置seed精确为 `hash([bounds.position,bounds.size,side,heights])`。Demo导出实际网格派生seed的int和decimal string，避免JSON53位精度损失；生产RNG只在configure局部存在，之后不保留state。accepted-time抽样确定性controller，不编造“当前RNG状态”。

实际span为`clamp(radius×0.08,6,14)=11.84m`；尺寸0.72–1.0倍、间隔0.8–3.2m、时偏0–30s、速度0.82–1.19。0/4、1/5、2/6、3/7源网格成对共位。alpha controller stop_time为29.96666717529297s；不同packet速度使整岛没有共同的这个循环周期。配置提取轮廓/网格O(N²)，源更新O(P)，N为网格边长、P为实际短片数；相机不重建海岸。

[源shader](../../../modules/scene_engine/terrain/natural_shore_surf.gdshader)使用原 `surf_bart3.dds` 全部mip、恢复控制器和`nativeAlpha×lifeEnvelope×0.78`展示alpha，阈值20/255。0.78、薄浪头、生长/侵蚀是本作适配；nativeFrontDistance是源恢复诊断，不是第二条渲染轨迹。源浪头重锚到海面解析相位，自身保留薄尾。

[ProjectedOcean](../../../modules/scene_engine/ocean/projected_ocean.gd)使用生产80段投影网格、五波和[reference_game_water](../../../modules/scene_engine/ocean/reference_game_water.gdshader)。ShoreField512在真实网格bounds外扩100m采样岸距，局部近岸高度纹理直接保存257网格，source patch自带同一数值网格。保留dry-terrain mask、折射与真实planar reflection；[有限海底羽化](../../../modules/scene_engine/ocean/reference_shore_foam.gdshaderinc)不改公式。

| 控制 | 默认 / 范围 | 实际展示变更 |
| --- | --- | --- |
| `analytic_enabled / analytic_opacity` | true / 1，0–1步长0.05 | `coastal_breaker_strength=0.36×effective`，缩放解析浪头、尾沫、接触lace |
| `source_enabled / source_opacity` | true / 1，0–1步长0.05 | 隐藏source owner，或将当前`controller_alpha`乘倍率；native状态/packet不变 |
| `residue_enabled / residue_opacity` | true / 1，0–1步长0.05 | `shoreline_residue_strength=0.38×effective`，同时控制edge_foam和解析项接触lace |
| `shore_edge_feather_m` | 当前0.6垂直米，0–0.6步长0.05 | 0为硬边baseline；同刻改变水色与不折射opaque scene的线性合成coverage，不改变岛或水的ALPHA、地形/时钟 |
| `shore_edge_water_weight` | 新实验候选0.55，0–1步长0.05 | “贴岸水色覆盖”；1为相同width的上一版效果，降低值只在部分coverage过渡带露出更多背景，0/1coverage端点保持 |
| `camera_mode` | close / close、edge、wide | 近岸浪带/俯视水岸交界/整岛固定镜头，支持orbit与zoom重放 |
| `paused` | false | 阻止接受时间推进 |

`*_opacity`是展示倍率；解析/残沫实际是颜色混合强度，source才直接乘alpha，UI据此标注。解析项包含已乘residue强度的lace，最终水色还取`max(edge_foam,surf)`；不声称三层线性独立拆分。residue开关不能移除source自己的薄尾。quality默认balanced，可配置low/balanced/high；live set_parameter返回`reset_required`，不暗中重建或复位。

用户指出沙滩与浅水硬边后，追加可控[shore_edge_coverage](../../../modules/scene_engine/ocean/shore_edge_coverage.gdshaderinc)候选，复用水面生产接线。首轮width0.35候选经真实原帧对照后，主线程将实验与共享shader宽度更新为0.6；新water-weight0.55仍是本轮研究候选，不把旧GPU结果冒充它的通过。width实际单位为垂直高差米；用户描述的宽度方向是图中垂直于岸线的过渡，当前模型通过地形坡度把高差映射成该岸段水平过渡距离，并非直接输入岸线法向距离。coverage依据`min(dry_clearance,water_clearance,optical_vertical_depth)`的非负部分，0到width内smoothstep，在terrain clearance从width到2×width逐渐撤销。最终ALBEDO在线性色空间混合不折射opaque scene与水色，水和岛仍ALPHA1，保留opaque/depth和dry-land gate；不是改变岛alpha或透明队列，不修改五波、height_at、地形网格或底部羽化原公式。

继续反馈“红框贴沙滩带要更透明”后，只改变过渡内部水色占比。新的helper为`weighted_coverage=c*(w+(1-w)*c)`，c是原coverage、w是shore_edge_water_weight。w=1严格保留相同width上一版；w=0得到c²；w=0.55、c=0.5时由0.5降为0.3875，更清楚露出同像素opaque沙底。c=0和c=1对任何w保持端点；深水/外侧浪头处若原coverage=1，完全不进入混合修正分支，源短浪alpha/controller也不被此控制改写。接岸区内最终像素效果及外侧浪头不变仍需新的GPU同刻同镜头A/B，不能仅凭material绑定声称已验收。

configure原子校验，挂树前返回pending、_ready同步构建。宿主将delta累积成1/32s，单次最多8步，超出追赶预算的墙钟时间丢弃；无自动_process/physics推进。reset重建唯一场景并清零tick/累积量，确定性比较不混入对象身份。开关直接缩放当前材料，不再次调用source；camera-only刷新投影/镜像。advance入口即使暂停也调用生产cached update_projection，另提供refresh_viewport纯展示刷新；宿主布局后viewport aspect变化不会留着旧网格，刷新不抽样source。dispose显式释放生产镜像renderer、本地节点及terrain/texture引用，允许重复调用。

## 实验设计

CPU固定输入：Godot4.7.2 stable、headless、独立World3D、960×640、balanced、0s初态、32Hz、seed1661、正式厦门网格。close焦点为eastmost实际源packet，朝向由patch outward决定，修后偏移海外36m/向上40m、约53.8m视距；wide仍330m/230m。FOV45°、near0.1m、far3000m。另重现实际UI尺寸1260×449，检查真实投影网格覆盖四边和真实岸线到24m推进浪区都在垂直视野中。inspection导出实际16值column-major transform/projection、viewport、orbit、zoom、参数和资源数，不能仅靠镜头标签重放。

edge固定俯视近镜头：焦点仍为实际coast+6m，offset为outward10m/up32m、约33.5m视距。首轮width A/B为0/0.35（附0.6），保持镜头、接受时刻、岛shape、source packet/state相同。新增weight A/B固定width0.6，其余因素完全相同，只比较weight1和0.55（附0/1端点），edge/低位/wide，接受时刻0、0.5、2、8s。检查红框贴岸带更透明及外侧浪头/外海像素不变；保存实际相机矩阵，不把低位harness覆盖称close preset。新weight候选另存唯一run-id，不覆盖之前width证据。

CPU接受：预挂树无资源、ready同步成功；两半步仅接受一步；192步=6s；暂停/开关/镜头保持完全相同source packet/state/调用数/时钟/构建数；海岸误差<0.0002m、实际材料倍率误差<1e-6；同输入reset完全一致；非法数/类型/未知控制原子拒绝；追赶最多8步；dispose实际镜像/源节点失效、资源归零。实现前先测试缺失Demo的RED，资源计数RED另行保留。

GPU计划固定1280×720、balanced、真实图形后端：close/wide，接受0/6/12/18/24s，同时间全开、analytic-only、source-only、residue-only、all-off，保存原帧及完整snapshot。检查真实海岸、短片尺度、接岸退场、无空中环/直格/明显折叠；因素切换不能改变controller。source-only关闭analytic/residue；analytic-only关闭source/residue；residue-only关闭analytic/source，此时解析lace被乘零，只留下edge_foam。CPU不能替代此项。

性能只能声明独立scope的configure、32Hz update、camera-only成本，须暖机并保存全样本，p50/p95用nearest-rank `ceil(q×n)-1`。本分工未执行性能采样，没有FPS结论；完整世界/沙洲和船壳光学另行验收。

首轮CPU/GPU baseline源码/fixture冻结SHA256；用户反馈之后共享水shader追加默认0的候选seam，当前候选另列，不能把旧hash称当前源码：

| 文件 | SHA256 |
| --- | --- |
| `natural_shore_surf.gd` | `d3f3a52a187a34afb7271d9500d57272fd9695f894c641d614ca2b4fd1785c51` |
| `reference_game_water.gdshader` 首轮baseline | `87ed0e1baebc6fa281b96f38a4036442045ec08adbd21caedef9ab224dfb29ca` |
| `reference_game_water.gdshader` v2.2羽化候选 | `2be7cfcaa6d7fabd32e23b8e9723deab99768d9eafeb0f7997366f3ac911dabc` |
| `shore_edge_coverage.gdshaderinc` v2.2羽化候选 | `72eb9dd5a5322ab869342cd5ac37f6ece229f80993d73a7800c8978c1c0bdd1d` |
| `reference_game_water.gdshader` 09:19新weight候选 | `d832e418028fc163905fc11a60fc038ebcfe1bdf3a9804f5b421b4b7c4d5b617` |
| `shore_edge_coverage.gdshaderinc` 09:19新weight候选 | `5aea4e22d03af9192d98e6f733ba1e84a11a4ad8a89a9298a860f699b57e21e6` |
| `coastal_visuals.gdshaderinc` | `f461320d4baef716d42f77e723f8eb140d878c9295cf8337521f4f79cc665fd7` |
| `shore-scene.json` | `7784cb7d4f0bcae579c82862acbb9a85ee1bfef12d4b6597f4d77154fdffdb22` |
| `mingqi-geography.json` | `d95116df5583e6f9c229837da1bc909e056ee7c75bc20381f7a209e7e017a912` |

## 结果与证据

最终宿主结果见 [环境实验交付](../../../docs/research/laboratory-environment-delivery-2026-10-14.md)。[最终 GPU](../../../docs/research/evidence/laboratory-environment-2026-10-14/final/GPU_VERIFY.json) 包含close连续0/6/12/18/24秒、wide、edge宽度0/0.1/0.35/0.6、同宽度water-weight1/0.55、三层及all-off。原两侧投影断区已在修后原帧消失；原近岸硬线变为连续透底过渡。用户所指方向是垂直岸线的水平过渡带，本实现仍以真实地形高差映射该带，0.6不是水平海岸宽度。

新权重同刻比较实际改变65,739像素，限定本帧y59–209，最大通道差5/255；下半幅逐像素相同。这个小幅调整发生在靠沙滩、岸浪消散的位置，不是整片海水透明化。[共用正式世界原帧](../../../docs/research/evidence/laboratory-environment-2026-10-14/production/GPU_VERIFY.json) 同时保留码头、岩石、植被与原船舶组件。对应实际截图与源码散列可复查。

[三镜头时序及间隔](../../../docs/research/evidence/laboratory-environment-2026-10-14/feather-wide-study/GPU_VERIFY.json) 保存t=0/0.5/2/8的24张成对图。低位9m观察发现原投影裁切/大面片，两边基线均存在，因此低位整场观感判为未通过，不把它掩盖为羽化成功。像素探索指标不是预先冻结ROI确认；普通近景可作为本次局部接线依据，任意坡度/透明喷雾遮挡仍未穷尽。

以下保留各阶段分工记录和首次失败；“待主线程／未测”是当时阶段状态，最终本轮证据以上述交付为准。

本轮2026-10-14实测：严格runner每次自测29断言/0失败，并检查exit、Godot ERROR、唯一完成标记。原stdout/stderr包含在JSON，不隐藏失败：

- [初始RED](../../../Temp/research/laboratory-shore-red.json)：06:52:25 UTC，缺少独立Demo，1断言/1失败、exit1。
- [资源计数RED](../../../Temp/research/laboratory-shore-resources-red.json)：06:56:44 UTC，75断言/1失败、exit1；缺实际reflection/source-patch计数，之后补齐。
- [独立GREEN](../../../Temp/research/laboratory-shore-green-2.json)：06:57:12 UTC，75断言/0失败、exit0，无Godot ERROR；预配置、真实沿岸、暂停/同时间因素、reset、镜头、非法输入、追赶及实际释放均通过。
- [首轮冻结源码复验](../../../Temp/research/laboratory-shore-frozen.json)：Demo源码SHA256 `b64b654c6c3d9511055b975c34665bd8102b0225e9ee659aa9d90b9c4067e197`，75断言/0失败、exit0，无Godot ERROR；这是后续GPU发现夹具缺陷之前的CPU候选，不是最终视觉通过。
- [生产岸浪回归](../../../Temp/research/laboratory-shore-production.json)：06:57:34 UTC，3脚本全通过；hotpath59、state_reuse32、surf52，共143断言/0失败，各exit0，无Godot ERROR。
- [生产光学回归](../../../Temp/research/laboratory-shore-optics.json)：06:57:34 UTC，29断言/0失败、exit0，无Godot ERROR。

统一首轮GPU原帧[close t12](../../../docs/research/evidence/laboratory-environment-2026-10-14/shore-close-t012-ui.png)及[snapshot](../../../docs/research/evidence/laboratory-environment-2026-10-14/shore-close-t012.png.json)显示两侧垂直/斜向水面覆盖缺口，close却主要展示整岛并裁掉山顶。[wide原帧](../../../docs/research/evidence/laboratory-environment-2026-10-14/shore-wide.png)没有该投影缺口。实际viewport是1260×449；初轮Demo只在build和camera动作更新投影，布局resize之后接受tick384也不刷新，切wide才重新投影。原失败证据保留，未靠隐藏地形或换标签忽略它。

- [viewport反例RED](../../../Temp/research/laboratory-shore-viewport-red.json)：77断言/1失败；同一生产投影网格在暂停resize后不能覆盖实际屏幕四边。
- [viewport修复GREEN](../../../Temp/research/laboratory-shore-viewport-green.json)：77断言/0失败；纯展示refresh恢复网格四边覆盖，源状态/调用数/时钟不变。
- [close镜头RED](../../../Temp/research/laboratory-shore-close-red.json)：79断言/1失败；原90/45m镜头约100.6m视距不满足局部岸浪近景目标。
- [修后冻结CPU](../../../Temp/research/laboratory-shore-view-final.json)：08:46:07 UTC，79断言/0失败、exit0，无Godot ERROR；源码SHA256 `cea7ce2016c3d471e71f8375500a06638ef6d8f8671225bb14040d9f03452b1c`。近岸36/40m重放正确，真实0–24m浪带在1260×449视野中，镜像/网格resize不推进controller。

- [羽化控制RED](../../../Temp/research/laboratory-shore-feather-red.json)：91断言/9失败；缺候选默认/控件、actual uniform、原子校验及edge镜头的反例均保留。
- [追加候选最终CPU](../../../Temp/research/laboratory-shore-candidate-final.json)：08:55:07 UTC，93断言/0失败、exit0，无Godot ERROR。验证uniform在shader中声明，实际材料0/0.6绑定、非法输入原子拒绝、同时间源/地形/调用数不变，edge固定俯视镜头重放正确。Demo源码SHA256 `0132e9824585369e4ef943cd655ece0e2b3917216ddb80158d256ead5aa38467`；测试SHA256 `0ed1c2d9fdd579a05a997b0a84036b0d80e761cc8361404bfda010adb04c5071`。

v2.2真实GPU原帧[width0](../../../docs/research/evidence/laboratory-environment-2026-10-14/candidate/shore-edge-width-00.png)/[width0.35](../../../docs/research/evidence/laboratory-environment-2026-10-14/candidate/shore-edge-width-35.png)已阅，硬直色线在候选中连续淡化；这是旧width候选的局部图像证据，不是新weight0.55的验收。

- [water-weight RED](../../../Temp/research/laboratory-shore-water-weight-red.json)：105断言/9失败，缺默认/控件/实际uniform/参数与同刻合同的失败保留。
- [water-weight GREEN](../../../Temp/research/laboratory-shore-water-weight-green.json)：09:19:20 UTC，106断言/0失败、exit0、无Godot ERROR。声明shader seam、实际1/0/0.55绑定、固定width0.6、非法数/范围/类型原子拒绝、源状态/地形/时间/调用数不变均通过。Demo SHA256 `0ee6fa398d3af9974b7f433d06674b9129cebc52068c08b0401816a18a4d7b42`，测试 `522d7aacc0f095d91e22b7a5c7dc5fc7ee97488077f8f046e892fd3f0f503436`。

合计5脚本当前278断言/0失败是CPU/资源合同证据，其中生产4脚本采用本轮06:57定向回执，Demo采用09:19候选回执；新weight helper公式与shader集成测试由环境课题统一归档。尚须新weightGPU同刻A/B、性能交替区间及正式入口验收，不能拿旧width图像或CPU绑定称贴岸透明度已最终通过。没有重复229脚本；先前全审计8项异常没有被本轮修改。

历史柔和过渡为RED1/1失败后29/0失败、正式Ocean接线87/0失败，来源是原报告；本轮不冒充重新执行历史全场景。历史[sailing-turn原帧](../../../docs/migration/evidence/reference-splash-fusion/native/sailing-turn.png)与[元数据](../../../docs/migration/evidence/reference-splash-fusion/native/sailing-turn.json)仍是绿色海底直边排查起点；CPU标量连续不能证明最终光栅硬边消失。[历史世界覆盖账本](../../../docs/migration/evidence/weather-cloud-shadow-wake-integration-2026-10-13/COVERAGE_VERIFY.json)保持原语义。

## 局限与失败

- 三展示seam有生产耦合，不另写shader伪造独立性。source-only保留海面相位重锚，analytic-only也不是完整旧版本材质。
- 局部exact257近岸texture与正式WorldView全世界512重采样texture覆盖不同；只证明同一厦门三角输入，不证明多岛边缘、沙洲、进港、森林与建筑融合。
- 没有浅水方程、质量守恒或全部原Surf ABI等价证明；强弯岸、极短轮廓、退化三角仍需专门反例。
- DXT3 alpha1/15量化、20/255阈值使低强度可见面积非线性变化；保留原mip/filter，等待GPU审阅，不能加白或更改高程掩盖失败。
- 沙滩与浅水的硬色边是另一个已观察失败：首轮水shader在`dry_height>u_tide+0.035`直接discard，其余像素ALPHA1；已有shore_transition只混12%水色，bottom_visibility只处理海底深度/窗口贡献。当前追加候选以线性opaque-scene合成模拟接岸透明coverage，待GPU A/B；修投影/镜头或CPU绑定通过都不能称硬边已修。关闭dry-land gate、改岛alpha或增加白沫不是替代方案。
- 生产配置RNG不保留state；能重放grid seed、packet和完整source样本，但不声称导出不存在的当前state。camera/开关不抽样，source调用数可观察。
- 没有船，不能验收船壳遮挡/折射或真实整场FPS；本分工GPU、性能未测，历史限制保留。

## 集成与复现

先读[研究流程](../../../docs/research/README.md)和[环境规格](../../../docs/superpowers/specs/2026-10-14-laboratory-environment-design.md)。仓库根目录配置本机GODOT_EXE，每次使用新输出文件：

```powershell
rtk proxy node tools/verify-godot.mjs --godot $env:GODOT_EXE --filter laboratory_shore --output Temp/research/shore-replay-new.json
rtk proxy node tools/verify-godot.mjs --godot $env:GODOT_EXE --filter natural_shore --output Temp/research/shore-production-new.json
rtk proxy node tools/verify-godot.mjs --godot $env:GODOT_EXE --filter reference_shore_feather --output Temp/research/shore-optics-new.json
```

普通Godot主菜单进入实验室选择shore-surf，由宿主创建独立SubViewport/World3D，把默认options传configure后挂树。固定32Hz advance/单步，暂停后单因素切换，保存inspection和实际原帧。parameters可直接传reset_experiment，比较实际矩阵、grid fingerprint、seed decimal、source packet/state和资源数。无需浏览器或HTTP服务。

论文和source运行资源在包内；Temp原日志是仓库证据，不作为发布包依赖。统一宿主需新验证普通入口、切换、返回、重复重建、暂停/继续、截图、释放和包内读取，之后附新manifest。独立视觉与接线都有证据后才能更新目录验证状态。

首轮岸浪夹具没有改生产shader/controller；后续用户反馈由统一研究接线增加coverage/weight seam。当前width0.6，weight0.55作为新实验候选；把weight设1恢复相同宽度上一版，把width设0恢复硬边baseline，两种对照不可混称。完整实验回退撤销Demo注册，保留WorldView/NaturalWorld/ProjectedOcean及原controller。新weight仅在独立GPU、性能和真实入口均有新证据后接正式默认。失败保存原帧、snapshot、候选散列，用新run-id复验，不覆写旧RED或个人存档。
