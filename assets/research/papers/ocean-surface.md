# 五波海面：独立光学响应与镜像／折射对照

- 课题：`ocean-surface`；报告版本：2026-10-14 独立环境实验；实现负责人：本轮 Ocean Agent。
- 类型：既有生产集成的事后整理，新增独立实验及新 headless 合同；两类证据分开。
- 状态：研究中。新 Demo 的 CPU 合同已测，真实 GPU 连续画面、主菜单和包内接线由本轮宿主验收补录；不能继承历史 `integrated` 结论。
- 摘要：复用生产五波、投影 ArrayMesh、海水 shader 和真实纹理，在同一接受时间控制柔化／旧镜面响应、实际平面镜像、深度折射和细节强度。当前只有 headless 合同通过。
- Demo：[ocean_surface_experiment.gd](../../../game/research/demos/ocean_surface_experiment.gd)，由独立 SubViewport 宿主推进；无需 HTTP 服务或外部来源目录。
- 来源：[正式世界海面融合](../../../docs/migration/reference-ocean-world-integration.md)、[ProjectedOcean](../../../modules/scene_engine/ocean/projected_ocean.gd)、[WaveField](../../../modules/physics_engine/ocean/wave_field.gd)。第三方纹理沿用仓库来源记录，没有本轮新增许可推断。
- 新证据：[RED](../../../Temp/lab-ocean-red.json)、[GREEN](../../../Temp/lab-ocean-green.json)、[源码冻结](../../../Temp/lab-ocean-sources.json)。这些为本地原始回执；宿主最终归档后补充稳定证据路径。

## 问题与假设

海面既要与船舶物理一致，又要在低角度下保留自然细节和可读浅滩。只迁移参考片元会改变既有风纹，并可能让近岸泡沫偏离真正绘制的地形。

假设 H1：正式位移与 CPU 共用接受的五波参数，近岸衰减仍读 canonical field，就能保持浮力与展示合同；光学可以单独融合，不能偷偷调整波高。

假设 H2：同 World3D 的镜像摄像机与实际 opaque color/depth，比没有真实目标的反射替代更能提供物体、离屏对象与地形贡献，但增加一次镜像渲染及生命周期成本。

本轮可证伪 H3：只更新现有光学参数，能在同一接受时间改变可见镜像／折射／细纹响应，同时保持五波 descriptor、投影网格、WaveField 样本和镜像所有者不变。反例为开关推进 tick、参数非法输入部分接受、重置重放不一致，或材料未消费控制值。

位置、深度、近远裁面为米；时间为接受的秒；方向向量无量纲。五波幅度为米、空间波数为弧度/米、时间频率为弧度/秒。纹理频率和美术混合量不能解释为物理流量。

## 方案比较

- 原正式材质：保留五波与既有风纹、白浪，玩法适配成熟；缺少本次实际镜像和精确近岸光学接线。
- 直接采用参考四组 Gerstner 及正弦细纹：独立学习方便，却更换物理波合同；初版正式低角度出现规则网纹，已被历史实拍否决。
- SSR：可复用屏幕数据，但离屏或被遮挡物体缺失；不能把 ray-budget 或 0-target 的旧接口当成已存在实际镜像。
- 五波加镜像/深度的融合：保留权威输入，分开光学与物理；当前采用。镜像是有限分辨率平面近似，反射中物体出现仍须实拍确认。

独立参考示例仍保留原四组行为；通过该示例的回归，不能自动证明正式海面 GPU 结果。

本轮选择生产投影 ArrayMesh；保留真实调用链及 ArrayMesh 顶点诊断。均匀近场载体能改善特定镜头的覆盖，但改变空间采样，这组对照不采用。固定柱体和沉水色块提供光学目标；它们是校准夹具，没有船舶、操船或近岸模型含义。

## 算法与实现

[ProjectedOcean](../../../modules/scene_engine/ocean/projected_ocean.gd) 保留投影网格和 API，正式 [reference_game_water shader](../../../modules/scene_engine/ocean/reference_game_water.gdshader) 融合材质；[integration_wave_functions](../../../modules/scene_engine/ocean/integration_wave_functions.gdshaderinc) 提供高度、法线与地形采样。

