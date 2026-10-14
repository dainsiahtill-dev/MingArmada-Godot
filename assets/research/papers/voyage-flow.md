# 首航目标与结算可见性

- 课题 ID：voyage-flow；2026-10-14；前瞻工程研究。
- 状态：已通过独立与生产接线的 headless 合同验证；GPU、普通入口与实机节奏待主整合者验证，因此目录应先标 integration-ready。
- Demo：`game/research/demos/voyage_flow_experiment.gd`，统一目录由整合者登记。
- 源码：`game/domain/mingqi/voyage_flow.gd`；原生 Campaign、OpeningStory、Runtime、Interface 是现有合同所有者。无外部资产或第三方算法。
- 证据：`docs/research/evidence/voyage-flow/20261014-closure/`，各轮文件独立保留。

## 问题与假设

当前首航已实现两份委托、支线决定、原生交差、船务和安全存档。HUD 只有目标标题；期限、已送达货物、结算收入、返港改造位置及继续游戏方式分散在不同页面。H1：只读投影能在任意阶段同时说明实际进度与下一步，不改变权威状态。反例：合同标为 settled 但没有对应回执时不得显示已到账奖励；逾期不得显示负的剩余时间；部分损失不得写完整交付。

单位：秒、粮食单位、银两。时间所有者是 Campaign.simulationSeconds；截止日用合同 deadlineAt，绝不按接单/阅读界面重置。安全性只读 Runtime.canSave/saveReason；本投影不授权交易。

## 方案比较

1. 为首航建立第二套任务状态机：需存档迁移，可能同真实交差不一致，拒绝。
2. 从合同、航程、付款回执和船务推导只读进度：每次 O(航程+回执+作业)，复用现有 UI 操作，采用。
3. 强制分支对白或模拟等待以凑10–15分钟：影响原玩法与真实节奏，拒绝。

## 算法与实现

按第一份未终结合同选择活动目标；各航程状态只统计加载/在途/到达/损失。到账数据仅来自合同指向的规范 claim-convoy 回执，且核对 contractId。选择反馈来自 story-choice 回执，保存历史已付成本；当前声望单列，避免把配置增量误称上限截断后的实际增量。

已付改造只显示真实 work；未改造自有存活船提供现有船务入口。150两、120秒和厦门限制由原交易核验，快捷入口仅选择船只。存档入口进入现有菜单，按钮仍由真实 Runtime 安全门控制。无 RNG、缓存、存档字段或后台计时。

## 实验设计

独立 Demo 使用明确标注的只读 UI fixture：待接、在途、逾期、部分交付、全部损失；不把 fixture 当航行证据。基线显示原 OpeningStory 目标；候选附加期限、交付、已付结果。固定32Hz、初态时间0、无 RNG，观察镜头为固定文本面板。暂停、重置、切换 fixture 不写用户存档。

CPU 接受标准：源状态逐字节不变；期限只随接受时间变化；缺回执无奖励；损失不丢；支线已付成本不重复累计；作业与资金变化实时回读；暂停不推进，重置确定，dispose无所有者。生产接线测试必须经真实 Control -> Runtime.command 完成已有选择与改造，安全导出/载入保持账目且不能重复付款。

GPU：由主整合者串行验证普通入口、HUD/日志/船务/菜单，1600×900与1280×720。节奏：新真实首航完成后记录物理接受秒与wall秒，10–15分钟只为目标，不改时钟或注入货物。未运行不宣称达标。

## 结果与证据

本轮基线是工作区开始时的 `42761b71e73c1174eecf5a34e524d80475c06df3`；不存在 voyage-flow 模块。先写本报告与反例，再新增独立投影/实验，独立 GREEN 后才挂入 OpeningStory.project 和 Interface。最终源码 SHA256 在 [source-final.json](../../../docs/research/evidence/voyage-flow/20261014-closure/source-final.json)。

