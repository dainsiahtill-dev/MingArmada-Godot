# 岸线交界覆盖率羽化：预先设计与接受标准

- 日期：2026-10-14；课题：既有 `shore-surf` 的水岸覆盖率候选，不另建重复算法课题。
- 状态：初版设计及其默认0阶段记录保留。最新阶段按用户连续反馈，由主线程将正式／Demo宽度选为0.6；本Agent仅新增局部water weight，不重置该宽度。新weight候选的GPU接受仍待主线程。
- 来源：用户提供的沙滩／浅水交界原图，当前 `reference_game_water.gdshader` 与生产岛材质。用户图未附相机、时间、源散列和viewport，不能当本候选实测。
- 基线 shader SHA256：`87ed0e1baebc6fa281b96f38a4036442045ec08adbd21caedef9ab224dfb29ca`。
- 范围：一个现有海水uniform、纯coverage include、独立合同测试、此设计；不改岛透明度、五波、泡沫、尾迹、物理、原光学公式或接受时钟。

## 问题与假设

最新局部透明阶段（新增函数实施前写定）：用户要求过渡范围接近第一道岸浪，并让靠沙滩、推进浪消散后的带更透明。宽度0.6由主线程已选，固定不变。H2：只降低覆盖带内海水合成权重，可使该带显示更多原沙滩／浅底，同时coverage的0/1端点、深海和先前宽度因子保持不变。与H1初版阶段分开，不将新用户反馈倒写为初版已满足。

目前水面干地mask直接discard；全部水面光学完成后ALPHA恒为1。水／岛在几何交点由深度获胜关系切换，现有 `reference_shore_transition` 仅混入最多12%浅青色，不是覆盖率羽化；`reference_bottom_visibility` 处理海底有限窗口，是另一边界。

H1：在相同地形、原光学、泡沫和接受时间下，只令水面颜色覆盖率在交界连续趋近实际不透明场景，可降低沙滩／浅水颜色跳变，同时保持远海、岛遮挡和所有模拟状态。

反例：边缘仍跳变；生成另一条带状轮廓；深海船壳旁的水变透明；未折射背景颜色合同错误；暂停对照改变time/native历史；关闭uniform仍改变基线。

world Y向上，地形与水面高度、光学垂直厚度和宽度均为米。宽度是垂直厚度，不是沿岸水平距离；0.35m在坡度0.1处约等于3.5m水平带，在坡度0.02处约17.5m。平滩的过宽褪色是明确失败风险。

## 方案比较

采用完成海水颜色与实际未折射opaque scene的线性合成，ALPHA保持1；岛继续提供当前screen/depth。直接将岛改为透明会改变其opaque/depth参与，破坏本实验依赖的数据基础，故不采用。

海水ALPHA直接变为coverage是另一候选，但当前depth_draw_always仍写深度，薄浪、喷雾及透明对象排序须另做实验；不与本候选混合。

不使用既有coast_distance gate：它是mean-tide真实零交叉的粗RF无符号近似距离，不能保证对齐本次实际三角地形或波面交点。它可能提前关闭羽化、重新制造轮廓。使用实际高度clearance的局部带门控，保证远离地形接触时深度边缘不会单独触发。

## 算法与实现

记 `h` 为当前height_at采样，`tide`和`water_y`沿用当前接受状态；`D`为当前未折射SCREEN_UV下的光学view-depth厚度，`v`为当前视线单位向量。纯函数输入：

```text
dry = tide + 0.035 - h       # 与已有干地discard严格同边界
water = water_y - h          # 实际被绘制水面与地形的垂直clearance
optical = D * abs(v.y)       # 视线深度差的垂直近似
w = shore_edge_feather_m
if w <= 0: coverage = 1      # 精确旁路，不使用smoothstep(0,0,x)
else:
    terrain = min(dry, water)
    d = max(0, min(terrain, optical))
    near = 1 - smoothstep(w, 2*w, max(terrain, 0))
    coverage = mix(1, smoothstep(0, w, d), near)
```

terrain≤w时即为已选的三clearance最小值公式；w至2w连续关闭光学深度修正。terrain≥2w时严格返回1，即使opaque depth来自深海近处船壳／物体也不触发羽化。每像素O(1)，不新增纹理资源、RNG、clock或历史。

光学vertical是由view Z差乘单位视线Y得到的近似，斜视时不等于精确射线长度差；实际高度为主要门控，深度只在接触带内收紧，GPU低位镜头须检查其偏差。

新增uniform `shore_edge_feather_m` 默认0，实验候选0.35，控制域有限[0,1]。仅 `mask_dry_terrain && (has_shore_field || has_reference_near_field)` 参与；没有有效地形输入的深海旁路。已有field范围之外回落-20m时，局部带返回1。

原海水完成颜色、fog和display→linear转换仍原样执行；仅coverage<1时在**线性空间**合成：`C = mix(texture(u_scene,SCREEN_UV).rgb, C_water_linear, coverage)`。取未折射SCREEN_UV，避免边界恢复邻近被扭曲沙滩／船壳。ALPHA=1和已有depth策略保留。海水依赖的全部opaque背景／色彩合同必须由目标backend实拍核对。

