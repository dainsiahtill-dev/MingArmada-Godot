# 天气、云、阴影与尾迹：交付接收和 Godot 接入合同

接收日期：2026-10-13（Asia/Shanghai）。已读专家总报告、AGENT_HANDOFF、STATUS、三个主题报告、学习代码入口，并核对当前 Godot 调用路径。此文件记录已接收的资料与下一阶段实施依据；本轮没有修改游戏实现代码，也未宣称新增效果或 FPS 已通过。

**接收结果：离线交付有效，Godot 移植待实施。**

复跑专家总复验：11 项执行检查全部退出 0，valid=true，errors=[]。161 份来源、其中 27 份 Godot 源文件一致；34 份 IDA 文本、47 组 REA 文本、52 条 REA 记录、60 个本地引用核验通过。交付清单为 327 文件。主线程另外逐一重算 161 份输入 SHA256，并核对复验回执副本与专家当前回执逐字节相同。

- [专家总报告](C:/Games/Pirates-REA-Reference-20261011/weather-cloud-shadow-wake-study-20261013/IMPLEMENTATION_REPORT.md)
- [专家实施合同](C:/Games/Pirates-REA-Reference-20261011/weather-cloud-shadow-wake-study-20261013/AGENT_HANDOFF.md)
- [专家未闭合项](C:/Games/Pirates-REA-Reference-20261011/weather-cloud-shadow-wake-study-20261013/STATUS.md)
- [本轮复验完整副本](evidence/weather-cloud-shadow-wake-handoff-2026-10-13/REFERENCE_REVERIFY.json)
- [执行回执与范围](evidence/weather-cloud-shadow-wake-handoff-2026-10-13/REVERIFY_RECEIPT.json)
- [已接受的161份原件/传递依赖清单](evidence/weather-cloud-shadow-wake-handoff-2026-10-13/ACCEPTED_INPUTS.json)
- [当前引擎接收审计与准确代码位置](evidence/weather-cloud-shadow-wake-handoff-2026-10-13/ENGINE_ADOPTION_AUDIT.md)

复验命令：

~~~powershell
rtk proxy python -B C:/Games/Pirates-REA-Reference-20261011/weather-cloud-shadow-wake-study-20261013/verify/verify-delivery.py
~~~

以上验证覆盖离线原字节切片、有限数学译本、资源身份和只读源对照。GPU pass/draw/像素、实际原版正常航行、Godot 新效果与 FPS 均不因此成为已验收。

**已接收的系统与核心约束**

| 系统 | 采用的原实现依据 | 不能混用的规则 |
| --- | --- | --- |
| 世界天气 | 4604A0 原整数时刻/风向/扰动；3个天气中心移动与越界重置；显式 CRT RNG | 每原调用步进，原 loop 最低31ms等待不代表固定32Hz；不得依渲染/额外开炮展示次数推进 |
| 天空云环 | domecloud1..5 原模型、wrapper旋转、严格阈值一次更新、完整 sky camera | 无源 controller 的天空云环不按天气风场作通用线性漂移，不附加 cloud00 的云影平面 |
| 天气云与纹理影 | 中心0 stormcloud_sound、中心1/2 cloud00；原父链/TRS、UV、alpha/depth | cloud_sh 同 root 随天气actor移动；stormshadow与stormcloud_parent是兄弟，不能误继承兄弟局部动画 |
| 光照与水色 | 419D60 → 4AC640 → 4AC4F0 → 4E3AE0 原场景时段、light/controller与海面颜色字段 | day/late-day/night不是晴/雨/暴风枚举；现自建太阳方向/energy不算这条链已移植 |
| 海航尾迹 | Dummy_Wake、30点历史环、三维距离门、严格跳变、原root scale、LUT/宽度分支与ARGB | 透明度主要来自实际更新次数和行号；AlphaFunc资源存在不等于绘制消费，不能套统一age fade |
| 海战尾迹 | 90项位置/航向历史、tick相位、7段各3次提交，共21次draw实参 | 逐调用历史不等于90秒或90渲染帧；不能用30点海航环代替 |
| 船首与船侧白沫 | Dummy_Bowfroth、通用bowfroth、9船族authored sidefroth及原controller/粒子 | 独立资源和挂点；不能用当前泛用尾迹条带替代全部局部白沫 |
| 阴影体积 | FShadowManager 原边抵消、apex/封口、两次stencil pass、屏幕quad与caster gate | 与纹理影、Godot DirectionalLight shadow map、水面reflection分别实现和验收 |
| 地雾 | NativeFogSystem 持久controller状态、原TRS/控制器/源资源 | 原townsneak实例资格、摆放与最终调度尚未闭合；本作港口雾必须标成场景适配 |

