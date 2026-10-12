# 实际第二趟 aftermath：返航命令与操纵生命周期审计

2026-10-12，只读独立审计。仅新增 `build/second-aftermath-work/fleet-return-audit/*` 与本报告；未改产品、测试、QA、存档、既有 evidence、Git 状态。CodeGraph本会话已确认项目无索引，使用RTK定点读取。未重跑完整航程。

## 证据身份及实际结论

- 输入：`docs/migration/evidence/opening-story/second-voyage-aftermath/journey-second.json`。
- 实读SHA256：`191170ccf22ab26dfd00521c3ea2ff6933e30c2c24b98d575e7ea856b2a3c037`。
- 实际首趟检查点581.6；第二趟1691.2实交20粮、损失0、结算200+50两；2517.8旗舰真实靠厦。82/1，唯一失败为全船队普通checkpoint。
- 最终2981.6，saveReason为 `save-fleet-not-anchored:mingqi-1650-grain-b`，并不表示快船已合格；检查在粮船乙处先失败。
- **不是完整往返通过。** 旗舰已靠港的事实和全船队尚不能保存同时成立。
- 当前Encounter探针实载SHA记录在 `command-probe.json`，为 `0910d581…c9df9` 当前修复版本；不是旧5a86版本。

## 核心判定

**粮船乙：已证产品生命周期缺陷。** Rally完成只清navigation与帆，遗留自治输出rudder。该舵值从首次完成记录持续到末态，船只在港外漂远。真实QA未发controls/选船/手操指令，selected/player一直旗舰，不能解释为玩家排队手操。

**快船：当前owner限制真实存在，但并非末态救援的唯一阻碍。** 合法navigate确实取消Rally并恢复Egress权限；1691.2返航开始及2981.6末态，实际Egress都无安全连接。不能用“允许Rally Egress”或“QA改navigate”单独宣称解决。

**快船更早的protect阶段存在已证恢复窗口和失去窗口过程。** 1511.6仍在Planner安全起点内；1526.6已在其外、实际船体仍湿，但合法接管后Egress有可行连接；1541.6已不能安全转身。此前近护航目标、收帆时仍全舵，原生低速舵/船员力继续作用。应调查并修复自治近目标操纵/停止生命周期，不应把正常使用protect视作QA误用。

**界面缺口已实测。** “选择此船”支持快船，但航位按钮仍固定指向旗舰。每船navigate是已实现API能力，尚无对应常规航位按钮。键盘接管当前选择船是已有路径；面板文案/滑杆仍围绕旗舰，不能把API调用当成玩家已有顺畅救援流程。

## 粮船乙完成过程

所有位置/速度来自真实stage；采样间隔15秒，因此完成时刻只能界定在2141.6至2156.6之间，不能伪称精确tick。

| 时间 | Rally | 距厦门中心 | 速度m/s | 舵 |
|---|---|---:|---:|---:|
|2141.6|active|30.6417|0.630347|0.1442985465|
|2156.6|completed|21.8809|0.547474|0.1448271765552296|
|2171.6|completed|14.2261|0.483863|同上|
|2186.6|completed|7.5018|0.433349|同上|
|2517.8旗舰dock|completed|66.1449|0.146767|同上|
|2981.6最终|completed|103.7856|0.087207|同上|

2156.6之后navigation=null、sail=0。最终位置`(-294.4059,-141.3889)`；目标`(-306.2571,-38.2821)`。

调用链：

1. `OrderController.decision:23`：Rally的完成条件为距点<25、speed<1。
2. `Encounter._tactical_tick:604-606`：标记completed后仅erase navigation、sailDeployment=0；未清rudder/tack/route/lowSpeedTurn/sailRecovery。
3. 后续固定tick无navigation则跳过autopilot；`_fixed_tick:523-527`仍将保存的rudder和船员舵力送给native。
4. `ship_dynamics.gd:370-402`：液压舵与低速船员侧向力独立于帆；sail0不等于舵无力。由于历史残余速度也参与漂移，本报告不把103.8米位移全部定量归因旧舵；已证旧舵持续施加、且永久阻断严格anchored判定。
5. `Encounter.is_anchored:942-946`要求speed<=.05、yaw<=.01、rudder==0、sail==0、无navigation/active order；这是正确安全边界，不应为此放宽。

零step复现：取2156.6真实完整pose/velocity/yaw与rudder，重新通过真实`issue_order`下同点Rally，再调用一次`_tactical_tick`。结果接受并completed，rudder仍精确`.1448271765552296`、navigation=null、sail0，motion严格未变。没有physics step/手操命令参与，直接证明完成分支遗漏输出清理。