最新候选增加纯函数 `reference_shore_edge_water_weight(coverage, weight)`：

```text
b = clamp(weight, 0, 1)
water_weight = coverage * mix(b, 1, coverage)
             = b*coverage + (1-b)*coverage²
```

新增uniform `shore_edge_water_weight` 默认0.55、控制域[0,1]；仅在已有coverage<1时调用并用water_weight替代最后合成权重，不改coverage公式、宽度0.6、原光学、泡沫或ALPHA。weight=1恢复同宽度先前效果；coverage=0仍0、coverage=1仍1。深海coverage1不进入新函数／背景采样分支。导数 `b+2(1-b)*coverage` 非负；降低weight只提高局部背景贡献，不生成负透明度。

## 实验设计

最新water weight的预先接受值：纯函数先RED再GREEN；误差≤1e-6；coverage三端点0/0.5/1与weight0/0.55/1手算；0.55时中点0.3875，四分点0.165625、四分之三点0.665625；weight1严格恢复coverage、非法域外weight被夹到端点。输出单调且[0,1]，邻边±1e-5仍连续；真实deep-water coverage1经新函数仍1。实际shader默认宽度仍0.6，新weight默认0.55；同刻改变weight不改wave/time/grid/mirror。

最新GPU固定width=0.6，仅比较weight=1和0.55；主线程保存用户指定第一道岸浪内、沙滩与推进浪消散带的同刻近景，确认更多背景贡献且没有新轮廓或远海变化。若新带仍不透明，保留失败并检查coverage是否已等于1，不能通过继续降低weight突破该端点合同。原H1的0/0.35矩阵是前一阶段，不混算为本阶段通过。

先写缺失纯函数的RED，再执行实际include函数体的手算CPU夹具，不复制一份独立算法冒充生产验证。另以实际Ocean材质验证uniform默认0及设置0.35后原五波、纹理、时钟、镜像所有者不变。

CPU接受值：无失败／Godot ERROR；标量误差≤1e-6；w≤0严格1；接触d≤0为0；d=w/2为0.5；terrain≥2w即使optical为0仍为1；w..2w的深度修正连续，端点附近±1e-5的输出差≤1e-3；输出在[0,1]。宽度0不取新背景样本且保留原ALBEDO路径。

GPU接受值在执行前固定：基线0、候选0.35，只差此uniform；实际field/mesh/texture/hash、viewport、quality、transform/projection及tick相同。先取得能复现硬线的干净原帧，冻结岸线ROI和沿其法向的取样段，避开UI、箭头及非岸物体。候选的岸线RGB相邻像素最大跳变中位数须≤基线70%，且人工检查没有替代硬圈、过宽褪色或岸上覆盖。没有baseline硬线时此项记“不足以判定”，不能宣称通过。

同刻A/B与连续序列分别保存：t=0、0.5、2、8秒；近景俯视、斜视和低位。原泡沫全开为正式比较；关闭残沫／折射、mask关闭只能作为单独标注诊断，不可代替正式候选。检查平滩、常规坡面、陡岸、离岸浅洲、岸边船壳／码头、薄浪和喷雾、镜像和深海。0.1／0.35／0.6宽度仅在主0.35实验后作独立宽度因子，不能事后改主接受门限。

资源／状态接受：相同time/tick、wave descriptor和原生更新数；暂停同刻变化不推进；重置/释放依原宿主合同；深海像素在稳定目标上与基线差≤1/255每RGB通道，边缘ROI内变化不算远海失败。图形backend、实际色彩空间和MSAA必须记录，未测backend不宣称支持。

性能为隔离arena frame interval，充分暖机后交替32组0/0.35，保存每个样本和nearest-rank p50/p95。候选p95不得超过同场景基线10%；这只限定本arena，不能推出正式游戏FPS。新scene采样只在真实coverage<1的带内发生。

## 结果与证据

写定本设计时，本候选CPU／GPU均未运行。后续追加真实命令、输出、完成标记、退出码、ERROR检查、源码散列和结果，不以计划文本代替验证。旧reference_shore_feather回执仅证明旧海底窗口／色带，不证明本交界覆盖率。

本轮随后实际执行（均headless，Godot `4.7.2.stable.official.ed1daf0bf`）：

- RED：`rtk proxy node tools/verify-godot.mjs --filter shore_edge_coverage --output Temp/shore-edge-coverage-red.json`；缺少独立coverage函数，`SHORE_EDGE_COVERAGE_TESTS assertions=1 failures=1`、退出码1。是功能缺失失败，无parse/import错误。
- 首次GREEN尝试保存于 `Temp/shore-edge-coverage-green.json`，实际97项／1失败。纯函数全部夹具通过，但未显式覆盖的shader默认uniform在headless `ShaderMaterial.get_shader_parameter` 返回null，测试把它当数值0，造成错误断言。保留这次失败；未因此改生产默认或添加伪造材质值。
- 修正测试读取当前实际shader的uniform初值并执行它，验证初值下的coverage行为；该项为源码初值／标量合同，不伪称GPU读取。命令 `rtk proxy node tools/verify-godot.mjs --filter shore_edge_coverage --output Temp/shore-edge-coverage-green-v2.json`；唯一完成标记 `SHORE_EDGE_COVERAGE_TESTS assertions=99 failures=0`、退出码0，无Godot SCRIPT ERROR／ERROR。包含手算、连续性、单调界限及实际Ocean宽度设置后的wave/time/grid/mirror合同。
- 当前shader同时复跑独立海面63项、生产Ocean integration87项和layers15项、旧shore_feather29项，全部退出码0，无Godot错误。回执分别为 `Temp/shore-edge-ocean-regression.json`、`Temp/shore-edge-production-ocean-regression.json`、`Temp/shore-edge-old-feather-regression.json`。这里只运行4项受影响旧脚本，不宣称完整仓库审计。

