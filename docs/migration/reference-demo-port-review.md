# Island-water demo Godot 移植独立审核

日期：2026-10-11。当前阶段仅海岛/海面独立预览。原参考 `C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/demo/{model,renderer,shaders,app}.mjs` 已逐行只读检查；设计依据为 `docs/superpowers/plans/2026-10-11-reference-demo-godot-port.md`。CodeGraph 本会话不可用且目标未索引，按主任务要求使用 RTK fallback。不修改 worker 源码，不启动 GPU、完整 runner 或性能工作。

## 当前状态

**最新补充：发布启动参数截图协程的P2已修复并独立复验关闭，见文末限定审核。当前无确认的未解决P1/P2。最终取消guard版本已独立通过scene focused 35/0；此前主线程78/78完整runner属于guard修改前版本，不能冒充最终guard的完整回归结果。**

主线程通知 source-ready 后，已完成当前 ocean renderer/model、四波采样、water/sky/terrain shader、原生场景、菜单/router/主场景退出链的最终源码审核，并独立执行三项 focused headless 测试；随后完成分层修复的限定复审。**当前无确认的未解决 P1/P2。**本审核亲自执行的范围为源码合同及 headless 验证；最终四texel颜色过滤版本的 GPU 画面对照由主线程另行完成，证据归属见末节，不以这里的数学断言替代。

## 严格验收矩阵

