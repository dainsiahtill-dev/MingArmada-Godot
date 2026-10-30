# 主线全量完善第二批：真实交战、经济与验收切片

2026-10-30。在41号（按类薄层接线）之后全量推进：真实炮战与小游戏取胜闭环、经济真实化、入口表现完善、地区文书分支、以及文档38第4步的首个真实入口GPU/输入验收切片。**全仓回归同时验证中**；工作树保持未提交。

## 真实交战闭环

- **真实炮战**（`tests/test_story_live_engagements.gd`，STORY_LIVE_ENGAGEMENTS 8/0）：T04 的两艘反击舰由**真实舷侧齐射**击沉——选弹、射界、装填、弹道、损伤全部走原生引擎；结算见证读取真实沉没状态。26.4s（runner）。
- **真实决斗取胜**（`tests/test_story_duel_minigame.gd`，STORY_DUEL_MINIGAME 6/0）：CH-02 经 model-authoritative 决斗打到俘获胜利（每次新种子，败后诚实重试）。
- **真实陆战取胜**（`tests/test_story_land_minigame.gd`，STORY_LAND_MINIGAME 9/0）：CH-14 经 9×7 战棋真实取胜（贪心战术驱动：能攻则攻、否则进占射界位），resolve-land 由模型结果结算。
- 新夹具显式入档：`fixture_reload_multiplier`（装填加速，弹道/命中/伤害真实）；配合既有 `fixture_speed_multiplier`（引擎上限2.0）、静海与位姿摆放，全部记录于 `tests/story_walkthrough_support.gd`。

## 修复的真问题（真实交战暴露）

1. **重建复活已沉之敌**：原生名册重建不带战损 → 离港/业务变更会复活已击沉目标（玩家侧同样成立）。修为重建前同步原生 hull/sail/crew（`_sync_entity_damage`），显式战损夹具走免同步重建。
2. **种子超 int32**：路由 qaSeed 全 uint32，而世界/进度合同按 int32 校验 → 真实入口随机种子必然拒载。runtime 折叠种子入域范围。
3. 每次开火整包 flush 的热点、位姿缺船首向导致射界落空（目标不在舷弧内）、装填夹具未接线、`Dictionary.merge` 默认不覆盖等——均以真实失败暴露后修复（见41号同类记录）。

## 经济真实化

走查 CH-20 的购船/囤积资金**全部来自真实贸易收入**（CH-03 货运收入＋CH-16 丝绸套利 70 匹，扣文书/招募/购船/粮材支出），`fund()` 拨付夹具已从走查路径移除；丝绸本身仍是明示的货物本钱夹具（丝绸收购成本超出开局财力）。T07 补给来自舰队实存（先清舱转粮再交付），T01 装载来自出征积储。

## 入口与地区完善

- 故事场景补全：海图小图（SeaChart）、遭遇面板（EncounterInterface）、转场卡（年份+地区会面文本）、操作面板含剧情（想要/冲突/转折）、失败出口与**文书分支按钮**。
- **地区文书分支**（文档39五线落地为可选项）：CH-06/09/10/16/20 的条件文书各有 2-3 条真实选项（满剌噶转口/分段转运/改线柔佛；柔佛全担保/仅粮水；琉球按货单/以履约记录等），UI 选择即真实成本/条件差异；会面文本标注「原创戏剧重建，非史料对白」。严格加载器校验选项形状（`scenarios.gd`）。

## 第4步验收切片（GPU/输入）

- 新增 `tools/research/capture_story_voyage_gpu.gd` + `run_story_voyage_gpu.mjs`：真实首页→主线航程入口、**真实UI按钮意图**（开始/转场/离港/结算/重试/保存）、诚实失败结算、**真实存档写入并经 StoryRuntime.validate_save 校验**、菜单返回与 weakref 释放；PNG 逐张解码 RGBA 校验＋源码/原用户目录冻结审计。
- **`voyage-gpu-03` 全绿（valid=true）**：12帧/6采样/180接受步，诚实失败回执、真实存档、释放审计、PNG/RGBA 与双冻结全过；首页与实机帧已登记网页媒体（kind=game）。`voyage-guard-02` 无头精确拒收轨绿。切片≠全30阶段实机全程；全航程GPU验收仍待。
- `voyage-guard-01`、`voyage-gpu-01/02` 失败证据按惯例保留（01暴露种子/compact缺陷，02暴露sea_services契约缺口 `set_handling_mode`，均已修复）。

## 测试与证据（本批新增/重跑）

