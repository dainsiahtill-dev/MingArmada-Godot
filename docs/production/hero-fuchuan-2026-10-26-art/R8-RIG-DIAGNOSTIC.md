# H4：细索、帆面点划与甲板黑点的来源诊断

沿用 `hero-fuchuan` 课题、论文与已注册实验，不新建重复课题。2026-10-26 前瞻记录；R7c 正式默认保持。上一轮已集成材质，不代表这里的根因已定位。用户持续授权负责人自主推进，以下因子与实现方式为负责人决定，不宣称逐参数由用户批准。

## 问题、假设与备选

正式相机仍见细索/帆面点划和甲板高频黑点。源码与当前资产表明：五类刚体节点经代理进入 stencil overlay；细索与 sail 组合节点仍原生 shadow map；健康材质均 OPAQUE，甲板另有4mm实缝深色基底。H4a：点划主要来自原生薄几何投影；H4b：黑点来自 stencil receiver 与可见细节边界；反例为两项分别禁用都不改变症状，此时再检查可见几何/纹理频率。

方案一是研究实例内逐项隔离原生投影、stencil、rigging/sail caster；能辨别路径，成本小，选作先行诊断。方案二是直接改模型细节尺度/材质缝线；可能改善观感，但没有路径因果证据，暂不改正式模型。方案三整体提亮或换AA已在先前独立实验否决，不重跑成修复。禁用任何投影只用于诊断，不是最终美术方案。

## 输入、单位与控制

固定普通自由试航入口的seed1661/time0接受包、R7c LOD0、1600×900、FOV55、实际正式相机/灯光/环境/AA4。复用既有隔离HeroDemo、平面接收器，无船员/海岛；报告明确不代表全场。两镜头为正式视角与同目标旋转PI的反向视角。实验宿主拥有时钟，暂停不推进权威、RNG或形态。

逐组恢复原始状态，只变一个因素：A baseline；N native_off仅sun.shadow_enabled=false；S stencil_off仅CompositorEffect.enabled=false且刚体原生caster状态不变；R rig_cast_off仅rigging_* cast_shadow=OFF；C sail_cast_off仅sail_* cast_shadow=OFF（包含canvas/bamboo/seam/hemp，不能据此区分组内）。全部几何、材质、变换、帆态、相机、AA与光色能量保留。Baseline stencil必须先初始化成功，再保存caster快照；禁用时不能dispose或触发native回退。

## 执行与接受标准

1. 先测研究隔离器错误输入无副作用、逐因素互不残留、恢复原始枚举、dispose恢复、几何/材质/变换不变；RED/GREEN落盘。
2. 将因子接入既有HeroDemo参数，默认baseline；native模式下stencil_off明确拒绝。可重置、暂停、切因子和dispose。
3. 真实GPU保存普通入口baseline和两镜头五因素，共11张；逐项记录实际effect/native/caster状态、资源与形态快照、source/hash、保存文件。正式权威/显示包不变；研究shell接受时钟不变；个人设置/存档hash不变且MemorySlot零写。
4. stencil_off中initialized仍true/error为空、caster快照与baseline相等、GPU frame counter停止；恢复后继续增长。只有这些readback通过才称该单因素有效。
5. 审阅原帧分别判点划和甲板黑点，不以执行0失败代替根因。若任一症状无差异，保留反例，另预注册最小几何/材质隔离。当前不测性能，不把静态截图称连续视觉验收。

仅当明确来源并形成保留真实投影和可见组件的新方案，才进入新候选连续GPU与正式入口验收。此诊断本身不修改生产接线或宣称美术缺陷修复。

## 来源

## H4首轮结果与H5前瞻

`rig-frequency-20261026/study-01`真实GPU有效11张/0失败/exit0，源/存储不变。独立审阅10张隔离图：native_off及rig_cast_off使帆上主要粗断续线消退、细索实物仍在；stencil_off明显减少甲板/艉部细碎黑点，却保留帆点划与宽帆影。sail_cast_off主要移除宽帆影，不移除帆上的粗点线。证据定位到两条路径，尚未证明native取样参数或stencil几何/深度的最终机制。

H5运行前设计：保留全部原生与stencil投影、所有可见几何；只比较原生方向阴影filter。官方文档说明Soft Low可能出现可见dithering，作为机制依据，不当作本船实证。五因素baseline、Soft Medium(3)、Soft High(4)、仅shadow_blur=0、仅shadow_normal_bias=0，分别恢复原值；不组合。保留两镜头共11张，加baseline/medium/high各16个同刻0.03rad小相机弧，共59张。记录实际Light属性、启动ProjectSettings策略与调用的RenderingServer质量枚举；RenderingServer无getter，明确不能把请求值称运行时查询值。阴影disabled因素均不使用。

接受项：全部因素保持投影开启与rig/caster/几何/材料/帆态不变；模式真实产生可复查图像差异；原帧审阅粗断续感减轻且绳影连贯、帆/船体体积不丢；短相机弧用于观察变化，非原生航行或固定时间物理动画。先定性验证，不接生产、不称FPS达标；若形成候选，另测成本和完整游戏连续验收。失败原样保留。

H5结果：filter-01有效59张/0失败/exit0；独立看10静态+9弧采样图，medium/high点线仍在、收益不足；blur_zero正面全帆明显黑化，拒绝；normal_bias_zero无实质改善。请求值不冒充运行时getter；9张弧抽样不称完整连续审阅。四项均不接入。

## H6代理几何与深度诊断（运行前）

只读精确GLB交叠三角仿射高度比较发现：shadow_deck在quarterdeck共享XZ区域最大高于可见顶面3.071313mm；shadow_hull顶面相对可见deck最高34.455074mm。有限采样先得较小值，后续对交叠多边形顶点评估仿射极值修正；这些是CPU几何证据，尚未绑定黑点像素。原生Godot精确commit的MSAA深度resolve使用平均值，当前stencil用单样本中心深度比较，亦有合同差异，需分离。

预先固定六因素baseline、deck_visible仅deck stencil输入换可见deck.mesh、hull_visible仅hull换可见hull.mesh、deck_down4mm仅其原proxy整体局部Y下移4mm、hull_down35mm仅原proxy下移35mm、single_sample仅MSAA0。各组恢复baseline，保持全部五caster及其native OFF、原生帆/索投影、可见模型/材质/姿态不变；两方向加原正式baseline共13图。4/35mm由运行前3.071/34.455mm上界取整；不是按GPU结果调参。平移不是全域内包保证（侧/底和footprint尚未证明），只能定位量级，不得作为最终美术修复。

实际metadata Mesh ID、来源枚举、派生资源复用、完整caster状态与AA必须读回；两个visible因素只改变一个stencil输入，不能dispose触发nativefallback。每组最多一次构建派生Mesh，反复refresh复用；reset/dispose恢复原引用。若黑点随代理变化而不是single_sample变化，优先形成正确内包代理候选；若仅single_sample改善，继续逐样本receiver方案，不能删除投影。未运行时不预判结果。

[Godot投影与bias说明](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html)、[GeometryInstance3D投影枚举](https://docs.godotengine.org/en/stable/classes/class_geometryinstance3d.html)、[DirectionalLight3D](https://docs.godotengine.org/en/stable/classes/class_directionallight3d.html)于2026-10-26实际查阅，仅支持引擎机制，不证明本船根因；本机运行与原帧另记。项目源码为本轮路径证据，原生细索不属于刚体stencil分类，不能混称。
