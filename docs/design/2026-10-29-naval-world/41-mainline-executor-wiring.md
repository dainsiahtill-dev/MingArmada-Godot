# 主线真实玩法接线第一批：按类薄层铺上30阶段

2026-10-30。执行文档38交付顺序第3步：按 操船/交易/护送/海战/接舷/陆战/港口交互/handoff 八类，把现有可运行模块薄层接上24章30阶段主线。**全程走查已能以真实结算从开局走到结局**；第4步（正式入口全GPU与输入验收）仍待做，主线状态保持"实验中/粗闭环待验收"。

## 架构接缝（与计划的取舍）

1. **薄故事业务域**（`game/domain/story_world/`）：`story_world_session.gd`（钱/船/货/人/许可/协议/账本/封锁/交接的唯一权威，命令+回执+守恒记账）、`story_rules.gd`（从冻结 oracle 复制的靠港/接舷/俘获/贸易数学，**对照测试钉住**：`tests/test_story_world_session.gd` 驱动真实 legacy Session 镜像输入断言同判）、`story_save.gd`（世界+进度同档，交棒标记交叉核对）。`game/domain/legacy/**` 零改动。
2. **fact_adapter**（`game/domain/story_campaign/fact_adapter.gd`）：19 类 objective 的见证函数；`settle` 时对活世界重核（protect/stockpile/blockade/escort 以结算时为准）；事实 id 含进度里程碑（后期增长不改写已受证据）。
3. **执行器合并**：计划中的8个适配器文件合并为 `game/runtime/story_runtime.gd` 的按类执行面 + `story_encounter_coordinator.gd`（小游戏护栏分叉：伪造结果拒收/请求身份/练习隔离）。理由：薄层单缝、避免空壳文件；每类证据由各自测试文件保留。
4. **示意压缩地理**：`assets/data/story_campaign/geography_v1.json`（17港、REG-01..07、标注"示意压缩地理"）+ `scenarios_v1.json`（30阶段实体/结算绑定/转场/预算，严格加载器 `scenarios.gd` 与 catalog 1:1）。章节跳年为显式转场（含年份+锚地），不快进工资。
5. **正式入口**：`game/scenes/story/story_scene.gd`（仿 legacy_scene 组合：StoryRuntime + naval_world_view + sea_services + 薄操作面板 `game/ui/story/story_interface.gd`）；路由 `story`/`story-continue`、存档槽 `user://saves/story-v1.json`；首页按钮"主线航程/继续主线航程"。**无判胜/跳章按钮**；UI 只发操作意图（伪造 outcome/score/success 一律拒收）。
6. **CH12 交棒**：单一 `transfer-manifest` 事务（清单取自在场、缺席入 leftBehind、不修血、不清债、单回执、拒重复、主角仅在进度侧翻转）。**T10 三重门**：sign-terms + load-manifest 撤离（真实舱容/铺位）+ handover-facilities（逐项清点）+ 离港后结算时见证全过才 success。

## 逐阶段可操作/待适配表

| 阶段 | 真实结算（基础版） | 状态 | 待加深 |
|---|---|---|---|
| CH01 | 实航渡→靠港门→交货30粮 | 可操作 | 领航水道/潮窗演出 |
| CH02 | 核认身份→接舷门→俘获（教学窗预削弱；误捕诱饵不计功+关系代价） | 可操作 | 接舷小游戏演出 |
| CH03 | 每任务账本净收益（旧收益不累计） | 可操作 | 多港套利航段 |
| CH04 | 委托船真实航行到达+结算时存活 | 可操作 | 队形/护航战斗 |
| CH05 | 同伴签约入队（真实费用/岗位） | 可操作 | 意愿/条件谈判 |
| CH06 | 有限受命文书+护送履约 | 可操作 | 许可边界冲突 |
| CH07 | 压退敌船（原生损伤转换）+友船结算时存活 | 可操作 | 真炮战循环（原生已测） |
| CH08 | 核认首领俘获+商路保护 | 可操作 | 悬赏结算细节 |
| CH09 | 使船救援+到达+限定许可 | 可操作 | 王府交涉对白 |
| CH10 | 满嚆/柔佛两纸文书分别履行 | 可操作 | 旧货单核证分支 |
| CH11 | 接回人员+撤离记账 | 可操作 | 容量取舍 |
| CH12 | 单一交棒事务+进度翻转 | 可操作 | 人船意愿归属 |
| CH13 | 旧船护粮到达+旧部复约 | 可操作 | 旧伤保损 |
| CH14 | 岸点→装载→交付→撤回 | 可操作 | 陆战演出 |
| CH15 | 救援+复开码头+警戒线 | 可操作 | 修护窗口 |
| CH16 | 许可线经营净收益 | 可操作 | 区域行情 |
| CH17 | 首段护航到达+分队归来回执 | 可操作 | 分队独立航程 |
| CH18 | 伤船救援+船队撤出 | 可操作 | 风灾场景 |
| CH19 | 伤员+后卫+撤退 | 可操作 | 撤退时机 |
| CH20 | 文书+真实买粮/修材囤积（舱容/调拨） | 可操作 | 经济深系统 |
| T01 | 装载清单跨船实装+船团保护 | 可操作 | 配载演出 |
| T02 | 渡海到澎湖+运输船保护 | 可操作 | 海况压力 |
| T03 | 登陆场+首批补给+回路 | 可操作 | 陆战纵深 |
| T04 | 反击编队压制+立足点保护 | 可操作 | 真炮战循环 |
| T05 | 条件受降+设施逐项接收 | 可操作 | 谈判分支 |
| T06 | 围线封锁见证+伤员回运 | 可操作 | 封锁机动 |
| T07 | 补给交付+船团到达 | 可操作 | 补给线被截 |
| T08 | 援军压制+海侧围线 | 可操作 | 真炮战循环 |
| T09 | 棱堡压力阵地+最终围线 | 可操作 | 攻坚细节 |
| T10 | 谈降+撤离（120人/104货实装离港）+接收三重门 | 可操作 | 条款博弈 |