驱动commands无controls或select-ship。`SailingSimulation.advance:113-122`默认自动手操输入只针对当前playerId；实际始终旗舰。`controlsSequence`随native/reconcile演进，不能把其递增误认为粮船乙收到玩家命令。

## 快船几何与owner

记录实际shape：`stage.ships[].navigationDiagnostics`只有route、approachRecovery、wetRouteEgress、egressClearance、lowSpeedTurn、sailRecovery、motion；没有记录tack counters。没有猜造历史tack状态。

| 时间 | 实际位置(x,z) | speed | start circle wet | native船体湿深余量 | 合法navigate后的Egress |
|---|---|---:|---|---:|---|
|1511.6|(-126.5966,320.3951)|.213949|true|13.026m|ineligible-endpoint，正常Planner可用|
|1526.6|(-125.2372,323.2998)|.213741|false|10.056m|**可行**，节点(-93.2372,291.2998)|
|1541.6|(-124.3394,324.9004)|.067524|false|8.771m|no-safe-egress|
|1691.2返航开始|(-120.9335,325.6502)|.018838|false|8.183m|no-safe-egress|
|2981.6最终|(-121.3420,325.5123)|.004597|false|8.317m|no-safe-egress|

余量使用真实native九点船体足迹的最高地形与draft计算；不等价于Planner圆安全或转向包络安全。所有查询均保留真实同伴pose/velocity/yaw、相同地形、风、船体尺寸、货重、船员与原259秒安全包络。

1526.6合法Egress节点相对当前位置(+32,-32)，course=-45°，distance45.2548m，horizon259秒，padding3.26089m；仅零步可行性，不是已驶出。

更精确的近目标调用链：`_fixed_tick:491`先跑`_tactical_tick`；它通过`OrderController.decision`计算protect点，`:603`每tick写navigation；随后`_autopilot:730`先计算并写rudder，`:733`的到达判断**仅令deployment=0**，`:738`低速大角度时继续收帆；`:746`调用`_navigation_steerage`，后者`:852`在末点18米内直接返回空assist，**不清已写rudder**。Protect本身没有completed分支，故不会进入`:606`终结清理；而即便Rally进入该分支也遗漏rudder。没有达到点后中性操纵分支。

`protect-arrival-timeline.json`进一步证明目标船甲1496.6至1541.6一直arrived且水平速度0、位置`(-70.457675,296.978622)`、heading1.30024185，因此60米侧向护航点始终`(-128.275046,313.014569)`。快船1496.6距它仅4.4242m就已全舵收帆，不是目标高速机动导致的必要追赶。

隔离零步`_autopilot`调用在1496.6、1511.6、1526.6三份记录均得到rudder1、sail0、assist={}，motion严格未变。历史previous/tack未记录：探针明确用记录yawRate线性还原前一tick heading，不注入tack。这是当前函数的标量反例，不冒充精确历史tick复演。

1691.2与最终，8节点均拒绝：3向西节点`wind`，其余5个` swept-depth`（JSON真实值为`swept-depth`），失败发生在当前位置转向扫掠。终点厦门本身Planner湿安全；当前船体也湿。**不应称船已搁浅，也不能通过削弱circle/terrain/noGo/包络来“救”。**

更早记录1511.6/1526.6：protect目标均`(-128.2750,313.0146)`，快船距离目标约7.57/10.72m，sail0、rudder1、lowSpeedTurn=true，速度约.214；持续转向/漂移后1541.6首次记录empty unsafe-endpoint。`OrderController.protect:30-35`无敌时选目标船heading+90°的60米侧向编队点；没有完成状态。`_autopilot`即使在计划18米到达半径内将帆归零，仍计算rudder，而 `_navigation_steerage`在半径内不提供恢复助力。保护目标到点后的自治控制持续性，需与架构lane的owner生命周期一起修复；本审计没有重放1511至1541的精确轨迹，不能把单个具体tick认作全部根因已复现。

`_approach_authorized:843-848`排除activeorder；`_egress_authorized:759-760`依赖它。Probe实际调用 `navigate(fastId,Xiamen)`，order变blocked/manual-navigation、authorized=true、motion逐项相等；没有直接清orders。晚期几何仍拒，证实单纯解除/拓宽owner不充分。

## 玩家可用入口

