# 牛皮纸 UI 表面清单

日期：2026-10-25。范围：Godot 游戏 UI；不含小说、网站、玩法或渲染算法。

本记录为修改前静态源码审计，不是运行验收。主任务已确认 CodeGraph 无索引；本轮用 RTK 的定向源码检索。仓库只发现根目录 `AGENTS.md`，未发现 `game/ui`、`game/research` 下更近的约定。

视觉目标：暖色纤维纸、深褐墨色、少量朱砂与海军蓝；所有标题、按钮、数值保持实时 Control 文本。已选主背景为仓库根目录 `ming-armada-ui-background-parchment.png`，船只集中右下，左侧与中部用于正文。

## 实际入口

`project.godot:14` 指向 `game/scenes/main/main_scene.tscn`。`main_scene.gd:_ready()` 将 MainMenu、SaveRecovery、SettingsPanel 并列挂到 `EntryUI` CanvasLayer；后两者不是菜单子节点，不能依靠菜单主题继承。

| 入口 | 实际场景 / UI | 可达性 |
| --- | --- | --- |
| 新生涯 / 继续 1650 | `mingqi_scene.tscn` / `mingqi_interface.gd` | 普通首页；模式 `mingqi`、`mingqi-continue` |
| 单舰炮战 / 舰队遭遇 / 自由试航 | `scenes/naval_practice/naval_practice.gd` / `ui/naval_practice.gd` | 普通首页；`duel`、`fleet`、`sail` |
| 实验室 | `game/research/laboratory.gd` | 普通首页；`laboratory` |
| 海面与海岛验收 | `fidelity_island.tscn` 实际绑定 **`combined_island.gd`** | 普通首页；`fidelity-island` |
| 检阅船只 | `ship_book.tscn` / `ship_book.gd` | 普通首页；`ships` |
| 旧版新生涯 / 继续 | `legacy_scene.tscn` / `legacy_interface.gd` | 开发入口；`career`、`continue` |
| 玩法验收 | `practice.tscn` / `practice.gd` + EncounterInterface | 开发入口；`practice` |
| 画面验收 | `visual_qa.tscn` / `visual_qa_inspector.gd` | 开发入口；`qa` |
| 海岛水面参考 | `reference_island_water.tscn` | 开发入口；`water-study` |
| 参考海岛对照 | `fidelity_source.tscn` 实际绑定 **`fidelity_island.gd`** | 开发入口；`fidelity-source` |
| SailingTrial / NaturalIslandPrototype | 对应独立场景 / `sailing_hud.gd` 或局部工具栏 | 不在 GameRouter 模式中；直接场景、测试仍使用 |

开发入口由 `development_access.gd` 的 debug/editor host 判断与 `--dev` / `--qa` 参数共同控制；菜单与 Router 双重检查。`continue` 是旧版，不是 `mingqi-continue` 的别名。不要为了视觉验收改变入口权限。

## 表面、主题和局部覆盖