波高为各分量 `A * sin(dot(xz, k) + omega * t)` 之和。近岸乘 `smoothstep(0, 8, -canonical_ground_height)`；法线结合波梯度与衰减导数，地形两侧有限差分间距为 0.5 米。物理衰减始终使用全域 canonical field。

RF 纹理用 `pixel = uv * (size - 1)` 对齐真正端点，显式读取四角。全域双线性；近岸按实际 Float32 地形网格的 `(a,c,b)/(b,c,d)` 对角线三角插值。渲染近场拓扑不替换物理规则。

既有 `waternormals.jpg` 三层频率为 `.008 * surface_visual_scale`，相对倍率 1/1.6/4，互相旋转并按风向/风速滚动。fragment 重新求宏观法线，并按屏幕足迹过滤细节；不靠粗网格插值法线表达所有光学变化。

深浅基色历史选择为 `(0.12,0.48,0.66)` 与 `(0.18,0.73,0.73)`，按 1.5–17 米底深渐变；当前 shader 的吸收、反射、折射、细闪与岸浪共同构成最终颜色。这些参数属于本作美术选择。

```text
runtime 提交五波参数和接受时间 t
canonical 地形用于波衰减；实际近场三角地形用于光学定位
投影网格位移；同帧传入 simulation_time 与 u_time
镜像相机复制实际主相机参数，排除海面第20层
片元读取 actual opaque color/depth、镜像纹理、原风纹与泡沫纹理
合成吸收、浅滩、反射、细闪、近岸白沫与天空
```

[OceanRenderer](../../../modules/scene_engine/reference_island_water/ocean_renderer.gd) 使用同 World3D 的一个 SubViewport，反射宽度至多 768，aspect 来自主 viewport；包括实际相机 `h_offset/v_offset`，不复制世界或自动新增时钟。

切换相机需要显式重新绑定；脱树停止，回树复用；style 0 恢复调用者 layer 并销毁镜像，style 1 保留投影/波参数而重建镜像。`strength` 只调表面细节；非法输入、非零 tide、关闭物理 waves 等更新原子拒绝。

新 Demo 不复制海水算法。`optics_mode=soft/legacy` 仅写现有 `water_legacy_optics`；`reflection_enabled` 经生产 `set_reflection_enabled` 控制实际平面目标和 `u_use_reflection`，关闭镜像仍保留 shader 的程序天空贡献；`refraction_enabled` 经生产接口控制 `u_refraction_enabled`；`detail_strength ∈ [0,2]` 写生产 `set_reference_surface_state({strength})`，控制纹理法线斜率而非物理波幅。所有合法控制返回 `ok=true, reset_required=false`，无需重建。

宿主唯一调用 `advance(delta)`。32Hz 累积器最多接受八步，超过 0.25 秒的单次前台停顿丢弃其超额时长；权威时间严格为 `tick/32`。Demo 无 `_process` 自动推进、无状态 RNG，记录 `seed/rng_state=not_applicable`，静态纹理和 shader 的确定性噪声不冒充运行时随机状态。

configure 可在挂树前原子校验，返回 pending；_ready 同步构建。普通 reset 保留当前观察 orbit/zoom；显式传入 camera_mode 回到对应固定镜头。暂停、镜头和开关只刷新同刻生产材质与镜像。dispose 先使用生产 style 0 释放镜像，再释放本地 World、校准夹具和材质；连续调用无残留。

## 实验设计

历史合同实验用独立线性底部场，比较实际接受的 GPU uniform 与 CPU coastal 高度/法线，误差门限为 0.000002；另测 endpoint RF、相机偏移、换源、脱树、启停、资源复用和释放。

本轮 Demo 已实现固定五波 descriptor、32Hz 时钟和静态光学校准夹具。3 根不透明柱体在 `z=-28m`，9 个 9×10m 色块位于 `y=-5m`，低于五波最大 ±3.5m 范围；不新增海底 plane。未绑定岸场，生产深海 fallback 为 -20m。初态 `paused=false, camera_mode=camera_near, optics_mode=soft, reflection_enabled=true, refraction_enabled=true, detail_strength=1`。