- Runtime已有显式shipId navigate、select-ship；Encounter.navigate会正常撤销订单并设置目标，point:null转手操。不是私有救援接口。
- `mingqi_interface:617`可选择快船；`:924`航位按钮硬编码campaign.flagshipId，`:571-573`gate也检查旗舰。船页controls滑杆/调帆同样指定旗舰。
- 海图点击只填表坐标，`:590-598`明确要求战术页确认，未另发选中船navigate。
- UI实树探针：真实final packet下快船选择按钮enabled，发出select-ship fast；隔离UI回执选择fast后，按航位按钮仍发`navigate flagship`。仅UI回执身份更新，无runtime/world变更。
- 原生键盘入口 `MingqiScene._unhandled_key_input:166-169`送runtime.set_held；`SailingSimulation.set_held:68-80`对当前playerId取消navigation/order。fast team=player且有权限，setPlayerId允许。所以可以通过选船后键盘手操接管，但不能说有选中船航位/停止按钮，更不能保证这种手操已证明能从当前扫掠受限姿态驶出。

## 最小修复建议与不可省验收

1. **先修产品，不改现QA避开问题。** 对自治订单的terminal transition集中清理该owner产生的舵、帆及tack/route/恢复状态。仅在该owner完成/阻断/撤销交接时清理，不能每tick对所有idle船强制归零，否则会覆盖合法手操/排队命令。使用现有物理操纵减速，不能把速度直接写0冒充制动。
2. 区分“进入集结半径”与“停止操纵/可靠停留”。仅清舵是最小确定bug修复，但不能证明等待几百秒仍留在港内；必要时保留有身份的安全制动/到点hold阶段，再释放owner。保持arrival/save半径与速度边界；不要瞬移锚定或放宽保存门槛。
3. 快船应在protect近目标停留阶段停止无谓全舵，及时处理从圆安全域向边界漂移的状态；若引入tactical Egress，需绑定orderId/participant/goal与权限、只在相同安全评估通过时取得owner，保留实际手操/新订单撤销机制。1526.6窗口提供真实反例夹具，1691.2和末态必须继续安全拒绝。
4. 为玩家补“所选船驶向航位/接管或停止”清晰入口，调用已有runtime公开命令；标签显示目标船名。不能只让QA通过显式shipId完成玩家在界面无法直接表达的指令。UI改变应有真实Control命令目标测试，且不误操作旗舰。
5. 保留现QA路线/合法Rally，先验证产品修复。若之后确需新船长策略，单独说明策略和可见入口，再决定QA变更。不能以避开protect/Rally的脚本为产品已修证据。
6. 实施后先跑对应定点反例和权限/手操抢占回归，再冻结源码跑原正常checkpoint的完整第二趟。必须保持20/0/250、原期限与上限、真实全船返厦、普通export_save成功。当前82/1结果不能升级成完成。

最小regression触发建议：

- 真实1496.6或1511.6完整记录构造fixture；目标甲静止arrived，快船active protect、有效单目标route、距目标<18、speed约.213且heading大角度偏离。一次真实自治决策应输出中性舵/收帆，不能保留1.0舵；再短native段确认不因自治舵/船员侧向力主动向岸漂移。不要直接写速度0、删除同伴或更改目标点。
- 2156.6粮船乙真实pose、speed.547、旧rudder.144827，同点Rally通过真实issue_order并完成，terminal必须释放该order自有输出。对照在手操接管/新navigation/新订单之后执行旧order清理，不得抹去新owner输出。
- owner边界：仅处理当前仍有效的自主导航或当前order所拥有的到点输出；不要扩大Approach/Egress授权，不要给所有idle船做通用rudder0循环。中间waypoint、有更远有效目标、目标船移动离开站位、手动操纵、captured/disabled/service边界均需保留原语义。

## 本次工具证据

- `timeline.json`：真实记录中B/fast自返航起各stage数据；`fast-route-transitions.json`：protect阶段至返航route变化。
- `command-probe.gd/json`：当前正式Encounter与全部同伴标量重建，28船次零step；实际公开navigate与B复发Rally完成路径，并包含3个近protect点自治输出反例；不初始化Runtime/Campaign，不读写Storage。
- `ui-probe.gd/json`：真实Control树，选中快船后航位命令目标验证；零simulation time。
- 两个Godot进程均exit0，最终分别输出`FLEET_RETURN_COMMAND rows=28 acceptedSeconds=0`、`FLEET_RETURN_UI emitted=2 acceptedSeconds=0`。`--log-file`限定此build目录。

```text
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://build/second-aftermath-work/fleet-return-audit/command-probe.gd --log-file C:/Users/dains/Documents/Git/ming-armada/build/second-aftermath-work/fleet-return-audit/command-probe.log
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://build/second-aftermath-work/fleet-return-audit/ui-probe.gd --log-file C:/Users/dains/Documents/Git/ming-armada/build/second-aftermath-work/fleet-return-audit/ui-probe.log
```
