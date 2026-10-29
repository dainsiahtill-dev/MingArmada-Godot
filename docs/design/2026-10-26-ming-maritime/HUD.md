# 航行 HUD 与设置执行记录

本轮沿用户已授权的青绿设色、靛青深墨、暖纸、旧金、朱砂方向重新编排；共享主题与素材由主任务统一维护。Godot 原生控件、当前 `naval_practice` 正式路由、快照与意图合同继续作为接入点。本项仅为界面排版与控件适配，无新增表现或玩法算法。

## 布局决策与计划

巨大左上滚动板会遮住船与海平线。采用左上简短航行摘要、底部常用指令、按需操船手册；把全部信息塞入顶部横条会在小屏上过密，单纯缩小旧板会压低字号，因此不采用。

- [x] 航行摘要保留船名、模式、航向、航速、船况、风况；底部保留帆面、停船、调帆、暂停、视角、炮击、选弹、航图。
- [x] 手册初始收起，保留原帮助、设置、降旗入口；既有暂停、降旗确认、结果窗口由权威快照控制。
- [x] 设置窄屏改为标签在上、控件在下，保留节点路径、焦点恢复、只发补丁和默认静音。
- [x] 新增真实 UI 回归：1280×720 空间预算、320×480 水平可达、手册展开、原生键盘开关与滑条、快照无副作用；运行相关原有回归。

## 验证记录

修改前红灯：`test_maritime_hud_layout.gd`，25 断言、15 失败。准确复现旧 HUD 常驻长板、帮助常驻、缺少指令分区，以及设置在 320 宽视口实际宽 358 的溢出。原生开关与滑条键盘操作、补丁和焦点恢复的基线通过。

首轮 headless 回归共 8 项、224 断言、0 失败，Godot 4.7.2：

| 回归 | 断言 | 证据 |
| --- | ---: | --- |
| 新 HUD/设置布局与原生键盘控件 | 31 | `evidence/hud-layout-final.json` |
| Naval runtime | 58 | `evidence/hud-naval-regression.json` |
| 正式 naval scene，含炮击、暂停、降旗、M 航图、320 视口 | 16 | 同上 |
| 设置持久化与原补丁合同 | 22 | `evidence/hud-settings-regression.json` |
| 纸本组件与输入边界 | 29 | `evidence/hud-paper-regression.json` |
| 正式 scene 海面点击、右键视角、HUD 阻断 | 16 | `evidence/hud-mouse-regression.json` |
| Cannon readiness、短射程/友船遮挡反馈与 lean presentation | 42 + 10 | `evidence/hud-gunnery-regression.json` |

新增用例通过真实 `Input.parse_input_event` 验证 320 宽布局中音效开关、音量滑条、画质原生菜单（打开并提交 high），以及设置写入失败消息下返回按钮仍在视口内。`git diff --check` 对两个产品文件通过。未运行全仓库测试。

GPU 画面、纹理最终效果、真实入口连续操船由主任务统一验收；本项不启动并行 GPU 进程，不用 headless 布局结果替代视觉验收。

## GPU 集成失败定位：手册与小海图重叠

主任务 `evidence/naval-final` 原生 GPU 首轮保留了 15 截图、184 断言、2 失败。手册中的设置能打开，但降旗点后打开了航图，因而无法看到降旗确认。原失败证据保留，没有覆盖。

根因是本轮手册布局产生了真实层级冲突：1280 宽时手册区域 `(882,18,380,320)`，降旗按钮中心 `(1160,231)`；原 HUD 默认 CanvasLayer 1，小海图在 CanvasLayer 22，区域约 `(1031.6,18,230.4,263.4)`。降旗中心落在小海图的点击区。设置中心 `(984,231)` 位于其左侧，所以原 GPU 的设置可见断言通过。

新增 `test_maritime_manual_input.gd` 使用正式 duel scene 与 `root.push_input` 真实鼠标/键盘执行 M 开图、原生收图、手册、设置、返回、Esc、继续、降旗。修复前 10 断言、2 失败；chart 和 settings 关闭、Esc 和继续均通过，单次点击降旗却得到权威 `pauseReasons=["chart"]`，定位了点击被小海图截获，而非菜单或设置恢复失败。

修复仅将 HUD CanvasLayer 提升到 24，小海图仍为 22、settings 为 50、EntryUI 为 100，`_screen.mouse_filter=IGNORE` 保留。修复后同一真实输入用例 11 断言、0 失败；降旗显示权威确认，原生取消恢复航行。捕获工具的 naval 路径加入每步 pauseReasons、chart/manual/settings 可见性、层级、按钮矩形和 hover 路径诊断，便于追溯。

同时按主任务补充要求，CheckButton 文案由已确认快照显示“已关闭”或“已开启”；仅更新展示，不改变 `_controls`、静音默认或 patch。新旧文案红绿用例保存在 `settings-caption-red.json` / `settings-caption-green.json`，最终布局/原生控件回归 33 断言、0 失败。

修复后重跑 5 项 headless 共 98 断言、0 失败：manual input 11、HUD/settings layout 33、mouse course scene 16、naval practice scene 16、user settings 22。证据为 `manual-input-green.json`、`settings-caption-green.json`、`hud-layer-mouse-regression.json`、`hud-layer-scene-regression.json`、`hud-caption-settings-regression.json`；两个产品文件与 capture 工具 `git diff --check` 通过。

经主任务协调，在 GPU 空闲时独占运行一次正式 MainScene naval 捕获：`evidence/naval-manual-layer-fix/capture-result.json`，15 张原生 GPU 截图、186 断言、0 失败，进程 exit 0，源哈希守卫和原始玩家存档保护均通过。已查看 `naval-surrender-1280.png`：真实“向 VOC 武装商船降旗？”确认与“继续抵抗”按钮出现，没有误开的扩展航图。动作诊断显示正常 chart/settings 关闭后 `pauseReasons=[]`；降旗点击 hover 命中手册的 `surrender`，权威状态为 `pauseReasons=["surrender"]`、`surrenderQuoted=true`、`chartVisible=false`。

这轮 GPU 仅补足 UI 叠层与所列点击链的证据；模拟仍为静态布局捕获而冻结，不构成连续海战、性能或完整游戏验收。
