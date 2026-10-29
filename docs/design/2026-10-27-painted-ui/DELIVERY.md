# 生图窗口与克制金边交付

2026-10-27。承接用户对浅白程序界面、过度雕金云浪、字体层级、适度金边及每个窗口投影的连续反馈。本轮完成的是当前正式主菜单、1650航程、自由试航/单舰/编队、世界海图及船舶检阅下拉的窗口材料与交互复验；不是整个游戏美术与玩法的最终验收。

## 当前效果

独立窗口使用深青手绘旧册底、细旧金线和柔和外影。底板采用 `painted/quiet`，边框和阴影来自生图编辑后的 `quiet/framed` 透明PNG；没有用代码补画金矩形或模糊阴影。书页保留一个低对比云纹，去掉首轮显眼雕金四角、卷浪、朱砂大标题牌和罗盘装饰。阴影与标题字体分开，文字没有外发光、可见字影或描边。

主要标题为本机实际解析的KaiTi，正文为Microsoft YaHei。主要窗口28–30px、操船手册26px、原生文件窗口标题24px；叙事正文18px、关键HUD及设置字段16px。辅助炮舷信息仍有13px，未把它说成全界面字号均已达到18px。系统字体在其它机器上的替代尚未实测。

覆盖的外层包括船况牌、底部操船轨、航海日志与菜单、设置、降旗确认、独立近海图/minimap、恢复航程、嵌入式文件选择、下拉菜单、主菜单编辑菜单和窄屏菜单纸面。Tree/ItemList、输入框和书页内的条目保持inset；文件选择的client也保持inset，由完整Window外框承担唯一金线和投影。世界地图整页保留纸图，港口下拉使用统一浮层材料。船舶检阅固定侧栏属于整页分区，不另投影；ShipKind/CameraAngle/开发可见ShipLOD原生PopupMenu统一使用Maritime材料。

实际效果：

- [1650航海日志与许福](evidence/layered-mingqi-final/mingqi-story-portrait-1280.png)
- [航程菜单的前后层](evidence/layered-mingqi-final/mingqi-menu-1280.png)
- [主菜单上的设置](evidence/layered-menu-final-r2/menu-settings-1280.png)
- [窄屏设置](evidence/layered-menu-final-r2/menu-settings-narrow-320.png)
- [文件选择窗口](evidence/layered-menu-final-r2/recovery-file-dialog-1280.png)
- [海战降旗与固定手册标题](evidence/layered-naval-final-r2/naval-surrender-1280.png)
- [世界海图的实际港口下拉](evidence/layered-atlas-final/atlas-harbour-dropdown-1280.png)
- [船舶检阅的实际船型下拉](evidence/layered-shipbook-final/shipbook-ship-kind-popup-1280.png)

## GPU与输入证据

最终采用 [all-window-ui-delivery.json](evidence/all-window-ui-delivery.json)，五组全部从真实MainScene主菜单进入，由Windows上的Godot 4.7.2 / Vulkan Forward+ / Intel Arc 130T实际绘制。旧四组 `layered-ui-delivery.json` 保留为补纳船舶检阅之前的有效阶段记录。

| 组 | 最终目录 | PNG | 断言 | 失败 |
| --- | --- | ---: | ---: | ---: |
| 主菜单、设置、右键、窄屏、恢复与文件选择 | `layered-menu-final-r2` | 13 | 141 | 0 |
| 1650六页、手册、菜单、文件选择、剧情回执 | `layered-mingqi-final` | 21 | 265 | 0 |
| 单舰、编队、试航HUD/图、设置、暂停与降旗 | `layered-naval-final-r2` | 15 | 186 | 0 |
| 世界海图三尺寸、缩放、港口下拉与爪哇定位 | `layered-atlas-final` | 6 | 75 | 0 |
| 船舶检阅与真实船型/观察角度下拉 | `layered-shipbook-final` | 6 | 90 | 0 |
| 合计 | | **61** | **757** | **0** |

各组真实进程均exit0、无SCRIPT ERROR/ERROR、原玩家12项存档/备份/暂存状态不变。finalizer重新核对当前源码依赖、图像和日志SHA、runner SHA及唯一完成标记，不只依赖截图脚本的失败计数。源码覆盖包含UI、相关runtime/domain/persistence与全部生成素材。61张图的几何审计均无unclippedOverflow候选；另人工抽查了标题底、设置/文件窗、叙事、海图、确认窗、检阅下拉和窄屏代表状态，这不等于逐像素审查全部文字。

实际鼠标、滚轮和键盘路径在Godot viewport中注入；菜单由原生Control处理。剧情步骤真实支付80两，650→570，完成old-ledger回执并释放肖像；不是更改图片里的数值。默认sound/music关闭，设置持久化与焦点/intent合同保留。

为使UI状态可重复，场景进入后冻结世界的自动process/physics；不把这些静态UI画面作为连续航行、战斗、世界动态或FPS证据。桌面自动操作工具本轮native pipe不可用，按规定恢复尝试后停止，未用其它OS输入接口替代；因此没有宣称本轮通过操作系统鼠标的手动完整游玩。嵌入式Godot FileDialog也不是系统原生文件选择，其Path/Favorites等引擎标签仍有英文。

