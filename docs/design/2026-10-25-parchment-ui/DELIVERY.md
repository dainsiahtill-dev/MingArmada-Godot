# 大明海战纸本 UI 交付记录

日期：2026-10-25。项目：`C:/Users/dains/Documents/Git/ming-armada`。本次已将用户选定的旧纸、淡墨海景、明式帆船与朱砂配色接入实际 Godot 游戏控件。最终七组 GPU 检查通过：83 张截图、905 项检查、0 失败。逐图发现的实验室小窗口问题已修复并复拍，最终代码、素材和截图哈希均匹配当前文件。

## 已实施的界面

| 范围 | 实际变化 |
| --- | --- |
| 主菜单 | 右下帆船海景背景、宋体标题、旧纸菜单与输入框、朱砂主要按钮；1600 首屏可见设置与退出，较小窗口保留滚动 |
| 设置、恢复与文件窗口 | 统一纸面、深墨文字、下拉／勾选／滑块／焦点状态；修复嵌入窗口灰底、标题透字和浅色导航图标；导入操作标题与按钮中文化 |
| 海上明旗 | 航程 HUD、旗舰、船队、港口贸易、俘获、战术、日志、暂停与存档界面接入共享主题 |
| 海战与试航 | 单舰、舰队与自由试航 HUD、炮火操作、设置、暂停与投降确认使用纸面板；保留海面视野和现有输入路径 |
| 海图与旧版航程 | 深海色、墨色与朱砂标记；旧版市场／存档／设置等继承统一控件；保留原地理数据、投影与航线逻辑 |
| 船只检阅与实验室 | 侧栏、目录、参数、论文、来源与通知统一纸本风格；首航实验纸板支持视口缩窄和恢复 |
| 其他现有入口 | 决斗／陆战／寻宝／宴会、画面验收、海岛验收、水面参考、来源对照、独立试航与海岛原型的 UI 统一 |

共享实现位于 [`game/ui/shared/parchment_theme.gd`](../../../game/ui/shared/parchment_theme.gd)。按钮、文字、数值仍由 Godot 实时绘制；装饰背景忽略鼠标。正常、悬停、按下、禁用、键盘焦点，以及 SpinBox 增减箭头均有对应样式。

没有修改 3D 海面、光影、航行、战斗或存档算法。直接叠在 3D 实验视图中的诊断标签保留浅字和深阴影，以维持跨背景可读性。既有并发模型制作文件保留。

## 生成素材

全部由 ChatGPT 内置图像生成工具制作，PNG 原图保存在项目根目录。背景实际为 1672×941，面板为 1254×1254，按钮为 2172×724；没有将提示词期望尺寸写成实际尺寸。

| 文件 | 用途 |
| --- | --- |
| `ming-armada-ui-background-parchment.png` | 当前主菜单背景 |
| `ming-armada-ui-background-ledger.png` | 管理、恢复、实验室等账册背景 |
| `ming-armada-ui-panel.png` | 实际九宫纸面板 |
| `ming-armada-ui-button.png` | 实际普通按钮底 |
| `ming-armada-ui-button-primary.png` | 实际朱砂主要按钮底 |
| `ming-armada-ui-background-chart.png` | 已生成的备用海图背景；未替换带真实地理信息的游戏航图 |
| `ming-armada-ui-background-parchment-draft-v1.png` | 保留的主菜单初稿 |

5 张本轮补充素材的完整提示词见 [`asset-prompts.json`](asset-prompts.json)，早先主背景记录见根目录 [`ming-armada-ui-background-generation.json`](../../../ming-armada-ui-background-generation.json)。[`assets.json`](assets.json) 记录原尺寸、字节数、SHA-256 与完整 PNG 解码检查。另有 11 个简单 SVG 控件图标位于 `assets/ui/parchment/`。

## 代码与行为验证

Godot `4.7.2.stable.official.ed1daf0bf`。所有测试使用任务隔离 profile；GPU 捕获还只读核对原存档与设置的前后哈希。

| 验证组 | 实际结果 | 证据 |
| --- | --- | --- |
| 设置／恢复／旧版／实验室／路由 | 6 套、591 断言、0 失败 | [`surface-inventory.md`](surface-inventory.md) 末尾与 `evidence/post-test_*.json` |
| 正式游戏 UI 与相关合同 | 12 套、2271 断言、0 失败 | [`gameplay-implementation.md`](gameplay-implementation.md) |
| 辅助场景与 UI | 10 套、1095 断言、0 失败 | [`auxiliary-implementation.md`](auxiliary-implementation.md) |
| 最终共享主题与主菜单 | 56 + 62 断言、0 失败 | [`root-final-tests-r2.json`](evidence/root-final-tests-r2.json) |
| 明旗真实文件窗口 | 10 断言、0 失败；既有明旗 UI 195 断言、0 失败 | [`post-picker-test_mingqi_file_dialog.json`](evidence/post-picker-test_mingqi_file_dialog.json) |
| 首航实验纸板缩放 | 24 断言、0 失败；既有生命周期 16 断言、0 失败 | [`p2-fixed-test_voyage_flow_paper_resize.json`](evidence/p2-fixed-test_voyage_flow_paper_resize.json) |
| 实验室小窗口与滚轮 | 10 断言、0 失败；既有 UI 26、架构实验 46 断言、0 失败 | [`laboratory-viewport-layout-fix.json`](evidence/laboratory-viewport-layout-fix.json) |

