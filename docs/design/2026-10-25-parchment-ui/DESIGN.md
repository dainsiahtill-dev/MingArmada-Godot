# 大明海战 Godot 纸本界面改版

用户在审阅生成背景后明确要求整套Godot UI应用此风格，包括主菜单、按钮与各种背景，并继续生成相近风格素材。该明确新方向优先于2026-10-22网页原型DESIGN中“宣纸不铺满”的旧约定；本次直接实施，不等待重复选型确认。

## 场景与视觉

玩家在桌面上阅读一册晚明海务图志：菜单与管理页是有纤维、磨损边缘的暖纸，海图与舰船以淡墨附在边缘；实际航行和战斗保留3D世界，信息以纸签、账页与小面板叠在边缘。图像保留纸质细节，阅读区域控制对比，按钮和文字仍是可交互的Godot控件。

明确采用已生成的ming-armada-ui-background-parchment.png作为主菜单方向：右下舰船、左侧留白。继续生成账册底、海图底、可九宫拉伸的纸面板和两种按钮底。所有生成原图保存项目根目录，并留真实prompt与来源。图像不烘焙文字/按钮标签，不用假UI截图代替实际控件。

配色：PAPER #ead3a6，INK #33281d，MUTED #6b513b，OUTLINE #9b7346，CINNABAR #8d3d2b，SEA #315a5a。状态以文字/图标和颜色共同表达。标题保留宋体风格，操作、数据使用中文无衬线系统字体。正文默认16–17px，键盘焦点清楚，normal/hover/pressed/disabled/focus齐全。

## 实施边界

覆盖实际可达的主菜单、设置、存档恢复、明旗航程、旧版航程、海战HUD、自由试航HUD、遭遇/决斗/陆战/寻宝/宴会、海图、船只检阅、实验室、论文阅读及开发验收面板。库存调查文件列明具体入口。通过共享主题替代相互独立的局部主题，再处理写死的文字色/背景/图表色。

保持既有信号、动作token、generation/nonce、存档、输入路由、世界渲染和玩法状态合同。装饰控件MOUSE_FILTER_IGNORE，不能截获船只操作。默认不改3D海面、光影、战斗或新表现算法；这是UI艺术和控件主题工作，不以此制造算法研究课题。新界面的证据必须来自真实Godot入口和必要的渲染截图，headless只能证明脚本/状态。

## 共享接口（实施约定）

`const Parchment = preload("res://game/ui/shared/parchment_theme.gd")`

- `create() -> Theme`：统一Button/OptionButton/CheckBox/CheckButton/Label/LineEdit/TextEdit/RichTextLabel/PanelContainer/PopupMenu/ItemList/TabContainer/TabBar/HSlider/VSlider/ProgressBar/FileDialog/Window/滚动条等实际用到的控件。
- `panel(margin: float = 14.0, tone: String = "paper") -> StyleBox`：paper/inset/overlay/dark。多数是纹理纸面；消费者不得强转StyleBoxFlat。
- `button_style(state: String = "normal", primary: bool = false, margin: float = 12.0) -> StyleBox`：normal/hover/pressed/disabled/focus。
- `background(parent: Node, variant: String = "ledger", node_name: String = "ParchmentBackground") -> TextureRect`：menu/ledger/chart；装饰放在子节点底部，拉满父Control，KEEP_ASPECT_COVERED，忽略鼠标。
- `title_font() -> Font`：标题宋体系统字体。
- 常量`PAPER, INK, MUTED, OUTLINE, CINNABAR, SEA, SUCCESS, DANGER`，其中SUCCESS深绿，DANGER深朱砂。

背景文件：res://ming-armada-ui-background-parchment.png（已有），res://ming-armada-ui-background-ledger.png，res://ming-armada-ui-background-chart.png。
纹理：res://ming-armada-ui-panel.png，res://ming-armada-ui-button.png，res://ming-armada-ui-button-primary.png。

## 执行与验收

1. 固定当前UI清单及截图方法，保留已有工作，不提交/推送/清理。
2. 生成并检查5张补充素材；首两张已完成，保留实际1672×941尺寸事实，不伪称2560×1440。
3. 为共享主题加入有意义的控件状态/资源与输入透明检查，看到失败后实现；分组替换现有表层样式，保留行为。
4. 运行相关UI/设置/路由/航程回归和Godot脚本导入检查；先修失败，再扩展到真实入口。
5. 在正常GPU渲染下覆盖主菜单、设置、存档、航程管理、海图、海战/遭遇、船只和实验室等界面截图，检查字体、对比、裁切、焦点、弹窗和鼠标遮挡。1600×900为原生基准，并核验缩放/小窗口。
6. 更新实际覆盖/证据及未测限制，给出可直接运行的完成版本；不把静态代码审查称为运行验证。