固定镜头：near 眼位 `(20,8,26)`、mid `(70,28,120)` 均看向 `(0,0,-12)`；horizon `(0,7,180)` 看向 `(0,1,-220)`。FOV 50°，near 0.2m，far 3000m，透视 projection；orbit/zoom 为显式观察输入，眼位最低 4.5m。inspection 导出实际 column-major 16 值 transform 和 projection、FOV/裁面/offset/cull_mask、实际 viewport、参数、资源计数、材质 uniform、生产波采样和镜像诊断。

CPU 固定 viewport 为 800×450，balanced，生产投影分段96；测试从 t=0 连续16个32Hz tick 至0.5秒，再重置重放。CPU 和 shader 实际 uniform 同时记录；波样本与生产 WaveField 误差门限为 0.000002。GPU 固定同一镜头和 tick 成对切换每个因子；连续记录 t=0、0.5、1、2秒，捕获实际 viewport 并审阅原帧。GPU、driver、电源策略和实际 capture 分辨率须来自该次 manifest，当前未测。

本课题没有状态随机数时，也要明确写 `seed: not_applicable`；静态纹理、shader 和 terrain 仍需散列。不能用运行时变化的相机或 shader `TIME` 替代确定输入。

- 对照：相同五波与网格的光学开关；更换物理波模型属于另一实验，不混入这组比较。
- 接受标准：CPU/uniform 合同在既定门限内；暂停/重复时间不推进；非法更新不部分接受；镜像不递归渲染海面；切换释放无残留。
- 视觉标准：near/mid/horizon 的连续实际原帧与同时间光学开关成对截图；镜像柱体、沉水色块与细纹响应必须出现可定位的控制差异，检查规则网纹、投影近端覆盖、色块透射及遮挡。该深海 Demo 不验浅滩。headless 不判视觉通过。
- 性能标准：分辨率、quality、可见对象相同，分别记录网格更新、镜像、材质 CPU 和实际 frame interval p50/p95；当前报告没有海面专项性能达标数据。

## 结果与证据

本轮 RED：`rtk proxy node tools/verify-godot.mjs --filter laboratory_ocean --output Temp/lab-ocean-red.json`。缺少独立 Demo 导致期望失败，`LABORATORY_OCEAN_TESTS assertions=1 failures=1`，退出码1；没有用编译错误作为 RED。

本轮 GREEN：同命令输出 `Temp/lab-ocean-green.json`，Godot `4.7.2.stable.official.ed1daf0bf`，`LABORATORY_OCEAN_TESTS assertions=63 failures=0`，退出码0。严格 runner 要求唯一完成标记并检查 Godot SCRIPT ERROR／ERROR；本次无引擎错误。测试对应 [test_laboratory_ocean.gd](../../../tests/test_laboratory_ocean.gd)。

逐项本轮状态：构建、挂树前 configure、确定性重置及16步重放、暂停、同刻开关实际 uniform、非法参数原子拒绝、固定镜头／orbit／zoom、八步追赶边界、显式镜像释放均通过 headless 合同。真实 GPU 连续画面和同刻 A/B、实际主菜单切换返回、包内资源／报告读取、专项性能均未测，不能以63断言代替。

本候选源码 SHA256：Demo `450e1c3b9c0e2c3ae2aa614d68b7ec0a9ccf63a499ccd48e15e8e904ddda9859`；生产 ProjectedOcean `be04e291b9f8e139c8272da828c651725610ad030be5aac1362ec40ba0254071`；生产五波 shader `87ed0e1baebc6fa281b96f38a4036442045ec08adbd21caedef9ab224dfb29ca`。完整纹理／源码 SHA256 在本轮冻结回执；生产文件本轮未编辑。

以下仅为历史既有集成，不归入本轮新实验的通过数：

历史 [ocean-green](../../../docs/migration/evidence/reference-world-integration/ocean-green.json) 记录 78 项、0 失败；前置 RED 为 34 项、8 失败，涉及脱树 transform、错误状态接受及相机 eye 偏移。

历史 [ocean-fusion-green](../../../docs/migration/evidence/reference-world-integration/ocean-fusion-green.json) 为 85 项、0 失败；旧纹理未被消费的 RED 为 85 项、7 失败。资源接线改善有对应反例，不只是文件存在检查。