| 项目 | 原源码合同 | 必测与判定 |
|---|---|---|
| 输入数据/比例 | app:20–22；索引图120×140；extent160、heightScale0.35、seaIndex128 | 原JSON与复制资源哈希/values一致；不能用彩色预览亮度替代palette索引；显示比例不标为原作物理常量 |
| 原始高度 | model:13–20 双线性；闭区间[-80,80]，外部-20 | 中心、四角、四条边、刚越界、非整坐标；原始height_at与mesh-height两种接口不可混用 |
| 地形网格 | model:21–33，res160，161²顶点，a,c,b / b,c,d | 所有positions/normals/indices对JS fixture；法线用clamped半步高度差，先double归一化再Float32；Godot面剔除适配不能改查询对角线 |
| 实际三角高度LUT | renderer:19–23，从已绘Float32顶点Y生成R32F；shaders:79–92手工texelFetch | LUT161²各texel与mesh顶点Y逐项相等；cell两侧、ax+ay=1与epsilon、末行末列、边界和外部；使用NEAREST/无mip/无sRGB。原model.meshHeightAt是double顶点近似，不能把它当GPU实际三角高度的唯一oracle |
| 海底环带 | renderer:15调用seabedApron(field,160)，不是默认64；model:67–81 | 5×640=3200顶点、15360索引；首圈贴原边界，其余高度-16/-30/-60/-80；累计面法线后归一化，环闭合与角点无裂口 |
| 水网格/footprint | model:43–53，res192，193²顶点；spread .7→120，外圈二次扩展→1000 | 先生成Float32原网格，再spread并写Float32，再由邻点差构造footprint；不能用理想double间距替代；中心、.7转折、四角、边界邻居均比对 |
| 四Gerstner波 | model:2–8、55–64；Q=.42；phase=k dot(d,base)-speed*time | 4个原方向归一化、振幅/长度/速度不改；strength0/1/2、tide-3/0/4、负/零/固定时间；position含XZ位移；normal=normalize(cross(dz,dx))，以有限差分独立检验上法线 |
| 两级波细节滤波 | waveVisibility与waveCode：长度*.25至*.5；waterFS:107–109：world导数*.4至1.3 | 顶点footprint与fragment footprint不能合并；四波逐一测试两个阈值及中点；waves=false令uStrength0，同时关Gerstner与ripple，而非停time |
| 水深/折射 | shaders:103–117；主场景opaque颜色/深度、view-depth差、前景fallback | reverse-Z用实际inverse projection适配；不得套WebGL固定公式；Godot SCREEN_UV方向需连同n.xz偏移验证；near/far、地形前景遮挡、浅水/深水、出屏UV clamp均覆盖 |
| 平面反射相机 | model:85、renderer:94–96；eye/target绕tide镜像，up=[0,-1,0] | 共享同一World3D；主/镜像相机pose、投影aspect、tide同步；镜像使用向下up不能仅翻eye.y；检查左右不翻、上下映射正确、地平线及非中心landmark |
| 反射排水与clip | 原scene()先sky+land+apron，无water；terrainFS uClip时discard y<tide-.02 | 水仅layer20、镜像cullmask排除bit19；无递归水面反馈；共享材质不能用两相机争写uEye。镜像低于tide识别仅在app相机始终高于水面的约束内成立，检测不误裁主pass |
| 反射采样 | waterFS:120–121，rp.xy/rp.w*.5+.5+n.xz*.009 | rp.w>0、UV严格0..1，失败回程序sky；ViewportTexture Y翻转必须连同偏移一起适配，不能单独反转投影而保持错误distortion符号 |
| 颜色与光照 | 原全套display-space程序色；scene/reflection targets为RGBA8 | Godot sampled linear先转display，公式结果再转linear；unshaded、无额外fog/PBR/ACES/exposure。须处理原RGBA8中间clamp，否则太阳>1会改变折射/Fresnel结果；8bit量化差异明确记录，不把HDR结果称逐像素等价 |
| 水面末端公式 | waterFS:115–133 | absorption(.19,.075,.035)、水色/指数.08、Fresnel .02/.98、spec指数110×.7、foam band/width及noise、fog指数.0015全对应；未引入原demo没有的调色或风浪参数 |
| 天空 | common.sky、skyFS:71，tan(FOV/2)=.41421356 | 相机实际forward/right/up与aspect形成相同ray；镜像sky不能仍用主相机朝向；sunset唯一改sun/sunColor，storm仍用clear太阳 |
| 渲染尺寸 | renderer:58–62，源DPR上限1.5；reflection宽min(768,viewWidth)，高round(rw*h/w) | 明确Godot实际render尺寸与源CSS/DPR映射；宽小于/大于768、纵向窗口、极小viewport和resize后texture/projection一致；保持实际aspect，不把反射固定为正方形 |
| 默认/预设状态 | app:4–6、11 | clear,strength1,tide0,foamWidth1.5,四开关true,pausedfalse；orbit(-.65,.68,185)，target0/upY；clear1、sunset.65、storm1.8，只改preset和strength，其他状态保留 |
| 输入/重置/暂停 | app:12–18、27 | drag -.006dx/+.004dy，elevation clamp[.22,1.25]；滚轮指数与Godot离散wheel映射说明；distance[70,280]；reset仅orbit；dt cap .05，暂停/隐藏不加time但仍可render/调相机；截图不得推进time |
| 错误与释放 | 原resize释放旧targets；新Godot需显式owner生命周期 | configure失败可清理；重复dispose、进入/退出/重新进入、反射toggle/resize/camera失效不留viewport或悬空texture；Environment/World所有权不得影响现有游戏场景 |

## 首轮风险提示

1. **RGBA8与HDR差异**：原renderer.mjs:50使用RGBA8。只增加sRGB转换还不足以复制原离屏pass，超1颜色要在对应阶段截断。原程序天空计算值可超过1，而原offscreen texture已经截断；水面直接程序sky fallback则在最终输出才截断，两条路径不可混为一谈。
2. **实际Float32三角面**：原model.meshHeightAt以double重新查询四个高度；renderer GPU LUT来自Float32已绘顶点。冻结fixture应区分这两个oracle，以实际顶点三角面为岸线合同。
3. **反射up与Y翻转**：镜像eye/target、up=[0,-1,0]、projection→UV、ViewportTexture方向以及法线扰动偏移是一整条链，单看镜像相机位置或一张对称岛图不足以证实。
4. **状态语义**：reset不重置时间/潮位/预设；storm只调strength；暂停仍可改变相机和开关。新增独立入口应保持这些原app行为，同时不改变既有五波游戏物理或存档地理。

## Source-ready 最终审核结果

