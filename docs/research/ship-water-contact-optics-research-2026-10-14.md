# 船体与水面接触：透射、消光、倒影和吃水研究

日期：2026-10-14。状态：一手资料研究与独立 GPU 对照实验。已在真实自由试航场景完成首轮 18 张、细化轮 8 张受控截图；实验仅替换独立 QA 进程内存中的 shader，正式运行时代码和 shader 默认值未修改。当前双侧尾迹、原有五组海浪、船舶运动与浮力必须保留。

当前证据支持优先研究**水体透射的消光与颜色合成**。船体已经进入水面；关掉透射后水下船壳消失且船位不变。没有证据支持先把船整体下移、把全海改成不透明，或把问题归结为缺少倒影。较强消光已经改善当前视角，但参数、动态水线和其他船型仍需验收。

## 1. 本项目已观察到什么

本节区分三种来源：本研究直接核对 JSON；主任务提供的源码审计；主任务对原始 PNG 的视觉观察。图像变化的数量不等于视觉质量评分。

- [GPU_VERIFY.json](evidence/ship-water-optics-2026-10-14/research-1/GPU_VERIFY.json) 为 `valid=true`、`failures=[]`，共 18 张图：低、高两个机位各 9 种模式。全部时间为 8 秒；每个机位内 camera 完全一致，18 条 geometry 记录完全一致。设备为 Intel Arc 130T。该证据声明为受控正式自由航行路径，不是全游戏 FPS。
- 几何记录：2152 个实际刚体船壳顶点中，233 个低于权威五波面；最低间距为 **−2.444082717 m**。这证明存在实际浸水，不能把顶点占比解释为排水体积，也不能把最深顶点的垂直距离当作某像素的光线路径。记录把局部 GPU 尾迹位移另列为最多 0.25 m 的范围。
- 主任务原图观察：[低机位 baseline](evidence/ship-water-optics-2026-10-14/research-1/low-baseline.png) 已有船和岛的平面倒影；[关闭透射](evidence/ship-water-optics-2026-10-14/research-1/low-no-transmission.png) 后水下船壳消失；[较强吸收](evidence/ship-water-optics-2026-10-14/research-1/low-stronger-absorption.png) 减轻龙骨清晰裸露；线性域混合稍亮，未单独解决接触观感。本研究未独立评判这些 PNG 的美术质量。
- 主任务对冻结 [reference_game_water.gdshader](../../modules/scene_engine/ocean/reference_game_water.gdshader) 的审计：`ALPHA=1`；已有平面倒影和屏幕折射；`T=exp(-vec3(.19,.075,.035)*optical_depth)`，路径量取 view-space Z 差；兼容原 WebGL 外观的分支在 display RGB 域做 `scene*T+water*(1-T)` 后转回 linear；岸羽化已有 `near_terrain` 限制。本文没有再次审读该运行时文件。GPU receipt 中该源码的冻结 SHA-256 为 `a2c9f873a3251c3f1edd6d87de1a1d08bfc07679aed1b3693831692d54628051`。

[PIXEL_COMPARE.json](evidence/ship-water-optics-2026-10-14/research-1/PIXEL_COMPARE.json) 的全图差异计数如下；指标为文件中的 `pixels_changed_gt2`，不是船壳区域分割结果。

| 相对 baseline 的单因素 | 低机位 | 高机位 | 当前能支持的判断 |
|---|---:|---:|---|
| 关闭透射 | 30,262 | 11,718 | 配合原图观察，透射确实贡献水下船壳可见性 |
| 关闭物体倒影 | 360,564 | 401,813 | 已有物体倒影；全图变化包括其他反射物，不能认定它是船底问题主因 |
| 关闭岸羽化 | 62 | 14 | 此场景、此时刻下影响极小，优先级降低 |
| 系数改为 (.8, .4, .22) | 28,790 | 9,003 | 原图观察有改善；仍是待标定候选 |
| Z 差改射线长度 | 127 | 34 | 此次差异很小，不能把光程近似当作已证实主因 |
| 改线性域混合 | 26,871 | 7,287 | 有颜色变化；没有单独治愈证据 |

Receipt SHA-256：`155bd84053b03699c6fd70b0b9cd14a12ac9bf06fa6f13166e743364e3695ab9`。深度和浸水诊断图也包含在这 18 张中。以上结果只覆盖两个机位、一个受控时刻；不能外推到全部船型、风浪或全场景性能。

