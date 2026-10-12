# QA呈现与安全到港泊船：顺序独立审查

2026-10-12。先QA presenter，后Arrival冻结包、P1与P2修复增量，分别做Spec及独立Standards；只读生产/工具，不重复已执行的测试、不GPU、不性能、不Git。CodeGraph已无索引，RTK定向读取。**QA presenter增量通过；Arrival原P1、新增P2均已Addressed，最终scoped审查通过，无遗留实质finding。** 下文保留历次请求修改的历史；当前结论以末尾最终冻结复审为准。全套、真实旅程、正常checkpoint/Continue和RETURN GPU尚不由本审宣称成功。

## Verdict 1：QA presenter 增量通过

- [QA scoped patch](return-capture-presenter-qa-scoped.patch) SHA256 `923f20e03b55fe72e16f6c5343d57717b908162229577c9b2283247b2d2af837`、79行；[工具](../../../../tools/capture-opening-return.gd)冻结SHA `6f3b2734a4ca7b58d8ce42818edad677475b95431805b1b1aa76245f013cb4cb`均匹配。独立子审查员只读逆应用后恢复原baseline SHA `dba3e0d484dcb0af2a4dab94dfdfd5fb163ce88335e182324cca1757fc9202cf`，不把其他dirty修改混入增量。
- `button()`仍使用实际Input鼠标事件，再在main/scene有效且 `main.current_scene==scene` 时调用普通Scene._present(0)。每次capture也刷新当前真实场景，并检查打开operation/menu时实际chart不可见；退役或释放的场景不会被补呈现。没有直接设置UI.visible来伪造结果。
- 生产Scene._present消费snapshot、drain表现事件和呈现服务，没有Campaign命令或船位修补。本增量没有修改state、pose、健康、货物、Codec或生产源码。
- 原成功旅程门禁、原始record SHA、capture source SHA、严格unchanged final.campaign encode/equality、正常Router/native adopt/preflight、隔离slot和cleanup保护保持。PresenterProbe自测不构造Campaign；MainScene仅new、不入tree，因此不执行其_ready默认settings读取；helper不读写实际用户slot。
- 原工具在GPU执行时仍只初始化本进程新的user://tests前缀，用exact accepted save走普通Continue；实际用户slot仅做既有前后存在性/散列检查，cleanup只清拥有的隔离路径。不得把本增量当成绕过未锚泊或精度失败的方法。

[作者报告](task-return-capture-report.md)记载新呈现RED16/1→GREEN16/0和check-only通过；本审未重跑。此前canonical-port-mismatch预检和GPU未运行边界保持。**此verdict是QA增量来源/行为通过，不是RETURN截图已经通过。**

## Verdict 2：首轮Arrival请求修改，P1必须关闭（历史）

[Spec](task-arrival-berthing-brief.md)、[patch](arrival-berthing.patch)、[身份清单](arrival-berthing-hashes.json)、[实现报告](task-arrival-berthing-report.md)。核验如下：

| 来源 | SHA256 |
| --- | --- |
| before Bridge | b1802c077abb19855422fec274522f88fa21ce7fdebe2363989723a48239726d |
| Bridge |8621c85da31d14de50ee9c27137268866ab29b80dfe3d9a02333fe6771e86617 |
| 新测试 |b24b89cc28f13b0ab2685aeea2e4accdc4b0b4bc536cae51a7725e8574242928 |
| scoped patch |55205caa615bd154d5ab7a56db2697ffcc2f26d015c9e29b225d5a3a17aa0daf |

实际文件均匹配；独立Standards从before/live重建unified diff与交付一致。范围仅 [NearFieldBridge](../../../../game/runtime/near_field_bridge.gd)和 [新测试](../../../../tests/test_arrival_berthing.gd)，不改Campaign、Encounter、物理、Planner、存档或QA。