STORY_LIVE_ENGAGEMENTS / STORY_DUEL_MINIGAME / STORY_LAND_MINIGAME 全绿；走查在真实贸易资金下重跑绿（31回执不变）；entry/scenario_catalog 在地区分支后重绿；全仓回归 `wiring-repo-suite-01.json` 归档（405测/386过/19失败）——其中9个为本机60s runner 临界（含 autopilot：零依赖本批、直跑24/0通过），4个为保留 RED（crew_work×2、mingqi_fire×2，对应32号锁定设计与火势后移），3个为本机既有证据目录残留（hero_obstacles×2、painted_shadow，测试要求全新证据目录），另3个（layer_boundaries/maritime_entry/menu_consolidation）为本批引入并已修复：
- **layer_boundaries**：域层禁引 `res://assets/`。内容JSON按 mingqi 惯例迁入 `game/domain/story_campaign/data/`（顺带根治 catalog.gd 既有违例），全部引用更新。
- **maritime_entry / menu_consolidation**：1280 首屏与入口集契约——火攻/试航并入对战网格（净零行）、story-continue 单行文案、期望集补主线两枚。
最终证据聚合 `wiring-final-02.json`；设计检查 0 错误。

## 限制（如实）

- GPU 切片只覆盖开局段（真实入口/意图/存档/释放）；全30阶段实机 GPU/输入验收、真人手柄/键鼠长测未做。
- 战斗/经济夹具边界如上；平衡、演出、火势分区、地区3D纵深仍后置。
- 主线状态仍为「实验中」——升「已可玩」以第4步全航程实机验收为准。

## 持续迭代纪要（loop 第1-11发，2026-10-30）

每发同步网页航志与测试证据，均过走查/类目回归：

1. **键鼠操船**：WASD/帆桁/舷炮/换弹/相机全接线（STORY_INPUT）；无头跳过海景着色的可测性缝。
2. **护航压力+地区五线**：CH-06/13/T07 袭扰者（交战挡结算）；暹罗查船分支、吕宋名册会面。
3. **行情仓栈**：确定性日漂移±25%、仓栈守恒（STORY_ECONOMY）。
4. **难度四轴**：压力档1-6驱动敌方加成/日用、CH19追兵/T09援扰（STORY_DIFFICULTY）。
5. **同伴专长**：领水/炮手/账房/庖长四职生效（STORY_COMPANIONS）。
6. **船装升级**：四系统三级、真实银两、船坞门（STORY_UPGRADES）。
7. **英雄图鉴**：12命名英雄、本港意愿、签约入账（STORY_HEROES）。
8. **十二专长全落地**：救援人手/接舷省员/船匠半价/医者返岗/通事折扣/乐师/瞭望/信号员（STORY_ROLE_EFFECTS）。
9. **宴饮情报**：声望真议价、远程行情情报（STORY_PORT_SERVICES）。
10. **船队号令**：三形队列+指定护航真导航（STORY_FLEET_ORDERS）；修购船落位原点缺陷。
11. **全量回归大检**：故事全套+受影响面（layer/menu/entry/router）全绿归档 `wiring-full-suite-04.json`。
12. **风暴天气**：三态风场接入原生物理、全员收帆0.55、CH18/19/T02 风暴章（STORY_WEATHER）。
13. **伤员医疗**：失利送病榻不蒸发、付费疗伤、医者日康复（STORY_WOUNDED）。
14. **合伙分利**：半独立合伙人携资远航、按真实行情差六四分账（STORY_PARTNERSHIPS）。
15. **动态商船**：四条商路客舟真实往返、到站折返（STORY_TRAFFIC）。
16. **存读档实机回环**：`voyage-gpu-05 valid=true`（真继续入口恢复+精确续走）；suite-09 34/34 净档；测试瘦身（weather 44→1.1s、走查 48→29s、sailing 59.5→29.5s）。
17. **终章实机验收**：`endgame-gpu-09 valid=true`——三重门真实按钮、清舱售卖、离港、结算、结局全链留证；**钓出真bug**：恢复会话 runId 未同步致证据静默拒收（异名 runId 回归钉死）。
18. **整合复验**：suite-10 全套 34/34 + layer/menu/entry/router 四面复绿（终章改造后）。
19. **尾声结算**：航程结算面板（阶段/日数/银船人手/同伴/交棒账目），终章GPU切片 `endgame-gpu-10 valid=true` 含结算帧；走查12/0。
20. **航海手册**：可开合键位/流程/终章要领手册（STORY_INPUT 补开关断言）。
21. **六幕回望**：尾声增六幕完成度回望（真实回执映射章幕）；文档追平；二轮全仓大检开跑。
