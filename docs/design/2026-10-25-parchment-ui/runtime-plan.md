# 羊皮纸 UI：运行环境与验证计划

记录日期：2026-10-25。此次为只读运行环境勘查；唯一新增文件为本文。未启动 Godot 编辑器、游戏、GPU 捕获或新服务，未运行游戏测试，未终止进程，未修改配置。以下“计划命令”尚未执行，不能用来声明界面通过。

## 当前实测环境

| 项目 | 2026-10-25 实测结果 |
| --- | --- |
| 项目目录 | `C:/Users/dains/Documents/Git/ming-armada` |
| Godot 可执行文件 | `C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe` |
| `--version` | `4.7.2.stable.official.ed1daf0bf`，退出码 0 |
| Node | `v24.18.0`；`C:/Program Files/nodejs/node.exe` |
| Windows 显卡枚举 | `Intel(R) Arc(TM) 130T GPU (16GB)`，驱动 `32.0.101.8132`，Status OK；另有 OrayIddDriver 虚拟显示设备 |
| Godot 进程快照 | 本次 `Get-Process -Name '*Godot*'` 未返回进程；仅代表该查询时刻 |
| 主入口 | `res://game/scenes/main/main_scene.tscn` |
| 项目显示配置 | 1600×900；`canvas_items`；aspect `expand` |
| 项目渲染／物理配置 | `Forward Plus`、`Jolt Physics`；README 以 Windows Vulkan 为当前验收驱动 |
| 当前 Godot 测试文件 | 286 个 `test_*.gd`；不是 286 个已通过测试 |

Godot `--help` 已确认 Windows 支持 Vulkan、D3D12、OpenGL；支持 `--rendering-method`、`--rendering-driver`、`--log-file`、`--resolution`。显卡枚举和命令行帮助不能证明 Vulkan 当前成功初始化，需由后续真实 GPU 日志确认。

仓库根 `AGENTS.md` 要求 RTK、保护未提交工作、区分源码检查与实际运行、不得用静态截图宣称动态或性能验证。项目内定向文件枚举仅发现根 `AGENTS.md`。CodeGraph 无索引由主线程先行确认；本次按该状态使用 RTK 定向文件检查，没有独立 CodeGraph 审查结论。

## 背景资产：实际字节检查

通过已有 `tools/inspect-story-image.mjs` 检查 PNG 签名、块边界、CRC、IDAT 解压长度和扫描行过滤值；两图 `rasterValidated=true`。

| 文件 | 像素 | 字节数 | SHA256 |
| --- | --- | ---: | --- |
| `ming-armada-ui-background-parchment.png` | 1672×941 | 2,961,560 | `2772c1fbc69ee73cfdac75115e55e89fcafd421d306ea05c37c7fd9537733bd2` |
| `ming-armada-ui-background-parchment-draft-v1.png` | 1672×941 | 3,091,053 | `94d83c36db058a5b40f2c4b5f90b15cd603f0578671598015a51f6eeb77ab26c` |

这只证明文件完整性、尺寸及两份资产不同，不证明正式游戏已引用它们或排版合格。正式背景接入后需同时检查 1600×900、1280×720 和窄屏裁切。

## 已有验证入口及限制

