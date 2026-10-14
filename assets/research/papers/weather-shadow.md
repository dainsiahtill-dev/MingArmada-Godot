# 天气、云与云影：源状态推进和目标场景适配

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