此阶段冻结SHA256：`reference_game_water.gdshader` 为 `2be7cfcaa6d7fabd32e23b8e9723deab99768d9eafeb0f7997366f3ac911dabc`；`shore_edge_coverage.gdshaderinc` 为 `72eb9dd5a5322ab869342cd5ac37f6ece229f80993d73a7800c8978c1c0bdd1d`；`test_shore_edge_coverage.gd` 为 `15a503e30d4a0335d1132ede2cedd3ff53758d38b9c029a8d961c8551bb5a423`。production默认仍0，修改仅为新增9行seam与纯include，不改原公式。

真实GPU同刻／连续原帧、颜色空间、透明对象遮挡、岸线跳变指标及性能接受值仍未测；主线程另行执行与归档。GPU接受后若选择改变生产默认，须明确更新本阶段的default关闭合同、源散列及新回执，不能把默认0的旧通过直接赋给最终候选。

最新局部water weight阶段的新实测：本阶段起始shader SHA256为 `db7db1a1840ba336aba003750c86e1b1cf9ae83a3f019f128fae9fb782531381`，已经包含主线程所选宽度0.6；本Agent未改宽度或Demo。

- 先适配标量函数提取器的name／任意参数和clamp映射，再添加新函数夹具。命令 `rtk proxy node tools/verify-godot.mjs --filter shore_edge_coverage --output Temp/shore-edge-water-weight-red.json`；完成标记92项／1失败、退出码1，明确缺少 `reference_shore_edge_water_weight`，无parse/import错误。
- 实现纯函数与新增uniform后，同命令输出 `Temp/shore-edge-water-weight-green.json`；`SHORE_EDGE_COVERAGE_TESTS assertions=254 failures=0`、退出码0、唯一完成标记，无Godot SCRIPT ERROR／ERROR。包含13个weight手算夹具、三个weight下的单调／范围、weight1逐点恢复原效果、邻边连续、真实coverage深海端点、新uniform实际初值及同刻材质所有者合同。
- 复跑4项旧脚本：独立Ocean63项、生产Ocean integration87项及layers15项、旧feather29项，全部通过。新回执为 `Temp/shore-edge-water-weight-ocean-regression.json`、`Temp/shore-edge-water-weight-production-regression.json`、`Temp/shore-edge-water-weight-old-feather-regression.json`。含新脚本共448项／0失败，均headless；没有扩大为完整仓库审计。

最新阶段冻结SHA256：shader `d832e418028fc163905fc11a60fc038ebcfe1bdf3a9804f5b421b4b7c4d5b617`；include `5aea4e22d03af9192d98e6f733ba1e84a11a4ad8a89a9298a860f699b57e21e6`；test `723fc40b08acc408b2cc58857cee7b9b315587c9fa3a5d174d63f35f164c4698`。width默认0.6，water weight默认0.55。

此Agent没有启动GPU或改Demo。新weight的红框带视觉接受、第一道岸浪范围、实际连续画面与生产接线由主线程补录；此前width比较原帧不能直接证明新weight通过。若红框处原coverage已经1，新weight按合同不改变该像素，应保存这个反例并单独研究范围，不能暗改端点或全域海水。

## 局限与失败

局部field与真正三角地形仍可能有采样误差；光学深度边缘可能来自船壳而非岛；低角度depth精度、view-Z转垂直厚度近似、screen-color色彩空间、透明特效不进入opaque scene等均需GPU反例。宽平滩的水平羽化带过宽时保留失败，下一步才研究坡度归一化。

候选保留depth_draw_always，不承诺改变透明对象顺序。coverage=0不改变物理地形／水面，也不复原任意材质历史。没有GPU新证据前生产width维持0。

## 集成与复现

严格headless命令：`rtk proxy node tools/verify-godot.mjs --filter shore_edge_coverage --output Temp/shore-edge-coverage-new-run.json`。本轮初始RED/GREEN使用不同路径。独立Shore Demo的0/0.35因子、GPU主菜单／导出接线由主线程处理。

新增helper仅供现有 `reference_game_water.gdshader` 使用；不更换海水shader。独立新证据通过后，主线程再决定生产uniform默认与WorldView显式接线，并重新冻结源hash、执行相关海面／岸线／暂停／生命周期回归。回退将uniform归0并保留本轮原帧与失败；不覆盖历史baseline或修改存档／设置。
