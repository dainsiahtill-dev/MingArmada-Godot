# 开场剧情 UI 交付

完成航海日志、HUD 当前目标、真实选择意图与偿债表单。仅修改 `game/ui/mingqi/mingqi_interface.gd`，新增 `tests/test_opening_story_ui.gd`；没有修改 domain、runtime、Main、海岛、海面、粒子或图形资源。没有 Git 操作、子 Agent 或 GPU 窗口。CodeGraph 本会话无工程索引，使用 RTK 查询源码。

## 交付文件与审查入口

- [完整 UI 实现](../../../../game/ui/mingqi/mingqi_interface.gd)
- [定向 UI 测试](../../../../tests/test_opening_story_ui.gd)
- [编辑前 baseline](../../../../build/opening-story-ui/baseline/mingqi_interface.gd)
- [本任务 scoped diff](../../../../build/opening-story-ui/scoped-ui.patch)：只包含本任务 UI 和新测试，未使用整个 dirty branch 的 Git diff。

交付 SHA256：

```text
baseline/mingqi_interface.gd
169f500b45820ada29e614ac5aa7983380ee345fe1c62c566924e8f789513281
game/ui/mingqi/mingqi_interface.gd
baa673b5a8bb75994e3234e832341a51c5c34b203a7ef8cfe4bca52e5d5c88e9
tests/test_opening_story_ui.gd
b581f660d922a2dcd084ca6f5f455a58122ca16572833b556fe30165cd3ebbf7
build/opening-story-ui/scoped-ui.patch
876f39f0c52da10eb73ad985b1cfa37db6d482f26cfc5b0d15ca39f9a035a5f2
```

## 已实现行为

`nav_story` 与 `panel_story` 标为“航海日志”，复用原生 Mingqi Theme、operation ScrollContainer 和 `_button` / `_send` 生命周期。日志仅消费 `packet.story`：章名、前情、下一步、NPC 姓名/职责与完整对白、投影给出的代价/后果、完成后的决定与回复、人物立场、最近六条非空记录。未硬编码 choice 业务效果，没有虚构 merchantCredit 价格折扣或完成战绩。承家号/明旗号的所有权区别来自 chapter.summary。

可用场景显示全部原对白与每个 choice 的 label、silverCost、consequence；锁定场景只显示首段 prerequisite，不展示可点击 choice 或后续未来对白；完成场景显示 selectedChoiceId 对应 label 与 reply，不能再选。Domain worker 应使 locked.text[0] 是实际前提提示，该约定已通知 Root。

HUD 的 `current_objective` 与 `objective_open` 只显示一个当前目标，并打开 objective.panel 指定的原有 panel；不发送接任务/完成任务意图。无 story 的旧 packet 有日志 fallback，目标行隐藏，旧五个操作面板保持可用。

选择按钮稳定命名 `story_choice_<sceneId>_<choiceId>`，发送：

```json
{"type":"story-choice","sceneId":"old-ledger","choiceId":"settle-wages"}
```

新增业务类型通过原 `_send` 取得 commandId 与 expectedRevision；双击、旧 generation 和旧 mount 都按原机制拒绝。`choice.enabled`、scene.status、实际银两与 `runtime.eligibility.story[sceneId].ok` 必须同时成立。原生拒绝原因可见，UI 不自行推断“低速附近就等于安全锚泊”。Root 提供真实 isAnchored/港口安全门禁。

Root 指定偿债 SpinBox 稳定 ID 为 **`debt_quantity`**，按钮为 **`repay_debt`**。发送：

```json
{"type":"repay-debt","quantity":100}
```

金额为正整数，范围 `1..min(principal, captain.silver)`；分数、零、负数、文字、超过当前资金的 draft 都拒绝。`story.debt.canRepay` 与 `runtime.eligibility.repayDebt.ok` 双门禁，拒绝原因可见。已还清时仅显示事实“债务已还清”，输入/pay 禁用。Enabled predicate 与展示原因独立：**false 门禁即使 reason 是空字符串也不能放行**。

story rebuild signature 包含 chapter/scene/choice IDs、status、selectedChoiceId、choice gate/cost/reason、native scene gate 与关系 IDs；不含 simTime 或连续变化的历史时钟。正文、代价、银两与人物立场通过原 watcher 刷新。普通 tick 保留 Control、draft 与焦点；同 generation 的必要结构 remount 捕获并恢复编辑器 draft/caret。SpinBox 自身的 deferred 文本同步已处理，generation 改变不恢复旧航程的草稿。

原 `_local_button` 改为 WeakRef 捕获 Button；过期 callback 在控件被释放后仍能按 token 拒绝，不产生“Lambda capture was freed”错误。原输入、菜单、关闭面板和操船键盘捕获机制保持有效。

## RED/GREEN 与实际结果

首次定向测试 RED：缺少 `nav_story`，1 assertion / 1 failure；非 parse 错误。实现后曾捕获 SpinBox remount 把 draft 改回旧 value 的行为，已修复并保持断言。额外 RED 还证明空拒绝 reason 不应启用偿债：56 assertions / 2 failures；改成独立布尔门禁后 GREEN。

最终相关 headless 验证 **1,707 assertions / 0 failures**：

