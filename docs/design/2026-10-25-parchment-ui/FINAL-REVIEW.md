# 纸本 UI 独立最终代码审查

2026-10-25。审查对象是本任务工作树中的实际 Godot UI，未比较整个分支，也未改动产品源码。CodeGraph 已由主任务确认无索引，本轮采用 RTK 定向源码与 diff 审查。

## 范围与结论

已读 `DESIGN.md`、`PLAN.md`、`surface-inventory.md`、`gameplay-implementation.md`、`auxiliary-implementation.md`；审查 `game/ui`、Laboratory/PaperReader/VoyageFlow 实验及清单内辅助场景共 21 个已修改产品文件，新增共享主题与 9 个 SVG 图标。源码审查未发现新增存档写入、命令修改、信号断连、权限绕过、算法改动或全屏装饰拦截操船输入。

**复审结论：原两项 P2、随后追加的实验室小窗裁切与文件选择器验证点均已关闭，未发现尚待修复的必修问题。** 首航纸板通过真实 SubViewport 缩放/清理回归；SpinBox 通过主题回归与修复后 GPU 图像复看。文件选择器的 resolved theme 与实际窗口证据已补足，并修复英文标题与动作标签。实验室小窗裁切通过布局/滚轮回归及 catalog r2 GPU 复拍。本审查不代替全部 GPU 验收。

## 已确认的优点

- 共享主题为真实 Godot 控件提供纹理、深墨文字与状态；菜单、设置、恢复、旧版和独立场景都接入相同接口，未把 UI 烘焙成图片。
- 新背景放在子节点底层并设 `MOUSE_FILTER_IGNORE`；海战和航行继续使用边缘纸板，保留世界画面、原输入根与动作 token。
- NauticalChart 保留地理素材、采样、投影和点击逻辑；新海图背景没有覆盖真实地理信息。
- PaperReader 仍先转义内容再添加格式，变化限于语义颜色。VoyageFlow 新父容器的释放已修正，既有生命周期回归保留了先失败后通过的记录。
- 历史失败报告没有被伪装成通过；报告明确区分 headless 状态测试、GPU 静态画面、实际 viewport 输入与完整玩法/性能验收。

## 原问题与修复复审

### P2：首航实验纸板不响应视口缩小——代码与回归已关闭

`game/research/demos/voyage_flow_experiment.gd:98`：纸板宽度只在 `_build()` 读取一次所属视口，随后固定在至多 720px。替换前 Label 使用 FULL_RECT 锚点；替换后既无锚点也无 `size_changed` 处理。实验室允许拖动 HSplit 分隔条，也允许调整窗口大小；视口缩至 744px 以下时，先前建立的 `x=24,w=720` 纸板会超出视口，右侧说明与回执被裁切。`laboratory.gd:256–259` 的视口变化回调只调用 `orbit_camera(0,0)`，该实验实现为空，因此不会重排纸板。

复审：`_build()` 现记录所属 `Viewport` 并连接 `size_changed`，`_layout()` 按可用宽度重排；文本最小尺寸变化后延后重排高度。`dispose()` 断开对应连接、释放纸板与 Label，重复 configure 保持一个拥有者和一个订阅。未改实验状态、时钟或只读合同。

本轮独立执行 `test_voyage_flow_paper_resize.gd`：24 断言、0 失败、退出码 0。真实 SubViewport 从 960 缩至 360 再恢复，验证两侧边距、文本换行/高度恢复、状态与时钟不变，以及三轮 configure/dispose 后无连接或 UI 遗留。另核对 [`p2-fixed-test_laboratory_voyage_flow.json`](evidence/p2-fixed-test_laboratory_voyage_flow.json) 的既有生命周期回归：16 断言、0 失败。这里是实际控件布局的 headless 证据；本审查未模拟 GPU 上拖动分隔条，不将它称为动态视觉验收。

### P2：SpinBox 增减箭头仍为浅色，纸面上难以辨认——已关闭

`game/ui/shared/parchment_theme.gd:76`：通用颜色循环包含 SpinBox 文本，但主题没有覆盖它的增减图标或对应调制色。已打开真实截图 [`mingqi-port-1600.png`](evidence/gpu-mingqi-r1/mingqi-port-1600.png)：右侧“交易数量”的上下箭头仍为默认白色，约在 `(1556,584)` 与 `(1556,600)`，与浅纸背景对比不足。数字与标签清楚，但可点击的数量调整入口几乎消失。此项有实际 GPU 图像证据，不是仅凭源码风格提出的问题。