- 仅原已付租grain-a/b，house-lin、原grain profile；业务/native两份权限、存活、able≥minimum都必须成立。随机船、旗舰、快船、继承船不受此自动泊船影响。
- 当前权威voyage匹配船并arrived/空货；实际native港位≤55m、水平速度≤.75。pendingAttacks、未俘获存活敌≤600m、work/boarding、captured/disabled/locked、实际nav/active order、非零rudder/sails全部拒绝。
- `_arrival_anchors`只读选择ID，经同一 `_apply→reconcileShips`交易应用；不先改native状态或位置。两条sync/reconcile入口一致，拒绝依旧走原原子回滚；重复不新增业务奖励、付款、损失或船员变化。
- 初次underway→arrived只清业务原末端导航；已arrived的后续显式导航不再每次sync删除。fresh-startup仍清导航，active orders和手操保持原权威。控制投影/clock/epoch围栏没有被替换；真正export_save与船长dock安全门禁也不改。
- 作者测试实际验证isAnchored、位置不变、600tick/10秒风中重复稳定、真假guard和拒绝时双权威不变。Fixture明确为单测初始条件，不是实际航次或接受瞬移；工作锁定原已有独立停船路径，测试未把该stop说成新自动锚泊。

报告记录干净RED607/12、最终723/0和17项scoped exit0；本审不重复该运行。Root新全项目103脚本和实际旅程在运行/待运行，**不能继承旧102或旧29/1的结果来宣称新Bridge真实问题已解决。**

## P1：自动导航残舵使真正到港后的泊船门禁持续失败

触发：原租粮船由真实autopilot带着非零自动rudder进入25m/低速卸货范围，正常underway→arrived交接。[Campaign._arrive](../../../../game/domain/mingqi/campaign.gd):492只清sails，不清rudder；`_sync`:665会取实际上一tick控制。Bridge清到港导航后，非玩家merchant不会再跑autopilot；Encounter.reconcileShips:948清nav也不清rudder。[Bridge](../../../../game/runtime/near_field_bridge.gd):142的 `live.rudder != 0`持续排除自动泊船，**时间本身不会让这个自动残舵归零，漂港/无法安全checkpoint的目的可能仍无法完成。** 来源足以证明该触发路径，无须先浪费一次完整真实航行才能提出finding。

测试fixture的arrive前没有native autopilot tick，rudder从0起步；它覆盖显式舵应被保护，没有覆盖实际autopilot到港带舵这一正常路径。作者报告披露风险限度，但该限度直接影响主修复目的，不能降为无阻断观察项。

最小修复目标：只在真实underway→arrived且属于原业务自动导航的交接时，使该自动控制中性；交接后的显式controls/nav/order继续保留。不能任意清用户舵、删除非零控制门禁或重写船位/存档。Root已接收finding并转实施者添加实际native tick/autopilot卸货的有意义RED，生产修复后提供新scoped delta再由本审重审。验收至少证明：真实自动残舵到港后能泊住；到港后用户实际打舵/升帆、显式goto、rally仍不被覆盖；原业务/native原子控制投影、存档安全保持。

首轮结论为 **Arrival P1未关闭**；旧723/0与17个scoped通过不足以覆盖此遗漏。该finding后续修复状态见下文，不把首轮数据改写为修复后的证据。

## P1修复增量复审：原缺陷已Addressed，新增P2待关闭（历史）

只审[增量patch](arrival-berthing-rudder-delta.patch)和[累计scoped patch](arrival-berthing-final.patch)，未拉取整分支dirty diff；[最终身份清单](arrival-berthing-final-hashes.json)中的五项均实算匹配：

| 来源 | SHA256 |
| --- | --- |
| Bridge |19cea28a36f55766126f066a5941f21477688a96f35e1815709629dcbabfbb9f |
| Campaign |f36ca92c29a9061ede634b414c5fd76a719ecdfd2b90cc9994a35b2b7becad1f |
| 测试 |ad7b0ea88b9b757fb7d8d91de60427260b7cc571f39362b6968d0bab76f98142 |
| delta |b4ac665a4880188181f1b2ce616718071ae57ee4486b89a6e242e9a07a0b58fc |
| cumulative |5496daf73da11b0f023bfbdccbd94aa20403b489755ce89778dca2c5eb7b3868 |