| 测试 | 断言 | 输出 |
| --- | ---: | --- |
| test_opening_story_ui.gd | 56 | `OPENING_STORY_UI_TESTS assertions=56 failures=0` |
| test_mingqi_ui.gd | 195 | `MINGQI_UI_TESTS assertions=195 failures=0` |
| test_encounter_ui.gd | 1,085 | `ENCOUNTER_UI_TESTS assertions=1085 failures=0` |
| test_legacy_ui.gd | 371 | `LEGACY_UI_TESTS assertions=371 failures=0` |

定向测试通过真实 Control tree/pressed/text_changed 操作验证：两个不同 scene 的真实 choice IDs；revision/id envelope；未变更 source/copy campaign；投影与 native affordability/eligibility；已还清；可见 objective link；loading/error/disposed；stale remount/generation callback；完成 outcome；tick 和 remount 草稿焦点；1280×720 与1600×900 长对白垂直滚动；旧 packet fallback。

Mingqi 原测试也确认无 story 时 HUD 在1600和1100宽均为430×333，原交易/接舷/战术/菜单与键盘 capture 行为保留。滚动测试在 headless 的真实容器布局执行，不是文本源码正则检查。

并行 domain 开发期间，第一轮 Legacy 输出虽然写371/0，但同时出现 SaveCodec `_opening_history` / `_story_receipt` 缺失的 compile error，**该轮不作为清洁通过**。Domain helpers 完成后重跑 Legacy，输出只剩正常 source 摘要和371/0，已通知 Root。

所有命令从 `C:/Users/dains/Documents/Git/ming-armada` 执行：

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_opening_story_ui.gd --quit-after 120
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_mingqi_ui.gd --quit-after 500
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_encounter_ui.gd --quit-after 500
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_legacy_ui.gd --quit-after 600
```

`--quit-after` 是异常挂起保护，验收依赖明确的最终断言结果和**无 script/compile error**，没有凭 exit0 单独判断成功。

## 交接边界

这是 UI 投影与意图边界的完整交付；域规则、存档和 runtime 由其他所有者实现。未运行 Main 的实际 GPU 画面或全工程共享验证入口，以免覆盖 Root 验收/并发工作。Root 的正式游戏流程与9张 native captures 负责最终集成和视觉验收；本任务不声称该部分已完成。源码与 scoped diff 已 source-ready，可独立 review。

## 正式窗口暴露的命令边界缺陷及修复

Root 的第一轮9张正式窗口截图发现按钮看似可点击，但工钱、原委托、偿债均遭 `invalid-command` 拒绝。原1707项检查中 UI 测试只核对字段/Control，不足以证明真实 `Runtime.command` 接受；不能用那一轮来宣称正式操作闭环完成。

Root 的最小实际 probe 为10/7；本任务合并这一发现，扩展 [test_opening_story_ui_runtime.gd](../../../../tests/test_opening_story_ui_runtime.gd) 到真实 `Interface -> _send -> Runtime.command -> Campaign` 路径，RED 为19/15。实际拒绝 payload：

```json
{"type":"story-choice","sceneId":"old-ledger","choiceId":"settle-wages","commandId":"ui:mingqi-1650:37731960312:1","expectedRevision":2}
```

JSON 表面字段正确，但类型探针为：

```text
type               String:String
sceneId            String:String
choiceId           String:String
commandId          StringName:String
expectedRevision   StringName:int
result             invalid-command
```

根因是原 `_send` 的 Dictionary **dot assignment** 给新 key 创建 `StringName`。`SaveCodec.command_data` 明确只接受 `String` key，故在 revision/业务规则执行前拒绝。修复只在 UI 发送端采用 `intent["commandId"]` / `intent["expectedRevision"]` 与 `intent["order"]["id"]`，**没有放宽 codec 或 domain**。

同根因还存在于旧 `_order_payload` 的 point/targetId/range 新 key，已同样改用字符串索引。实际 UI rally 提交也先 RED（23/2），再通过，未仅凭 envelope 类型推断所有 nested payload 已修好。

最新清洁验证：真实 UI-runtime集成 **23/0**、剧情 UI **59/0**、原 Mingqi UI **195/0**。真实集成确认：工钱使银650→570、拥护50→60；原委托真实 active；pilot 使真实 voyage 改走 `xiamen-kinmen-shallow`；偿债使 principal/silver 各减少100；旧战术 rally 提交成功。所有这些实际 emitted commands 通过 `SaveCodec.command_data`，不是 spy 断言。

展示修正有独立负例：label 已含80两时不再添加第二个同一行的80两；`拥护+-4` 显示为 `拥护-4`，原 `packet.story` 字符串保持不变。只修符号/重复，保留应急选择的真实负面后果。

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_opening_story_ui_runtime.gd --quit-after 180
```

输出：`OPENING_STORY_UI_RUNTIME_TESTS assertions=23 failures=0`；wire types 中 commandId/expectedRevision 都已是 String key，runtime 返回实际 story receipt。Root负责重新运行9张正式窗口验收，本任务没有开启 GPU，也不声称该新轮已完成。scoped diff 已更新，包含 UI、剧情 UI 测试及合并 Root 发现的实际 runtime 集成测试。

独立 review 后再补 Q2：港口服务的 slot/quantity 仍有同根因，已只改 UI 两行，并以合法真实 refit/treat-wounded 按钮做 RED36/8→GREEN39/0。最新同文件 dot-key 审查、2种服务的真实费用/active作业、88行增量patch与哈希见 [task-ui-q2-report.md](task-ui-q2-report.md)。本报告上面的23/0是Q1阶段历史结果，最新真实集成为39/0；剧情UI59/0、Mingqi195/0。没有放宽codec/domain。