复审：主题现覆盖 Godot 4.7 的 `up`/`down` 及 `_hover`、`_pressed`、`_disabled` 图标，配套每个状态的 icon modulate、hover/pressed 背景和 16px 按钮宽度；两个新增 SVG 为 16×8，避免扩大数量输入行。普通深墨、悬停朱砂、按下浅字配深朱砂底均有明确状态来源。

本轮独立执行 `test_parchment_theme.gd`：56 断言、0 失败、退出码 0；覆盖八个状态图标的尺寸、普通/悬停调制色的线性亮度对比至少 3:1。普通态以 `PAPER` 纸色计算，悬停态以实际 hover StyleBox 底色计算，不能将它扩大为整张纹理每一像素的对比保证。

已直接复看修复后 [`mingqi-port-1600.png`](evidence/gpu-mingqi-r2/mingqi-port-1600.png) 和 [`mingqi-tactics-1600.png`](evidence/gpu-mingqi-r2/mingqi-tactics-1600.png)：数量输入的上箭头呈深墨，当前最小值处的下箭头较淡；战术面板三个 SpinBox 的两向箭头均清楚，未再出现白箭头消失在浅纸面的情况，输入行未被新增图标撑高。此证据关闭原对比度问题；本轮未逐个实际点击 SpinBox，也未把静态图描述为所有交互状态的动态验收。

### 追加问题：1280×720 实验视口挤压导致诊断末行裁切——已关闭

完整逐图验收在 catalog r1 发现：实验控制、纸面间距与统计区占用高度后，架构实验子视口仅约 134px，白色诊断文本末行被子视口裁掉。此项是后续 GPU 逐图检查发现，原复审未将结构检查零 overflow 当作全部文字无遮挡的证明。

窄复审 `game/research/laboratory.gd`：实验区改为垂直 `ScrollContainer` 包含原内容 VBox，禁用水平滚动；`ExperimentView` 保留扩展能力并设最小高度 200px，下方统计/提示可滚动访问。`start_demo()` 将滚动归零；实验视口禁止强制透传滚轮，`_view_input()` 在调用实验镜头 zoom 后 `accept_event()`，避免同一次滚轮输入同时缩放镜头和滚动父容器。未修改实验算法、参数合同或暂停/步进时钟。

独立复跑 `test_laboratory_viewport_layout.gd`：10 断言、0 失败、退出码 0。实际 1280×720 SubViewport 加载架构实验，验证诊断文字在实验视口内、统计可滚动到达；使用 `host.push_input()` 发出真实滚轮事件，确认镜头 zoom 增加且父滚动仍为 0；恢复 1600×900 后视口扩展，暂停 tick 保持 0。已核对 [`laboratory-viewport-layout-fix.json`](evidence/laboratory-viewport-layout-fix.json) 的初始 3 失败、加入滚轮回归后的 1 失败、最终 10 通过，以及既有 Laboratory UI 26 / Architecture 46 断言通过记录。

已直接复看 [`laboratory-parameters-1280.png`](evidence/gpu-catalog-r2/laboratory-parameters-1280.png)：200px 高实验画面内五行白色诊断文本完整，原末行不再裁切；控制区右侧有滚动条，下方统计的后两行需继续滚动，前述真实控件回归已验证其完整可达。已核对 catalog r2 的 [`capture-result.json`](evidence/gpu-catalog-r2/capture-result.json) 与 [`gpu-catalog-r2-process.json`](gpu-catalog-r2-process.json)：8 图、110 检查、0 失败、退出码 0，无引擎错误；当前 `laboratory.gd` 与该 PNG 的 SHA-256 均匹配记录。此处只复看指定小窗图，未重复启动 GPU，也未宣称其它图已由本审查逐张复看。

## 文件选择器验证点——已补足 resolved theme 证据

原审查保留疑问：`import_file_picker` 未显式赋 theme，需确认 Window 的主题继承，而非仅凭这一差异认定漏肤。现核对 [`baseline-visible-test_mingqi_file_dialog.json`](evidence/baseline-visible-test_mingqi_file_dialog.json)：显式 theme 为 false 时，真实窗口已经解析 `StyleBoxTexture`，按钮墨色为 `33281dff`；原两项失败均为英文标题/动作。因此不能将原状态写成“文件窗口漏肤”。