学习实现入口：

- [weather-state.mjs](C:/Games/Pirates-REA-Reference-20261011/weather-cloud-shadow-wake-study-20261013/weather-cloud/weather-state.mjs)：stepOriginalWeather、originalSceneDayMode、originalLocalWindStrength。
- [native-learning.mjs](C:/Games/Pirates-REA-Reference-20261011/weather-cloud-shadow-wake-study-20261013/weather-cloud/native-learning.mjs)：复用原云环、OriginalFrameClock、completeSkyState、NativeFogSystem、nativeComposeWorld。
- [wake_reference.py](C:/Games/Pirates-REA-Reference-20261011/weather-cloud-shadow-wake-study-20261013/wake/wake_reference.py)：NativeHistory.update/profile、原INI/LUT、历史与宽度/透明度夹具。
- [battle_trail.mjs](C:/Games/Pirates-REA-Reference-20261011/weather-cloud-shadow-wake-study-20261013/wake/battle_trail.mjs)：90历史和21次提交合同。
- [shadow_native.py](C:/Games/Pirates-REA-Reference-20261011/weather-cloud-shadow-wake-study-20261013/projection/shadow_native.py)：边抵消、有限volume geometry、重建判定与登记gate。

这些是学习实现与原字节验证入口，移植时转为项目模块。游戏运行不依赖外部 Python/JS 学习台或原 EXE；不增加独立游戏示例，不复制一套玩法私有渲染引擎。

**当前项目可以复用什么、还缺什么**

现工程的 modules/scene_engine 已有源资源编译、mesh/UV/mips、TRS、ControllerClock、per-pass billboard、动态vertex region更新与reflection接线。game 层负责场景编排，现模块可继续成为基础引擎的一部分；物理表现与场景渲染仍分层，甲板3D人物保持。

仓库已经有 cloud00、stormcloud_sound、bowfroth 和9船族sidefroth 的定义。当前运行 atmosphere 加载器仅接 domecloud1..5 与 groundfog，因此目前缺少的是正确的实例/时钟/场景接线，不应再称素材缺失，也不能说这些天气云或白沫已经在正式游戏里播放。

主线程核对的关键字段损失点：

- [NavalWorldView正常展示](C:/Users/dains/Documents/Git/ming-armada/game/presentation/world/naval_world_view.gd:352)仅向 WorldView 传 time/wind/battleId/focus。
- [质量重建回放](C:/Users/dains/Documents/Git/ming-armada/game/presentation/world/naval_world_view.gd:159)重复收窄上述字段；后续只修正常展示仍会在重建时丢失新的环境输入。
- [WorldView向atmosphere提交](C:/Users/dains/Documents/Git/ming-armada/modules/scene_engine/world/world_view.gd:326)仅传 time，没有3中心、原light、source clock或controller历史。
- [资源/天空绑定](C:/Users/dains/Documents/Git/ming-armada/game/presentation/world/naval_world_view.gd:134)在灯初始化之后再次设置sun方向/颜色/energy；只改初始化不能接通原light链。

现普通入口复用 NavalWorldView；另有旧 SailingTrial 直连 WorldView。接入清单须覆盖真正可达的正式入口以及仍保留的直连路径，不按界面名称猜调用路径，也不让共享能力只藏在单一玩法里。