表中是各次有关联的运行记录，部分套件重复，不等于互不重复的全项目测试总数。最初失败、修复和复测证据均保留。相关源文件通过 scoped `git diff --check`，未提交或推送。

真实开局 HUD 使用相同 runtime 数据时，由旧界面的 430×486 变为 430×470；旧小夹具的 430×360 不能用来描述真实开局。详见 [`live-hud-comparison.json`](evidence/live-hud-comparison.json)。

## GPU 与交互验收

| 最终证据目录 | 图片 | 检查 | 失败 |
| --- | ---: | ---: | ---: |
| `evidence/gpu-menu-r4` | 11 | 121 | 0 |
| `evidence/gpu-mingqi-r2` | 16 | 198 | 0 |
| `evidence/gpu-legacy-r2` | 8 | 94 | 0 |
| `evidence/gpu-naval-r3` | 15 | 178 | 0 |
| `evidence/gpu-catalog-r2` | 8 | 110 | 0 |
| `evidence/gpu-practice-r1` | 8 | 64 | 0 |
| `evidence/gpu-auxiliary-r1` | 17 | 140 | 0 |
| **合计** | **83** | **905** | **0** |

[`final-delivery-manifest.json`](evidence/final-delivery-manifest.json) 由 `finalize-delivery.mjs` 实际生成：逐张完整解码 PNG、校验截图 SHA-256，核对每组源文件对当前工作树的哈希，校验 7 张原图与 11 个 SVG，并记录代表截图副本。七组记录均显示原玩家槽和隔离 profile 默认槽前后不变。

四张 **真实 Godot 运行截图** 已复制到项目根目录，便于直接打开：

- [主菜单](../../../ming-armada-ui-preview-main-menu-2026-10-25.png)
- [航海设置](../../../ming-armada-ui-preview-settings-2026-10-25.png)
- [港口贸易](../../../ming-armada-ui-preview-port-2026-10-25.png)
- [舰队海战 HUD](../../../ming-armada-ui-preview-naval-2026-10-25.png)

执行工具与边界见 [`capture-tool.md`](capture-tool.md)，逐轮发现与修复见 [`gpu-review.md`](gpu-review.md)，独立代码审查见 [`FINAL-REVIEW.md`](FINAL-REVIEW.md)。两项审查 P2（SpinBox 箭头对比、首航纸板缩放）和明旗文件窗口验证点已关闭。文件选择器内建 `Path`、`Favorites` 等少数引擎标签仍为英文；中文化覆盖本游戏设置的标题和操作按钮。

逐图复核另发现 1280×720 实验室的参数换行会挤压预览并裁切诊断末行，现给预览保留至少 200px 高度，让实验控制区纵向滚动。滚轮位于预览时仍控制镜头缩放，不同时滚动整页；底部统计可滚动访问。旧 `catalog-r1` 保留为失败视觉证据，最终采用修复后的 `catalog-r2`。

真实 GPU 为 Intel Arc 130T，Vulkan Forward+。基准 1600×900，另检查 1280×720、320×480 菜单与实验面板缩窄／恢复。键鼠事件经 Godot `Window.push_input` 进入真实 GUI 分发；不是操作系统级鼠标自动化。文件窗口为实际 Godot 嵌入窗口。

截图时冻结场景自动处理以稳定布局；这里证明指定 UI 状态、入口与输入操作，不证明连续海况、完整航程或 FPS。未制作新的 Windows 导出安装包，也未将 Godot UI 改版发布到小说网页。

## 运行与复查

在 Godot 打开根目录 [`project.godot`](../../../project.godot)，按 F6 可运行选中场景，按 F5 运行真实游戏入口 `game/scenes/main/main_scene.tscn`。

复跑主题与菜单测试（仓库根目录）：

```powershell
rtk proxy node docs/design/2026-10-25-parchment-ui/run-check.mjs --headless --script res://tests/test_parchment_theme.gd
rtk proxy node docs/design/2026-10-25-parchment-ui/run-check.mjs --headless --script res://tests/test_main_menu.gd
```

`run-check.mjs` 使用本机已验证的 Godot 路径并隔离 APPDATA／LOCALAPPDATA；换机器时需先调整其中引擎路径。