细化轮 [research-2/GPU_VERIFY.json](evidence/ship-water-optics-2026-10-14/research-2/GPU_VERIFY.json) 新增 8 张图，同样 `valid=true`、无 failures；低、高机位各含 baseline、extinction、extinction-linear、no-transmission。组内相机一致、时间均为 8 秒，8 条 geometry 一致；正式 shader 冻结 SHA 与首轮相同。主任务说明变体仍只在 QA 内存中运行，未修改正式 shader。

`extinction` 在原 (.19,.075,.035) 上加中性标量 .65，得到 (.84,.725,.685)。这是一组**有效散射/消光艺术参数**，不是实测海水吸收数据；`extinction-linear` 在此基础上只换混合域。主任务查看 [低机位 extinction](evidence/ship-water-optics-2026-10-14/research-2/low-extinction.png)、[低机位 extinction-linear](evidence/ship-water-optics-2026-10-14/research-2/low-extinction-linear.png)、[高机位 extinction-linear](evidence/ship-water-optics-2026-10-14/research-2/high-extinction-linear.png)，观察到水下船壳随深度融入蓝海，水线上方木色保留，悬浮观感减轻；仍属候选，不是最终美术验收。

[APPEARANCE_COMPARE.json](evidence/ship-water-optics-2026-10-14/research-2/APPEARANCE_COMPARE.json) 以同一 run 的无透射图为对照，在固定船底 ROI 内计算 RGB 残差，并除以同 run baseline 残差：

| 模式 | 低机位残差比例 | 高机位残差比例 |
|---|---:|---:|
| baseline | 1.000 | 1.000 |
| extinction | .324 | .557 |
| extinction-linear | .389 | .634 |

这是外观差异指标，不是物理透过率；越接近无透射对照也不自动代表越美。它支持本轮消光方向有效，线性混合在其上稍亮，不能把后者当作主要遮蔽修复。下一步应保留窄幅透明水线，强化更深处的颜色与细节衰减，再做动态、岸边和船型验收。第二轮 receipt SHA-256：`d23e36f04de615c721a88a16ab55dff09cdcb597f2b553c595b3690367d8549b`。首轮驱动保留为 [driver.gd.txt](evidence/ship-water-optics-2026-10-14/research-1/driver.gd.txt)，避免把更新后的诊断工具误认为首轮冻结版本。

## 2. “透明”并不只等于 ALPHA

需要区分三个量：材质进入哪条渲染路径、最终 framebuffer 的 alpha 混合、着色器内部取背景颜色的权重。Godot 文档说明读取或写入 `ALPHA` 会进入透明路径；4.7.2 源码的 `ShaderData::uses_alpha_pass()` 也把 screen/depth/normal texture 读取计入该分类。因此 `ALPHA=1` 既不证明使用不透明路径，也不证明最终 RGB 中没有背景船壳。[Godot spatial shader](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)、[Godot 4.7.2 uses_alpha_pass 源码](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/forward_clustered/scene_shader_forward_clustered.h)

Godot 3D screen texture 在不透明阶段之后、透明阶段之前获得；它能包含不透明船壳，却不会自动包含其后绘制的透明物体。正式源码也在 transparent pass 前准备 screen/depth copy。由此，本项目显式合成 `screen RGB` 就足以让船底可见，无须低 alpha。[Godot screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html)、[Godot 4.7.2 Forward+ 绘制顺序](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp)

实验含义：把折射偏移设为零只消除扭曲，仍会透出背景；要隔离透射，应把内部背景贡献设为零。若还需单独判断几何接触，使用保持同样顶点位移的诊断材质，取消 screen/depth 读取与内部背景合成。后者是诊断方案，不是要求正式海面永久不透明。

## 3. 深度、厚度与真正的水中光程

