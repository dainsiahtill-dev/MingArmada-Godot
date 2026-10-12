# Q2：港口服务命令键类型遗漏

独立 review 指出 `_build_port` 中改装/治伤仍有与 Q1 相同的 Dictionary 新键问题。本轮仅改生产 UI 两行：`intent.slot = ...` → `intent["slot"] = ...`，`intent.quantity = ...` → `intent["quantity"] = ...`。没有修改 codec/domain/runtime，没有 GPU、子 Agent 或 Git 操作。

实际扩展 [test_opening_story_ui_runtime.gd](../../../../tests/test_opening_story_ui_runtime.gd)，保留此前剧情/偿债/战术23项，并通过真实 `Interface -> _send -> Runtime.command -> Campaign` 操作两个合法港口按钮。

## RED 与根因证据

改装使用初始 Runtime 的真实自有继承船。治伤使用 `mingqi-reference.json` 中有3名伤员的 careInitial，通过 `SaveCodec.encode -> Campaign.restore` 合法载入，再配置真实 Runtime；没有手改 Runtime 内部状态、没有伪造 eligibility、没有放宽码校验。

```text
refit actual enabled button:
{type:refit, shipId:mingqi-1650-heritage, slot:sails,
 commandId:ui:mingqi-1650:198088596954:1, expectedRevision:2}
slot key/value = StringName:String
result = invalid-command

treat-wounded actual enabled button:
{type:treat-wounded, shipId:care-heritage, quantity:3,
 commandId:ui:care:282897423851:1, expectedRevision:2}
quantity key/value = StringName:int
result = invalid-command

OPENING_STORY_UI_RUNTIME_TESTS assertions=36 failures=8
```

这8项 RED 同时确认真实按钮启用、协议校验失败、作业未创建、银两未扣，属于本次用户实际路径，非源码正则断言。

## GREEN

修复后 wire 中 slot/quantity 都为 String key，真实结果：

- 改装受理、扣150两，创建 `status=active` / duration120 的 refit 工作。
- 治伤受理、扣12两，创建 `status=active` / duration90 / quantity3 的 treatment 工作。
- 工作没有被虚构为立即完成；原字段和游戏工期保留。

清洁结果：`OPENING_STORY_UI_RUNTIME_TESTS assertions=39 failures=0`；原剧情 UI59/0；原 Mingqi UI195/0。之前23项实际剧情/债务/航路/战术链路保留通过。

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_opening_story_ui_runtime.gd --quit-after 240
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_opening_story_ui.gd --quit-after 120
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_mingqi_ui.gd --quit-after 500
```

## 同文件核查与限定

按函数与变量类型检查同文件全部 dot writes，逐一区分 transmitted Dictionary、新增本地 UI 状态与 Node/Theme 属性。Q1 修过 `_send` envelope、order.id、`_order_payload` point/targetId/range；本轮服务 slot/quantity 是剩余两处 canonical command 新键。修复后对 intent/payload/command/request/order/result 的 dot-write 查询无匹配。

`input.name/placeholder_text/...` 是 TextEdit 的原生属性；其它保留的 dot writes 为 Control/Theme/FileDialog 属性及 `_form.point_x/z` 本地 UI 数值，未作为整个 Dictionary 发往领域。没有做宽泛重构或把合法引擎属性改为字符串键。

审查入口：[Q1生产baseline](../../../../build/opening-story-ui/baseline/mingqi_interface-q1.gd)、[Q1集成测试baseline](../../../../build/opening-story-ui/baseline/test_opening_story_ui_runtime-q1.gd)、[仅Q2增量patch](../../../../build/opening-story-ui/scoped-ui-q2.patch)。累计 [scoped-ui.patch](../../../../build/opening-story-ui/scoped-ui.patch) 也已更新，仅包含本任务 UI 与两个测试。

SHA256（Q2增量patch88行，累计patch735行）：

```text
game/ui/mingqi/mingqi_interface.gd
baa673b5a8bb75994e3234e832341a51c5c34b203a7ef8cfe4bca52e5d5c88e9
tests/test_opening_story_ui_runtime.gd
4a66da91648d59346f33cfc1f155a4dff233ee7b55018a31f77922c5fe114523
build/opening-story-ui/scoped-ui-q2.patch
4a6039d4ecacc7954946533304f1d38729cf5ac71094b9247616bd0b7273db87
build/opening-story-ui/scoped-ui.patch
876f39f0c52da10eb73ad985b1cfa37db6d482f26cfc5b0d15ca39f9a035a5f2
```

正式窗口和旅程仍由 Root 验收；本轮只用 headless 真实 Runtime/Command，没有打开 GPU，也没有声称全部游戏服务/所有状态已经完成验收。
