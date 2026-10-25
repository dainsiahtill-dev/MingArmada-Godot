# 主角福船 v3：造型重塑与实机验证

2026-10-26；当前为可继续审阅的游戏美术候选，不是整款游戏完成或用户最终认可。用户先要求提交已有全部工作，再优先解决主角船模型；检查点为codex/godot-migration上的d609f5ed246eab7fd0484b30e020cb7c0bf54ee5。本目录v3工作在该检查点之后，尚未提交；没有推送。

## 可编辑原件与实际模型

- 原件：assets/production/hero-fuchuan-blender/hero-fuchuan-v3.blend。
- 制作程序：tools/blender/build_hero_fuchuan_v3.py；Blender 5.4.0 Alpha fbe82a461016。
- 游戏资源：assets/models/hero_fuchuan_v3/fuchuan-lod0/1/2.glb。HeroProvider已用于正式主角福船；原v1/v2与参考船保留。
- 可见三角形LOD0/1/2为101,299 / 48,051 / 27,291；每档额外附1,614个不参与颜色绘制的阴影资源三角形。manifest中的triangles是包含这些资源的导出总数。
- 旧木、麻布、甲板和锻铁沿用四张image_gen原始PNG，逐字节来源与提示词位于assets/textures/hero_fuchuan_v2/provenance.json和assets/production/hero-fuchuan-blender/texture-prompts-v2.json。不是扫描或完整PBR贴图组。

船体以平滑断面、上扬艏柱、实心舷墙和真实四炮口重塑；艉楼顺着船体收束，补舱门、窗格、双梯、栏杆。三桅帆改为有张力的扇形，竹桁/活动索/绑扎随收帆形态同步移动。保留8炮管与烟口、炮架、长舵柄/舵叶、绞盘、锚具、盘绳和甲板作业件。32m长、9m宽、2m吃水与每舷4炮的原物理合同保持；形制是时期约束下的游戏解释，不称历史复原认证。

## 美术验证与失败历史

v3-r1至r4保留真实Blender多角度原帧与独立审查。r2负鼓帆穿桅，r3减小外推并修绑扎；r3周期波形又放大近切光下直桅投影，r4改C1连续sin²、0.025m起伏。未用关闭阴影或改光照来掩盖该局部形状问题。

gpu-r4/manifest.json记录257个固定1/32秒状态与GPU原帧SHA；hero-rig-v3-r4.mp4是该8秒受控动作序列，不能称原生驾驶录像。r4-art-review接受进入实机复核，仍指出舵叶较平、补丁偏方、细索硬影等可继续打磨点。

r5单独制作闭实体投影组合，完整可见模型保留。Provider只向完整节点附加同坐标框架Mesh资源，资源Node隐藏，实际变换和原生投影回退仍由完整节点拥有。精确焊接后hull包含286条degree4边，属于闭实体组合，不能称单一双流形；独立有向边余额为0、无退化、体积正。详见v3-r5-shadow-proxy-review.md。

shadow-gpu-r5-a的正面GPU比较通过，但正式入口健康帆面仍出现破碎暗斑，native-play/08-r5-healthy-shadow-failure.png保留失败，曾撤回默认代理。随后定位真正共同根因：Weather的source lightDirection是光线传播方向，目标消费者却期望指向太阳，旧适配少了一次取负，正午发光方向Y=+0.698182。native-shadow-isolation-r5-a保持同一冻结正式场景，证明原生阴影图也由船底向上遮帆。

只修Weather目标公式为[-source.x,-source.z,+source.y]，原sourceLightFields与天气/RNG不变。shadow-gpu-corrected-sun-a保存连续真实GPU及正反面，原生影与模板影均保留；shadow-gpu-legacy-sun-a为反例，且精细可见模板在一个光向超出uint16范围并明确失败。native-shadow-isolation-corrected-sun-a实际正式场景不再把船底影投向高帆，投影代理恢复默认使用。此诊断冻结权威，不冒充原生操船证明。

## 实际输入与合同

native-play/01至04：普通主菜单自由试航，鼠标改变航向，三帆100%→41%→0%，船速降零。05至08是r5进一步实机复验，07显示点击右舷齐射按钮后弹药40→39、右舷装填6.6秒；E注入没有触发，不能认证键盘快捷键。05至08早于最终太阳适配修正，截图不冒充最终光照验收。

最终太阳与代理默认下的真实普通入口09至14：healthy船体/风帆100%，鼠标航向000→338度；帆面100→41→0%，船速0.0；UI“继续”确认最终暂停现场。11帧附近他船有遮挡/穿插，保留原帧，未将其裁掉冒充单船效果。实际隔离profile的settings.sound=false、music=false已回读确认。

最终独立实验还补了“初始即暂停”的渲染就绪交接：首个GPU post-draw只刷新投影策略，不推进时间；退出/重置会断开未消费回调。shadow-gpu-final-paused-ready验证两因素均time=0、五个完整刚性节点已关闭重复原生影，随后连续序列与反面帧0失败。final-paused-laboratory-r5.json验证宿主生命周期。final-review.md审查时提到的初始暂停边界由此补齐。

定向验证证据位于Temp/hero-fuchuan：art-v3-r5-model.json为5文件331断言/0失败；shadow-geometry-matrix-r5.json为227断言，覆盖三LOD闭合组合、有界代理、8光向体积索引范围、颜色可见性与投影回退；shadow-parity-r5.json验证原有有序边/体积合同。sun-direction-red/green.json保留5断言的三项符号失败与修后0失败；weather-corrected-sun.json、source-environment-corrected-sun.json复验天气历史与生产消费者。实验室参数、暂停和释放另有shadow-laboratory-r5.json。以上为定向复验，不称本轮全量套件重跑。

## 性能范围与未完项

同源码交替CPU微基准cpu-proxy-pairs-01至04：慢转光compose p95从60.754/66.289ms降至0.243/0.155ms，五caster总源面43,124→1,614，末样本hull体积2,782点。只表示CPU边界，不表示整场FPS。

实际菜单自由试航，seed1661、1600×900、默认质量、三船35可见船员，10秒暖机后保留全部30秒frame intervals：perf-r4-visible-a平均204.199ms（4.90FPS）、p95 213.167ms；perf-r5-authored-a平均73.681ms（13.57FPS）、p95 79.373ms。两次都valid=true。慢基线触及每帧8物理步上限，故接受时间/末位置不同，不把墙钟比较宣称为完全相同运动轨迹的严格提速百分比。最终太阳修正后的性能以新perf-r5-corrected-sun-a回执为准。

最终perf-r5-corrected-sun-a：414样本，平均72.480ms（13.80FPS）、p50 72.075ms、p95 78.420ms、最差103.293ms，valid=true，invalidReasons=[]，三船35可见船员保留。正式native接受时间0.45→40.65秒；此结果仍远超16.67ms预算。统计p50为工具的偶数样本中间两项平均，p95为nearest-rank。

帧率尚未达到60FPS，不宣称流畅验收通过。此轮未完成海/岛整体氛围重塑、导出包验收、船员握舵IK或新的完整战役。默认声音/音乐关闭已在检查点实现。下一步仍先收敛主角船实机表现，再处理海岛与整体氛围；不得用好看的单张Blender图替代这些边界。