| 文件 / 构建点 | 实际表面 | 主题现状与遗漏风险 |
| --- | --- | --- |
| `ui/menu/main_menu.gd:_build(), _entry(), _theme()` | 主背景、标题、船长名输入、普通/开发菜单、加载/错误/重试状态、设置和退出 | 独立菜单主题；主任务单独处理此文件 |
| `ui/menu/save_recovery.gd:build()` | 恢复整页、原因与提示、重读/备份/导入/导出/返回按钮、JSON TextEdit、导入/导出 FileDialog | 创建 MainMenu 实例仅调用 `_theme()`；背景 `123837`，纸板 `f1e6cb`。应直接使用共享主题，取消跨视图主题依赖 |
| `ui/settings/settings_panel.gd:build()` | 全屏遮罩、居中设置面板、原因、操船/画质 OptionButton、CheckButton、音量/晃动/地平线 HSlider、滚动和返回 | **未设置根 theme**；直接设置面板样式与局部 Label 色。主菜单和 `sea_services.gd` 都独立实例化它 |
| `ui/legacy/legacy_interface.gd:_build()` | HUD、12 个操作页、暂停菜单、投降确认/结算/退休结果板、文件导入窗口 | `_screen.theme = legacy_theme.create()`，绝大部分样式可通过共享主题统一 |
| `legacy_interface.gd:_market(), _shipyard(), _recruit(), _officers(), _quests(), _people(), _fleet_page(), _factions(), _chart(), _log(), _save(), _settings()` | 市场、修船船坞、招募、军官、委托、人物、舰队、势力、地图、日志、存档、设置 | SpinBox、OptionButton、LineEdit、TextEdit、CheckBox、HSlider、角色图片。唯一明显浅字覆盖在 `_button()` 的 gate 原因 `e6b89a`；需转深色语义 token |
| `ui/legacy/legacy_chart.gd` | 旧版大海图 | 仅数据适配，继承 `nautical_chart.gd`；无需新增主题逻辑 |
| `ui/encounters/encounter_interface.gd:_ready(), _build(), _grid()` | 决斗、陆战 9×7 网格、寻宝、宴会、挑战结果/结算/再试 | 已用 `legacy_theme.create()`。陆战格子 modulate `a0e7d8` / `f4b6a0` 会整体染纸与文字，需改为受控状态样式或纸面适配色 |
| `ui/mingqi/mingqi_interface.gd:_build(), _make_theme()` | 正式 1650 HUD、旗舰、船队海图、靠港交易、接舷俘获、战术、日志、首航流程、暂停/存档/退出与文件窗口 | 独立 dark teal theme；多处局部颜色。另有 `_build_ship()` ProgressBar、`_build_menu()` FileDialog；必须一起统一 |
| `ui/mingqi/mingqi_chart.gd` | 正式航图 | 继承共享 NauticalChart，只负责正式地理数据 |
| `ui/naval_practice.gd:_ready()` | 炮战/舰队/试航 HUD、炮火/弹种/风帆操作、通知、暂停/投降/结果/重启/退出弹窗、航图关闭按钮 | 当前只创建字体 Theme；HUD/弹窗复用本地 StyleBox；按钮/滑块仍易落入 Godot 默认样式 |
| `ui/sailing_hud.gd:_ready()` | 独立 SailingTrial 的状态板、标题与操船提示 | 本地暗色面板和浅字覆盖，无共享主题 |
| `ui/charts/nautical_chart.gd:_draw()` 等 | 大海图与 minimap、航线/船只/港口/图例/罗盘/印章 | 已是纸海图，使用 `ming-nautical-chart-v2.png` 与 land paper；大部分色已经墨褐/金/朱砂。图例/友军 cyan 可适配；地形采样、缓存、投影、标记语义不变 |
| `research/laboratory.gd:_build_ui(), _theme()` | 实验室背景、目录、选中课题、论文/来源页、实验控制、SubViewport 外框、统计与通知 | 独立 navy Theme + 背景；整个 host 与下列控件均需继承统一主题 |
| `research/parameter_panel.gd:bind_specs()` | 动态 CheckBox、OptionButton、SpinBox | 无色值；继承 Laboratory 主题即可 |
| `research/paper_reader.gd:to_bbcode()` | 论文 RichTextLabel 的代码块、二级标题、引用 | BBCode 嵌入 `#94c2cf` / `#cfb580` / `#a9b9bb`，根主题无法覆盖；需直接改语义色 |
| `scenes/ship_book/ship_book.gd:_ready(), _build_controls()` | 舰船预览侧栏、船型/视角/动画/损坏控制、数据与返回 | 已用 `legacy_theme.create()`；共享迁移覆盖侧栏。3D 海水/灯光色属于预览，不是 UI 背景 |
| `scenes/practice/practice.gd:_ready()` | 玩法验收整页、玩法/难度选择、状态、返回及 EncounterInterface | 已用 legacy theme，但整页 `ColorRect("173e3e")` 需显式替换 |
| `scenes/visual_qa/visual_qa_inspector.gd:_ready()` | QA HUD、场景/画质/时间控制、视角、状态、重启/设置/返回 | 自建字体 Theme + 暗板 `Color(0.03,0.12,0.13,0.94)`；需共享主题 |
| `scenes/reference_island_water/reference_island_water.gd:_label(), _build_ui()` | 开发海岛参考的标题、视口、侧栏、预设/滑块/开关、截图/返回、状态 | `0f1b22` 整页、`142630` 板、`b8d9da` 字；明确改 UI 构造，不改 Environment/水体材质 |
| `scenes/fidelity_island/combined_island.gd:_build_ui()` | 普通首页可达的海岛验收工具栏、暂停、返回、底部状态 | 没有自设 theme 或背景；默认 Godot 控件，需显式统一，保留 SubViewport |
| `scenes/fidelity_island/fidelity_island.gd:_build_ui()` | 开发来源对照工具栏、各种查看控制、返回、状态 | 没有自设 theme；给 UI 根赋共享主题，不动环境/太阳的 Color |
| `scenes/natural_island/natural_island_prototype.gd:_build_ui()` | 独立原型的工具栏和状态 | 直接场景/测试使用，默认主题；保留世界渲染颜色 |

