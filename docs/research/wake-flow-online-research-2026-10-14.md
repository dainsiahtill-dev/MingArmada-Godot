# 船尾水流实现研究：Crest、实际游戏与 Godot 迁移边界

日期：2026-10-14。状态：**研究与实验设计；尚未迁移实现，尚未通过候选 GPU 验收**。

本轮仅改本文，尾迹核心源码冻结。用户已明确双侧尾浪是正确结构；此前把双峰构图本身视为缺陷、将 v2 改成中央主水流，属于错误方向。v2 保留为失败实验，不接正式场景。本研究要解决的是双侧尾浪的传播、弯曲、交水响应与泡沫演化，不能再次用一条中央白色拖带取代它。

## 1. 结论与来源范围

建议保留现有五层大浪和双侧尾浪主结构，在现有研究入口增加**局部波高/竖直速度场 + 持久泡沫密度场**实验。船体的水平运动、升沉和浸没程度提供输入，水波在世界坐标传播；泡沫独立累积、平流、扩散、衰减，最后参与同一海面的位置、法线和着色。该建议是根据下列一手实现作出的设计推断，不是对当前代码效果的验收。

| 来源 | 本次确证范围 | 不应扩大成的结论 |
| --- | --- | --- |
| Crest 官方文档与公开 Crest 4 源码 | 球体交互输入、波高场求解、泡沫密度、平流、渲染与浮力分工 | 完整 Navier–Stokes、精确船体 CFD、直接可装入 Godot 的插件 |
| Rabaud / Moisy 2013 论文 | Kelvin 外形、Froude 数与可见尾浪角的适用范围 | 所有船、所有水深均必须固定半角 19.47° |
| Triton 作者技术说明 | 产品将 Kelvin 波、propeller wash、bow wave/spray 分层，并支持曲线航迹 | 已公开了可直接复制的完整数值求解器，或其营销性能适用于本项目 |
| Rare 的 SIGGRAPH 2018 作者论文 | 游戏采用持久 foam buffer、反馈模糊扩散与艺术纹理 | 论文完整公开了 Sea of Thieves 船尾求解器 |
| Atlas 的 GDC 2019 作者讲义 | 当时发布效果与 eWave 交互原型的清楚区分；频域色散与独立泡沫演化 | 原型已经是当时正式船尾，或演示 GPU 的耗时可沿用到本机 |
| GodotOceanWaves 公开源码 | Godot RenderingDevice、GPU 位移/法线图、Jacobian 生沫和持久衰减可实现 | 已具备船尾、交互船体或本项目集成 |

### 固定版本与许可

