# 第二趟返航命令与导航契约只读审计

2026-10-12。只读产品/QA；仅新增本报告与 `build/port-approach-work/return-command-contract/probe.gd`、`probe.json`。没有全程回放、存档写入、船位/货物/HP/奖励/期限/阈值改动。CodeGraph 返回此项目无索引，按要求改用 RTK 定点读取。

## 证据身份与边界

- 本次实际第二趟：`docs/migration/evidence/opening-story/wet-route-egress/journey-second.json`；实读 SHA256 `92b76d0daa85d64cf0ff5c2cecdd4f80e3accd3feecf8843ddbe34fd58a310e4`。
- 当前 Encounter SHA256 `5a86e578f41846b90ccd21c74f89518c6994441ce9beb2018bcfefc5fe7698e9`，与同行方向探针相同。
- 零 step 标量重建：使用 1410.2（真实结算并发出返航命令）与 2999.8（最终）两个记录，保留其 pose/velocity/yaw/crew/hull/draft 与全部同场船；历史 active order 从真实 commands + stage.runtime.orderStatuses 重建。隔离 SnapshotCore 只读返回记录的 motion；从未调用 physics step、runtime.advance 或 campaign。
- 调用实际公开 `Encounter.navigate`，不通过 `orders={}` 人为解除。8 船次全部接受；motion 逐项严格相等。测试只证明命令/静态安全条件，不能证明完整回程成功。
- 当前代码实际函数为 `_tactical_tick`；未找到名为 `_step_tactics` 或 `native_contract.gd` 的源文件。对应契约实际落在 `navigation_contract.gd`、Runtime、Bridge、Campaign 与 Encounter。

## 结论

1. **Rally 合法，但不是目前具有安全进港/Egress 恢复能力的导航 owner。** QA 的 assign-order 全部通过原生业务 fence；不能将合法命令说成作弊或无效操作。然而 active Rally 明确排除 `_keep_tack_after_replan` 与 `_approach_authorized`，后者进一步排除 `_egress_authorized`。粮船甲一直保持 active Rally，因此在当前 owner 下永远不会进入 Egress；这不是单靠等待会解除的状态。
2. **取消 Rally 是必要的 owner 切换选项，不是末态粮船甲恢复的充分条件。** 真正 `navigate(shipId, Xiamen)` 后，粮船甲/B 的 active order 清除，Egress authorized 从 false 变 true；末态甲仍 `unsafe-endpoint`，`Egress.plan` 仍 `no-safe-egress`。8 个候选节点：3 个因 `wind` 拒绝，5 个因 `swept-depth` 拒绝；后者均在真实当前位置的转向包络就失败。不能放松安全 gate 使其通过。
3. **旗舰停滞不能归因 Rally。** 旗舰始终使用 navigate，无 active order；其有效 route 仍停滞，需要同行调查的选舷/干点偏航/真实 sail force 根因修复。粮船 B 同时有有效 route 与 active Rally，受两类行为影响。
4. **35 米 QA 切换与45米原生中间点弹出没有成为本次末段停滞的已证原因。** QA 已实际推进到第三个返航目的地；未卡在前两 waypoint 的到达判断。45米提前弹出是否在其他近岸折角切掉安全航段是另外的潜在审计项，本次没有因果证明。

## 实际命令与路线

`tools/play-continued-voyage.gd:128-176`：

- 1410.2 实交20粮并 claim250；旗舰 navigate 到 `(-60,250)`；另外3船分别 Rally 到厦门 `(-306.2571,-38.2821)`。
- 1506.0 旗舰 navigate 到 `(131.3682,337.9916)`。
- 1633.8 旗舰 navigate 到 `(-280.5167,235.9541)`，直至2999.8未进入最后厦门 waypoint。
- QA 内部推进条件是距离 `<35.0`；不是45米。
- 返航数组将 supply 的倒序前两点与 outer 倒序前两点拼接。它并非完整倒走两条 route：从 supply 第二点直接跳到 outer 第二点，交由每次 native Planner 验证。合法但产生东向绕行；没有业务要求第二趟回程必须经过该拼接线。
- 零step Planner 验证：1410.2四艘可控船的真实位置均可直接规划厦门，返回单目标点。当前 QA 采用既有 route 点可以保留作回归覆盖；也可以让玩家明确选厦门作为回程目标，但改目标本身不能修复底层选舷错误。

