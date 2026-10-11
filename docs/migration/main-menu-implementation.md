# 原生主菜单接口与实现

Task10 的主菜单局部实现。`game/ui/menu/main_menu.gd` 继承 `Control`，动态构造真实原生控件；不读写存档，不创建业务 Runtime，不直接改变游戏设置，也不播放声音。父级负责路由、存储、音频、模态设置与生命周期。

## 原版合同

来源为只读冻结树 `C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada`，HEAD `9ad6a44` 的 `apps/game-client/src/components/MainMenu.svelte`、`GameEntry.svelte`、`components/adventure/MingqiQASeed.ts` 与 `simulation/GameSettings.ts`。目标仓库是独立路径 `C:/Users/dains/Documents/Git/ming-armada`。

| 原生按钮 ID | 发出意图 | 原版条件 |
| --- | --- | --- |
| `mingqi` | `type:start, mode:mingqi` | 1650 新生涯，始终可选 |
| `mingqi-continue` | `type:start, mode:mingqi-continue` | 始终可选；missing/unreadable 仍通向恢复或导入 |
| `career` | `type:start, mode:career` | 1661 旧版新生涯，始终可选 |
| `continue` | `type:start, mode:continue` | 仅 `hasLegacySave == true` 可选 |
| `duel` | `type:start, mode:duel` | 单舰炮战 |
| `fleet` | `type:start, mode:fleet` | 舰队遭遇 |
| `sail` | `type:start, mode:sail` | 自由试航 |
| `ships` | `type:ships` | 检阅船只 |
| `qa` | `type:start, mode:qa` | `dev == true` 或 `qa == true` |
| `practice` | `type:practice` | 同开发/QA 门控；四种玩法由父级进入验收器 |
| `quit` | `type:quit` | 桌面原生退出请求，父级决定退出时机 |
| `Settings` | `settings_requested` 信号 | 空闲时打开共享设置面板 |

按钮存在表示保留入口；其对应功能是否已具备原生运行能力，由父级判断并返回真实结果。菜单不把尚未实现的入口伪装成已进入游戏。

启动时姓名严格遵从原版：JavaScript 空白集合 trim，连续空白折叠为一个 ASCII 空格，截取前 **20 个 UTF16 单元**，空姓名默认 `沈沧海`。使用现有 `game/domain/legacy/utf16_text.gd` 的可逆编码，保留被截开的代理项、NUL 与标记字符。`LineEdit.max_length` 不承担此合同，因为 Godot 按 Unicode 字符计数。输入变化同样按 20 个原版 UTF16 单元裁剪；确认快照可保留较长历史姓名，到实际启动时才规范化。只打开船册、设置或验收器不规范化姓名。

QA 种子仅对新的 `mingqi` 航程生效，初始 `1661`。原版 trim 后留空不携带 `qaSeed`；仅 ASCII 十进制整数，含前导零，范围 `0..4294967295`。其他模式不验证此字段。菜单展示原版的校验错误。

## 父级调用

```gdscript
var Menu = preload("res://game/ui/menu/main_menu.gd")
var menu = Menu.new()
add_child(menu) # _ready 调用幂等 build()
menu.intent_requested.connect(_route_menu_intent)
menu.settings_requested.connect(_open_shared_settings)
menu.apply_view_model({
    "settings": confirmed_settings_snapshot,
    "hasLegacySave": has_legacy_slot,
    "mingqiSlot": "missing", # present | unreadable | missing
    "dev": development_enabled,
    "qa": qa_enabled,
}, generation)
```

`apply_view_model(model: Dictionary, generation: int) -> bool` 深拷贝输入，接受当前或更高 generation，拒绝更旧 generation。未改动的姓名草稿从确认设置 `captainName` 水合；同 generation 的刷新保留用户已编辑草稿。更高 generation 清除旧操作锁并重新水合姓名。父级应在新菜单会话提供递增 generation，避免重用会话编号。默认 `hasLegacySave:false`，`mingqiSlot:missing`，开发与 QA 门控关闭。门控来自父级可信环境值，不能由存档解锁。

`intent_requested(intent: Dictionary)` 是脱离内部状态的请求副本。每次可执行请求含单调递增 `nonce`、当前 `generation`，启动请求含规范化的可逆编码 `name` 和原版 `mode`；QA 种子仅在有效、非空的1650新航程请求中携带。`ships/practice/quit` 保留当前草稿姓名，但父级不应因此写入姓名。菜单在发出请求**之前**锁住启动按钮和输入，以拦截双击与同步重入。

父级在收到启动请求后，负责确认姓名持久化及对应 Runtime 的真实加载。不得从 `Text.display_text(name)` 的展示字符串反推原始姓名；业务/存储传递请求原值，只有玩家显示使用展示函数。

```gdscript
menu.apply_status({"phase":"loading", "progress":35,
    "message":"正在准备港口。"}, request.generation, request.nonce)
# 成功：父级切换并卸载菜单；保留菜单时必须明确确认。
menu.apply_status({"phase":"complete"}, request.generation, request.nonce)
menu.acknowledge(request.generation, request.nonce)
# 失败：显示玩家能理解的原因，保留重试/返回。
menu.apply_status({"phase":"error", "message":"港口资源暂不可用。"},
    request.generation, request.nonce)
```

`apply_status(status: Dictionary, generation: int, nonce: int) -> bool` 仅接受精确匹配的活动 token。`progress` 钳制为 `0..100`。状态顺序为 `menu -> pending -> loading -> error|complete`；pending 可直接到 error 或 complete。error 和 complete 拒绝迟到的进度或重复终结；error 必须重试或返回。complete 保持锁定，直到精确 token 的 `acknowledge(generation, nonce)` 成功，或父级卸载菜单。已确认请求不再接受回调。