Crest 公开仓库此次读取固定在提交 [`db0658ff0b2e93e4a9e28cc2867509658b0ecc00`](https://github.com/wave-harmonic/crest/commit/db0658ff0b2e93e4a9e28cc2867509658b0ecc00)，提交时间为 2026-06-18 UTC。其 README 明确是 **Crest Water 4 / Unity built-in renderer**；现行官网介绍页明确是 **Crest 5.10.2**。下文算法和默认数值来自固定的 Crest 4 源码；新版文档仅用于说明现行概念和已披露限制，不将新版功能倒推为公开旧版已有。[Crest 4 README](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/README.md#L5-L32)，[Crest 5 文档版本](https://docs.crest.waveharmonic.com/About/Introduction.html)。

公开 Crest 源码根目录采用 MIT，所读 C#/shader 文件亦标注受该 LICENSE 约束。若移植代码或实质部分，应随分发保留版权与许可通知。本次没有取得、读取或假定 Crest 5 商业包及其资源的许可；不把公开旧版 MIT 推广到其他商业包、贴图或第三方依赖。[固定提交 LICENSE](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/LICENSE)。

## 2. Crest 实际链路：船体先对水施力

官方建议在物体下放一个或多个球体，用半径和权重近似非球形船体。动态波叠加于原有环境波。这里的球体是交互力的空间分布，不是画在水上的两个白色条带。[官方 Dynamic Waves](https://docs.crest.waveharmonic.com/Manual/Simulation/Ripples.html#adding-interaction-forces)。

### 2.1 位置、速度、升沉、浸没

精确代码入口：`Scripts/Interaction/SphereWaterInteraction.cs`。

| 函数 / 行 | 已读到的行为 | 本项目含义 |
| --- | --- | --- |
| `LateUpdateComputeVel()` 198–235 | 以真实三维 `transform.position` 的帧差除以动力学时间差；极小 dt 置零；超过 teleport speed 丢弃；另有限速 | 升沉必须来自真实船体点；不能从 y 固定为零的 yaw-only 航迹点求出 |
| `LateUpdate()` 147–183 | 查询海面位移；减去水平 `surfaceFlow.xz`，竖直速度乘 `_weightUpDownMul`；计算浸没权重，再向 shader 提交 | 公开版只扣除水平 flow，**没有在此扣除波浪轨道竖直速度**；不可称为完整三维相对流速模型 |
| `LateUpdateSphereWeight()` 238–256 | 球心在水下时影响随深度指数减小；在水上时按球体剩余接水比例平方根减小，完全离水为零 | 同一航速下，船体升沉也能改变输入强弱；停船时若仍在升沉，仍可能有交互涟漪 |
| `Draw()` 288–315 | 按模拟子步时间重建输入位置，并施加速度预测偏移 | 高频模拟不必把每个子步都写在同一个最新位置；曲线运动仍须正确插值 |

以上均可在 [SphereWaterInteraction.cs](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Scripts/Interaction/SphereWaterInteraction.cs#L136-L315) 核对。该版本的艺术默认值为半径 1 m、weight 1、竖直权重 0.5、内球倍率 1.55、内球偏移 0.109、速度偏移 0.04、水平波位移补偿 0.45；`LateUpdate` 另有 3.75 和重力归一系数。这些是现有实现调节值，不是船体水动力常数，也不直接作为本项目验收参数。[参数定义](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Scripts/Interaction/SphereWaterInteraction.cs#L29-L59)。

### 2.2 力注入不是贴图透明度

真正使用的 shader 是 `Shaders/OceanInputs/Resources/DynWavesSphereWaterInteraction.shader`，`Shaders/Resources/` 下同名文件只是已迁移提示，不能拿它作为实现证据。

`SphereSDF()` 计算水平方向到球轮廓的有符号距离和径向法线；`InteractionFalloff(a,x)` 采用带正负号的衰减函数。`Frag()` 的竖直输入来自 `-velocity.y` 与有符号衰减的乘积；水平输入来自径向法线与水平速度点积，并用内外符号和内球倍率平衡。最终以加法混合写入 **第二通道的速度增量**，第一通道高度不直接改写；增量包含模拟 dt、weight、波长尺度和边缘羽化。[实际 shader / `InteractionFalloff`, `SphereSDF`, `Frag`](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Shaders/OceanInputs/Resources/DynWavesSphereWaterInteraction.shader#L85-L156)。

设计推断：要使船上下起伏真正“推水”，应在船尾/船侧若干真实船体点上采样三维位置与接水量，再生成有方向、有正负的力。单独增加纹理滚动、按航速调 alpha，表达不了这条因果链。

## 3. 波高场怎样留下、展开和传播

`LodDataMgrDynWaves` 使用 `R16G16_SFloat` 存储动态波；`UpdateDynWaves.compute::UpdateDynWaves()` 的两个分量是波高 `h` 和竖直速度 `v`。这是二维水平网格上的波动方程，即常说的 2.5D 高度场，不能翻卷或形成离水飞沫。[格式定义](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Scripts/LodData/LodDataMgrDynWaves.cs#L16-L23)，[求解核心](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Shaders/Resources/UpdateDynWaves.compute#L56-L151)。

按源码整理的计算顺序如下，公式用于解释，不是新移植代码：

1. 把当前 texel 转成世界 XZ；按 `x - dt * flow(x)` 回溯采样上一状态，同时映射上帧窗口/LOD，避免历史跟着相机拖走。
2. 每层用代表波长 `lambda = 2 * gridSize` 求深水相速 `sqrt(g * lambda / (2*pi))`，并受 Courant 上限限制。
3. 用四邻居 Laplacian 更新速度：`v_next = v + dt*c*c*laplacian(h)`；施加 damping，再 `h_next = h + dt*v_next`。
4. 非水域清零、边界衰减、浅水衰减，异常非有限值清零，防止整个场传播 NaN。

该源码注释提到旋转 Laplacian，但当前 kernel 的 X/Y 邻居轴实际固定；本研究以执行代码为准。每层的代表相速也是近似：**单层固定相速的局部波方程，不等价于覆盖所有波长的精确深水色散关系**。不能保证只移植一张局部高度图就自动得到正确远场 Kelvin 角。[`ComputeWaveSpeed` 与固定邻居轴](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Shaders/Resources/UpdateDynWaves.compute#L27-L118)。

`LodDataMgrPersistent::BuildCommandBuffer()` 维护历史 texture、固定时间子步、子步之间 ping-pong，以及 LOD/窗口变换；先做模拟再提交本子步输入。即使不推进模拟时间，也要做窗口重映射。动态波默认 60 Hz，damping 0.05、Courant 0.7；它们应配合网格尺寸和目标波速测试。[历史调度](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Scripts/LodData/LodDataMgrPersistent.cs#L103-L207)，[子步与设置](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Scripts/LodData/Settings/SimSettingsWave.cs#L33-L50)。

最后 `ShapeCombine.compute::ShapeCombineBase()` 把动态高度加到环境位移，并从动态高度梯度构造受限水平位移，使波峰更尖。这个水平压缩又会影响下一节的生沫。只改变独立白色尾迹网格，不会自动改变主海面的法线、反射和波峰。[合成路径](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Shaders/Resources/ShapeCombine.compute#L121-L148)。

## 4. 泡沫：密度演化与纹理运动是两件事

`Shaders/Resources/UpdateFoam.compute::UpdateFoam()` 保持单通道泡沫密度。它先在 `x-dt*flow(x)` 取旧值，再乘 `max(0,1-fadeRate*dt)`；从最终位移图的水平 Jacobian determinant 检测压缩并增加泡沫，另加浅水源，最后限制到 0–1。公开版默认泡沫模拟 30 Hz、fadeRate 0.8。[平流/衰减](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Shaders/Resources/UpdateFoam.compute#L29-L80)，[Jacobian 与浅水源](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Shaders/Resources/UpdateFoam.compute#L82-L115)，[设置](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Scripts/LodData/Settings/SimSettingsFoam.cs#L26-L53)。

这里没有显式泡沫 Laplacian diffusion 项；双线性回溯可能带来数值平滑，但不能将它描述为主动湍流扩散。需要可控扩散时应额外设计，并注明来源/选择。Crest 官网另允许用 texture/mesh 向泡沫场注入源；它是追加密度，并非固定在船上的最终贴图。[Foam 输入说明](https://docs.crest.waveharmonic.com/Manual/Appearance/Foam.html#user-inputs)。

`OceanFoam.hlsl::WhiteFoamTexture()` 把密度转为纹理阈值，从而逐渐显露/消散泡沫细节。`ComputeFoamWithFlow()` 在两个错开半周期的流动 UV 样本之间交叉淡化，避免纹理无限拉伸。**前者的持久密度 transport**决定泡沫在水中的位置，**后者的 UV flow**决定微观纹理外观；只有后者会出现“贴图在一根绳上滑动”的局限。[密度到细节阈值](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Shaders/OceanFoam.hlsl#L18-L43)，[双相流动采样](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Shaders/OceanFoam.hlsl#L152-L191)。

`Flow` 是水平水体速度输入，不是船速本身。Crest 的波和泡沫读取该场，但这些 kernel 没有反过来求解完整水平流体速度场。将 `flow = -shipForward*shipSpeed` 铺到整张场会让历史整体跟船跑，不能称为正确世界平流。[官方 Flow 定义](https://docs.crest.waveharmonic.com/Manual/Simulation/Flow.html)，[上述两个 compute 核心](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Shaders/Resources/UpdateFoam.compute#L47-L73)。

## 5. 水面对船的力是另一条路径

公开 Crest 4 `BoatProbes::FixedUpdate()` 查询多个探针水位和船心水面速度；`FixedUpdateBuoyancy()` 按探针浸没深度施加向上力；`FixedUpdateDrag()` 使用船速减水面速度，分别施加竖直、横向和纵向阻力。这解释船如何产生升沉/横摇，再将真实运动提供给交互球。[BoatProbes 查询与调度](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Scripts/Interaction/BoatProbes.cs#L116-L175)，[浮力和阻力](https://github.com/wave-harmonic/crest/blob/db0658ff0b2e93e4a9e28cc2867509658b0ecc00/crest/Assets/Crest/Crest/Scripts/Interaction/BoatProbes.cs#L206-L235)。

不能直接把两个方向闭环接上就称完成：现行 Crest 5 文档明确指出 Sphere Water Interaction 尾浪可能反馈到浮力而造成抖动；5.2.0 增加的 collision layers 可让浮动物体只查询 animated waves、排除 dynamic waves。文档还提示位移补偿过高可导致环形反馈伪影。[查询层及反馈限制](https://docs.crest.waveharmonic.com/Manual/Advanced/Queries.html#collision-layers)，[交互参数与补偿限制](https://docs.crest.waveharmonic.com/Components/Inputs/SphereWaterInteraction.html)。

本项目最小实验先采用单向关系：现有船体姿态/大浪 → 局部交互场；浮力仍按既有水面采样。启用自产尾浪回驱船身属于另一个需要稳定性证据的阶段。航行停下后“旧航迹继续消散”与“船仍升沉而产生微弱交水纹”可以同时成立，不应由一个 `speed == 0` 开关全部清除。

## 6. 双侧主形与实际游戏证据

### Kelvin 与帆船尺度

Rabaud / Moisy 的论文使用 `Fr = U/sqrt(g*L)`，解释低 Fr 的 Kelvin 型尾浪与高 Fr 时变窄的可见最大幅度角；论文的低速近似半角为 19.47°，并包含横波和发散波，不能用两根永久均匀白线代表全部波形。角度还受扰动尺度及其他条件影响，不能把 19.47° 用作所有情形的硬编码定律。[原始论文，式 1–4 及图 1–5](https://arxiv.org/html/1304.2653v1)。

项目当前读到的约 3.54 m/s，若用名义长度 32 m，则 `Fr≈0.20`；这仅是量级估算，实际水线长度须从模型世界尺寸确认。此前名义宽 9 m 与测得世界宽约 4.97 m 已显示尺寸不能混用。即使用约 17.7 m 长作示例，`Fr≈0.27`，仍不支持以高速快艇的狭长中央喷流作为默认主视觉。此段是尺度推断，绝非船型阻力计算。

Triton 作者将 Kelvin 波、propeller wash、bow wave/spray 明确分开；产品说明称动态波叠加到环境波并支持弯曲路径，转弯时增加 propwash 分段。可借鉴它的分层与路径处理要求，但文章没有公开完整数值内核。其固定 38.94° 描述只作产品说明，物理边界以论文为准，也不沿用其性能宣传。[Frank Kane / Sundog，Triton 2.3 技术说明](https://sundog-soft.com/2013/07/ship-wakes-in-triton-2-3-kelvin-wakes-bow-wakes-propeller-wash-and-more/)。

### Sea of Thieves：泡沫需要历史

Rare 作者的 SIGGRAPH 2018 论文 §1.1 描述：FFT 海面；在相机窗口内通过深度比较为交水物体生沫；持久 foam buffer 反馈并渐进模糊，形成扩散，再与艺术纹理混合。它支持“持久密度 + 可控扩散 + 纹理细节”的设计，并未给出完整船尾求解器。§1.2 的浅水模拟是甲板水/瀑布/溪流等功能，不能偷换成海洋船尾的已公开实现。[Rare 作者原文 PDF，p.1 §1.1 / p.2 §1.2](https://history.siggraph.org/wp-content/uploads/2022/09/2018-Talks-Ang_The-Technical-Art-of-Sea-of-Thieves.pdf)。

### Atlas：已发布泡沫与频域交互原型要分开

Mark Mihelich（Grapeshot Games）与 Tim Tcheblokov（NVIDIA）的 GDC 2019 原始讲义，第 66 页说明当时尾迹采用 foam sprites，不影响海面位移；第 67、69 页明确为 **Prototype**。原型每格保存复数位移和速度势：注入 → 正向 FFT → 按色散关系推进 → 生成横向位移 → 逆向 FFT；周期边界用指数衰减处理，泡沫另外注入/演化并与环境泡沫合成，列出的总过程为 2 次正向、4 次逆向 FFT。[Atlas 原始 PDF，p.66–69](https://gpuopen.com/gdc-presentations/2019/gdc-2019-agtd6-interactive-water-simulation-in-atlas.pdf#page=66)。

第 56 页还给出泡沫路径：位移 Jacobian 触发“湍动能”量，逐步 blur + fade，再调制艺术纹理。第 73 页的交互波耗时为演示配置的 Radeon VII 0.8 ms、RTX 2080 0.6 ms，不是本项目 Godot 的测量。[泡沫页](https://gpuopen.com/gdc-presentations/2019/gdc-2019-agtd6-interactive-water-simulation-in-atlas.pdf#page=56)，[演示计时页](https://gpuopen.com/gdc-presentations/2019/gdc-2019-agtd6-interactive-water-simulation-in-atlas.pdf#page=73)。

设计判断：若后续要求远场波长相关传播与 Kelvin 波结构，Atlas 的频域交互路线比单层固定相速高度场更贴近该目标，但需 FFT 管线和边界/泡沫系统。第一步近船实验无需替换既有五层海浪；将其视为以后可选的 **delta 位移求解器**，而非以重写整片海面掩盖尾迹问题。该讲义的公开阅读也不等于获得游戏资产或商业源码的再分发授权。

## 7. 能否迁到 Godot，实际成本是什么

**能迁算法，不能直接装入现有工程。** Crest 的 C# MonoBehaviour、Unity CommandBuffer、ShaderLab/HLSL 宏、texture-array cascade 管线都需要改写与接缝验证。Godot 官方确认 compute shader 使用 GLSL 和 RenderingDevice，只支持 Forward+ / Mobile，不能假设 Compatibility 路径可用。[Godot compute 官方说明](https://docs.godotengine.org/en/stable/tutorials/shaders/compute_shaders.html)。

GodotOceanWaves 固定提交 [`a171446f8174348895aaafc426576c26261058b9`](https://github.com/2Retr0/GodotOceanWaves/commit/a171446f8174348895aaafc426576c26261058b9) 已实现 RenderingDevice 包装；`fft_unpack.glsl::main()` 59–67 行由位移导数计算 Jacobian，读取上一泡沫密度，指数衰减、增加新源，再写回法线图 alpha。这是本引擎的可行性证据，不是交互船尾成品。该仓库同为 MIT，复用代码仍应保留其独立版权通知。[RenderingContext](https://github.com/2Retr0/GodotOceanWaves/blob/a171446f8174348895aaafc426576c26261058b9/assets/render_context.gd#L30-L118)，[foam 实际内核](https://github.com/2Retr0/GodotOceanWaves/blob/a171446f8174348895aaafc426576c26261058b9/assets/shaders/compute/fft_unpack.glsl#L53-L67)，[LICENSE](https://github.com/2Retr0/GodotOceanWaves/blob/a171446f8174348895aaafc426576c26261058b9/LICENSE)。

| 迁移层次 | 必须新增/处理 | 相对成本与适用范围 |
| --- | --- | --- |
| 单层局部实验 | RG 高度/速度历史、R 泡沫历史、固定子步、移动窗口重映射、球/船体力源、边缘吸收、海面合成 | 中等；足以验证船旁与近尾的动态反馈，无法承诺远场色散 |
| 局部场参与现有海面 | 主 ocean vertex/normal/foam 采样；纹理与世界原点一致；反射/折射几何一致；释放与设备恢复 | 中高；如果只叠独立薄片，只验证泡沫外观，尚未验证真实水面响应 |
| 全部 Crest 式多尺度场 | 多层 texture arrays、LOD 拼接、相机高度缩放、窗口迁移、尺度权重、GPU query/readback | 高；等同引入水模拟子系统，不是改一个材质参数 |
| 双向船水耦合 | 探针、力/力矩、读取时序、去反馈、低帧率稳定性、确定性边界 | 高且独立；本轮先不纳入 |

上述成本是架构判断，不是工时或 FPS 承诺。GPU 读回不能放进每个顶点/每个球的同步循环；最初保持船物理在现有 CPU 海浪采样路径，局部扰动只供显示，避免为验证外观引入同步瓶颈与新物理风险。

## 8. 建议的最小实验与可裁决问题

以下为待实施候选参数，**均非已验收结果**。在现有 `wake_flow_experiment` 研究入口切换，不另造顶层游戏样例；保留原版 oracle、v1/v2 失败图与明确开关。

1. **场与坐标。** 第一版 256×256、64 m×64 m，格距 0.25 m；中心按 texel 对齐移动并回溯世界历史，不随船 yaw 旋转。14 s、3.54 m/s 的参考历史约 49.6 m，因此窗口中心需要偏向船后并记录边界截断；高航速或强弯曲必须扩窗/缩短有效历史或另做多尺度，不假装固定窗口无限覆盖。
2. **状态预算。** `RG16F h/v` 双缓冲约 0.5 MiB，`R16F foam` 双缓冲约 0.25 MiB；总 0.75 MiB 是裸状态下限，不含 normal/output/flow/depth、临时纹理与驱动开销。若改 RG32F 便于数值诊断，预算相应增加。先单层，无全场 FFT 改造。
3. **力源。** 沿真实水线放少量球/椭圆近似，初试 3–5 个，半径按实测世界 beam 的 0.15–0.3 倍标定。采真实三维船体点和 accepted time；yaw-only `targetTrail.position` 仅是航迹，不可提供升沉。用浸没权重、有限差分速度、限幅和 teleport 清零；按固定子步插值位置。先关闭自产尾浪对船的反馈。
4. **传播。** 固定 60 Hz、四邻居 h/v 更新，按 dt/网格设置稳定上限；边缘吸收和非水域屏蔽。保留现有五层波，在海面取样处相加局部高度并更新法线。先分别观察 height、normal、force 调试图，不能只看白色泡沫猜波形。
5. **泡沫。** 30 Hz 持久密度；源优先来自交互压缩/交水强度，也可单独注入少量双侧船后源用于艺术可读性。按水体流速平流，加入小量可控扩散（这是结合 Rare 论文的新增选择，不冒称 Crest kernel 已有），按时间衰减。可用 `exp(-lambda*dt)` 实现帧率稳定衰减；若希望约 14 s 降到 5%，起始候选 `lambda=-ln(.05)/14≈.214/s`，不是把“寿命14秒”直接套入 Crest 的 fadeRate 0.8。
6. **外观层。** 保留双侧 wake 主轮廓；`wake3unique` 的双峰 U 构图是可用形状资源，不能作为无方向平铺噪声。微观 froth 只调制颗粒和断续；中央扰动很弱。密度驱动纹理阈值；两相流动以 accepted time 驱动并交叉淡化。波、泡沫、飞沫分开裁决。

最低验收矩阵：

| 情景 | 应观察/记录的证据 | 能排除的问题 |
| --- | --- | --- |
| 相同航速、禁用/启用真实升沉 | 输入点 y/vy、浸没权重、力图与近尾差分 | 只有水平速度调亮度，实际没有升沉响应 |
| 平静水直行 | 双侧结构、近尾起始、波纹横向传播、泡沫斑块演化 | 两条机械固定绳 / 中央白色长拖带 |
| 左转/右转与相机绕行 | 世界历史保持、旧波不跟船旋转，曲线连续 | 船局部坐标贴图冒充世界历史 |
| 停止与静止升沉 | 旧密度继续衰减；仅真实交水保留微弱新源 | 停船冻结全部历史，或静止无限生强尾迹 |
| teleport / pause / 相同时间重复 | 无跨场连接、无同时间重复积累、恢复稳定 | 时钟与场生命周期污染 |
| 窗口移动、低位/远位镜头 | 无整场拖动、接缝、边缘反射、浮在船上的泡沫 | 历史重映射或深度合成错误 |
| 30/60/120 fps、极端 dt | 相同模拟时间的数值/密度近似一致，有限值，真实GPU耗时 | 帧率相关衰减、数值爆炸或同步回读瓶颈 |

若本地高度场只产生近场涟漪而无法形成所需双侧远场，应明确分层：局部场负责交水响应和泡沫，双侧主波使用世界历史驱动的波列/解析位移或具色散的后续方案。不能为获得想要的 V 形而宣称单层近似已实现精确 Kelvin 波。

## 9. 证据与未做事项

本次直接阅读官方页面、固定提交源码及作者论文，未采用第三方演示视频作为成熟算法依据。Crest 15 个左右定点文件保留在本地忽略目录 `Temp/research/crest-db0658ff0b2e/` 便于复核，正式可追溯入口为本文固定 GitHub 链接。

Atlas 的 99 MB 官方 PDF 经本地提取复核，路径为 `Temp/research/wake-online-sources/atlas-gdc2019.pdf`；逐页文本为同目录 `atlas-pages.json`，关键页截图为 `atlas-page-56/66/67/69/73.png`。页码以上述 PDF 的 1 起始页为准。

未改 `wake_flow.gd` / shader、原版 history/oracle、生产 packet 或正式接线；未下载商业包；未运行新 GPU 实验。本文的窗口尺寸、力源数、衰减与架构建议需要下一轮 RED 数值实验和真实场景 GPU A/B 才能晋升为实现结论。
