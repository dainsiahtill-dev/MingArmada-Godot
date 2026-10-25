# 天气、云与云影：源状态推进和目标场景适配

2026-10-26 H5（修复前声明）：hero-fuchuan原生验收发现健康帆面被船壳向上投影。`Daylight.light_direction(position,target)` 返回光线传播向量；WeatherState只换轴后将其命名target.direction，而WorldView把该字段视为指向太阳，调用looking_at(-direction)。冻结正式入口实测正午发光方向Y=+0.698182，符号反了。对照保存于docs/production/hero-fuchuan-2026-10-26-art/native-shadow-isolation-r5-a；并非先前代理CPU/正面GPU测试能覆盖的缺陷。修复候选仅在源→目标adapter将方向取负并换轴，原sourceLightFields、天气/RNG/颜色不变。接受项：发光方向与源传播向量换轴后dot>0.999999；海面towardSun与发光方向相反；独立hero-fuchuan实验保留旧方向与修正方向同镜头GPU对照，帆不再受船底向上遮挡；随后普通正式入口回归。依据：[Godot DirectionalLight3D -Z发光约定](https://docs.godotengine.org/en/stable/classes/class_directionallight3d.html)。当前尚未修正或通过。

H5执行结果（2026-10-26）：test_weather_sun_direction先复现3/5失败，修正Weather目标公式[-x,-z,+y]后5/5通过，source_weather与retention、source_environment_consumers以及四个ordinary_natural正式入口定向回归通过。独立hero-fuchuan实验source_legacy/source_corrected保留同源字段，仅反目标符号，GPU旧方向出现船体/索具向上遮帆，新方向正反视角消除异常。冻结实际正式场景修后worldLight=(-.502184,-.698182,-.510249)向下；原生操作最终healthy帆与收放帆也已复验。全部原始图和日志在docs/production/hero-fuchuan-2026-10-26-art/，最终交付记录为DELIVERY.md。本修复未触及源Daylight数学、源天气、RD深度比较或模型winding。

> 2026-10-14 CPU候选（实现前声明）：`profile-world-components.gd`沿普通sail入口，用完整`sea._world_packet(native)`与当前World调用次序测32个新接受时间，headless atmosphere p50 22.712ms、naturalShore16.259ms。旧diagnose工具只传time，走无环境包fallback，不用于本候选归因。独立内部计时40步：TRS compose243481us，scalar sample108779us，minimumZ17851us；包含计时开销，父子不得相加。完整原始数据`Temp/world-components-baseline-20261014.json`及`Temp/world-components-detail-20261014.json`。1704岸浪短片、30云clone/161mesh、6雾/120mesh和3天气实例/45mesh保持。
>
> 单因子H5：云层TRS矩阵的9元素GDScript循环重复动态取值/调用；等价展开表达式，并用PackedFloat32Array一次执行同序二进制32位结果存储，可降低CPU而保持每个输出字节。接受：先独立kernel比对旧Compiler及Native，覆盖实际6资源、非单位矩阵/负数/零/极端量级、输出持有和调用者修改隔离；同数据多轮微基准中位数下降，原始样本保留。若不降速或任何位差，不接生产。再通过旧renderer的完整资源/暂停/epoch/rewind/cache回归接线，root复拍GPU。禁止省略任何矩阵项、合并改变舍入次序、减少云/雾/岸浪数量或更新频率。基线hash见`docs/research/evidence/weather-transform/20261014/baseline-hashes.json`。这是CPU候选，不是FPS结论。
>
> H5实测与接线：独立kernel缺失RED1/1后7172/0；weather实验缺factor RED1/1后6/0；生产dispatch RED7173/1后7173/0。`cloud_transform_kernel.gd`仅展开multiply/transform/transpose并批量存最终float32，乘加先后与转置反向相加保持；三处私有Compiler委托接线，不改TRS compose/clock/curve/场景容量。基线循环保留在实验`cloud_transform_trial.gd`，weather Demo新增`cpu_transform_batching`，关闭为旧循环，开启为候选；同接受时间不推进RNG/history，重置后完整node/material输出逐字节相同。控制数测试从5更新6，原首次85/1结果保留于`lab-final.json`。
>
> 独立同输入交替CPU配对：30天空clone、6完整雾实例，8次暖机、32样本、1/32接受秒；每次完整源graph结果全字节相同。基线p50/p95=14.226/16.589ms，候选12.436/14.116ms，p50下降12.6%。原样本和sourcehash见[配对回执](../../../docs/research/evidence/weather-transform/20261014/independent-pair.json)。这是源render-state编译局部CPU，不包含整个world、GPU或FPS。
>
> 当前生产回归8/8、43208断言/0失败：float/scalar/原资源、完整渲染、cache、pause/rewind/epoch、真实NavalWorld接线均覆盖；实验weather85/0、新factor6/0、parameter11/0；无Godot错误，exit0。结果在`docs/research/evidence/weather-transform/20261014/`，最终hash为`source-final.json`。本轮未改变NaturalShore/NaturalWorld/Atmosphere/WorldView/海面shader/地形；无需新catalog课题。
>
> 限制与失败保留：`world-candidate-concurrent.json`与回归并行，atmosphere p50升至32.544ms，未改岸浪也升至25.591ms。该结果受CPU争用混杂，不用于前后加速比例或达标声明；只报告独立交替配对结论。生产GPU复拍与整场帧耗时由root串行执行。用户随后优先尾迹表现，本任务到此收敛，不扩展岸浪/旅程或再造课题。独立复现：`rtk proxy <GODOT_EXE> --headless --path . --script res://tools/profile-weather-transform.gd -- --output=<fresh-path>`；正式入口分段复现`tools/profile-world-components.gd`，full环境packet是必要条件。

- 课题：`weather-shadow`；实验版本：environment-lab-v2-observation / 2026-10-14；报告类型：历史整合事后整理 + 新独立工程实验。
- 状态：新 Demo 的CPU、修后实际GPU及菜单生命周期均有本轮证据；观察面是明确标注的诊断网格，未声称完整天气场景还原。
- Demo：[weather_shadow_experiment.gd](../../../game/research/demos/weather_shadow_experiment.gd)，实验室目录由宿主登记；配置、时间和资源隔离。
- 摘要：分开整数天气权威、天空云环、三中心世界云和纹理云影；保持源调用与接受时间各自的状态所有权。
- 来源：[接收与边界记录](../../../docs/migration/weather-cloud-shadow-wake-integration-2026-10-13.md)、[整合交付报告](../../../docs/migration/weather-cloud-shadow-wake-delivery-2026-10-13.md)。

## 问题与假设

只向 WorldView 传 `time/wind/focus` 会丢失天气中心、源 RNG、controller 历史与光照；画质重建若再次收窄 snapshot，正常展示的修复也会失效。暂停转镜头需要刷新朝向，却不应重复消费源调用。

假设 H1：天气在权威 runtime 中按明确 source call 推进，向渲染层发送完整环境 packet，可让正式航行、海战和重建共享同一状态。

假设 H2：稀疏 checkpoint 加输入 journal 能保留近期精确回放，避免每帧复制完整历史；窗口外请求必须原子拒绝，不能伪造被裁掉的输入。

假设 H3：原纹理云影、方向光 shadow map、船舶 stencil 体积与水面 reflection 有不同合同，分别接入和验收才能解释最终像素。

新独立实验 H4（运行前写定）：同一 32Hz 接受序列复用 WeatherState 和 Atmosphere，三个可见性因素与镜头操作不改变天气中心、RNG、天空旋转或 controller 历史；完整重置重放可恢复逐字节相同 packet。最小反例是暂停时切掉世界云而误把它的纹理影也切掉，或因刷新镜头额外调用天气 advance。

源天气坐标为整数源单位；目标默认 `source_position_units_per_metre=10`，世界云映射为 `[source_x/10, source_height/10, -source_y/10]` 米。源 heading 为 int32 环角，目标 heading 为弧度；调用计数不是渲染帧或秒。

## 方案比较

- 每个 renderer 独立按墙钟更新：局部代码少，但暂停、反射 pass、终局续播与重建会重复推进随机数；不采用。
- 只用当前 `time` seek controller：能得到单点展示，却丢失持久 accumulated/last 状态，不能代称恢复历史。例如 lastApp=10、accumulated=6、nextApp=10.25 应得 6.25，而 reset seek 得 10.25。
- 每步复制全历史：可做回放，但历史长度增长使内存和扫描成本持续增加；历史整合已替换此方案。
- runtime 所有权加 journal/checkpoint：渲染只消费完整 packet，近期回放有明确域；当前采用。32Hz 与 120 秒窗口是本作服务策略，不称原作固定 cadence。

云影平面使用源烘焙贴图；船影的 RD stencil 是另一路。当前六船族不得擅自套用仅有明确来源的 fluyt 纹理影。

新 Demo 采用生产 producer + renderer 的隔离观察夹具。另一方案是为研究另写云漂移、程序阴影和天气 shader；它减少依赖，却失去原旋转次数、三中心和完整 DDS/controller 合同，不采用。实验夹具只增加固定海面/地面、镜头与可见性 gate，正式游戏代码保持原样。

## 算法与实现

[WeatherState](../../../modules/environment_engine/weather_state.gd) 实现 int32 包裹、截断整数除法、固定三角表及源 RNG。每次 `step_original_weather` 平滑 windHeading，按 `frame & 15` 条件更新位移与速度，移动三个中心，并按源距离条件重置越界中心。

目标 `advance(t)` 以 `floor(t*32 + 1e-9)` 计算应完成调用数；每个源调用只消费一次 RNG。天空云环按接受 delta 推进；每实例 controller 保留独立状态，向正式 renderer 发布资源节点、光照和三个世界云 actor。

默认 CRT seed 和天空 seed 均为 1；源初态 lightTime=1200、windHeading=1073741760、windDisplacement=0、windVelocity=0，三中心 `(8000,0)/(3000,4000)/(6000,-4000)`。复现必须保存整个 options，不能只保存一个 seed。

```text
检查 epoch、暂停、合法 t；同时间直接复用 packet
窗口外回退：先拒绝，保持 RNG/controller/packet 不变
窗口内回退：找最近 checkpoint，重放其后 journal 输入
前进：补足 source calls；按接受 delta 更新云环与 controller
生成完整环境 packet；记录输入
每128条输入保存 checkpoint，并裁剪120秒窗口之前的历史
```

原始 epoch 零点单独保留，time0 是明确重置。窗口内新接受点可开新分支；已裁掉的中间输入不会恢复。diagnostics 报 admission、retainedFrom/Through、journal 和 checkpoints。

[CloudRenderCompiler](../../../modules/scene_engine/fidelity_fx/cloud_render_compiler.gd) 处理源 mesh、TRS、持久 controller 与 DDS mip；[WorldView](../../../modules/scene_engine/world/world_view.gd) 与 [NavalWorldView](../../../game/presentation/world/naval_world_view.gd) 消费完整环境包并完成场景装配。

原 TRS 对 local translation 的旋转、f32 存储和 parent scale 顺序必须保留。云影投到海面、雾 phase 调度与目标光照 energy 是显式 Godot 适配；不能混写为原场景完整恢复。

新 Demo 的宿主唯一拥有 advance；固定步长 `1/32s`，每次调用最多 8 步，超出墙钟时长丢弃，仅保留不足一步的余量。每步调用生产 `WeatherState.advance(tick/32, observer, wind)` 并提交完整 `environment`。天空环保留严格 `accumulated > 0.03333333507180214`、每次最多一次旋转、按输入 delta 的 f32 规则；天气的三中心和 RNG 每源调用更新。renderer 使用 stormcloud_sound + 两个 cloud00 与五个真实烘焙影网格，不以 shadow map 或程序暗斑替代。

`sky_enabled` 只 gate 天空环，`clouds_enabled` 只 gate 三个天气 actor 的非纹理影记录，`shadows_enabled` 只 gate bakedShadow 记录。先用完整同时间 packet 刷新原 renderer，再 gate 当前 visibility；不改变透明度曲线、UV、TRS、缓存时间或 producer。预设属于明确目标初态：clear 使用生产默认三中心；storm 将中心0移到 `(2000,0)` 源单位观察近景，并保留 daylight=1200；sunset 只把 clear 的 lightTime 设1930。storm 不是源 dayMode 枚举或降雨强度。预设切换返回 reset_required，不能在运行时间暗改天气。

configure 挂树前只校验 options，_ready 同步构建。非法因素/配置先原子拒绝；reset 重新建立同 seed/初态与独立 renderer。dispose 清空 producer 引用与 renderer 原网格、材质、压缩 DDS texture/cache，释放整个夹具节点。inspection 保存完整 environment、实际32位 CRT seed/state 的十进制字符串、初始化天空 draw 数、实际镜头矩阵/投影/viewport及各类可见/资源计数；天空初始化 RNG 没有运行期间新 draw。

## 实验设计

历史源值差分以 [source_weather fixture](../../../tests/fixtures/source_weather.json) 为有限 oracle；独立测试分为天气数学、资源/controller、packet 消费、保留窗口及正式场景生命周期。原值域等价和目标单位映射分开检查。

新独立 Demo 固定 CRT seed=1、sky seed=1、epoch=1、sourceCallsPerSecond=32、units=10、modelScale=1、hold_light=true、observer=(0,0), heading=0、wind.speed=0；clear 初态见前段。v2 overview/sky 使用 perspective、FOV=55°；ground 使用 orthographic、初始size=180m；均 near=0.1m、far=4000m。overview中心为 `(initial_center0_x/10-96,18,0)`、offset `(0,82,128)`；ground中心相同x且y=0、offset `(0,160,40)`，镜头不依赖运行packet跟随。实际16值变换、投影、正交size和 viewport 从当前 Camera3D/SubViewport 导出，默认测试960×640。海面与校准地面是局部观测载体，不执行全航程/水面模拟，不代表原场景地形。

运行前接受矩阵：C1 挂树前配置无资源，_ready 正确建立三个天气 actor、天空环和5个影网格；C2 两个1/64s只产生一个源调用，其 CRT state=2745024、draws=1、windVelocity=3、中心0.x=7970，第二个1/32s才旋转天空；C3 重置后64个1/32s所得完整权威 packet 与首次重放逐字节一致；C4 暂停/镜头/三个因素任意组合的 time/tick/environment 不变，cloud gate 不隐藏纹理影；C5 非法输入原子拒绝；C6 10s stall最多推进8步，后续无长程追赶；C7 dispose 两次资源计数归零、外部持有 renderer 的 texture/cache 为空，producer weakref消失。任何非零失败、Godot ERROR 或重复/缺失完成标记均失败。

GPU 接受 G1：overview/sky/ground 三镜头、clear/storm/sunset 三初态可审阅；G2 连续0/1/2接受秒的原帧与 snapshot 显示天空旋转、世界云/纹理影运动；G3 暂停同一时刻 shadows/clouds/sky 分开对照并保持完整 environment 一致；G4 退出/换课题/重建无原 owner 残留。GPU 原帧不得由 headless 数学或资源计数替代。本候选不设 FPS 提升承诺；性能、原D3D全场景像素一致性和新生产集成均不在本轮验收。

基线 source/manifest/fixture SHA256 在实现前保存于 `Temp/research/lab-weather-baseline-hashes.json`（planned）；CPU 原始 RED/GREEN 保存独立新文件，GPU 由主线程新 run 归档。不覆写历史首次失败和最终冻结证据。

v2 夹具修订接受项（首轮 GPU 失败后、修订实现前写定）：保留完整 native packet、modelScale=1、单位/32Hz/源纹理/光照/影opacity=0.38，不放大云或影。旧 `weather-storm-overview-ui.png`、`weather-storm-ground.png`、on/off 原帧作为失败基线原样保留。新接收面为单独标注的无光照5m网格诊断地面，extent≥10000m，源水色静态海面保留在下方；此载体不称原海面或原版色彩。固定 overview 镜头围绕中心0在0–2接受秒轨迹中点，不追随云；ground 使用正交投影近看纹理影。C8：960×640中0/1/2s中心0的云/影观察点距边缘≥24px，矩阵固定、native scale不变；ground中20m影跨度≥40px，换镜头完整权威packet不变；诊断texture随dispose释放。G5：复拍时实际云/影纹理可审阅，receiver截断边界不入画，5m刻度与画面诊断标签可读；on/off有对应原纹理像素差异。C8不能代替G5，修订前预先记录失败判据。

- 对照：连续前进与 checkpoint 回放；同时间重复与真实新调用；暂停镜头刷新与运行镜头刷新；低/高画质重建。
- 接受标准：有限 source fixture 精确匹配；同时间/暂停不消费 RNG；回放恢复 controller 历史；窗口外拒绝不部分修改；time0 可重置。
- 渲染标准：天空云环与三中心 actor 分开运动；云影/雾/光照各有实际输出；镜像 pass 仅更新依赖相机的部分；切换场景释放。
- 长程标准：至少 30,000 步记录 journal/checkpoint/内存量的时间序列，不能只看最终一次内存；相同源状态与目标参数比较。
- 性能标准：CPU 权威推进、资源编译、渲染提交与 frame interval 分开记 p50/p95。天气资源数或回归数不等于整场压力 FPS。

## 结果与证据

最终宿主 [GPU 原始回执](../../../docs/research/evidence/laboratory-environment-2026-10-14/final/GPU_VERIFY.json) 保存clear/storm/sunset与overview/sky/ground、0/1/2秒云移动、同刻云/云影/天空分别开关。首轮过远镜头和有限黑色平面已修为固定云中心近景及5m诊断网格；原模型尺寸、源时间、纹理与完整weather packet保持。云影现在能在网格上定位，天空云环在sky镜头检查。该诊断载体不是新的正式海水方案。

最终宿主范围、包内检查、原帧及局限统一见 [环境实验交付](../../../docs/research/laboratory-environment-delivery-2026-10-14.md)。下文保留当时阶段的CPU与历史结论；“未测／待主线程”仅指分工时点，不代替最终回执。

历史交付记录了天空与天气云共 45 个原网格、三个世界云 actor、完整 DDS mip 与 5 个资源烘焙影平面；实际源纹理、控制器和 TRS 已接入正式场景。来源见 [交付报告](../../../docs/migration/weather-cloud-shadow-wake-delivery-2026-10-13.md)。

历史 30,000 步保留测试的末段 10,000 步增量约 35KB，旧方案约 28.74MB/段。该结果说明持续增长问题的定向改善，未给出任意选项或无限运行的绝对内存上界。

[覆盖账本](../../../docs/migration/evidence/weather-cloud-shadow-wake-integration-2026-10-13/COVERAGE_VERIFY.json) 覆盖最终 209 个 GDScript 脚本：首次 205 项中 197 通过、8 失败，修复后定向复验及新增 4 项合并覆盖。不能称另一次 209 项单轮全绿。

历史 [源专项回执](../../../docs/migration/evidence/weather-cloud-shadow-wake-integration-2026-10-13/source-final-suite.json) 为 16/16；[首次完整执行](../../../docs/migration/evidence/weather-cloud-shadow-wake-integration-2026-10-13/full-suite.json) 保留失败。此论文整理未重新跑测试。

历史 [正式 GPU 验收](../../../docs/migration/evidence/weather-cloud-shadow-wake-integration-2026-10-13/gpu/VERIFICATION.json) 记录 Godot 4.7.2、Vulkan 1.4.325、Intel Arc 130T、Forward+，8 组正式场景截图涉及航行、暂停转镜头、画质、炮战和炮烟；实际源 stencil 初始化运行。

开阔航行 4 个接受秒位移 11.094 米有实际记录，不能用靠岸 HUD 速度代替位移。原版卡岸观察样本已撤回为正常操船/尾迹证据，纠错见 [观察报告](../../../docs/migration/play-observation-corrected-2026-10-13.md)。

以上属于历史整合证据。2026-10-14 新候选 CPU 实测如下；GPU 与性能尚未运行，没有原 D3D 全场景像素一致性证明。

- 有效 RED：`Temp/research/lab-weather-red-feature.json`，缺少实验文件，`LABORATORY_WEATHER_TESTS assertions=1 failures=1`、退出1；之前测试 WeakRef 类型推导警告单独保留 `lab-weather-red.json`，不是有效功能 RED。
- 首次实现失败：`Temp/research/lab-weather-green-attempt1.json`，使用不存在的 `Environment.REFLECTED_SOURCE_DISABLED` 导致解析失败和60s runner超时；移除无关覆盖，保留失败，不声称引擎有此枚举。
- 新合同 GREEN：[测试脚本](../../../tests/test_laboratory_weather.gd)，`Temp/research/lab-weather-green-attempt2.json`；Godot 4.7.2 headless，退出0，唯一 `LABORATORY_WEATHER_TESTS assertions=68 failures=0`，无 Godot ERROR，执行约2934ms。C1–C7 均通过：生命周期、手算首步、天空/世界云各自运动、64步重放、暂停/同时间gate、非法输入、8步上限和真实owner释放。计时是测试进程墙钟，不是 frame/FPS。
- 定向生产回归：`lab-weather-source-rules.json` 为2/2，`lab-weather-consumers.json` 为2/2，`lab-weather-atmosphere.json` 为8/8，均退出0且原始输出含各自唯一完成标记，无 Godot ERROR。12项源回归加新合同共13脚本；没有重跑229脚本，也不声称此前8项异常已修好。
- 实现后重新核对 `lab-weather-baseline-hashes.json` 七份生产源码/manifest/fixture，`baselineSourceChanges=[]`。只新增独立 Demo/合同和更新本论文，正式游戏 producer/renderer 没有更改。
- G1–G4 原帧、主菜单切换与包内资源验收待主线程新run；性能与新生产集成未运行。当前可见计数证明gate边界，不代替实际像素或观感。

首轮新 GPU 原帧已由主线程执行并由实现者审阅：[storm全景](../../../docs/research/evidence/laboratory-environment-2026-10-14/weather-storm-overview-ui.png)、[storm地面](../../../docs/research/evidence/laboratory-environment-2026-10-14/weather-storm-ground.png)、[影关闭](../../../docs/research/evidence/laboratory-environment-2026-10-14/weather-shadows_enabled-off.png)、[云关闭](../../../docs/research/evidence/laboratory-environment-2026-10-14/weather-clouds_enabled-off.png)。结论为失败：有限深色海面边界入画，近20m storm影与10–20m云在约800m远镜头里难以审阅；t=2中心0已从200m移到8m，旧ground却看600m。Headless真实mesh探查确认geometry/纹理资源存在、native modelScale=1，问题是夹具/投影/对比度。不得将原帧有像素或CPU gate计数解释为观感通过。v2新GPU待统一复拍。

v2 CPU：有效 `lab-weather-fixture-v2-red.json` 为70断言/1失败（缺诊断观察metadata）；`lab-weather-fixture-v2-final-cpu.json` 为84断言/0失败，退出0，唯一完成标记、无 Godot ERROR，约3667ms。C1–C8通过，原失败及首轮GPU不覆盖。`lab-weather-fixture-v2-samples.json` 保存960×640在0/1/2s的完整packet、矩阵与投影点：云约 `(895,255)/(480,252)/(77,246)`，影约 `(845,377)/(480,374)/(124,366)`。这是CPU投影，不是像素原帧。`lab-weather-fixture-v2-native-equivalence.json` 对首轮storm-on的2s原packet做递归键排序后精确JSON值比较，`nativePacketEqual=true`；变化限定为诊断carrier/镜头/标注，没有天气、RNG、controller或原纹理尺度改变。G5仍待主线程真实GPU审阅。

## 局限与失败

- 32Hz 源调度、10 单位/米、120 秒保留、云影海面投射和雾摆放均是明确目标适配；不能用“原算法”统称全部场景行为。
- 原雾最终调度、全部 caster 分类/方向生产者/skinning 与全场景 DX9 像素仍未闭合。
- 任意近期回放需真实 journal 输入；不能从当前 camera、船宽或墙钟猜历史，也不能用 reset seek 替代 accumulated 恢复。
- renderer capability、资源数、CPU fixture 和正式 GPU 接线证明范围不同；只有看过冻结候选原帧，才能评价观感。
- 十几船、上百炮的整场压力 FPS 尚无历史达标证据；不得把离线数学测试提升为性能承诺。
- 新 Demo 直接引用生产 Atmosphere 的受拥有 record 集合，保持 bakedShadow 分类并只 gate 节点visibility；若该内部结构以后变更，合同需重新验证。校准地面与静态海面无动态地形/波浪，纹理影仍按生产适配投射0.12m平面，不证明崎岖陆地阴影接收。
- 新 Demo 明确不创建降雨、雾或完整天气事件选择；storm 是靠近观察区的中心0初态，KF事件选择与原雾最终调度仍 unknown。天空初始化 RNG 的最终内部state未保留在生产packet，报告真实seed和draws并标明无live RNG，不补造该字段。
- v2无光照网格仅用于观察纹理影，不能从它的亮度推断生产光照/海水效果。固定近景只预先保证中心0的0–2s轨迹，后续可移出镜头；另外两个cloud00仍按完整生产packet在原位置推进，但近景不宣称同时审阅全部三中心。sky开关像素对照须用sky镜头，cloud/texture-shadow对照使用overview/ground；不得用不含目标的镜头判定该因素没有输出。

原研究路径 `C:/Games/Pirates-REA-Reference-20261011/weather-cloud-shadow-wake-study-20261013` 是 provenance。当前代码和 fixture 在仓库内；阅读和执行不依赖该路径，资源来源不授予新增版权许可。

## 集成与复现

按照 [研究工作流](../../../docs/research/README.md)，先固定 options/fixture/source 散列，保存新回执，不覆盖旧首次失败记录：

```powershell
rtk proxy node tools/verify-godot.mjs --godot $env:GODOT_EXE --filter source_weather --output Temp/research/weather-rules.json
rtk proxy node tools/verify-godot.mjs --godot $env:GODOT_EXE --filter source_environment --output Temp/research/weather-consumers.json
```

新 CPU 合同：`rtk proxy node tools/verify-godot.mjs --filter laboratory_weather --output Temp/research/weather-lab-<new-run>.json`。新 GPU 使用 Godot F5 普通主菜单进入实验室、天气云影，选择预设、暂停、单步与三个因素，保存完整 inspection 与原帧；新 run 路径不得覆盖旧候选。正式场景 GPU 验证仍从自由试航、单舰炮战与舰队遭遇执行，其结论与实验室单独记录。

后续新算法先注册论文与独立 Demo，获得源值/单位/时钟/资源/GPU 的分别通过记录，再覆盖正式入口、质量重建与仍可达的直连路径。接线失败回退 packet/consumer seam，保留原天气权威、操船风权限、基线和失败证据。


## 2026-10-14 补充：世界云体与海面的透明合成修复

用户报告云底在海面边界被水平截断。实际正常航行的 stormcloud_sound 云体在俯视机位甚至会整朵消失。固定场景/时间的原样、海面隐藏与顺序改变对照定位为透明管线排序错误：海面优先级1，云0；云先混合且不写深度，随后海面覆盖云像素。

修复仅调整云体的绘制优先级为2；保留深度测试，先完成海面，再按深度混合云。天空云初始化/布局重建和三中心世界云均接入；烘焙云影、地雾保留各自原先优先级。没有修改云形、源DDS透明度、天气坐标、速度、RNG或controller。

这朵深色云是独立世界对象，拥有自己的worldPosition，接受时间变化会移动，移动相机不会把它带走。天空背景与既有云环是另一条路径；本修复不将三中心天气云变成skybox。

[研究记录](../../../docs/research/cloud-ocean-composition-2026-10-14.md)及[GPU验收](../../../docs/research/evidence/cloud-ocean-composition-2026-10-14/production-1/COMPOSITION_VERIFY.json)保存固定三个机位与19张主/反射原帧：
- 水平截边机位，云作用像素4839→7369；俯视34→7109；低机位7423→7436，近似保持。
- 使用明确标注的洋红色不透明遮挡夹具：遮挡区内开/关云的变化像素为0，验证没有绕过深度测试。
- 镜像viewport开/关该云有2675个变化像素，云继续参与原反射链。
- 1→3秒固定机位检查真实世界中心移动；同刻画质重建不推进天气，云/影分层保持。
- 新合同RED为2项排序失败，修复后7/0；源/缓存/正式入口大气8份、实验室天气2份回归通过。

首个诊断把云提到1，两个观测机位可以恢复，但与海面同优先级仍不可靠。生产owner合同抓住这一点，最终使用2。保留这轮中间失败，不将局部成功称为最终方案。
另一次测试夹具清理错误误调用Ocean.dispose导致超时，已修正并保留原失败日志；它不是渲染产品缺陷。

既有weather-shadow实验继续消费同一Atmosphere。海面截断反例需要真正的透明海面，本轮用正常自由试航隔离回归工具重放，不在校准地面实验中伪造可见差异，也不新增首页示例。
复现工具：`tools/verify-cloud-ocean-composition.gd`。范围为合成/遮挡修复；不声称新云造型、降雨或完整原版天气像素还原。

## 2026-10-15 补充：世界云离场生命周期 A/B

本轮沿用 `weather-shadow` 与同一独立 Demo；新增的是第七个实验控制 `cloud_lifecycle`，默认开启。源天气中心仍按原整数规则复位，RNG、源风场、天空环及 controller 接受时钟保持权威。开启时，可见世界云与其纹理影连续漂移，完整保守边界离开受保护视锥后才回收并安排下一代；关闭时直接使用逻辑中心位置，保留可见瞬移基线。该显示生命周期是目标适配，不能称原游戏回收算法。[问题、方案和预先接受标准](../../../docs/research/world-cloud-lifecycle-2026-10-15.md)记录三实例上限、镜像保护、48m扩张及重建/同刻刷新边界。

H6：相同 seed、初态、32Hz输入与固定相机，仅切换 `cloud_lifecycle`，可令源中心在镜头中复位时，旧云及全部云影继续向西移动而不直接跨越千米；两组完整权威 environment 逐字节相同。最小反例是 `cloud_exit` 初态：center0为 `(-15980,0)` 源单位，另外两中心不变。中心0在首个1/32s步越过西侧距离门槛并复位。固定overview仍围绕初始世界x=-1598m的0–2s连续离场轨迹中点，即 `(-1694,18,0)`；这让基线故障立刻可复现，无需等待自然长程重置。ground继续用同一x中心的正交投影；模型尺寸、纹理、5m校准网格和光照不变。此预设是明确诊断夹具，不能称常规天气枚举。

独立 CPU 接受项在实现前由行为测试固定：L1 默认选项传递到真实 Atmosphere，暂停开关及转镜头不消费权威时间、RNG或回收状态；非法非bool原子拒绝。L2 `cloud_exit` 零时刻云体/云影观察点处于960×640固定镜头内，首32Hz步确实生成新的源generation，而原可见云仍retiring=true、recycles=0。manager的generation记录最新观察到的源代数，因此该字段应为1，不能把它误称当前可见物体的出生代数；旧物体保留由实际mesh位置验证。L3 该步每个原云/影mesh位移小于10m且中心向西；关闭候选后同一源packet的首mesh位置与候选相距大于1000m。L4 A/B资源数、实际相机、源天气/天空/controller及RNG相同；宿主恰好显示七个控制。测试入口为 [test_laboratory_weather_lifecycle.gd](../../../tests/test_laboratory_weather_lifecycle.gd)，旧实验室天气和CPU矩阵对照继续回归。

首次 [RED](../../../docs/research/evidence/world-cloud-lifecycle-2026-10-15/lab-cpu/red.json) 已执行：新控制尚未实现时1断言、1失败，退出1。最新 [GREEN](../../../docs/research/evidence/world-cloud-lifecycle-2026-10-15/lab-cpu/green.json) 为三文件112断言/0失败：既有weather86/0、生命周期20/0、CPU矩阵对照6/0；每个唯一完成标记存在，exit0、无Godot ERROR。真实首32Hz步全部云/影mesh最大位移3.0120849609375m，基线首mesh与候选相距2953.84521484375m；两组完整权威environment相同、资源数和相机相同。[目录回归](../../../docs/research/evidence/world-cloud-lifecycle-2026-10-15/lab-cpu/catalog.json) 同样通过。此处只报告实验室定向headless结果，不称全项目回归；本候选GPU连续原帧及正式入口结果分别记录，headless位移、frustum或资源合同不能代替真实GPU观感、镜像像素和整场性能结果。

保留两次中间失败：[首次接线](../../../docs/research/evidence/world-cloud-lifecycle-2026-10-15/lab-cpu/first-integration-failure.json)发现生产视锥条件表达式返回未类型化空Array，导致原weather失败及新实验超时；修复显式Array[Plane]初始化后该错误消失。[第二次](../../../docs/research/evidence/world-cloud-lifecycle-2026-10-15/lab-cpu/generation-semantics-failure.json)仅一项失败，原因是测试把manager.generation误当显示出生代数；查实际合同后改为断言最新源generation=1、retiring=true、recycles=0，并继续以全部mesh位移验证物体保留，没有更改生命周期实现来迎合错误预期。

实验室复现：F5进入普通首页“实验室”，选择既有“天气、移动云层与云影”，选择“可见云离场回收对照”预设并重置，保留overview、默认seed、zoom=1和三个可见性开关。先暂停，在0秒保存inspection与原帧；单步一次到0.03125秒，候选应保留原云及云影并向西移动。关闭“可见云与云影出镜后回收（A/B）”，同条件重置并单步一次，保存直接源复位基线。两组对照完整environment，不用候选的视觉位置替代源天气中心。随后按固定接受步长连续推进、保存出镜前后原帧及inspection；只有旧物体完整出镜才可回收，不能把暂停转镜头当作一次生命周期推进。实验叠字明确显示“源天气中心照常复位”和当前候选/基线。

本实验接收面无真实海面反射，因此镜像保护仍须由独立/正式GPU工具和生产合同验证。观察固定近景只预先保证离场轨迹0–2s；基线复位后离开原镜头正是失败现象，不能自动转镜头追踪后声称连续性。开关实验策略可能立即重置显示历史，严格A/B必须分别“同条件重置”；该切换不推进权威状态。

```powershell
rtk proxy node tools/verify-godot.mjs --filter laboratory_weather --output Temp/research/weather-lifecycle-lab-<new-run>.json
```

最终GPU与正式接线：见[完整交付记录](../../../docs/research/world-cloud-lifecycle-2026-10-15.md)。最终独立lab-3在129个接受时刻/组保存50张原帧，覆盖3.5625秒的完整离场回收前后；正式production-2从真实自由试航保存20组主/倒影共40张原帧，原重置帧的生产位移1.599976m，基线2951.203857m。七时刻主/镜像差分均通过，重置后的云可见且连续移动。生产默认启用，质量变更复用原owner；恢复减弱动态不会补完冻结期间位移。原天气/RNG保持相同，仍仅三个世界实例。

[可播放的逐帧A/B](../../../docs/research/evidence/world-cloud-lifecycle-2026-10-15/review.html)关联原始回执、PNG散列、明确的近重置初态和失败夹具。production-1遗漏simulation快照刷新，旧0秒云不在目标镜头，连续性失败，已排除；不得用该轮缺目标的截图作结论。显式rewind/新epoch仍按源状态重建显示，没有任意历史相机轨迹恢复承诺。整项目回归与云专项证据分别列示，不把微型CPU计时称为完整游戏FPS。

最终全套回归272文件：265通过、7失败，保留[原始完整回执](../../../docs/research/evidence/world-cloud-lifecycle-2026-10-15/full-headless.json)。两个60秒超时项在180秒保护下串行复跑分别37.923/29.603秒通过，原失败不覆盖；其余五处地形/阴影架构/旧测试夹具问题及直接依赖核对见完整研究记录的回归表。云、原天气、正式大气及实验室相关合同均通过。