现实现显式绑定共享主题，并在打开窗口后设置“导入航程存档 / 导入 / 取消”。本轮独立执行 `test_mingqi_file_dialog.gd`：10 断言、0 失败、退出码 0；真实菜单动作打开窗口后确认纸纹 panel、纸纹标题框、按钮文字对比、中文标题/动作，且文件模式、访问范围、JSON 过滤器保持原值，打开过程不发送导入或世界命令。已核对既有 Mingqi UI 回归 [`post-picker-test_mingqi_ui.json`](evidence/post-picker-test_mingqi_ui.json)：195 断言、0 失败。

已直接复看 [`mingqi-file-dialog-1280.png`](evidence/gpu-mingqi-r2/mingqi-file-dialog-1280.png)：实际嵌入窗口有纸纹标题、边框与客户区，深色导航图标、文件名与中文标题/动作清楚，窗口在 1280×720 内完整可见。引擎自带的 `Path`、`Favorites`、`Directories & Files` 等标签仍为英文；本次修改与验收限于自定义标题和动作，不宣称文件窗口全部文本已汉化。

## 验证证据与边界

- 已检查对应 JSON 的完成标记、退出码及失败数：游戏 UI 12 套/2271 断言、辅助 UI 最终 10 套/1095 断言、管理/设置/实验室 6 套/591 断言，共 28 套/3957 断言通过。辅助组采用 VoyageFlow r2、完整 QA r3、Inspector r4；未把保留的旧失败报告计入通过。
- 本审查执行的 scoped `git diff --check` 返回 0；没有重复运行全套测试，没有启动新的 GPU 进程，没有提交、推送、重置或删除。
- 已读取 menu r3 与 Mingqi r1 的 GPU 记录。Mingqi r1 为 14 图/174 检查/0 失败；记录显示原用户槽与隔离默认槽前后未变。记录只能证明所列文件及操作，不能扩大为所有用户数据永不受影响的保证。
- 本审查直接查看了 `mingqi-port-1600.png`，用于确认 SpinBox 问题；其他图片的逐张视觉结论由运行验收负责人记录，不能把本审查描述为全部截图的人工复核。
- 修复复审独立复跑三项 headless：共享主题 56、首航纸板缩放 24、Mingqi 文件窗口 10，共 90 断言、0 失败；全部由 `run-check.mjs --headless --script res://tests/<对应测试>.gd` 使用隔离 APPDATA 启动 Godot 4.7.2，退出码均为 0。此处是修复后的窄范围增量验证，不重复累计成完整测试总数。
- 修复复审 scoped `git diff --check` 返回 0；仅修改本报告，未启动 GPU、未修改产品或并发 model-preproduction 工作。
- 已读取 [`gpu-mingqi-r2-process.json`](gpu-mingqi-r2-process.json) 和 [`capture-result.json`](evidence/gpu-mingqi-r2/capture-result.json)：真实 Windows / Vulkan / Intel Arc GPU，16 图、198 检查、0 失败，进程退出 0，无引擎错误；实际 viewport 输入打开 Mingqi 文件窗口。当前共享主题、Mingqi interface 以及上述三张已复看图片的 SHA-256 均与该记录匹配。本审查只直接复看这三张 r2 图片，完整 16 图的视觉结论仍由运行验收负责人记录。

## 本轮不判断的内容

- `assets/production/model-kit` 与 model-preproduction 的既有/并发工作：不属于本次 UI diff。
- 海水、光影、模型、战斗、导航性能和连续动画：本任务要求保留原实现，静态 UI 图不能证明其运行质量。
- 未导出的 Windows 发布包、原生操作系统文件选择器：当前证据是项目实际入口与 Godot 嵌入窗口。
- `architecture_convergence_experiment.gd`、`weather_shadow_experiment.gd` 的世界诊断标签：实施报告明确保留浅字深阴影，避免遮住实验视图。
- `water_probe.gd` 的独立水面诊断文字：未在此次入口清单及改动范围内，不因其浅色世界标签认定纸本 UI 漏接。

两项原 P2、追加实验室裁切及文件选择器验证点已闭环；其余入口的完整 GPU 覆盖仍以运行负责人最终记录为准。