| 工具 | 可复用能力 | 本次使用注意 |
| --- | --- | --- |
| `tools/verify-godot.mjs` | 真实 headless Godot；发现测试；检查退出码、唯一完成标记、脚本／加载错误；支持 `--filter` 和 `--output` | 默认输出会写旧 `docs/migration/evidence/verification.json`，本次必须明确新路径。默认每套 60 秒超时，超时时会终止自己启动的子进程树；本次勘查未运行它。 |
| `tools/capture-main-menu.gd` | 真实原生菜单 Controls；1600×900 和 320×480；GPU PNG／元数据；自动退出 | 输出写死为历史 `docs/migration/evidence/menu`；不覆盖完整 Router。不可原样重拍覆盖历史。 |
| `tools/capture-native-entries.gd` | 真正主 PackedScene、菜单点击、设置、损坏槽恢复、两生涯、海战、船图鉴、小游戏；PID 隔离槽 | 输出写死为历史 `docs/migration/evidence/entries`；包含较多 3D 场景，超出最小 UI 验证范围。 |
| `tools/capture-opening-clarity.gd` | 继承真实开场鼠标操作、Campaign 事务；主菜单进入、故事、接单、工资、领航、还债、离港、航行及返回；1600×900／1280×720 | 接受显式新 `--output`；拒绝已有目录及 headless；原槽前后哈希比对；PID 隔离槽；自行清理本次新槽；自动退出。现成最合适的正式游戏 UI 捕获。 |
| `tools/capture-opening-return.gd`、`capture-return-clarity.gd` | 从已有、不可变的真实航程结果恢复，经实际 Continue 路由展示回港和损伤 | 需要有效航程输入，UI 主题修改无须重新展开长航程。 |
| `--start-game=mingqi --game-capture=<绝对PNG路径>` | 正式菜单按钮／Router 启动，真实活动 viewport、启动回执、snapshot、GPU、PNG SHA | 支持 `mingqi/career/sail/duel/fleet`。普通启动默认使用真实用户存档／设置，必须先做子进程 profile 隔离；截图后游戏不会自动退出。无需为本次 UI 检查直接冒用用户 profile。 |
| `tools/record-entry-captures.mjs`、`record-native-qa-captures.mjs` | 老截图完整性／元数据整理 | 固定历史目录；后者还固定旧 53 套测试数量。不能原样当作本轮 286 套仓库的通用验收器。 |
| `tools/verify-game-ui-prototype.mjs`、`verify-game-ui-detail-contracts.mjs` | 浏览器 HTML 原型检查 | 明确不证明 Godot 运行、GPU、原生持久化或玩法；不能代替本次正式 UI 检查。 |

## 聚焦回归计划

优先现有测试，不为颜色、字体、纹理等低风险可逆样式重复制造实现镜像测试。主题如改变尺寸或输入行为，补实际失败夹具。

| 改动触及面 | 建议现有测试 |
| --- | --- |
| 菜单、标题、按钮、滚动与聚焦 | `test_main_menu.gd`、`test_menu_consolidation.gd` |
| 设置、恢复、进入／返回 | `test_user_settings.gd`、`test_game_router.gd`、`test_release_game_entry.gd` |
| 明旗 HUD、右侧面板、故事与接单 | `test_mingqi_ui.gd`、`test_opening_story_ui.gd`、`test_opening_story_ui_runtime.gd`、`test_voyage_ui_clarity.gd` |
| 共用主题影响旧生涯／战斗／实验室 | `test_legacy_ui.gd`、`test_encounter_ui.gd`、`test_laboratory_ui.gd` |
| 海图主题、图例或覆盖关系被改动 | `test_mingqi_chart.gd`、`test_nautical_chart.gd`、`test_sea_chart_overlay.gd` |

已有布局约束包括：主菜单 320×480 真正滚动且初始标题／聚焦合理；明旗 HUD 宽≤430、高≤390，宽屏右侧操作面板分离，800／900 宽时下置且不越界；旧生涯 1600／1100／600／400 宽布局无重叠；海图不盖住已有 HUD。样式接入应保持这些约束。

下面命令在仓库根执行。每次 `--output` 使用独立文件；后续重跑增加 `-r2` 等后缀，保留失败证据。

