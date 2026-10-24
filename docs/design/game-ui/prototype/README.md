# 海上明旗 · 完整游戏界面原型

**剧情版本说明：**《一官入海》已重写为[五幕二十场第五稿](../../../narrative/zheng-zhilong/index.html?edition=5#top)。本72页原型仍是旧六幕43场的界面与经营演示，尚未接入新版主线；统一审阅栏以醒目提示区分版本。不要把旧角色样例、章节状态或236个演示状态当作新主线已经实现。

构建与验证使用 `tools/game-ui-story-baseline.mjs` 明确读取冻结的 `docs/narrative/rewrites/baseline-v4-2026-10-22/story.json`，校验原SHA-256 `29e7de2c9308548b37293630530a5f3f84187862ee290629dcd80eda5826e801`，并验证43条旧阅读锚点均可转到新稿有效场次。这里保留演示合同，而非放宽新稿引用检查。新主线接入UI时须另行更新剧情状态、玩法流程与相应业务验收，不直接把主JSON替换进旧数据脚本。

本轮细节打磨交付见[DETAIL_REVIEW.md](../DETAIL_REVIEW.md)：72页、236个有效状态、专用美术出处、制作资产预算与严格合同验证。最终浏览器视觉结果在该报告中单独更新；此前的[REVIEW.md](REVIEW.md)保留为旧轮次验收记录。

这是依据《一官入海》六幕43场剧本制作的可点击网页UI原型，覆盖**30个玩法系统、11个底层系统、72个游戏页面、13条操作流程**。用途是评审游戏的界面、信息结构、导航和局部操作反馈。底层能力另列职责、现有依据与设计目标，不强行增加页面。

交易、维修、招募、岗位、弹药、寄信和保存等操作在当前页面会话的内存中模拟。数值变化用于验证界面反馈；“演示存档”也保存在内存，刷新或关闭页面后不会保留。本原型不读写Godot个人存档，没有把43场新战役接入原生游戏，不能据此认定航海、海战、AI、历史战役、音频或性能已经完整实现。

## 启动

从正确仓库 `C:/Users/dains/Documents/Git/ming-armada` 根目录启动本地服务：

```powershell
rtk proxy python -m http.server 8794 --bind 127.0.0.1
```

浏览器打开[原型首页](http://127.0.0.1:8794/docs/design/game-ui/prototype/)。已有8794服务时直接访问，不需要再开第二个进程。必须从仓库根提供服务，因为页面还引用仓库内的共用美术与叙事图片；仅复制本目录会缺少这些资源。

页面为经典脚本、系统字体和本地资源，不需要npm依赖安装或外部CDN。构建与验收命令需要Node.js，本地服务示例需要Python。

## 浏览与操作

- 顶部“全部页面”提供72页预览目录；“系统总表”同时列出玩法与底层系统；“玩法流程”按13条典型操作链浏览。
- “页面目录”支持按中文标题、系统或页面ID搜索，并直接进入目标页面。
- 页内按钮、底部游戏导航和URL片段共同定位页面，例如[旗舰总览](http://127.0.0.1:8794/docs/design/game-ui/prototype/#ship-overview)、[航行HUD](http://127.0.0.1:8794/docs/design/game-ui/prototype/#sailing-hud)、[家书匣](http://127.0.0.1:8794/docs/design/game-ui/prototype/#letters)。
- 页面状态选择器用于审阅提示、条件和恢复入口；这不等于完整原生状态机或所有分支任务已经接通。
- 交易、修船等主要操作会改变演示资源并在相关页面反映；部分说明性按钮给出提示。可用“重置演示”恢复初始值。
- 截图入口采用 `?capture=1#页面ID`，例如[旗舰截图视图](http://127.0.0.1:8794/docs/design/game-ui/prototype/?capture=1#ship-overview)。它隐藏审阅工具，保留游戏界面；这是网页截图模式。

## 系统、剧情与现有游戏的关系

完整范围见[系统说明](../systems.md)与[机器可读目录](../systems.json)，页面实现合同见[renderer-contract.md](../renderer-contract.md)，现有原生界面依据见[只读资产与UI审计](../existing-ui-audit.md)。

P0／P1标识未来Godot实施顺序，不是本轮页面删减依据。72页均属于原型范围。11类底层系统为输入与镜头、航行运动与碰撞、世界渲染、粒子与尾迹、AI与舰队调度、任务与事件数据、存档恢复、音频、UI路由与本地化／无障碍、资源LOD与性能、实验室证据。每项的现有实现记录和未来设计目标分别列出，未验证部分保持开放。

剧情唯一来源是[zheng-zhilong-story.json](../../../narrative/zheng-zhilong-story.json)。当前为单线剧本，43场的 `choices` 为空。“行动安排”呈现局部经营、战术或执行方案，不能据此宣称有改变历史结局的完整分支战役。

1624福松出生、1628受抚、1630赴明、1633料罗湾、1635芝虎未归、1645赐姓与母亲赴明、1646父子分途及田川氏罹难等节点保持既定骨架。妻儿、船员和盟友拥有自己的诉求与去留，不能用好感、送礼或付款自动消除冲突。

## 图像来源与历史边界

图像均来自本仓库已落盘资产。图片承担游戏概念与历史情境表达，不是历史照片、实物考据或Godot动态渲染证据。

| 用途 | 实际来源 | 性质与记录 |
| --- | --- | --- |
| 福船检阅主图 | [assets/fuchuan-inspection.png](assets/fuchuan-inspection.png) | 本轮使用内置imagegen生成的完整透明底福船概念插图；不是当前活动Godot船模。提示词、原始生成路径、尺寸和审读说明见[ship-art-provenance.json](../ship-art-provenance.json)。 |
| 航行HUD背景 | [assets/sailing-background.png](assets/sailing-background.png) | 本轮内置imagegen生成的海上航行情境图；不是实时海水、尾迹或船体求解画面。来源见[sailing-art-provenance.json](../sailing-art-provenance.json)。 |
| 港口、人物、货物与弹药 | [仓库art目录](../../../../assets/art/) | 沿用既有项目图像；各项提示词与来源边界见对应目录及[资产审计](../existing-ui-audit.md)。人物立绘是角色概念形象，不声称复原历史人物容貌。 |
| 章首与剧情场面 | [叙事阅读器图片](../../../narrative/zheng-zhilong/images/) | 使用唯一剧本当前选定的图像路径；逐图提示词、尺寸、哈希和采用记录见[illustration-manifest.json](../../../narrative/zheng-zhilong/illustration-manifest.json)。旧图存在不等于本轮采用。 |

逐场历史依据与原创内容以剧本 `history.level`、`history.note`、`history.sources`为准。阮老六、杜七及具体私人对白、跨文化遭遇含原创内容。1629“湾口起火”是历史背景下的虚构战事，不能宣称为已证郑芝龙抗倭战绩；混合掠夺团伙也不等于所有日本人。原型人物、地图位置、示例价格和船队数量不作为史料。

## 构建与验收

在仓库根运行：

```powershell
rtk proxy node tools/build-game-ui-prototype.mjs
rtk proxy node tools/verify-game-ui-prototype.mjs
```

构建工具从系统目录与唯一剧本生成经典脚本 `data.js`，并登记已存在的页面预览。静态验收工具在Node VM加载数据、核心与三个渲染模块，实际调用72页渲染器，核对：

- 30个玩法系统、11个底层系统、72页和13流程的数量、唯一ID及归属。
- 全部渲染器恰好注册一次、没有多余注册、页面主体非空。
- 去掉共用页头与导航后，页面正文HTML与可见文字哈希分别不同。
- 真实剧本场景引用、导航目标、本地HTML／图片／CSS资源及JavaScript语法。
- 已有 `previews/页面ID.jpg` 的JPEG头尾和尺寸，以及 `data.js` 的预览索引是否同步。

结果写入[verification.json](verification.json)。默认运行在预览未齐时记为 `pending`，不能作为全量完成结论。72张浏览器截图导出后，重新构建数据，再执行严格模式：

```powershell
rtk proxy node tools/build-game-ui-prototype.mjs
rtk proxy node tools/verify-game-ui-prototype.mjs --require-previews
```

严格模式要求72张JPEG预览全部存在且文件头、尾和尺寸有效，缺失或损坏会退出失败。静态验收不执行真实浏览器点击，文件头也不能证明视觉质量；实际界面、图片加载、溢出、键盘和操作反馈要另做浏览器检查。截图清单与目视记录由导出任务另行保存，不能把尚未生成的证据写成通过。

本网页与其截图仅为UI原型证据；Godot正式入口、原生业务、GPU、长时资源释放及性能需单独验证。

