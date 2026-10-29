# 船影诊断结果：H4/H5/H6

2026-10-26，沿用hero-fuchuan。正式默认仍R7c。新制作的研究控制器和以下实际GPU证据用于确定下一步模型修正；没有把关闭投影或整体移动代理接入正式游戏。R8候选另见[R8-PROXY-CANDIDATE.md](R8-PROXY-CANDIDATE.md)。

## 路径证据

[H4 process](../../research/evidence/hero-fuchuan/rig-frequency-20261026/study-01-process.json)：有效11张、0失败、exit0。同一正式入口fixture、R7c、正式光照/FOV55/AA4、1600×900、固定接受时刻，转入原HeroDemo独立World3D；无船员/海岛，不是完整游戏或原生操船。

独立审阅全部10张隔离图，帆上的粗断续点线随native_off或rig_cast_off显著减少，细索实物仍在；stencil_off不清理帆点划，却明显减轻甲板与艉部黑点。sail_cast_off主要移除宽帆影，不移除粗索影。因此应分别处理原生索影和刚体代理接收问题，不能用删索、关帆影或整体提亮交付。

## 被否决的参数候选

[H5 process](../../research/evidence/hero-fuchuan/rig-frequency-20261026/filter-01-process.json)：有效59张、0失败、exit0。全部投影保留；独立看10张静态和9张小相机弧抽样：Soft Medium/High请求收益不足，粗点线仍明显；shadow_blur=0使正面帆大面积黑化；normal_bias=0无实质改善。四项均不采用。RenderingServer没有质量getter，元数据明确只记录请求枚举；灯光blur/bias为实际属性读回。9张离散抽查不代表整段连续视觉验收。

## 代理几何对照

[H6 process](../../research/evidence/hero-fuchuan/rig-frequency-20261026/proxy-01-process.json)：有效13张、0失败、exit0。独立审阅12张正反向原帧：

| 因素 | 观察结果 |
| --- | --- |
| hull_visible | 主甲板散点显著减少，抬高艉甲板仍脏 |
| hull_down35mm | 与上一项改善区域相近，宽帆影保留；整体位移仅作量级诊断 |
| deck_down4mm | 艉甲板明显变干净，主甲板原散点仍在 |
| deck_visible | 甲板噪点增密、成片变暗，拒绝作为候选 |
| single_sample | 黑点未清理，颗粒/锯齿更硬，拒绝 |

这把主甲板与抬高艉甲板分到不同代理，尚不等同全域包含性证明。每个因素保留五个刚体caster及原native cast状态，读回metadata实际资源ID；代理变化不触及可见几何、材质、帆态或时钟。

只读[CPU截面及交叠三角分析](../../research/evidence/hero-fuchuan/rig-frequency-20261026/proxy-section-cpu.json)显示：共享顶面上shadow_deck最多高于可见艉甲板3.071313mm；shadow_hull所选顶面最多高于可见主甲板34.455074mm。精确输入为GLB FP32顶点，FP64进行交叠多边形仿射极值计算；未作形式化数值误差证明，也未证明侧面/底面/XZ内包。原生MSAA depth平均值与私有单样本中心比较确有合同差异，单独关闭MSAA仍未消除黑点，不能把它当唯一根因。原始机制、精确引擎commit与来源见[RD调查](../../research/evidence/hero-fuchuan/rig-frequency-20261026/RD-EVIDENCE.md)。

## 实验室入口审查与修正

新控制器接入既有HeroDemo，默认baseline；基线恢复、dispose、精确cast枚举、派生资源缓存与无效输入均有真实节点测试。审查发现两个Important：暂停时参数只改metadata未提交renderer；不兼容proxy preset先销毁有效场景再返回伪成功。均已在一次修正中处理：公共setter同步提交，内部apply与refresh分离防递归；configure在dispose前验证shadow/model能力。

实际回归：headless RED36/4、GREEN36/0；新GPU暂停入口试验没有在参数后显式刷新，RED25/5、GREEN25/0，检查真实rigid输入revision和renderer volume revision同步变化、baseline恢复、接受时刻不动。最初GPU测试脚本有void返回值的解析错误，保留red-01日志，不把该解析失败当行为RED；有效行为RED为[paused-probe-red-02](../../research/evidence/hero-fuchuan/rig-frequency-20261026/paused-probe-red-02/PAUSED_RIG_GPU.json)，通过为[paused-probe-green-01](../../research/evidence/hero-fuchuan/rig-frequency-20261026/paused-probe-green-01/PAUSED_RIG_GPU.json)。随后相关[9项回归](../../research/evidence/hero-fuchuan/rig-frequency-20261026/hero-regression-01.json)通过950断言；这是R8新provider测试加入之前的诊断阶段结果，不外推当前全部测试。

历史study/filter/proxy报告保留当时源码hash；修正后不冒称旧报告绑定当前源码。新暂停GPU回执绑定修正后的source。旧严格全量2个60秒超时仍未关闭，未重跑全量或宣称全绿。

## 审查范围裁定

- R7c生产接线及累积改动已有其独立记录，本次不重复审查；本轮不改变生产资源，代价是不能凭此覆盖累积分支风险。
- 艺术观感由独立原帧审阅负责，代码审查不替代它；未审阅全部动态画面，仍可能存在闪烁。
- 完整游戏FPS、原生连续驾驶、最终阴影修复均不在此诊断证据中，继续留作交付门槛。
- 平移代理不证明全域内包，也未进入生产；否则有漏光或轮廓偏移风险。
- 不为源码后来变化重写历史H4/H5；其结论限当时版本，当前入口另有新证据。
- 未请求再次提交或合并；保留未提交续作，HEAD仍b21e2a52。

未发现独立Minor。以上是研究诊断阶段收尾；真实船模艺术目标继续推进，R8a作者导出失败与下一R8b包装已单独记录。