### 研究 Demo 内部的额外文字

大多数 `research/demos/*.gd` 仅构建 3D 世界；不能把它们的灯光、海水、实验靶标色当 UI 批量替换。确实存在以下独立于 host 的文字：

- `architecture_convergence_experiment.gd:149-150`：世界 CanvasLayer 下白字 + 深阴影诊断标签。
- `weather_shadow_experiment.gd:212-221`：世界 CanvasLayer 下浅米字 + 深阴影诊断标签。
- `voyage_flow_experiment.gd:_build()`：`VoyageFlowFixture` Label，22 px，默认主题，作为只读首航流程实验内容。

这些位于 SubViewport 或非 Control 祖先下，不能假定继承实验室主题。诊断标签可保留跨 3D 画面高对比表现，或加小型纸面底板；如改造，明确仅样式，不修改实验数据与状态推进。

### 关键硬编码色

| 所在处 | 修改前值 | 目标语义 |
| --- | --- | --- |
| Settings 遮罩/面板/边/字/原因 | `(0.015,0.04,0.05,0.8)` / `173b3b` / `c4a36d` / `f5e7c4` / `e6c58d` | 暖墨遮罩、纸面、褐边、墨色、朱砂原因 |
| SaveRecovery 背景/纸 | `123837` / `f1e6cb` | 统一暖底；细纸纹 |
| Legacy gate reason | `e6b89a` | 深朱砂 / 深赭 |
| Laboratory 字/hover/disabled | `dce7e5` / `ffe2a4` / `7a9295` | 深墨 / 朱砂或深海蓝 / 可读浅墨 |
| Laboratory 按钮/背景 | `20373e` / `142930` / `0c1c23` | 普通纸 / 稍深纸 / 背景纸 |
| Laboratory 选中课题/未选中/状态 modulate | `e2c48b` / `dce7e5` / `c5b590` | 深朱砂 / 正文墨 / 次要墨；避免 modulate 叠乘导致偏色 |
| PaperReader 代码/标题/引用 | `94c2cf` / `cfb580` / `a9b9bb` | 深海蓝 / 朱砂或褐墨 / 次要墨 |
| NavalPractice 状态/提示/通知 | `f1e6cb` / `d2c6a7` / `e7c887` | 正文 / 次要 / 通知语义色 |
| SailingHUD 标题/状态/提示 | `f0d6a1` / `f8edcf` / `e4dfc5` | 标题墨 / 正文墨 / 次要墨 |
| Mingqi 旧面板/按钮/正文 | `(0.045,0.14,0.155,0.95)` / `264d49`, `3b6256`, `806b43`, `152f33` / `eee6d4` | 统一纸面状态与墨字；同时审计局部覆盖 |

## 最小共享接缝

