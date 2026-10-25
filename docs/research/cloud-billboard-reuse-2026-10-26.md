# 云层调用内重复计算复用

课题：`architecture-convergence-2026-10-21`。状态：独立CPU与受控GPU验证后已接入生产；首轮全量302项通过300项，两项失败已定向修复。最终全量303项已结束：301通过、2项视觉QA超时失败，整套回归未通过。完整游戏的性能、美术和玩法目标仍开放。

所有原始回执位于`docs/research/evidence/architecture-convergence-2026-10-21/billboard-reuse-20261026/`。本轮代码、资源、测试、研究记录与证据将随用户要求的checkpoint一起入库；本记录保留失败与未达目标。

## 实际改动

生产`cloud_render_compiler.gd`仅在一次静态`render_minimum_states`调用内，对九个旋转double的完整字节复用纯函数`_billboard_mode0`。本次调用的相机不变；保存/恢复旧作用域。缓存与每个输出的旋转数组相互独立，不跨帧，不改源时钟、RNG、云片、顶点、minimum-Z扫描或质量。

冻结基线为`game/research/fixtures/cloud_billboard_baseline.gd`，SHA256`1f6c2696e59f440e518884fb4fb5e533ae2ebd7eae721fc84298127910909afe`；独立候选继承它。通用静态/动画`render_states`保留原工作量与完整控制器状态。

## CPU与真实接线证据

- 研究RED为608断言/1预期工作量失败；GREEN及工厂重构后均608/0。三组镜头、真实30云环转置调用1449→378，完整结果逐字节一致。覆盖signed-zero、退化阈值、输入/发布数组所有权、交替owner、重复时间及动画控制器。
- 实际普通场景Encounter seed1661与天空CRT seed1不同；初始错误夹具及常量折叠负零的无效尝试均保留。CPU工具在运行前已纠正为实际默认30云环。
- CPU两对暖机、12对交替批次，每批24×30云；107.279333→87.637083ms，均值下降18.31%，12对全部更快。门槛事先为均值至少下降5%、至少10/12更快、完整结果一致。编译/文件IO/字节校验在计时外；不是单帧时间。分位数nearest-rank。
- 首次Object.set未替换Atmosphere推断为生产编译器类型的成员。真实读回`labidentity-readback-02.json`打印两边均为生产脚本，96/2。原GPU01/02不是有效A/B，保留valid=false，不能转述为候选验收。
- 研究adapter继承生产类型，完整委托给实际冻结/候选对象，并检查注入对象引用与实际实现路径。修后`labadapter-work-green-02.json`103/0，真实helper下转置483→126，完整状态相等；切换始终保持同一个可见carrier。实验的天气相机缓存刷新仅为确定的全状态观察，不进入生产。

## GPU方法与结果

独立审查指出双可见树切换存在资源混杂，基线自身重绘也有少量像素不稳定。方法在GPU03运行前明确修订：同一套可见节点/网格/材质/RID，仅换CPU计算delegate，隐藏observer跑相反路径；实际提交的变换、材质属性及uniform、AABB、资源、主/反射镜头和天空输入须字节相等。保留连续真实GPU原帧，不改演员或画质，不设置像素容忍阈值。

`gpu-03/GPU_VERIFY.json`及`gpu-03-process.json`：Forward+、Intel Arc130T、96连续接受步×1/32s=3秒，985断言/0失败，退出0，无Godot错误，运行内源码/资源不变，设置/存档不变。从普通首页进入原实验室主题。288份提交二进制均保存，96组baseline/hold/candidate相等，哈希复核0不符。主图最终像素94/96完全相等、反射96/96；没有宣称主图像素全部相等。初/末原帧已实际审阅。该场景只有一个可见真实船、两个数值权威，没有完整游戏crew/战斗负载，不用于FPS结论。

三个早期船体像素的CPU射线命中真实teak表面，未证明中心共面重叠。没有据此改模型；GPU内部波动根因仍未知。明确保留这一范围，不能把失败A/A控制解释为候选缺陷或已修复的模型问题。

## 正式集成

生产专用RED608/1→GREEN608/0，正式测试保留于`tests/test_cloud_billboard_production.gd`。普通自由试航保持1600×900、默认画质、3船35可见船员，10秒暖机、30秒观测，两次valid=true、无排除项、无存档写入、运行内源码不变；两轮之间仅生产编译器源码变化，固定负载配置相同。

| 原生整场帧间隔 | 基线 | 接入后 |
| --- | ---: | ---: |
| 样本数 | 422 | 425 |
| mean ms | 71.177573 | 70.623304 |
| median ms | 70.9645 | 70.157 |
| p95 ms | 75.743 | 75.911 |
| observed FPS | 14.049369 | 14.159632 |

median使用排序中间值、偶数时两值均分；p95/p99为nearest-rank。仅一对顺序运行，温度/后台噪声未控制到可归因程度，p95也未改善；**不宣称整场有显著提速，更不宣称达到60FPS**。独立子批次收益与当前完整场景成本分别报告。

## 全量回归中发现的后续问题

首轮严格全量已终止：`full-suite-final-01.json`为302项、300通过、2失败。`test_laboratory_shadow_edges.gd`复现10断言/2失败，根因是实验准备快路读取可见高精网格，而生产Adapter已选择`target_shadow_geometry`代理，比较输入不同。新夹具7断言/5预期失败，逐个证明deck/hull/三桅的准备输入没有使用实际代理。此项不调用云编译器。修实验选材合同后，原实验10/0、新代理夹具7/0，保存于`shadow-proxy-green-01.json`；夹具已保留在正式测试目录。

另一项`test_terminal_scene_presentation.gd`为190断言/2失败：测试要求audio diagnostics为running，却使用新用户默认静音设置。诊断证明视觉时间/音频时间相同且_paused=false，只有state为disabled；产品时钟没有故障。测试专用内存设置显式启用sound，不加载/写入设置文件，music仍关闭；190项原断言全部保留，修后190/0。默认设置另验22/0；生产Settings、GameAudio、两个场景和生产云编译器在该RED/GREEN间哈希均未变。见`terminal-diagnostic-01.process.json`、`terminal-green-01.json`、`terminal-muted-defaults-01.json`。首次超时和所有RED保留。

最终全量`full-suite-final-02.json`已于2026-10-25 22:33:58 UTC结束（进程退出1）：303个测试文件全部运行，301通过、2失败，`passedAll=false`。`test_visual_qa_clock.gd`与`test_visual_qa_scene.gd`均在60秒超时、退出1且完成标记为0；后者仅记录startup=33101ms、quality=55961ms，未产生完成回执，根因尚未诊断。未发现Godot ERROR行。对`integration-progress-02.json.currentGameModuleHashes`记录的264项逐一复核，当前SHA256全部匹配；摘要见`full-suite-final-02-summary.json`。上述定向GREEN只证明对应修复，整套仍失败；本轮未重启或补跑测试。

下一美术对照见`docs/production/hero-fuchuan-2026-10-26-art/NEXT-MAIN-CAMERA-LIGHT.md`：先复现正式照明，再独立比较环境补光，保留米白帆/浅甲板/赤褐船壳/深水线层次。当前候选未运行，不把计划写成艺术验收。
