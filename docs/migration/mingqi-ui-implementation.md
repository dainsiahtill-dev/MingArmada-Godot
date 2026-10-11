# 当前 1650 原生界面

入口 `game/ui/mingqi/mingqi_interface.gd` 继承 `CanvasLayer`。所有界面由原生 Godot `Control`、布局容器、滚动容器、按钮、下拉框、滑条、数值输入与文件选择器构成。`mingqi_chart.gd` 只读绘制实际坐标、三港和四条目录航路。海图点可填入战术/航位草稿，不直接改变航行状态。

来源为只读网页工作树 `9ad6a44daecd4ec36a8172d83ff27493feffe5dd` 的 `MingqiShell.svelte`、`MingqiScene.svelte`、`ConvoyPanel.svelte`、`MingqiPortPanel.svelte`、`MingqiBoardingPanel.svelte`、`TacticalPanel.svelte`。本阶段覆盖当前 1650 五面板，旧版 1661 界面归后续迁移范围。

## 接口

```gdscript
var ui = preload("res://game/ui/mingqi/mingqi_interface.gd").new()
add_child(ui)
ui.command_requested.connect(handle_intent)
ui.view_requested.connect(set_tactical_camera) # bool
ui.apply_snapshot({"campaign": campaign_state, "naval": encounter_snapshot,
    "runtime": runtime_status})
```

`apply_snapshot(packet: Dictionary)` 深拷贝输入。界面不导入 campaign、naval、physics 引擎，不推进时间、改变船员/货物/位置或执行持久化。唯一目录读取为 `game/domain/mingqi/catalog.json` 的静态数据。

- `command_requested(intent: Dictionary)`：唯一指令出口。
- `view_requested(tactical: bool)`：`false` 驾驶视角，`true` 高位海图。
- `captures_keyboard() -> bool`：仅本界面可编辑 `LineEdit/TextEdit`（包括 `SpinBox` 内嵌编辑器）的输入焦点为真。普通按钮、下拉框、滑条和只读文本不会屏蔽持续操船键。
- `open_panel(id)`：`ship/convoy/port/boarding/tactics`。
- `open_menu()/close_menu()`：显示/收起菜单并发出 `menu {value}`。

`campaign` 保持冻结的 camelCase 状态：`captain/calendar/debt/flagshipId/currentPortId/vessels/voyages/ports/contracts/boardings/prizes/works/orders/intelligence/settlements`。兼容显示字段 `portStates`，正式来源仍为 `ports`。`naval` 保持 `ships[].visual.position/velocity/heading` 和真实船体、帆装、炮弹、装填、操船字段。

`runtime` 使用 `generation/noticeRevision/commandSerial/status/error/paused/timeScale/selectedShipId/controllableShipIds/canSave/saveReason/saveStatus/canDepart/departReason/canDock/eligibility/hasCheckpoint/importing/orderStatuses/drafts`。可选字段缺失时采用保守状态。`controllableShipIds` 也可取自 `runtime.policy.controllableShipIds`。

`canDock` 首选 `{portId:{ok:bool,reason:String}}`；也接受每港布尔值并从 `dockReason` 每港取说明。单个布尔 `canDock` 只对匹配 `runtime.portId` 的港口生效。

`eligibility` 值为 `{ok:bool,reason:String}`，一般查找顺序为 `type:id:target`、`type:id`、`type`。参数映射：粮食交易 `buy/sell`；船务 `type:shipId`；接舷及押船员 `type:fromShipId:targetId`；取货 `type:targetId:toShipId`；释放战利船 `resolve-prize:targetId`；救人弃船必须有准确配对的 `resolve-prize:targetId:toShipId`，不能继承无接收船的释放资格；售船 `sell-prize:shipId:crewToShipId`；编入 `incorporate-prize:shipId`。运行时提供实际条件证据；缺失时按钮禁用，显示“等待航况核验”。粮食交易必须同时满足资源报价与真实运行时资格，并显示原生资格拒绝原因。靠港按钮不会把请求显示为安全靠泊完成。

## 功能与意图

| 面板 | 当前功能 | campaign 意图 |
| --- | --- | --- |
| 旗舰 | 真实船体/帆装/船员、操舵、升降帆、帆角、自动调帆、三种弹药、两舷炮与装填 | 使用原生 `controls`，无 campaign 状态写入 |
| 船队与海图 | 全船货舱、船员、吃水、实际航路位置/进度、委托期限、情报、交付与奖励回执 | `accept-convoy/claim-convoy/depart/choose-route` |
| 靠港与贸易 | 三港靠泊条件、逐单位粮价与容量、选船修理、厦门自有船帆装、治伤、释放俘虏、工期与实付回执 | `dock/buy/sell/repair/refit/treat-wounded/release-prisoners` |
| 接舷与俘获 | 供船/敌舰、三据点推进/守住/断缆、士气/参与船/时间、押船员、货物、救人/释放、售船/永久编入、真实人员和处置回执 | `start-boarding/board-action/allocate-prize/take-prize-cargo/resolve-prize/sell-prize/incorporate-prize` |
| 战术 | 多船选择、护航/拦截/保持距离/集火/准备接舷/集结、明确目标和海图点、历史状态与草案 | `assign-order` |

19 种 campaign 意图保持原字段。每次有效 UI 意图增加唯一 `commandId` 和当前 `expectedRevision`；`assign-order` 填写 `order.id/shipIds/intent/issuedAt`，时间取实际 `campaign.simulationSeconds`。