- **地形实际表面**：terrain位置、法线、UV、indices与JS生成fixture整数组SHA校验；R32F LUT整图SHA校验，来源为实际Float32绘制顶点。两个cell半三角的手工插值保留a,c,b / b,c,d对角线，闭区间边界及外部-20规则一致。环带使用160 segments且累计double法线后转换Float32。
- **四波与滤波**：四组方向/幅值/长度/速度、Q=.42、负time项、水平位移、cross(dz,dx)法线逐表达式对应源代码。ocean_model先写Float32规则网格、spread后写Float32、再求相邻footprint；UV.x仅替代独立顶点attribute。shader保留顶点长度滤波和fragment导数细节滤波。新增世界XZ反求接口与原参数XZ的wave_at明确区分，未接替旧游戏五波物理。
- **水面公式与颜色**：保留原吸收、水色、Fresnel、高光、深度泡沫、程序噪声及雾公式。Godot reverse-Z由当前inverse projection重建view depth；SCREEN_UV折射及反射UV的Y方向和n.z扰动同时翻转。terrain/sky离屏颜色与water最终输出在display-space clamp到[0,1]再转linear。screen/reflection各四个texel先linear→display再双线性mix，避免在线性光空间过滤后才转换。未实现源RGBA8逐texel8bit量化，属于已知有限精度差异；没有错误地对过滤结果再round，不宣称逐像素字节相等。
- **反射/尺寸**：只有一个镜像SubViewport，与预览相机共享World3D；水层为bit19，镜像cullmask排除该位；源相机和镜像使用一致投影参数，镜像实际viewport aspect参与projection。正常尺寸下宽min(768,actualWidth)、高round(width*actualHeight/actualWidth)。镜像eye/forward/up以潮位平面反射，helper UV与实际camera.unproject一致；反射关闭和相机detach禁用viewport，reattach恢复。原生最小目标2px与源最小1px不同，原生UI最小320×280下不触发。
- **每pass地形状态**：共享材质使用CAMERA_POSITION_WORLD计算雾眼点，避免主镜像相机争写眼点。clip借镜像camera低于水面识别反射pass，在源app限制的elevation≥.22、distance≥70、tide≤4下主camera始终高于水面，因此正常交互域不会误裁主pass；未宣称支持任意水下主camera。
- **原生状态与菜单**：默认字段、预设strength切换、四开关、潮位/强度/泡沫范围、orbit公式、拖动尺度与dt上限.05一致；reset只改orbit，不写time/state；暂停仍调用render。set_state先构造next并逐项验证，失败不部分提交。water-study通过菜单白名单、router路径和staged startup进入；MainScene返回先禁process，再延迟移除/free，触发scene.dispose，镜像viewport与world随owner释放。未更改航行存档或现有游戏地理。
- **已知原生交互适配**：scene._process以窗口focus和场景visible决定是否加time，而源app只检查document.hidden，因此可见但失焦时原生预览暂停；Godot离散wheel按每格±120映射源wheel delta；preview使用原生SubViewport像素尺寸，没有复制网页CSS×DPR上限策略。这些不影响同相机/同time的聚焦画面对照，但不是完全相同的宿主输入行为。

## 独立实际执行与证据边界

Godot `4.7.2.stable.official.ed1daf0bf`；每项使用 `--headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/...`。未调用GUI、GPU截图、完整runner或性能测量，未修改任何实现源码。

| focused test | 独立结果 |
|---|---|
| `test_reference_demo_terrain.gd` | 591 assertions / 0 failures，exit0，无Godot错误 |
| `test_reference_demo_ocean.gd` | 最初3232；分层修复后独立复验3249 assertions / 0 failures，exit0，无Godot错误 |
| `test_reference_demo_scene.gd` | 21 assertions / 0 failures，exit0，无Godot错误 |

三项涵盖源网格/LUT哈希、波/法线/世界XZ反求、镜像投影与detach/reattach、非法非finite状态原子拒绝、暂停/隐藏时间、状态范围及幂等dispose。headless shader加载和uniform检查不证明实际GPU编译/屏幕采样颜色或图像方向；菜单路由与主场景释放在本审核中为源码追踪，实际菜单/画面交互证据由主线程提供。

## 分层修复最终限定复审