Root明确授权新增Campaign生产范围，限`reconcile_near→_sync→_inspect→_arrive`这条交易/到港链；原brief仅Bridge的范围由[作者报告](task-arrival-berthing-report.md):114–125记录的后续rulings扩展。两个arrival-control身份数组只属于当前调用上下文，默认`[]`；未新增state/save字段、命令、收据或虚构角色。

独立Standards审查员只读逆应用核验：delta精确还原初次冻结Bridge `8621c85…`、本次修复前Campaign `5290c193…`及测试 `b24b89cc…`；累计patch精确还原原Bridge `b1802c07…`、Campaign `5290c193…`及空新测试。Spec原P1及显式控制事项通过；Standards确认下述一项P2强校验回归，其余临时参数默认兼容、seq/epoch门禁、候选交易提交未发现新增违规。此双轴结果没有靠重复测试或全dirty diff替代。

| Spec项目 | 复审状态与源码事实 |
| --- | --- |
| 原P1：真实自动残舵卸货后不能泊船 | **Addressed**。Bridge:133–150要求原已付租粮船、underway、当前权限、profile/hull/crew、同epoch/projection revision/tick/sequence、真实旧末端港位导航且无active order；Campaign:484–508仅一次真正`_arrive`中清该自动rudder，原交易投影到native。后续安全观察才锚泊，无直接船位或速度修补。 |
| 首arrival显式舵/帆 | **Addressed**。实际sequence严格更新的另一数组不被归为自动；`_sync`正常观察真实控制，`_arrive`保留新舵与帆。之后非零实际控制仍阻止锚泊。 |
| 首arrival不同目的地、以后nav/order | **Addressed**。Bridge:64–68只清旧港终点；不同新点保留；active order仍由live Encounter权威保护，已arrived后不覆盖新导航。 |
| 旧callers兼容 | **Addressed**。默认两个空数组，不改原legacy卸货收帆行为；远航/旧sync调用仍不自动清舵；原Schema与普通dock/export保持。 |
| ownership授权、sequence/epoch/stale、原子失败 | 有条件通过。原租身份、双方权限和数值/projection围栏已实现；`_sync`旧stale规则与callback后commit保持。新增顶层snapshot/row结构预检存在下述P2。 |

已检查作者保存的真实日志：原自动残舵[RED747/4](arrival-berthing-rudder-red.log)、新增不同目的地[RED779/5](arrival-berthing-rudder-red-expanded.log)、中间[GREEN852/0](arrival-berthing-rudder-green.log)、真实新帆指令[RED863/2](arrival-berthing-first-sails-red.log)、当前[GREEN911/0](arrival-berthing-first-sails-green.log)。新测试先正常Bridge投影原航程，再执行真实Encounter tick进入25m/低速范围并确认残舵非零；不再以未推进native的零舵fixture替代该路径。测试还覆盖默认旧调用、观测新命令、错误身份/duplicate/epoch/proof、native拒绝回滚。来源为作者运行，本审未重跑。

[最终14项scoped记录](arrival-berthing-final-scoped-results.json)均exit0/passed，包含两个旧golden；未把原17项或旧102/103全套继承为本次新源证明。Root正在执行新的全套与正式旅程。作者报告明确将sequence非舵帆变化按新控制保守保护、可能延迟泊船，属于已授权的保留控制权取舍；不把这项保守性虚报为额外炮战/操作功能。

### P2：新ownership路径在通用snapshot验证前读取未经验证的船行

[Campaign](../../../../game/domain/mingqi/campaign.gd):634先执行`_ship(before,id)`；该helper:786–788直接遍历`before.ships`并访问`ship.id`。当arrival/explicit上下文有一个合法原租粮船身份，但`before.ships`为非Array，或包含`null`/非Dictionary/没有`id`的行时，新路径会先产生脚本错误。旧默认空数组路径会先到`_sync`:656/662，正常返回`invalid-near-snapshot`或`unknown-or-duplicate-near-vessel`。这是新增ownership参数路径引入的结构验证回归；普通Bridge.capture返回有效snapshot不会触发，不能因此把API原子拒绝合同忽略。