## Owner、订单完成与解除路径

- `Encounter.issue_order:262-279`：验证权限/可操作/目标船/目标湿地，取消旧订单，记录新 active owner。入口只验终点船体足迹，不承诺整个航路能完成。
- `OrderController.decision:23`：Rally完成须距目标 `<25` 且速度 `<1`；`Encounter._tactical_tick:599-606` 每tick继续写入 Rally 目标，仅到达才 completed 并收帆。没有“安全路规划失败一定次数就主动 relinquish”的规则。故失败路段上的 Rally 可无限保持 active。
- `Encounter._keep_tack_after_replan:730-737`：active order一律不保留旧 tack。`_autopilot:661-667` 约30秒缺乏5米进展时重规划，反复创建同段 route 仍可能重置 Rally 航行的 tack。**不是 Rally 每tick都清 tack**；是每次发生重规划时显式不保留。当前无法从记录中的缺失 tack counters 证明此限制是粮船B最终静止的独立充分原因。
- `Encounter._approach_authorized:826-831` 排除 active order；`_egress_authorized:742-743` 依赖它。`tests/test_wet_route_egress.gd:76-90` 已明确覆盖“tactical order撤销已持有Egress且不重开帆”。所以不能简单移除 owner gate 作为修复。
- `Runtime.command:136-143` 已提供 `navigate` 的显式 `shipId`；无需切换旗舰，也无需直接改 orders。`Encounter.navigate:287-295` 原子取消订单、清旧route/恢复owner并设置新目标；单船订单状态变 `blocked/manual-navigation`。`point:null` 对应 `manual-control`，同时清 navigation。
- 没有公开 `cancel-order` runtime command，也不需要新增一个才能完成本次业务。
- arrived voyage不会持续覆盖显式回程目标：`NearFieldBridge._apply:63-68` 只在从非arrived跨到arrived时清旧港口目标，保留明确新目的地。`Campaign.native_policy` 不把历史orders每次重放。正常 reconcile保留已取消的 native状态。
- 若要玩家手操：先 `select-ship`，再 `navigate(shipId,null)`；真实键盘舵/帆动作也经 `SailingSimulation._cancel_navigation:58-59,68-86` 清订单/导航。assisted recovery通过现有 `set_handling_mode/set_held` 操控链；直接 controls的帆舵指令不是注入推力。不要调用私有 core参数或改 pose 来代替驾驶。

## 建议的最小修复与验收顺序

1. 产品先修同行已定位的安全选舷/干点航向降级根因，保留湿地、风禁区、peer与 owner约束。旗舰无订单仍失去有效推进，足够证明仅换QA的Rally并不完整。
2. QA 回程若希望调用已实现的单船非战斗导航恢复，应对每个可控且存活船发送一次 `navigate` 到选择的回程目标，替代将Rally当作通用安全返港模式。已有真实API接受与owner切换证据。保留 cargo/receipt、20粮、250奖励、1200deadline、2400测试上限、dock/export_save gates。
3. 若需求是 Rally 本身支持完整近岸归队，则属于产品能力扩展：需专门定义 Rally下的 recovery owner、取消/抢占、禁火与完成语义，补测试后实现。不能在本审计中把几个 hasActiveOrder gate 全删。
4. 对已陷末态的粮船甲，先让有正常可航路线的船真实移开、再以合法新导航重新评估仅能消除peer约束；本次甲最终拒因是转向扫掠浅水，因此即使同伴离开也没有“必能恢复”证据。不能把这条建议写成已完成救援。更小且现实的修复证明应从原本正常的1410.2返航状态开始，验证不会把甲带到不安全转向位置，再跑原始检查点全程。
5. 完整成功仍须产品/QA冻结后，原始首趟正常checkpoint进入第二趟，实际native航行、20粮按期交付/结算、所有应返船只安全靠厦并导出普通checkpoint。零step探针、短程通过、改用直达目标均不能代替这一验收。

## 可复现探针

```text
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://build/port-approach-work/return-command-contract/probe.gd
```

输出：`RETURN_COMMAND_CONTRACT rows=8 acceptedSeconds=0`；exit0，Godot4.7.2。详细 JSON 包含 API receipt、owner前后、motion等值、Planner结果以及甲的8方向Egress拒因。探针不调用 Storage 或任何 save/export，也不覆写既有 evidence。