增加单一 `game/ui/theme/parchment_theme.gd`（路径可由主任务最终确定），提供静态 `create()`、纸面 StyleBox、背景图挂载和少量语义色。所有根 Control / CanvasLayer 下 `_screen` 显式使用它。现有 `_theme()` / `_make_theme()` / `legacy_theme.create()` 可保留短委托适配，避免让其他调用者直接依赖菜单实例。

共享主题至少覆盖：

- `Control`, `Label`, `RichTextLabel` 的正文/标题/次要文字，CJK 字体与字号。
- `PanelContainer`, `Panel`, `PopupPanel` 的纸面/边线；`Window`, `AcceptDialog`, `FileDialog` 的弹窗面板和标题文字。
- `Button`, `OptionButton` 的 normal、hover、pressed、disabled、focus；`PopupMenu` 项目、高亮/禁用；不只改 Button。
- `LineEdit`, `TextEdit`, `SpinBox` 的纸色输入底、墨字、placeholder、selection/caret、只读/焦点。
- `CheckBox`, `CheckButton`, `HSlider`, `VSlider`, 滚动条、ProgressBar 的轨道/选中/禁用和可见焦点。
- `ItemList`（文件选择器）、`Tree`（若 Godot 对话框使用）、Separator/TabContainer（如共享主题以后引用）。

背景与面板分工：标题页/恢复/实验室可使用完整纹理背景；海战 HUD、弹窗、船只侧栏用浅纹理纸面，保留实时海面可见。不要给所有父节点插入不透明全屏 TextureRect。纹理装饰设 `MOUSE_FILTER_IGNORE`，按钮文字仍由 Godot 绘制。

FileDialog 是 Window，需单独验证它的嵌入/主题继承结果；仅父 Control 赋 theme 并不构成验收证据。

## 并行所有权建议

1. **共享主题 + 首页 + 资源负责人**：唯一负责新 theme/helper、`main_menu.gd`、`legacy_theme.gd` 与生成纹理导入；先发布 API 名称和语义色，避免并行者各造工厂。
2. **正式游戏 UI 负责人**：`mingqi_interface.gd`、`ui/naval_practice.gd`、`sailing_hud.gd`、`encounter_interface.gd`；修局部样式并覆盖正式交互状态。共享航图仅按已约定颜色范围修改。
3. **辅助页面负责人**：`settings_panel.gd`、`save_recovery.gd`、`legacy_interface.gd`、Laboratory/Reader；同时负责 ShipBook、Practice、QA、海岛预览和独立原型的 UI 根主题/背景。
4. 验收者只读 diff + 真实程序；不要同时修改同一主题文件。图表算法、资源生成算法、业务命令/信号、存档会话令牌不在样式分区内。

## 验收入口与覆盖点

- 通过真实首页进入 mingqi、sail、duel、fleet、ships、laboratory、fidelity-island；公开菜单可见项与返回路径保持原样。
- 首页 / 海战内分别打开 Settings，检查下拉、开关、滑块、键盘焦点、缩小窗口后的滚动。
- 独立恢复夹具打开 SaveRecovery，检查 JSON 输入和导入/导出 FileDialog；无需破坏用户存档制造恢复状态。
- 正式 Mingqi 操作页、菜单、ProgressBar、文件对话框；NavalPractice 暂停/投降/结果纸面；实景不被背景遮住。
- Laboratory 阅读全文、来源、动态实验参数和统计；代码/引用/标题的 BBCode 颜色必须可读。
- debug/editor + `--dev` 覆盖旧版、挑战网格、QA、水面参考、来源对照；独立 Trial/Prototype 另注明直接场景验证。
- 只读检查已有测试：`test_menu_consolidation.gd`, `test_development_access.gd`, `test_game_router.gd`, `test_laboratory_entry.gd`, `test_release_game_entry.gd` 等；样式修改不能改变其命令合同。
- 纹理 import/脚本解析通过不等于 GPU 视觉完成；静态截图也不代表交互/动态验证。将实际测到的窗口尺寸、入口、焦点/弹窗状态与未覆盖状态写入最终报告。