```powershell
rtk proxy node tools/verify-godot.mjs --self-test
rtk proxy node tools/verify-godot.mjs --filter test_main_menu.gd --output docs/design/2026-10-25-parchment-ui/evidence/main-menu-r1.json
rtk proxy node tools/verify-godot.mjs --filter test_menu_consolidation.gd --output docs/design/2026-10-25-parchment-ui/evidence/menu-consolidation-r1.json
rtk proxy node tools/verify-godot.mjs --filter test_user_settings.gd --output docs/design/2026-10-25-parchment-ui/evidence/settings-r1.json
rtk proxy node tools/verify-godot.mjs --filter test_game_router.gd --output docs/design/2026-10-25-parchment-ui/evidence/router-r1.json
rtk proxy node tools/verify-godot.mjs --filter test_mingqi_ui.gd --output docs/design/2026-10-25-parchment-ui/evidence/mingqi-ui-r1.json
rtk proxy node tools/verify-godot.mjs --filter test_opening_story_ui --output docs/design/2026-10-25-parchment-ui/evidence/opening-ui-r1.json
rtk proxy node tools/verify-godot.mjs --filter test_voyage_ui_clarity.gd --output docs/design/2026-10-25-parchment-ui/evidence/voyage-clarity-r1.json
```

按实际改动面追加表内其余测试；不无故运行全部 286 套算法／物理／航程检查。每份报告需确认 `passedAll`、完成标记、错误／警告和实际命令，不能仅看 Godot 退出 0。

## 正式 GPU 检查计划

1. 为主菜单／设置／恢复提供本任务专属输出的轻量捕获适配，复用现有实际 Controls 和 Router，使用 PID 独立存档／设置。避免改写历史 `menu`、`entries`。主界面 1600×900、1280×720、320×480；设置检验文字对比、焦点、滚动、关闭；恢复页检验多行 JSON 与错误文字。适配尚未编写。
2. 原有 `capture-opening-clarity.gd` 可直接使用新证据目录；按当前项目 Vulkan／Forward+ 执行，保持窗口可见。一次只运行一个 GPU 验证进程。示例路径本次未创建，实际执行前再次检查。
3. 逐张打开新 PNG 做视觉复核：纸纹不过度抢字、文字足够深、输入与禁用状态清楚、按钮边界完整、中文无缺字、长文本无裁断、窄屏滚动可达、HUD 保留海面视野。实际鼠标及 Esc 流程继续采用现有 harness。
4. PNG／JSON／日志必须来自同一次当前源码；记录背景与主题源哈希、引擎／GPU／渲染器、实际逻辑视口、测试完成标记和原用户槽未变结果。

在本文目录已存在、输出目录尚不存在时，现成开场捕获计划命令为：

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --path C:/Users/dains/Documents/Git/ming-armada --rendering-method forward_plus --rendering-driver vulkan --log-file C:/Users/dains/Documents/Git/ming-armada/docs/design/2026-10-25-parchment-ui/opening-gpu-r1.log --script res://tools/capture-opening-clarity.gd -- --output=res://docs/migration/evidence/opening-story/parchment-ui-2026-10-25-r1
```

预期证据：新目录内每张 PNG 及 JSON、`run-result.json`；指定日志内 `OPENING_STORY_GPU_CAPTURE_COMPLETE ... failures=0`。需检查真实 GPU 名称、原用户槽前后哈希、所有源哈希稳定。当前 harness 对自有隔离槽做清理，不删除玩家槽。若窗口失焦影响原生点击，先保留失败日志／截图，再使用现有焦点处理方法修复测试操作；不可绕过实际合同制造成功。

捕获是多状态原生 UI 证据，仍不是连续动态或 FPS 证明。若新实现引入动画／新的表现算法，按根 AGENTS 研究流程另补固定状态、真实 GPU 连续帧及必要成本；本计划未提出或验收此类算法。无须为纯纸纹、主题和排版改动宣称完整玩法或性能提升。

## 勘查完成边界

已确认：Godot 文件／版本、Node、OS 显卡枚举、项目入口／显示配置、两张背景 PNG 的真实字节完整性和 SHA、现有测试与安全捕获路径。

尚未确认：当前资源导入和脚本编译、任何 UI 测试通过、新主题在 Godot 中实际显示、当前 Vulkan 初始化、GPU 截图质量、连续动画、声音、完整航程、性能或 Windows 导出包。没有对这些项目作完成声明。