## 本批证据

- 全程走查 `tests/test_story_voyage_walkthrough.gd`：开局→CH01..CH20→CH12真交棒→T01..T10→complete，含真实失败+重试（31回执=30成功+1诚实失败），~37s（无头）。
- 存读档 `tests/test_story_save_restore.gd`：交棒边界检查点同档复原续走、篡改/异档拒收。
- 类目七测（sailing 42s 真航渡13960tick/trade/escort/naval/boarding/land/port）+ handoff + fixture isolation + entry 全绿。
- 域层三测（world/parody、scenarios 1:1、fact_adapter 19类+结算时反例）全绿。
- 聚合：`docs/research/evidence/story-campaign-flow/wiring-full-suite-01.json`（test_story 全套）+ `wiring-final-01.json`（`tools/research/finalize_story_wiring.mjs` 汇总含逐源 sha256）。
- 路由/菜单回归 `wiring-router-recheck.json`、`wiring-menu-recheck2.json` 绿（菜单首屏契约在按钮挪入两列网格后保持）。

## 保留的失败与修正（本批）

- JSON 数字回读浮点导致往返不对称→世界层规范化器（int/float 按 schema 定型）。
- Oracle 校验"靠港即速度为零"未镜像→补世界不变量；对照平价三组（靠港/买卖/接舷俘获）钉死。
- `Dictionary.merge` 默认不覆盖→实体 hull/crew 被默认值吞掉（诱饵教学窗失效）；改强制覆盖。
- 业务改船员/船货后被 native 旧值覆写→业务后重建原生名册（Legacy 对 depart 同样重建）。
- 事实 id 不含进度里程碑→增长即"证据冲突"拒绝；id 带进度值。
- resolve-land 曾清空据点库存（误伤装载货源）；转场/双绑定实体重复；identify 查错层；`transfer-crew` 漏进白名单；CH20 买船未配员被离港门拒——均以真实门/见证暴露后修复。
- 60s runner 上限→走查拆分（save/restore 独立文件）+ 每tick快照节流。

## 已知限制（如实）

- 全仓回归 `wiring-repo-suite-01.json` 中 `test_autopilot_port_approach` 触及 runner 60s 硬上限被判超时；直接以 Godot 运行同一测试 **24断言/0失败 通过**——本机速度临界（3×36000 tick＋每tick取快照），与本批改动零依赖（该测试仅加载 native 模块）。超时证据按惯例保留，不改写为通过。
- 走查/类目测试使用**显式夹具**：位姿摆放（夹具起点）、任务资金拨付（fund/mint-grant 显式回执）、2× 速度倍数（引擎上限2.0）与静海——均记录于 `tests/story_walkthrough_support.gd`；到达/靠港/交货/俘获/账本/守恒全部真实结算。真实速度航渡由 sailing 类目测试证明（13960 tick 厦门→金门）。
- 战斗损伤经原生生名册损伤转换并由结算见证重核；真炮战循环属原生测试与第4步验收范围。
- **第4步未做**：正式入口全GPU与输入验收（首章→交棒→台湾→结局的实机录证）。
- 经济平衡、地区剧情深度、美术演出、火势分区接线均后置；合成 demo 仍标"非真实任务通关"且不写正式存档。