- 独立 domain RED：缺投影，1断言/1失败；GREEN：21断言/0失败。独立 lab RED：缺实验，1/1；GREEN：16/0。对应 `domain-red.json`、`domain-green.json`、`lab-red.json`、`lab-green.json`。
- 正式 UI 有效 RED：新快照字段、HUD 和改造入口缺失，4/3；实现后23/0。`ui-red.json` 是测试作者类型推断错误，不是有效 RED；保留，后续 `ui-red-valid.json` 才作为反例。
- 完整120秒物理推进最初触发严格 runner 的60秒 wall超时，保留 `ui-green-attempt1.json`；不放宽 runner。普通测试改为真实1秒作业/导出/恢复；另用 `--complete-refit` 执行真实601次0.2秒 native推进，无注入时钟/作业字段。独立进程15178 exit0、23/0，日志 [actual-refit-120s.log](../../../docs/research/evidence/voyage-flow/20261014-closure/actual-refit-120s.log)。实际通过UI支付150两，实际完成heritage-sails、速度系数1.10，正常导出/恢复保留账目并阻止重复收费；使用合法开局资金，不能宣称本航收益已用于升级。
- `ui-green.json`、`ui-green2.json` 保留数值类型比较错误：Codec将JSON数字恢复为float；`ui-restore-diagnostic.json`证实150与150.0等值。修正测试为双方JSON规范化比较，不改生产存档。
- 界面用错继续入口名称、准备阶段目标排在船务之后的 RED：25/2；修后最终 `final-flow-tests.json`，3/3脚本，16+21+25=62断言/0失败。实际120秒长测先于最后文案/排列改动；算法、改造交易与存档规则之后没有变化。该长测不能充当最后界面版本的GPU证据。
- 现有回归：opening五脚本116+47+122+59+39=383断言；second-aftermath四脚本107+107+400+110=724断言；deadline clarity37断言；均0失败/exit0。保留 `opening-regression.json`、`aftermath-regression.json`、`deadline-regression.json`。全量suite由主整合者执行，这里不是全套通过声明。

所有报告在本课题证据目录；正式代码仅新增只读投影与操作入口，不修改Campaign、Runtime、Codec的权限/付款/伤亡/时间合同。没有执行GPU、整场性能或新的完整首航；不报告10–15分钟达标。

## 局限与失败

独立 fixture 只能证实派生逻辑和标签；不能证实航行、战斗、GPU可读性或10–15分钟节奏。帆装实际改造仍只允许厦门的自有船；金门首航终点仅展示回厦门改造路线，不能虚构金门船坞。全部损失不开放第二委托。旗舰沉没不提供成功闭环。

## 集成与复现

先运行 `rtk proxy node tools/verify-godot.mjs --filter voyage_flow --output docs/research/evidence/voyage-flow/20261014-closure/independent.json`。随后将只读投影挂入 OpeningStory.project，UI消费同一数据并保留原操作按钮门禁；新增接线测试与受影响回归。

正式路径：主菜单新航程，航海日志决定欠薪，船队接单，再决定航路，离港操船/战斗，按实际粮食交差，金门安全靠港并处置收益；菜单安全保存并返回，主菜单继续。回厦门后港口船务选择自有承家号，申请帆装改造，按接受时间等待120秒，再安全保存。不能将未实际执行的步骤记为完成。

接口与实机复核：`story.flow`是只读数据，HUD `voyage_progress`显示分钟:秒；日志 `voyage_bill`显示规范回执所列交付/损失/到账及结算时伤亡；`voyage_upgrade_open`只设置已有`service_ship`选择器并打开港口页，付款仍用`service_refit`；`voyage_next_open`只打开既有convoy页；`voyage_save_open`调用原open_menu，`save`、`save_and_menu`仍受runtime.canSave控制。主菜单真实入口名称是「继续海上明旗 · 1650」。

完整旅程继续使用既有 `tools/play-opening-story-journey.gd -- --manual-fire --return --deadline --output=<new-path>`，不得用实验fixture代替。整合者须将新`game/domain/mingqi/voyage_flow.gd`加入各真实journey/capture要求的源码冻结清单，保持工具之间一致。原生返港图用 `tools/capture-opening-return.gd -- --journey=<successful-current-journey> --output=<new-directory> --save-readback`；原工具会保护用户槽位并拒绝不可信checkpoint。只有整合者完成新鲜GPU/旅程/全套测试与统一目录验证后，才能标integrated。

回退只移除新投影与UI消费，保留原交易、期限、安全存档和历史证据。