**基础引擎与玩法层职责**

| 层 | 负责的状态/工作 | 调用合同 |
| --- | --- | --- |
| 原规则模块 | 原整数/FixedTrig/f32数学、云环状态、controller、各类尾迹历史与几何 | 接受明确原值与原状态，返回输出；不从相机/墙钟或船宽猜原输入 |
| 玩法runtime与适配 | 天气/RNG状态、source-call调度、route、身份、时段、marker与生命周期 | 在权威更新处推进，提交独立环境packet；额外呈现、暂停、终局视觉续播不重复消费规则 |
| 引擎asset/renderer | 源NIF/DDS/KF/property、父链、每实例clock、UV/ARGB、动态buffer、camera与各pass | 一套共享实现供所有入口使用；只有真正依赖相机的部分随pass更新 |
| 本作美术/体验策略 | 已有海水、停船退场、港口雾等有价值表现选择 | 显式标明适配；原规则内不悄悄替换scale、alpha或时钟，不让风场锁死玩家前进 |

P0字段必须定义：source basis/units、scene root scale与挂点、原整数/RNG、world调用计数、cloud delta、controller appTime及历史、海航clock、海战tick、accepted time与terminal visual time、INI来源、明确route、main/reflect camera。任何本作采样周期选择单独记录为适配，不称原版固定cadence。

**本轮接收的实施顺序**

1. 输入和状态合同。先补当前snapshot收窄、质量重建、暂停/换场景/恢复、route与源挂点适配；原值域差分和单位映射分开测。
2. 已闭合原数学。修正两处TRS运算/存储顺序，接每实例持久controller；天空云环与3个天气对象分开驱动，接原纹理影与光照字段。
3. 三类船水效果。海航30点、海战90历史/7段、首/侧原资源分别实施，共用基础引擎的资产、controller、材质与动态提交能力。
4. GPU与场景装配。逐项验证纹理影、stencil、现方向光影与reflection；不以有限CPU测试推定GPU合成一致。
5. 冻结候选的画面和性能。相同船数、炮击、分辨率、quality、操作序列下复验；保持3D甲板人物，不通过隐藏人物/白沫或减少船数宣称等价优化。

已确认的迁移风险：原TRS是先旋转local translation并作f32存储，再乘parent scale；现两处先scale再rotate不等价。持久controller样例 lastApp=10、accumulated=6、nextApp=10.25 得到6.25；reset seek得到10.25，不能把移除reset当成完整状态恢复。原30点停止时保持旧几何，当前本作停船退场可作为明确的表现选择保留，但不能标成原30点行为。

**保留的未闭合项**

完整30点strip/head/normalize/自交修补差分及隐藏ABI、zero-length原NaN LUT/首帧、实际生效INI与单位映射、完整live RNG和调用间隔、雾实例最终调度、所有船型影可见性、skinning/caster/receiver、stencil backend、首侧白沫完整生命周期、GPU与性能验收仍待完成。profile有限fallback的 native_equivalent=false 标记必须保留，不能原样当成等价原算法。

**卡岸证据纠错已合并**

原版023/024实玩样本被岸线限制，不能验收正常点击转向、离岸或正常尾迹。撤回由这段画面概括“原版尾迹短且淡”的依据，原版正常操船与正常尾迹均为NOT_VALIDATED。截图字节与SHA保留；查看页改默认片段，卡岸样本显示排除范围。Godot的独立记录按其本身证据判断。

[纠正版观察报告](play-observation-corrected-2026-10-13.md) · [纠错账本](evidence/play-observation-2026-10-13/CORRECTION_20261013.json) · [截图查看页](evidence/play-observation-2026-10-13/review.html)

已将接收结果与纠错同步给逆向专家，明确无需因此新增逆向任务。其离线合同作为后续移植依据；卡岸画面不参与算法选取。CodeGraph确认该Godot仓库未索引，本轮源码接收使用RTK fallback，没有虚构图谱审查。
