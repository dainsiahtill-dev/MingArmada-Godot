# T3 首航可玩闭环接线报告

范围：保留现有首航/第二委托/aftermath、Campaign交易、Runtime安全门与Codec。未改共享物理、世界、scene输入或用户存档。CodeGraph本session无索引，按root结论用RTK fallback；未再查询、未造结果。

## 原有与新增

现有：真实接单、工资/领航/首次返港三个决定、两份粮食委托、部分/全部损失、一次性回执、伤亡、150两120秒自有船帆装升级、金门返港、严格全船队安全保存和主菜单Continue。2026-10-12历史first581.6秒为历史证据，不代表本候选。

新增：`VoyageFlow.project`从实际状态派生各航次阶段、期限/逾期、到达/损失数量、已到账报酬和租费、分支实付、实际改造作业/完成profile；HUD常显倒计时；日志集中结算与下一步。准备阶段人物决定优先；返港/航行阶段进度优先。直达自有船选择器、原委托页、原安全菜单。无第二套持久任务状态，无任何新增奖励或时钟调整。

## 文件边界

- 新 `game/domain/mingqi/voyage_flow.gd`，`OpeningStory.project`新增`flow`字段。
- `game/ui/mingqi/mingqi_interface.gd`新增HUD行及日志闭环区；全部执行仍走原控件/Runtime。
- 独立实验 `game/research/demos/voyage_flow_experiment.gd` 与论文 `assets/research/papers/voyage-flow.md`；明确声明只读虚构UI fixture，不作完成航程证据。
- 三个新测试：`test_voyage_flow.gd`、`test_voyage_flow_ui.gd`、`test_laboratory_voyage_flow.gd`。
- catalog由root登记：id/demo=`voyage-flow`，demo路径如上，status先`integration-ready`。

## 当前证据

`docs/research/evidence/voyage-flow/20261014-closure/`保留所有失败和最终源码hash；报告详见论文。最终新测试62/0；原opening383/0、second aftermath724/0、deadline37/0。独立长进程15178实际601次0.2秒native推进，23/0/exit0：Control支付150，真实作业完成heritage-sails，正常export/adopt无重复支付。长测使用开局资金，且先于最后纯文案/排序修订；不是首航收益消费或GPU证据。

## root待执行

1. 新flow源加入journey/capture/freeze的required source arrays；目前我未改旧QA工具，避免多处不一致。已有driver真实决策路径可复用，不从旧失败输出或实验fixture造checkpoint。
2. GPU普通mingqi入口，检查1600×900和1280×720的HUD、准备对白、返港日志新闭环区与自有船快捷选择；船务入口会滚到service_ship。
3. 新真实首航使用`--manual-fire --return --deadline --output=<new>`；记录accepted/wall时间，验证新story.flow与最终回执。10–15分钟尚未实测。若要求「收益支付改造」，须真实返厦门，再用已到账资金申请原150/120规则；不可在金门伪造船坞。
4. 普通safe Save/disk/主菜单「继续海上明旗 · 1650」可复用capture-opening-return的`--journey=<new-success> --save-readback`；新工具不写用户存档。
5. 全量suite、PCK、新独立review和最终GPU截图由root整合。不把上述定向headless结果称全目标已完成。

普通玩家可达控件：nav_story → story_choice_old-ledger_*；nav_convoy → contract_accept_convoy-001；nav_story → story_choice_pilot-plan_*；原depart、海图/鼠标/键盘操船与Q/E；原claim-convoy、port_dock_kinmen；story_choice_first-return_*；voyage_next_open进入convoy-002；voyage_upgrade_open选中承家号并打开原service_refit；voyage_save_open进入原save_and_menu；主菜单mingqi-continue。