最小修复：在新ownership查船之前验证`ships`是Array且每行有Dictionary/id结构，或用只读安全查船；保留原拒绝/不commit行为，不修写snapshot或状态。新增有意义RED需传合法ownership身份配无效`ships`/行结构，证明返回拒绝且Campaign/native都未变、无SCRIPT ERROR。该轮测试只覆盖畸形crew/navigation/tick，尚未覆盖这条结构边界。**该轮结论是原P1关闭、新增P2请求修改；P2后续关闭证据见下文。**

## 最终冻结：P2极小增量通过，全部本轮findings已关闭

按Root指定只复审[ownership rows增量](arrival-berthing-ownership-rows-delta.patch)的4行Campaign结构guard及11行测试；不重复P1/旧审、不重跑作者测试、不发散到其他源。`not identities.is_empty()`内先要求`before.ships is Array`，再要求每行是Dictionary且id通过已有4096上限验证，才执行原identity查询。无效输入用原理由返回失败，发生在候选复制/native callback/commit之前；默认两个空数组完全绕过新检查，原路径保持。

**Spec：P2 Addressed，新增实质finding 0。Standards：P2 Addressed，新增实质finding 0。** 独立Standards子审查员只读逆应用本增量，精确还原P2前Campaign `f36ca92c…`、测试 `ad7b0ea8…`；Bridge保持不变。最终[身份清单](arrival-berthing-final-hashes.json)及当前实际文件均匹配：

| 来源 | 最终SHA256 |
| --- | --- |
| unchanged Bridge |19cea28a36f55766126f066a5941f21477688a96f35e1815709629dcbabfbb9f |
| Campaign |beead54a168dc323eb0fe928fc436e9cf0d64d40e5d2b851fdcd477021b068c1 |
| 测试 |72940022677c33925d8dc053f98c7d5af13c58abc756b46b438412340e66536d |
| P2 delta |37fdfc958345aa74cf8bbde3d7d56965920cac1db606df33b7d9930b20ff9992 |
| cumulative scoped patch |279557688dc548851d1b4d94aeb82915f80b0fe9fb56bb8f3ede4854c9295259 |

已读真正[RED980/6](arrival-berthing-ownership-rows-red.log)：`ships=7`、`[null]`、`[{}]`分别在auto/explicit上下文触发，六次SCRIPT ERROR及原理由断言失败均保留；[GREEN980/0](arrival-berthing-ownership-rows-green.log)零SCRIPT/compile/resource错误。新增测试使用合法已投影真实native上下文，只修改脱离权威的输入副本；验证失败对象、原reason与两份权威完全不变。作者早期只看零失败marker但仍有SCRIPT ERROR的探索运行被拒绝为成功，不作为本审GREEN。

[最终四项scoped记录](arrival-berthing-ownership-rows-scoped-results.json)已核全exit0/passed且无SCRIPT ERROR：arrival980/0、Bridge13/0、Campaign source golden PASS、web-v2 save compatibility golden PASS。本审只查已落证据与源码身份，未重复执行。

| 本轮finding/保护事项 | 当前关闭状态 |
| --- | --- |
| P1：真实自动到港残舵导致不能泊船 | **Addressed**，P1 delta与真实native tick RED/GREEN支持。 |
| 首arrival新显式舵帆被卸货覆盖 | **Addressed**，真实新控制/帆单独RED/GREEN支持，后续门禁保留。 |
| 首arrival新目的地、以后nav/order保护 | **Addressed**，只清旧终点，原live order权威保持。 |
| P2：nonempty ownership未先检查ships/row结构 | **Addressed**，本极小delta与980 RED/GREEN支持。 |
| QA presenter冻结harness未更新普通呈现规则 | **Addressed**，独立QA verdict 1通过；没有用于修补Campaign或个人slot。 |

Root主动中止的session9221见[中止记录](../../../migration/evidence/opening-story/full-suite-ownership-review-interrupted.md)，不算完整103/103，也不替代最终源全套。Root重新启动的最终103脚本、真实航次、正常可续玩checkpoint/Continue及RETURN GPU仍属后续验收；本最终scoped通过只关闭上述代码finding，不宣称这些真实闭环已成功。历史patch、SHA、失败、723/911中间GREEN与旧完整/中止全套均保留。
