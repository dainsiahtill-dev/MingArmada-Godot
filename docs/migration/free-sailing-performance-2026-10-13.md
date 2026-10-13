# 自由试航卡顿：根因与第一轮修正

用户明确卡顿发生在“自由试航”。本轮以真实公开 `sail` 菜单、Router、Practice Scene 为验收对象。新生涯的战役／Bridge 成本另作背景资料，不作为自由试航的归因。

## 已证实的主要根因

原 `NavalPractice._physics_process()` 每次物理回调都执行完整 `_present()`，包括船模、船员、尾迹、海面、岸浪、云雾、UI 和海图。低帧率时，引擎每绘制帧连续补八个物理步，因而重复八次整套呈现。每步又超过 60 Hz 的 16.7 ms 预算，形成持续补步和游戏时间落后的放大链。

当前同步方法诊断在真实自由试航场景中，运行状态的 physics owner 中位为 38.183 ms。该值是 headless 同步方法时间，不是原生帧时间；工具的独立分项在另一步／同时间重入采样，不能与 owner 或 GPU 相加。

## 同场景原生对照

Godot 4.7.2、Vulkan Forward+、Intel Arc 130T，1600×900、产品默认 balanced／MSAA4X、3 船、35 名可见船员。每轮独立进程，预热至少 2 秒、观察至少 8 秒，原有自动 physics／process 调度；保持前台、可见、未暂停，测量期间不截图。用户实际存档未写入。

| 版本／单项探针 | 平均 FPS | 帧间隔中位 | 每绘制帧物理步中位 | 采样墙钟／原生时间推进 |
| --- | ---: | ---: | ---: | ---: |
| 修正前正式自由试航 | 2.350 | 412.517 ms | 8 | 8.086／2.533 s |
| 只合并呈现的私有候选 | 14.726 | 68.258 ms | 4 | 8.013／8.017 s |
| 合并呈现＋临时隐藏水面 | 14.632 | 见原始报告 | 见原始报告 | 8.064／8.067 s |
| 修正后正式自由试航 | 14.384 | 69.844 ms | 4 | 8.065／8.067 s |

第一轮正式修正提高约 6.12 倍，原生时间恢复与墙钟基本同步。**14.4 FPS 仍不能称为流畅，30／60 FPS 和长期稳定性尚未达成。**

修正前／私有候选的 194 份 production source hash 一致，固定 viewport／settings／物理频率／演员预算也一致，只有 Factory 注入的私有 Scene 呈现调度不同。正式修正的 production source 只额外改变 Practice Scene 与 Practice Runtime。

## 正式修正内容

- 物理回调继续接受每个固定步、预观察炮弹、记录船舶出生姿态历史和逐步推进 Jolt。
- 累积实际接受的时间，普通完整呈现移到 `_process()`，每个绘制帧一次。
- 开炮、船员受击、沉船首帧仍立即刷新；只读窥看原事件缓冲，不提前 drain。
- 暂停／菜单命令可以立即 flush 已接受时间，随后不重复消费。
- pending 时间绑定 battleId，restart 与 exit 清除旧航程区间，沉船尾段与音频门禁继续按原规则运行。

未改变船型、船员数量、海面 shader、岸浪、云雾数量、反射、MSAA、相机设置或物理频率。实际产品代码在 `game/scenes/naval_practice/naval_practice.gd` 与 `game/runtime/naval_practice_runtime.gd`。

## 剩余瓶颈与反证

在同一私有合并呈现候选中，仅把水面父节点临时隐藏，保留 CPU 海面调用与反射更新，主视口 GPU 中位由 26.922 ms 降至 6.251 ms，但 FPS 从 14.726 变成 14.632，没有改善。水面 GPU 确有成本；**当前剩余的总帧率首先受 CPU 更新限制，不能把隐藏海水或降低海水画质当作主要修复。**

该私人探针的诊断作用是隔离绘制负载，产品水面始终保留。改变调度后原生时间和相机轨迹不同，不能把两轮 GPU 毫秒差全部分配给某个 shader。

当前源码中下一批 CPU 热点包括：

- 同一 Sea 呈现中，crew 的 LOD、allocation、snapshot 三个入口各自执行 `_reconcile()`，重复动画 seek 与节点遍历。
- ShipView 每次遍历三份 LOD 模型，包括隐藏模型，更新节点与姿态。
- 岸浪按新时间采样所有 patch；云雾计算 source 控制器／billboard 并提交大量独立节点参数。
- 相机变化时，海面重投影遍历 6,561 个网格顶点并重建 ArrayMesh。固定相机的 cache-hit 时间不能排除该热点。

这几项的自由试航独占毫秒占比还需逐项计时。此前共享组件的新生涯 fresh-time 测量可证明实现的计算成本，但不能直接当自由试航占比。没有将战役全包复制或 Bridge reconcile 误归因给 Practice；Practice Runtime 根本不走这条路径。

## 可复现证据

- `Temp/performance-rootcause-native-sail-baseline-20261013-v1/live-observation.json`
- `Temp/performance-rootcause-native-sail-batched-20261013-v1/live-observation.json`
- `Temp/performance-rootcause-native-sail-water-hidden-20261013-v1/live-observation.json`
- `Temp/performance-rootcause-native-sail-production-20261013-v1/live-observation.json`
- `Temp/performance-rootcause-cpu-current-20261013-v1.json`
- `Temp/practice-presentation-schedule-red-20261013-v1.json`：初始 15 个断言、3 个失败。
- `Temp/practice-presentation-schedule-green-20261013-v2.json`：增加 restart epoch 回归后的正式验证。
- `Temp/terminal-practice-scheduling-regression-20261013-v1.json`：首帧、尾段、暂停、音频、有限 cap 的真实 Scene 回归。
- `Temp/performance-rootcause-verification-20261013-v1.json`：独立核验真实帧、hash、负载与本轮回归。

最终独立核验 259 项无失败；10 份回归脚本共 703 个断言通过，包括新呈现调度、restart pending epoch、炮火事件、Jolt、出生姿态历史、延迟入水、沉船尾段、暂停与音频。CodeGraph 项目无索引，源码审查使用 RTK 与两轮独立只读检查。

鼠标操作另外通过真实窗口验收，记录在 `Temp/mouse-casual-native-practice-20261013-v4/capture-result.json`：实际海面左键、第二次点击转向、可滚动 HUD 的真实停船按钮、暂停点击均无失败，保存五张实际 viewport PNG。公开 headwind fixture 中，6 秒速度约 2.90 m/s，45° 选航向后 8 秒实际船头约 40.7°；停船收帆后三秒约 0.718 m/s，体现渐进转向与减速。此项使用受控生产回调，只验证真实输入／权威／画面接线，不能作为 FPS 数据。

私人诊断脚本全部在 `Temp` 或现有 `tools`，没有新增玩家独立示例。诊断进程退出，原 Godot 编辑器保留。未提交、推送或部署。