Godot 4.3 起采用 reverse Z；当前 Forward+ 的原始深度为近处 1、远处 0，非线性，NDC 的 Z 范围为 [0,1]。须用当前 viewport 的逆投影重建 view position 并除以齐次 W；不能直接把 raw depth 差当米，也不能混用 world Y 和 view Z。另一个 viewport 的深度不属于当前 viewport。[Godot 深度重建](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html#depth-texture)、[Godot reverse-Z 变更说明](https://godotengine.org/article/introducing-reverse-z/)

以下是基于上述坐标合同的推导，不是新的引擎 API。设背景点和水面点的 view-space 正向深度分别为 `z_b=-P_b.z`、`z_w=-P_w.z`，同像素的轴向厚度为 `Δz=max(z_b-z_w,0)`。未偏移、同一射线时，若单位射线朝向为 `r`，水中直线段长可写成 `d=Δz/max(-r.z,ε)`，或直接计算重建两点的距离。它要求坐标尺度与米一致；正交相机应使用其平行射线，而不是套用透视相机原点。

折射 UV 偏移后，背景点和当前水面点未必共线；这样的差值只是屏幕空间光程近似，不能叫作 Snell 折射后的精确路径。若偏移采到水面前方的船壳，可能制造错误的船体拖影。GPU Gems 展示前景泄漏和遮罩回退；Crest 的 `OceanEmission.hlsl` 对偏移后的深度检查，遇前景则回到未偏移采样，还处理负厚度边缘。可借鉴这个合同，但不能照抄另一引擎的 raw-depth 比较方向。[GPU Gems 2：Generic Refraction Simulation](https://developer.nvidia.com/gpugems/gpugems2/part-ii-shading-lighting-and-shadows/chapter-19-generic-refraction-simulation)、[Crest OceanEmission.hlsl](https://github.com/wave-harmonic/crest/blob/master/crest/Assets/Crest/Crest/Shaders/OceanEmission.hlsl)

本项目建议：保持颜色采样和用于厚度判断的深度采样 UV 一致；对前景、屏幕外、天空/远平面分别输出 validity 诊断，再决定回退。不要只把一切负值 clamp 掉而丢失原因。现有 ray-length 单因素差异很小，先保留它作为正确性检查，不把它提升为当前主要修复方向。

## 4. 消光、散射与颜色空间

均匀介质的光束透过率为 `T_rgb(d)=exp(-σ_t,rgb*d)`。`σ_t=σ_a+σ_s` 包括吸收和离开该方向的散射；只有忽略散射时才能把它单称吸收系数。`σ` 的单位为 m⁻¹，路径 `d` 为 m；`d=0` 时 T=1，路径增长时单调衰减。这个定律描述背景光的损失，不自动求出进入视线的散射光。[PBRT 4：Transmittance](https://pbr-book.org/4ed/Volume_Scattering/Transmittance)

建议采用的解释模型是 `L≈F*L_reflection+(1-F)*(T*L_background+(1-T)*L_water)`。其中常量或低频 `L_water` 是对散射的艺术近似，整个表达式不是完整体积光传输解；不得把“加一点蓝色”叫作精确水体散射。Crest 的公开实现也使用指数深度雾，当前 Crest 文档则分别提供 absorption/scattering 的艺术输入与计算结果，这两代接口不能混作同一实现。[Crest OceanEmission.hlsl](https://github.com/wave-harmonic/crest/blob/master/crest/Assets/Crest/Crest/Shaders/OceanEmission.hlsl)、[Crest Water：Color](https://docs.crest.waveharmonic.com/Manual/Appearance/Color.html)

为解释参数量级，可从指数式推导半衰减距离 `d50=ln(2)/σ`。下表只计算两组系数的指数权重，假设输入路径为米；它不是实测海水光谱，也不是最终屏幕亮度。特别是现有 display 域合成会改变这些权重的光能意义。

| 参数组 | 1 m 时 T，RGB | 半衰减距离，RGB 米 |
|---|---|---|
| 当前 (.19,.075,.035) | (.827,.928,.966) | (3.648,9.242,19.804) |
| 已测候选 (.8,.4,.22) | (.449,.670,.803) | (.866,1.733,3.151) |

这说明两组参数对短路径背景细节的保留程度明显不同，但不能把船底的 −2.444 m 垂直几何间距直接代入，充当对应像素的光程。下一轮可以固定颜色、折射和反射，仅对消光量做小范围标定；随后单独试低频散射色。接受标准应是水下细节随路径合理衰减、浅水仍有层次、船体接触清楚，而不是保证所有水下几何永远不可见。

Godot Forward+ 在线性颜色空间渲染；sRGB 颜色纹理需要合适的 `source_color`，法线、粗糙度、高度等数据纹理不应按颜色解码。要先标注 screen、reflection、水色和诊断纹理各自的编码，避免对已经线性的 HDR 中间结果再次解码。[Godot source_color](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html#using-source-color)

光能合成要求线性量。设显示编码为 E，则 `E⁻¹(T*E(L_b)+(1-T)*E(L_w))` 通常不等于 `T*L_b+(1-T)*L_w`；事后转回 linear 并不能撤销中间的非线性混合。这个区别是数学正确性问题，不意味着转换后一定更暗或更能遮住船壳。[GPU Gems 3：The Importance of Being Linear](https://developer.nvidia.com/gpugems/gpugems3/part-iv-image-effects/chapter-24-importance-being-linear)

一个独立算例：只为说明，采用 `E(x)=x^(1/2.2)`，背景为 1、水色为 0、T=.5。display 混合再解码约为 .218，线性混合为 .5。因此修正颜色域可能变亮；这与本轮主任务观察相容。该幂函数只是示例，不是对本项目实际 sRGB/色调映射函数的声明。应把“修正合成域”和“重新标定消光/散射”做成两个独立实验，不同时改曝光或全海亮度。

## 5. Fresnel、平面倒影与 SSR 各负责什么

Schlick 近似可写为 `F=F0+(1-F0)*(1-max(N·V,0))^5`，`F0=((n_air-n_water)/(n_air+n_water))²`。采用空气 1、水 1.333 的假设时，F0≈.0204；掠射角反射增强。Crest 实现这类计算，同时允许调节幂和 specular，后者属于可调近似；不宜用任意高的固定反射比例掩盖错误透射。[Crest OceanReflection.hlsl](https://github.com/wave-harmonic/crest/blob/master/crest/Assets/Crest/Crest/Shaders/OceanReflection.hlsl)、[Crest Ocean.shader 参数](https://github.com/wave-harmonic/crest/blob/master/crest/Assets/Crest/Crest/Shaders/Ocean.shader)、[PBRT 4：Dielectric BSDF](https://pbr-book.org/4ed/Reflection_Models/Dielectric_BSDF)

平面反射的一手实现通常镜像相机、构建反射视图、裁掉反射面错误一侧，并处理镜像后的绕序/剔除；Crest 还排除海面自身以免反馈。单个反射平面加水面法线扰动，是对起伏水面的近似，不是每一片五波曲面都拥有精确镜像。若要排查船底倒影，应观察原始反射纹理与裁剪侧，而不是先提高反射强度。[Crest OceanPlanarReflection.cs](https://github.com/wave-harmonic/crest/blob/master/crest/Assets/Crest/Crest/Scripts/Reflection/OceanPlanarReflection.cs)、[GPU Gems 2 反射/折射水面示例](https://developer.nvidia.com/gpugems/gpugems2/part-ii-shading-lighting-and-shadows/chapter-19-generic-refraction-simulation)

Godot 的 SSR 只支持 Forward+，依赖屏幕已有信息，不能补出屏外或遮挡后的对象，也不包含透明对象；增大 depth tolerance 可能减少断裂但制造错误反射。因此“开启 SSR”不是这个已有平面倒影项目的首选修复，也不能保证屏幕读取的透明水材质获得预期结果。[Godot SSR 文档](https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html#screen-space-reflections-ssr)

当前 18 图已证明物体倒影存在。应保留这一事实；如果后续发现倒影中的船壳错误，再单独验证镜像平面高度、裁剪偏置、剔除层和相机投影。Unity 的斜裁剪矩阵不能未经 Godot reverse-Z 验证直接移植。

## 6. 吃水、湿水线与透明排序

浮力/姿态查询和光学遮蔽是两个系统。Crest 官方区分表面法线对齐与探针施力，且明确提供独立的高度偏置及查询波层选择。不能仅凭船壳仍可见就更改浮力高度。[Crest Floating Objects](https://docs.crest.waveharmonic.com/Manual/Basics/FloatingObjects.html)、[Crest FloatingObject 参数](https://docs.crest.waveharmonic.com/Components/Physics/FloatingObject.html)

建议继续使用真实完整模型变换计算接触：对船壳点 `P_i` 记录 `g_i=P_i.y-H_five_wave(P_i.x,P_i.z,t)`，另列 GPU 局部位移；保留 scale、pitch、roll 和同一 accepted time。点位覆盖船首、船尾、两舷与龙骨，不用名义尺寸或模型 pivot 代替实际水线。当前顶点统计已经排除了“整个船壳完全在水上”的解释，但尚未证明所有船型的设计吃水都正确。

湿水线可作为之后的**独立艺术实验**：只在实际交线附近试小幅粗糙度/颜色变化，仍以同一动态水面为依据。该方案尚未实现、尚无视觉验收；不建议用固定黑环、均匀白泡沫或把船整体下移来遮住剩余问题。先稳定透射，再判断是否确实缺少这一接触提示。

Godot 透明对象按 Node3D 位置排序，不是逐三角形排序；priority/offset 只能缓解部分情况。4.7.2 的普通透明 pass 在 `depth_draw_opaque` 下关闭深度写入，而强行写深度会改变后绘制物体的遮挡关系。因此改成 `depth_draw_always`、改透明优先级都应是独立且有证据的实验，需同时检查泡沫、飞溅、帆和水线边缘。[Godot 透明排序限制](https://docs.godotengine.org/en/stable/tutorials/3d/3d_rendering_limitations.html#transparency-sorting)、[Godot 4.7.2 深度写入源码](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/forward_clustered/scene_shader_forward_clustered.cpp)

## 7. 最小后续实验与通过证据

以下是由资料和现有实测推导的建议，不是已经完成的实现。保持五波参数、双侧尾迹 field、船舶状态、相机、accepted time、曝光、色调映射、分辨率与 GPU 质量相同；每个候选仅改变一项。沿用本次内存 QA 变体，不先改正式默认值。

| 优先级 | 单因素 | 需要记录 | 通过条件与风险 |
|---|---|---|---|
| 1 | 在细化轮候选附近继续动态标定消光量；保留当前颜色域作基线 | 船壳 ROI 原图、T/路径热图、低高机位、系数 | 保留窄透明水线，深处细节合理衰减，浅水不成实色；避免仅靠整海变暗 |
| 2 | 固定选定消光，仅换 linear 合成 | 合成前背景/水色的编码、HDR 数值与最终 PNG | 颜色域清楚、无双重解码；若变亮，作为重新标定需求记录，不宣称失败或治愈 |
| 3 | 固定透射，单调低频散射色/强度 | 同场景深浅水、晴天/阴天的配对图 | 维持可读层次，不新增完整体积渲染系统 |
| 4 | 只关闭折射偏移，或只显示采样 validity | 偏移前后 UV/深度、前景/屏外/天空拒绝计数 | 不把前方船壳错误当水下物体；若原图无泄漏则不扩修 |
| 5 | 只显示 Fresnel 或原始反射目标 | N·V、F、反射图、镜像相机/裁剪状态 | 正常倒影保留；仅对已证实错侧/错位修正 |
| 6 | 只增加窄幅动态湿水线 | 真交线、完整模型姿态、开关成对图 | 接触更明确且不出现固定黑环；独立验收，不掩盖光学错误 |

另需一个小型正确性夹具：静水面与已知背景平面相隔 1 m，验证重建距离与单位；把背景移到前景、屏外及天空，检查回退和无 NaN。1 m 夹具可预先约定厘米级容差，但该容差是测试目标，不是当前引擎已达成指标。不要用真实动态船的最深顶点代替这个解析基准。

正式推广前至少补连续波峰/波谷、左右转弯、停船、小船与大船；画面必须能看见水线和两侧尾迹，镜头取景一致。Receipt 保存实际船姿、同一模拟时间、场纹理 generation/bounds、源码 SHA、原始 PNG 和逐因素配置。CPU 合同测试只验证数值与生命周期；艺术接受仍需原图及连续运动观察，不能用 `valid=true` 代替。

## 8. 来源范围与限制

技术依据仅使用 Godot 官方文档/源码、NVIDIA 作者章节、PBRT 作者教材及 Crest 官方文档/公开实现。Godot 实现引用固定 `4.7.2-stable` 标签；`stable` 文档与 Crest `master` 为 2026-10-14 查阅的可变页面。Crest 开源 BIRP 代码与当前 Crest Water 文档属于不同代产品；本文借鉴原理，不声称可直接搬用到 Godot。将来若复制实现，须另行固定具体修订及核对许可。

本文的已验证结论限于：来源支持的机制、两轮共 26 条 receipt 的组内一致性、已有像素统计，以及明确归属主任务的源码/原图观察。两轮 GPU 实验只覆盖一艘船、两个机位及同一接受时刻，尚未完成连续风浪、多船型与岸线视觉回归；未测量排水体积或真实海水参数，也未证明全游戏性能。当前最有证据的下一步是小范围消光/散射标定与动态接触观察；岸羽化、射线长度、SSR 或整体下沉都不应在缺少新证据时扩大为主修复。

## 9. 复核与查看

- [同态原图对照页](evidence/ship-water-optics-2026-10-14/review.html)：现有、消光＋线性候选、无透射诊断，各两机位。原PNG无重绘或修改；对照HTML已生成，其浏览器交互未另行验收。
- [综合证据 VERIFY.json](evidence/ship-water-optics-2026-10-14/VERIFY.json)：两轮26图的SHA、归档驱动SHA、摄像机/几何一致性、正式运行时未改变检查。

只读复核命令：

```powershell
rtk proxy node tools/verify-ship-water-optics-research.mjs
```