历史 [最终相关合同](../../../docs/migration/evidence/reference-world-integration/ocean-final-related-green.json) 为 87+15 项；[相关 WorldView/optics](../../../docs/migration/evidence/reference-world-integration/ocean-related-surface-green.json) 为 32+122 项；[独立四组示例](../../../docs/migration/evidence/reference-world-integration/standalone-ocean-retained-green.json) 为 3249 项。来源报告冻结五份相关测试共 3505 项、0 失败。

这些是历史 headless 合同回执，不证明 GPU 像素、镜像中对象实际可见或帧率。`includes_transparent_objects/includes_offscreen_objects` 是能力诊断，不是对象计数或画面证据。

初版正弦网纹的拒绝依据与迁移过程保留在主来源文档；仓库已有 [低位岸边元数据](../../../docs/migration/evidence/reference-world-integration/mingqi-shore-low.json) 及对应 [PNG](../../../docs/migration/evidence/reference-world-integration/mingqi-shore-low.png)。本轮整理未重新观察 GPU，不能改标“本轮独立验证”。

## 局限与失败

- 平面镜像、有限 768 宽目标和深度屏幕数据有各自近似；没有原版逐像素恢复或完整波体积折射证明。
- 低角度投影网格的近端覆盖与细纹 aliasing 是不同问题；更换均匀诊断网格不能宣称正式投影覆盖已修复。
- 物理 canonical field 与光学实际三角近场各有权威范围；不能只让 shader 好看而迁移浮力采样。
- 必须保持 Linear tone mapping / exposure 1 等场景合同；环境绑定属于正式 WorldView 接线，不由孤立材质自动保证。
- 旧截图、旧回执与当前源码可能漂移；重现前核对散列，不把历史通过直接赋给新候选。

- 新实验尚无 GPU 实拍裁决。柱体和色块存在、uniform 消费与 mirror target 活跃只是合同证据，不能宣称物体实际在镜像／折射画面可见。
- 深海固定夹具不覆盖地形 field、浅滩、船体、尾迹、生产存档或操船；不能延伸为完整游戏接入验收。
- 生产 projected grid 保留其低位近端覆盖限制；若真实 horizon 画面失败，先保存失败原帧，本轮不暗改生产网格。
- 可重复 replay 需同 source/hash、viewport、固定镜头以及原顺序 orbit/zoom 输入；单张最终矩阵和 tick 不代表任意外部历史可恢复。

原学习台 `C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water` 仅为来源标识。仓库运行与本论文阅读无需该目录；第三方贴图的来源记录不等于新增再分发许可。

## 集成与复现

新实验入口为普通主菜单“实验室”的 ocean-surface 课题，allowlist 由 [Catalog](../../../game/research/catalog.gd) 控制。宿主读取 get_default_options/control_spec，以 set_parameter 原子更新；公共暂停、reset、32Hz单步和快照由宿主提供。包内直接加载 `.gd` 与本论文，不依赖 HTTP 或参考程序目录；主菜单与导出可达性由本轮宿主新证据确认。

既有生产入口仍为 [NavalWorldView](../../../game/presentation/world/naval_world_view.gd)、[WorldView](../../../modules/scene_engine/world/world_view.gd) 与 ProjectedOcean。本轮不替换正式算法，不改保存或设置；新增实验通过不自动改变既有集成状态。

仓库根目录配置 `GODOT_EXE` 后，保存新的合同回执：

```powershell
rtk proxy node tools/verify-godot.mjs --filter laboratory_ocean --output Temp/research/ocean-independent-new-run.json
rtk proxy node tools/verify-godot.mjs --godot $env:GODOT_EXE --filter reference_ocean --output Temp/research/ocean-contracts.json
rtk proxy node tools/verify-godot.mjs --godot $env:GODOT_EXE --filter reference_surface --output Temp/research/ocean-surface-contracts.json
```

复现新实验：先核对冻结 SHA256，运行独立合同；Godot 打开 `project.godot`、F5，从普通主菜单进入实验室选择本课题，固定 near/mid/horizon、32Hz序列、暂停同刻改变一个因子，保存原帧与参数快照。实际 GPU 结果必须分别确认时间、画面和资源生命周期，再更新本论文。重复 run 使用新目录。

复验后核对投影 grid、五波、terrain、snapshot 时间、镜像 layer 与释放合同，再测正式入口。若失败，回退光学 seam，保留原五波、全部基线与失败截图；新记录使用新目录，不能覆盖历史 RED/GREEN。