`ocean_renderer.gd` 已删除 `physics_engine/reference_gerstner_wave_field.gd` import，上传入口改为同层 `ocean_model.wave_uniforms()`。新函数以同四组源方向、amplitude和wavelength，在double scalar中执行相同sqrt归一化与TAU/length，再构造Vector4上传；未改变shader中的四个speed、Gerstner、法线、footprint或颜色/反射表达式。新增16项逐分量精确比较证明渲染层uniform与之前CPU descriptor产生的Float32值相等，而原JS位置/法线fixture仍保留。此修复未使terrain或renderer反向调用物理层，层守卫未放宽。

本审核独立执行：`test_layer_boundaries.gd` **16 assertions / 61 files / 0 failures**；`test_reference_demo_ocean.gd` **3249 assertions / 0 failures**；均exit0、无Godot错误。仅更新此审核报告，未修改实现，未运行完整runner或GPU。

## 主线程另行提供的最终实景证据

主线程报告最终过滤版本已完成15个状态、30张原始PNG及原生保存画面，capture exit0/failures0，亲自查看5张contact sheet，并与原浏览器同状态静态画面作定性对照。本审核只核对证据索引存在及其 `captureStates=15`、`nativePngCount=30` 和状态元数据，**没有执行该GPU捕获，也没有代替主线程亲自看图**；对照不是逐像素一致性证明。

外部证据：[visual-index.json](evidence/reference-demo-port/visual-index.json)、[原生保存画面](evidence/reference-demo-port/native-saved-frame.png)、[静态源状态](evidence/reference-demo-port/static-source-state.json)。主线程最终截图结果取代预审时“过滤版本待复拍”的状态；完整runner最终结果由主线程另报，本审核不据此虚构通过结论。

## 新增发布启动参数的限定审核（P2已修复关闭）

范围仅 `main_scene.gd` 新增 `_request_startup_preview` / `_capture_startup_preview` 及其保存返回保护。前述海水/分层结论保持；新增入口审核曾发现以下取消生命周期问题，现已修复。

**已修P2：已取消的启动截图请求可捕获随后另一轮预览。** 修复前 `main_scene.gd:47–50` 等待ready只验证主scene未dispose，未绑定发起请求的router generation/nonce；用户在启动loading期间Back/cancel后，旧协程仍等待最多240帧，在 `:53` 接收后续新打开的任意带save_frame的scene。结果是本应取消的请求仍写截图/元数据，并将另一轮状态标记为原启动请求。原`:57` await save_frame返回后也缺少再次验证请求token、preview存活和current_scene身份。

独立无GPU复现脚本 `C:/Users/dains/AppData/Local/Temp/reference_review_startup_capture_cancel.gd`：启动截图协程，调用router.cancel，下一帧挂载另一轮preview probe，观察旧协程是否调用其save_frame；probe只返回失败，不写任何图像文件。修复前实际输出 `CANCELLED_REQUEST_CAPTURED_LATER_PREVIEW=true`。问题已即时报告主线程，审核未修改实现。

修复前独立 `test_reference_demo_scene.gd` 为 **30 assertions / 0 failures**，exit0无Godot错误：覆盖未知/空args保留菜单、真实Button→staged/router→native启动、无新增游戏存档、active preview重复请求不替换，以及返回后释放，但当时未覆盖截图协程等待取消路径。无参数正常启动只新增一个立即返回的deferred检查，没有自动进入预览或写截图。

最终修复由同步按钮intent带入capture path，`_handle_intent` 从本次成功prepared深拷贝request，再传入capture协程；`router.is_current`联合校验generation、nonce及operation。ready等待每次yield后、8帧稳定等待后、save_frame返回后均验证请求；后两处同时验证preview存活和current_scene身份。场景save_frame也在frame_post_draw返回后验证disposed/view，避免已释放的预览继续取图。

独立最终复验：`test_reference_demo_scene.gd` **35 assertions / 0 failures**，exit0无Godot错误；新增真实有效token后取消等待、保存期间取消后不访问snapshot/不写metadata。原独立复现适配新的request参数，先确认 `REVIEW_REQUEST_VALID=true`，然后得到 `CANCELLED_REQUEST_CAPTURED_LATER_PREVIEW=false`，exit0且无错误。因此关闭该P2，当前无新增未解决问题。未执行GPU或完整runner；主线程guard前78/78完整结果与最终guard的focused验证分别记录，不混淆版本。