## 独立检查与实际修复

- 生成材质/真实字体/按钮状态/纹理最不利正文区：[151断言、0失败](evidence/frozen-test-maritime_art_theme.log)。主要正文最小6.242:1，次要文字最小4.557:1，所测enabled按钮状态最小5.282:1；禁用状态独立按3:1检验。每个正文区域使用48×48采样、原生九宫格映射及黑白背景界限，不宣称穷举全部纹理像素。
- 分层独立GPU：[17断言、0失败](evidence/painted-window-probe-v3/result.json)。正文、Window外扩标题安全区相对独立quiet底的最大像素差0；外部金边/阴影有3600个像素显著区别于无框基线，证明实际绘制发生。此小probe的OpenGL结果没有代替上表正式Forward+入口。
- 窄屏设置五种真实理由×三尺寸、逐字段滚动和实际点击返回：[195断言、0失败](evidence/settings-bounds-green.log)。旧固定scroll最小高度在三种双行错误下越界；RED为195项3失败。现由有界窗口和可扩展scroll分配剩余高度。
- 窄屏阅读窗漏外框：[84断言、0失败](evidence/compact-frame-green.log)。RED84项1失败；保留16px紧凑内容边距，在外侧单独补生成边框，未放回大云纹顶留白。
- 手册标题在设置返回/降旗后被滚动裁断：[14断言、0失败](evidence/naval-manual-fixed-heading-final.json)。RED13项2失败；固定标题移出Scroll，body和动作仍可滚动。旧 `layered-naval-final` 是 superseded 图组。
- [真实隔离PCK remap](evidence/pck-remap-headless-final.json)：父64/0、子90/0。10张图在没有原PNG、仅有.remap/.ctex时仍可加载；六项生产工厂选择当前quiet/framed runtime，解码像素与原项目native导入资源一致。修复了FileAccess选图造成导出退回旧图的问题。此为皮肤资源合同测试，未执行完整生产导出验收。
- FileDialog11/0、gameplay UI29/0、Mingqi UI195/0、scene18/0、portrait30/0、设置持久化22/0、菜单62/0、router55/0、世界海图57/0等相关回归已通过。浮动chart专项32/0、原chart507/0、overlay11/0由独立agent执行；完整项目历史测试套件未本轮重跑。
- 船舶检阅新增19项popup显式主题/同实例/真实framed PNG检查通过；[完整ShipBook回归](evidence/shipbook-popup-final-baseline.json)为851项、3失败，仍是本轮UI改动前已有的模型路径golden：原测试期待 `v3_r6`、当前provider默认 `art_r7c`。未为得到全绿而改动旧期待，也未修改模型/provider。中间 `shipbook-popup-final.json` 曾对应临时golden调整，该一行已恢复，不能把这份中间文件用作完整ShipBook通过依据。
- 后续船模工作重新确认[R7c正式交付](../../production/hero-fuchuan-2026-10-26-art/R7-DELIVERY.md)和当前provider合同后，纠正了ShipBook测试中已过期的R6固定路径预期，仍显式检查三档R7c路径及原有功能。新RED [851/3](../../research/evidence/hero-fuchuan/r9-cinnabar-20261027/shipbook-golden-red.log)，修正测试后[851/0](../../research/evidence/hero-fuchuan/r9-cinnabar-20261027/shipbook-golden-green.log)；这次只修复测试期待，没有改变正式船模或provider。上述历史851/3按当时状态保留。

## 保留的失败与范围

首轮花哨雕金、直接拉伸framed图片导致透明带侵入正文、StyleBoxTexture子类_draw在原生Panel未执行、Window probe误采边线以及旧手册标题裁断证据都保留。此前某些组即使counter零失败，也不能替代最终美术结果；旧mingqi-final还出现了已释放Scroll引用的SCRIPT ERROR，runner已改为错误即拒绝。

当前组合helper继承StyleBox，先绘quiet body，再绘draw_center=false的framed edge；两层共同处理Window的32/8/8/6外扩。浮动海图使用同父、无输入的兄弟边框，以避开图自身clip_contents；没有改海图节点路径或Mingqi嵌入图的状态权威。生成原图、提示词、alpha、裁切和SHA见[ASSETS](ASSETS.md)、[QUIET-ASSETS](QUIET-ASSETS.md)、[FRAMED-ASSETS](FRAMED-ASSETS.md)。

剧情逐步接入只完成许福的真实old-ledger肖像与布局；22章/44图叙事、其余人物与账册UI见[清单](STORY-UI-INVENTORY.md)，没有宣称全部原生化。船模、海水/海岛氛围、持续实机、LOD和全游戏性能仍为后续工作。旧1661兼容页及研究实验界面不在本轮61图的完成范围。

CodeGraph当前没有索引，本轮源码定位与审查采用RTK回退。保留既有dirty工作；本轮没有新增提交、推送、清理或重置。

