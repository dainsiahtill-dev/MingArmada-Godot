# 岸浪与浅滩：真实三角岸线、解析推进浪与源短浪对照

- 课题 ID：`shore-surf`；报告 v2，2026-10-14。
- 类型：既有正式算法的事后整理，加本轮独立实验夹具；不补造“先研究后集成”的历史。
- 状态：生产接线是历史事实；新 Demo 的 CPU 合同已测，真实 GPU、普通菜单生命周期与包内复现由统一验收补齐。证据补齐前不宣称独立视觉验证通过。
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
| `camera_mode` | close / close、wide | 近岸/整岛固定镜头，支持orbit与zoom重放 |
| `paused` | false | 阻止接受时间推进 |

`*_opacity`是展示倍率；解析/残沫实际是颜色混合强度，source才直接乘alpha，UI据此标注。解析项包含已乘residue强度的lace，最终水色还取`max(edge_foam,surf)`；不声称三层线性独立拆分。residue开关不能移除source自己的薄尾。quality默认balanced，可配置low/balanced/high；live set_parameter返回`reset_required`，不暗中重建或复位。

configure原子校验，挂树前返回pending、_ready同步构建。宿主将delta累积成1/32s，单次最多8步，超出追赶预算的墙钟时间丢弃；无自动_process/physics推进。reset重建唯一场景并清零tick/累积量，确定性比较不混入对象身份。开关直接缩放当前材料，不再次调用source；camera-only刷新投影/镜像。dispose显式释放生产镜像renderer、本地节点及terrain/texture引用，允许重复调用。

## 实验设计

CPU固定输入：Godot4.7.2 stable、headless、独立World3D、960×640、balanced、0s初态、32Hz、seed1661、正式厦门网格。close焦点为eastmost实际源packet，朝向由patch outward决定，偏移海外90m/向上45m；wide偏移330m/230m。FOV45°、near0.1m、far3000m。inspection导出实际16值column-major transform/projection、viewport、orbit、zoom、参数和资源数，不能仅靠镜头标签重放。

CPU接受：预挂树无资源、ready同步成功；两半步仅接受一步；192步=6s；暂停/开关/镜头保持完全相同source packet/state/调用数/时钟/构建数；海岸误差<0.0002m、实际材料倍率误差<1e-6；同输入reset完全一致；非法数/类型/未知控制原子拒绝；追赶最多8步；dispose实际镜像/源节点失效、资源归零。实现前先测试缺失Demo的RED，资源计数RED另行保留。

GPU计划固定1280×720、balanced、真实图形后端：close/wide，接受0/6/12/18/24s，同时间全开、analytic-only、source-only、residue-only、all-off，保存原帧及完整snapshot。检查真实海岸、短片尺度、接岸退场、无空中环/直格/明显折叠；因素切换不能改变controller。source-only关闭analytic/residue；analytic-only关闭source/residue；residue-only关闭analytic/source，此时解析lace被乘零，只留下edge_foam。CPU不能替代此项。

性能只能声明独立scope的configure、32Hz update、camera-only成本，须暖机并保存全样本，p50/p95用nearest-rank `ceil(q×n)-1`。本分工未执行性能采样，没有FPS结论；完整世界/沙洲和船壳光学另行验收。

本轮未修改的生产源码/fixture冻结SHA256：

| 文件 | SHA256 |
| --- | --- |
| `natural_shore_surf.gd` | `d3f3a52a187a34afb7271d9500d57272fd9695f894c641d614ca2b4fd1785c51` |
| `reference_game_water.gdshader` | `87ed0e1baebc6fa281b96f38a4036442045ec08adbd21caedef9ab224dfb29ca` |
| `coastal_visuals.gdshaderinc` | `f461320d4baef716d42f77e723f8eb140d878c9295cf8337521f4f79cc665fd7` |
| `shore-scene.json` | `7784cb7d4f0bcae579c82862acbb9a85ee1bfef12d4b6597f4d77154fdffdb22` |
| `mingqi-geography.json` | `d95116df5583e6f9c229837da1bc909e056ee7c75bc20381f7a209e7e017a912` |

## 结果与证据

本轮2026-10-14实测：严格runner每次自测29断言/0失败，并检查exit、Godot ERROR、唯一完成标记。原stdout/stderr包含在JSON，不隐藏失败：

- [初始RED](../../../Temp/research/laboratory-shore-red.json)：06:52:25 UTC，缺少独立Demo，1断言/1失败、exit1。
- [资源计数RED](../../../Temp/research/laboratory-shore-resources-red.json)：06:56:44 UTC，75断言/1失败、exit1；缺实际reflection/source-patch计数，之后补齐。
- [独立GREEN](../../../Temp/research/laboratory-shore-green-2.json)：06:57:12 UTC，75断言/0失败、exit0，无Godot ERROR；预配置、真实沿岸、暂停/同时间因素、reset、镜头、非法输入、追赶及实际释放均通过。
- [冻结源码复验](../../../Temp/research/laboratory-shore-frozen.json)：最终Demo源码SHA256 `b64b654c6c3d9511055b975c34665bd8102b0225e9ee659aa9d90b9c4067e197`，75断言/0失败、exit0，无Godot ERROR。仅UI标签据真实seam改为强度/透明度后重跑。
- [生产岸浪回归](../../../Temp/research/laboratory-shore-production.json)：06:57:34 UTC，3脚本全通过；hotpath59、state_reuse32、surf52，共143断言/0失败，各exit0，无Godot ERROR。
- [生产光学回归](../../../Temp/research/laboratory-shore-optics.json)：06:57:34 UTC，29断言/0失败、exit0，无Godot ERROR。

合计5脚本247断言/0失败是headless CPU/资源合同证据。本分工没有GPU原帧、普通菜单/返回或包内验证，统一验收应附新run-id。仅运行受影响脚本，没有重复229脚本；先前全审计8项异常没有被本轮修改。

历史柔和过渡为RED1/1失败后29/0失败、正式Ocean接线87/0失败，来源是原报告；本轮不冒充重新执行历史全场景。历史[sailing-turn原帧](../../../docs/migration/evidence/reference-splash-fusion/native/sailing-turn.png)与[元数据](../../../docs/migration/evidence/reference-splash-fusion/native/sailing-turn.json)仍是绿色海底直边排查起点；CPU标量连续不能证明最终光栅硬边消失。[历史世界覆盖账本](../../../docs/migration/evidence/weather-cloud-shadow-wake-integration-2026-10-13/COVERAGE_VERIFY.json)保持原语义。

## 局限与失败

- 三展示seam有生产耦合，不另写shader伪造独立性。source-only保留海面相位重锚，analytic-only也不是完整旧版本材质。
- 局部exact257近岸texture与正式WorldView全世界512重采样texture覆盖不同；只证明同一厦门三角输入，不证明多岛边缘、沙洲、进港、森林与建筑融合。
- 没有浅水方程、质量守恒或全部原Surf ABI等价证明；强弯岸、极短轮廓、退化三角仍需专门反例。
- DXT3 alpha1/15量化、20/255阈值使低强度可见面积非线性变化；保留原mip/filter，等待GPU审阅，不能加白或更改高程掩盖失败。
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

本轮没有修改生产shader/controller接线；实验回退是撤销本Demo注册，保留WorldView/NaturalWorld/ProjectedOcean及历史基线。失败保存原帧、snapshot、候选散列，用新run-id复验，不覆写旧RED或个人存档。