运行时意图为 `controls {shipId,rudder|sailDeployment|sailAngle|autoTrim|ammoType|firePort|fireStarboard}`、`navigate {shipId,point:{x,z}}`、`select-ship {shipId}`、`pause {value}`、`time-scale {value}`、`menu {value}`、`save`、`save-and-menu`、`export-save {kind:current|backup}`、`import-save {json}` 或 `{path}`。菜单只发保存/导入意图，成功与失败来自运行时快照。

## 防误操作与呈现

普通快照通过绑定更新已有控件，保持输入焦点与未提交数值。仅实体结构、权限、状态组或世界代际变化时重建控件。每次构建带代际和挂载令牌，旧回调无法向新世界发指令或改动新草稿。相同快照的同一意图只发送一次；业务、存档和齐射另有 250ms 合并窗口，防同步回执后再次触发双击。

操作面板的显隐状态独立保存；结构重建保持已收起状态，显示中的面板保持当前选择。视口尺寸与 HUD 的 `minimum_size_changed` 合并触发一次延迟布局；原生容器完成文本换行、流式按钮排布后，HUD 自动按最新最小尺寸收缩，无需逐帧轮询或等待下一次快照。

炮击必须来自真实 native 船只，拥有炮数、弹药、装填就绪与操船权限。港口/俘获操作还检查本地资源和服务限制，实际安全资格仍由运行时提供。借用旗舰不能申请帆装，补给点最多单次修理船体20与帆20，补给点不能售船。结算须存在真实装载回执并且全部航次实际抵达或损失。

界面采用深青海色、金边与浅纸文字，保留暂停、当前时间速度、选中弹药、船员分桶、真实工期和禁用原因。左 HUD 使用 430px 宽、24px 标题与14px正文/按钮，按内容高度收拢；空提示不占行。右操作面板独立保持470px宽，收起后隐藏背景。已导入船长与厦门港插画用于旗舰/港口，保持主要数据可读。所有面板可滚动，菜单支持粘贴 JSON 和原生文件选择。

## 直接验证

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_mingqi_ui.gd --quit-after 300
```

2026-10-11，Godot `4.7.2.stable.official.ed1daf0bf`：`MINGQI_UI_TESTS assertions=195 failures=0`，无脚本、编译或资源错误。首次 RED 为界面缺失；随后扩展测试发现并修正未完成航次提前结算门槛、售船估价和同步回执后的快速重复齐射。

测试实例化完整 Control 树，验证五面板、真实姓名/银两、靠泊/存档/炮击禁用与原因、原生齐射意图、快照只读、旧代际回调、焦点和输入草稿保持。全部19种 campaign 意图通过实际按钮或下拉事件，对照 `tests/fixtures/mingqi-reference.json` 中原网页运行得到的成功命令和其前态，检查原字段、当前版本与唯一命令 ID；测试资格仅用于 UI 边界验证，没有假执行 gameplay 或生成回执。

审查修复追加17项回归断言，先取得13项失败，再修复并全绿：有真实价格/库存的旧网页前态在缺少或拒绝原生资格时不能启用买卖；拒绝原因可见；资格满足后才启用。实际原生按钮、下拉框、滑条获得焦点不会冒充文本编辑，可编辑 JSON 和已有数值编辑器仍保护输入。布局在1600×900和1100×900经过容器布局帧，HUD测得430×333px，右操作区不重叠；收起面板没有全高左侧背景。根任务提供的原始 D3D12 `opening.png` 已目视确认遮挡问题；修复后的 GUI 截图仍由根任务重新验证。

实际 GUI 补充发现面板内容已切换但标题保留旧值。追加10项原生 Control 断言，四种非默认面板标题先失败；`open_panel` 现在只更新既有标题和可见性，五面板逐项断言即时正确，标题控件实例保持不变，无重建或输入草稿重置。

第二轮追加800×900和900×900窗口的4项原生布局断言，先复现2项重叠失败。宽度小于960时，操作面板按HUD实际底边加16px间隔定位，而非截断到300px；高度取视口剩余空间并保留底部18px。窄窗口无重叠、面板底边在视口内，1100/1600宽的430×333px HUD、焦点和五面板标题回归继续通过。

运行时资格联接追加10项 Control 断言，使用原网页成功救人命令的真实前态（待接管战利船及有容量的接收船）。缺少配对资格或接收船距离被拒绝时，救人弃船禁用，但基于战利船资格的释放仍可执行；准确配对资格通过时，两项操作可用。释放输出仍为`resolve-prize {choice:release,targetId}`，不携带接收船字段。先复现4项失败，再修复全绿，快照人员与战利船状态不变。

根任务最新 D3D12 首次呈现截图仍出现全高左背景，且收起的右面板会在结构更新后重开。新增7项生命周期断言，先复现5项失败：UI 添加后立即只应用一次原网页初始快照，再自然经过8帧，HUD 高度为2643px，而已稳定的最小高度只有333px。修复后同一路径自动得到430×333px；面板切换、真实 `FileDialog` 弹出后取消及菜单关闭、原网页结构变化后的重建均保持紧凑尺寸，已关闭操作区仍关闭，显示中的战术面板选择和标题仍保留。800/900/1100/1600窗口尺寸回归也改为仅自然经过8帧，不重复应用快照或手动布局。实际 D3D12 重截图由根任务完成。

本任务不运行 GUI、截图或全套测试，不改场景/运行时/领域/项目配置。运行时联接、真实输入航行、GUI 布局和全套验收由根任务负责；本结果不替代这些证据。