重试发出 `type:retry`，保留原 `name`、可选 `mode/qaSeed`，新增 `entryType` 保存原 `start/ships/practice/quit` 类型，使用同 generation 和新 nonce。父级按该目标再次尝试，不应强制把所有重试转成试航；原请求后来的回调因 nonce 不符被拒绝。

返回在菜单本地先建立下一代隔离，再发出：

```gdscript
{"type":"back", "generation":old_generation,
 "nextGeneration":old_generation+1,
 "nonce":new_nonce, "cancelledNonce":abandoned_nonce}
```

父级用 `generation`、`cancelledNonce` 校验被取消操作，用 `nextGeneration` 进入新的菜单会话；随后用新 generation 回传确认模型。这里的 back 请求仍使用旧 owner generation，便于父级消费，而菜单已经拒绝旧回调。后台资源释放、暂停/输入独占、场景退出及异步取消必须由父级完成。

`settings_requested` 仅在 menu 空闲阶段触发，pending/loading/error/complete 均阻止。父级打开 `game/ui/settings/settings_panel.gd`，处理其设置意图并成功落盘后重传确认快照；菜单不接受未确认设置草稿。设置面板关闭后，父级恢复先前焦点。音频仍由共享设置及音频控制器驱动，不在菜单添加另一套状态。

## 控件与布局

使用已复制原港口画作 `assets/art/ports/xiamen-harbor-v1.png`，暖纸色菜单、黄铜线框、深青墨色及宋体标题。信息层级为时代、标题、介绍、姓名、加载/错误状态、两代航程、战斗/试航/船册、开发入口、设置/退出。玩家界面不展示迁移内部进度或技术门槛。

完整菜单置于受窗口边界约束的垂直 `ScrollContainer`，横向滚动关闭，`follow_focus:true`；姓名输入、QA 种子、所有按钮为原生可聚焦 Control，Enter 启动1650新航程。窄窗320×480有真实内容溢出与可用纵向滚动，加载/错误状态在入口上方，发出请求时回到顶部。缩小窗口不压低正文到不可读字号。

## 局部验证

先写原生行为测试，直接 headless 运行得到预期 RED：`FAIL: native main menu exists and emits detached source entry intents`、`MAIN_MENU_TESTS assertions=1 failures=1`、exit 1。

完成实现后用同一直接 Godot 命令验证，无共享验证文件写入：

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_main_menu.gd
```

Godot `4.7.2.stable.official.ed1daf0bf` 输出 `MAIN_MENU_TESTS assertions=60 failures=0`，exit 0，无 Godot 错误或警告。覆盖原生控件发出源模式、两代继续门控、开发入口隐藏及绕过拒绝、QA decimal/uint32/blank、真实姓名输入 UTF16 裁剪、代理项/标记/NUL、水合/草稿隔离、双击、nonce/generation、重试目标、返回取消、终结状态、320×480滚动及延迟焦点取消。

### 首屏焦点与滚动回归

主线程真实1600×900 D3D12截图 `docs/migration/evidence/menu/main-menu-wide.png` 揭示初始标题、姓名被滚走。针对实际 `add_child -> apply_view_model -> viewport layout -> focus` 顺序增加八个真实 process frame 的首屏断言，修复前得到 `MAIN_MENU_TESTS assertions=52 failures=1`，`initial wide menu keeps title/name visible after layout/focus frames; scroll=115`。

诊断定位到原 `Captain.call_deferred("grab_focus")` 在容器两阶段排版完成前触发：瞬间姓名控件全局 y=1610，而滚动视口 y=50、高800，`follow_focus` 为临时布局滚至底端；随后内容排版为915高，姓名回到正常位置，却保留115滚动偏移。开发入口可见时内容更长，主线程截图因此连首个启动按钮也裁掉。

修复只将首次取得焦点延后到两次 process frame，让文本宽度与换行最小高度稳定；保留 `follow_focus`，没有关闭键盘自动滚动或持续强制回顶。新增断言覆盖宽屏首屏顶部、初始姓名焦点、聚焦末端控件后真实滚动、发出加载请求后的回顶以及新建320×480菜单首屏与焦点。最新56项全部通过；修复后的GPU截图与人工视觉确认仍由主线程执行。

### 延迟焦点生命周期回归

独立复审发现：父级在两帧等待期间将仍存活菜单从 SceneTree 移除，原第二次 `get_tree().process_frame` 在成员检查前访问 null。新增真实 detach/free/会话切换/重新加入树用例，修复前复现 `ERROR: Parameter "data.tree" is null.`、`Invalid access to property or key 'process_frame' on a base object of type 'null instance'`，并报告两项旧焦点回调失效断言失败。

延迟任务现在在 yielding 前捕获 SceneTree；每帧恢复后检查树成员身份、取消序号与 menu 阶段，再触碰控件。离开树、后续 generation 更新或返回动作推进取消序号；第二帧额外校验 generation。初次确认模型的水合不取消合法首次焦点，而重新进入树不会恢复已取消任务。实际 detach/free、等待期间新会话与重新加入树用例及前述滚动回归均通过，最新60项全部GREEN，日志无引擎诊断。父级模态面板与后续会话的主动焦点恢复仍由父级管理。

本报告仅证明菜单局部行为。未运行全套测试、完整路由启动、GPU/截图、浏览器或发布验收；这些由主线程在接入全部入口后执行。CodeGraph 在本次会话已确认目标及冻结源均 UNINDEXED，遵照主线程要求使用 RTK 源码回退，无索引操作。
