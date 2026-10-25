# Mingqi r2 截图逐张视觉复核

2026-10-25。只读复核 `evidence/gpu-mingqi-r2/` 全部 **16 张原始 PNG**，每一张均通过 `view_image` 直接打开；没有只看缩略图、拼图或凭 JSON 代替看图。本轮没有修改产品、启动 GPU、点击控件或执行新的游戏动作。

同时读取 `capture-result.json`：198 项检查、0 失败、errors 为空，记录的原用户槽前后哈希一致。以上属于运行负责人的捕获记录；本复核只对下面直接看到的图像作结论。

## 结论

本轮可见状态未发现需要再次修改产品的阻塞性视觉问题。六个操作页、航程菜单与实际嵌入 FileDialog 均使用纸本样式；主要墨色文字、朱砂标题、数字与控件边界可辨。先前 SpinBox 白箭头问题在这些实际截图中已改善：贸易、押船人数和战术数字框的墨色箭头清楚可见；最小值处的禁用箭头较淡，仍能辨认位置。

FileDialog 的标题“导入航程存档”、导入/取消按钮与 JSON 过滤器是中文，字体和纸面继承正常。但 Godot 内置的 `Path`、`Favorites`、`Recent`、`Directories & Files`、`File` 标签仍为英文，**不能称为完全中文化的文件选择器**。本轮未把这个已有内置文案范围扩大为样式故障，也未自行修改它。

## 全部 16 张直接打开结果

| 图片 | 直接看到的结果 |
| --- | --- |
| [mingqi-ship-1600.png](evidence/gpu-mingqi-r2/mingqi-ship-1600.png) | 旗舰标题、人物、船体/帆装/船员数值和滑块清楚；滑块红色把手与轨道区分明显。右页不覆盖中央主要船体。 |
| [mingqi-ship-1280.png](evidence/gpu-mingqi-r2/mingqi-ship-1280.png) | 核心状态与三条滑块保持清楚；下部弹药内容进入滚动区下方，属于较矮窗口的内容折叠。关闭入口仍完整。 |
| [mingqi-convoy-1600.png](evidence/gpu-mingqi-r2/mingqi-convoy-1600.png) | 航图标题、厦门/金门/近岸补给点标签与比例尺均可读，地理图框完整；下方委托文字与按钮无横向截断。 |
| [mingqi-convoy-1280.png](evidence/gpu-mingqi-r2/mingqi-convoy-1280.png) | 航图尺寸与港口标签完整，委托说明自然换行；下方领取/离港内容需滚动。小船标记尺寸较小，本图不能单独证明所有敌我配色状态。 |
| [mingqi-port-1600.png](evidence/gpu-mingqi-r2/mingqi-port-1600.png) | 港口图、泊港说明、粮食交易与数量框可读；数量 1 的上箭头墨色清楚，下箭头为淡色禁用状态。底部船务页开始处可见。 |
| [mingqi-port-1280.png](evidence/gpu-mingqi-r2/mingqi-port-1280.png) | 港口与交易信息没有横向裁断；数量框和箭头完整，购买/船务内容处于滚动下方。 |
| [mingqi-boarding-1600.png](evidence/gpu-mingqi-r2/mingqi-boarding-1600.png) | 供船/敌舰下拉箭头明确，接舷条件换行正常；押船人数 12 的上下箭头均可辨，未被粗纸边遮住。 |
| [mingqi-boarding-1280.png](evidence/gpu-mingqi-r2/mingqi-boarding-1280.png) | 上部条件与战利船说明可读；人数输入完整，后续行动在滚动边界下方。 |
| [mingqi-tactics-1600.png](evidence/gpu-mingqi-r2/mingqi-tactics-1600.png) | 复选框、指令/目标下拉、距离与 X/Z 数字框完整，三个 SpinBox 的深色箭头明显；禁用动作采用较淡文字，与可输入数字区分。 |
| [mingqi-tactics-1280.png](evidence/gpu-mingqi-r2/mingqi-tactics-1280.png) | 同一组控件仍完整；下部“实际指令与草案”接近滚动末端，标题仍可读。 |
| [mingqi-story-1600.png](evidence/gpu-mingqi-r2/mingqi-story-1600.png) | 章节、下一步、旧账与工钱卡片及两项选择清楚。内页比外页更深，墨色正文保持可读，段落没有横向截字。 |
| [mingqi-story-1280.png](evidence/gpu-mingqi-r2/mingqi-story-1280.png) | 章节、任务和首个故事卡片正文正常换行；第二选择位于滚动下方，画面底端显示部分后续文字，未据此把滚动裁切误判成丢失内容。 |
| [mingqi-menu-1600.png](evidence/gpu-mingqi-r2/mingqi-menu-1600.png) | 中央航程菜单纸面完整，保存/导出/设置、JSON 文本区、选择文件与收起入口均清楚；输入区空态与禁用验证按钮可区分。 |
| [mingqi-menu-1280.png](evidence/gpu-mingqi-r2/mingqi-menu-1280.png) | 中央菜单在视口内；下部导入操作需滚动。菜单叠在既有 HUD/日志之上，部分底层文字被遮挡属于当前菜单覆盖关系，不能称底层全部无遮挡。 |
| [mingqi-file-dialog-1600.png](evidence/gpu-mingqi-r2/mingqi-file-dialog-1600.png) | 实际嵌入文件窗口完整，中文标题、导入/取消、路径输入、目录/文件图标与 JSON 过滤器可读；文件网格选中项明确。长文件名按网格规则换行/省略。 |
| [mingqi-file-dialog-1280.png](evidence/gpu-mingqi-r2/mingqi-file-dialog-1280.png) | 文件窗口四边及底部按钮都在 1280×720 内；列表重排为更多行，路径字段和文件类型选择完整。内置英文标签仍存在，与大图一致。 |

## HUD 与世界视野的准确范围

图中真实初始 HUD 为 430×470；本轮没有把旧 fixture 的 430×360 当作实际航程尺寸。此前同一 canonical 初始 runtime packet 对比得到旧界面 430×486、当前 430×470，详见 `gameplay-implementation.md` 和 `evidence/live-hud-comparison.json`。

1600×900 的非菜单图保留较宽中央海面和主要船体。1280×720 中，左右纸页之间的海面明显变窄，右页会遮住部分船尾/旗帜；它们仍是边缘操作页，右上“收起”入口可见，没有新增全屏不透明纸层覆盖整个航行世界。本组是操作页打开时的静态画面，不证明所有航行姿态均无遮挡。

## 剩余限制

- 这次直接视觉复核范围就是 16 张图，不能据此认定全部滚动下方内容、所有弹出选项、焦点/悬停状态或所有存档操作都已逐项看过。
- 图像显示滚动边界裁切；实际滚轮与按钮输入证据应引用捕获脚本列明的动作和现有回归，不能由静态图单独推断。
- 文件选择器是 Godot 嵌入窗口，不是 Windows 原生 OS 文件选择器；内置标签仍有英文。目录内容来自测试运行位置，未执行实际用户存档导入。
- 航图只展示当前初始舰队；未在本次图集中覆盖全部敌方、盟方、俘获或战斗状态。小型标记的连续可辨性仍不属于静态图证明范围。
- 本组不验证连续海面/动画、操船手感、完整航程、GPU 性能、发布包或长期运行。原用户槽一致结论仅覆盖捕获报告列出的文件与该次执行。
