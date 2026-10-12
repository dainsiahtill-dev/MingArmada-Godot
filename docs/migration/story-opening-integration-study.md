# 1650 开局剧情与航程闭环：只读源码审计

日期：2026-10-11。按最新分工，海岛/岸线/海面参考逆向交由外部 REA Agent，本地团队转向剧情等方向。本轮只读核查 Godot 现有 domain/runtime/UI/save，不改生产、不执行 GPU、不写用户存档，也不重新查询无索引 CodeGraph。

## 结论

现在适合先做**《旧账新帆·四十袋军粮》**：让已有1650两段真实护粮委托成为有角色、有原因、有后果的开局。现有系统已经能支付租费、实装粮食、选深浅航路、指挥租用旗舰/快船、面对真实炮舰、交粮按实际货物/时间/人物存活结算，再接下一次补给运输。缺少的是把这些状态组织为明确的故事节点与人物反馈，而非另造任务完成按钮。

1650与1661是两条独立已迁移业务路径。当前1650更符合用户提出的青年船长、旧账、继承商船和商路战争目标；1661的六章任务、决斗、陆战、寻宝和宴会可作为后续复用系统，不能直接把1661进度字段塞进1650存档。

## 核心源码与接口

| 入口 | 实际接口/职责 | 剧情接入意义 |
| --- | --- | --- |
| [Campaign](../../game/domain/mingqi/campaign.gd) | `_init(seed, captain_name, campaign_id)`；`snapshot()`；`command(input, context={})`；`advance(seconds, near_ids=[], context={})`；`evaluate_convoy(id)`；`serialize(utc)` / `restore(json)` | 1650纯领域权威，拥有货物、人员、关系、任务、收据与纪事 |
| [Catalog JSON](../../game/domain/mingqi/catalog.json) / [运行常量](../../game/domain/mingqi/catalog.gd) | 三港、profiles、四条 routes、七个 roles、spawn | 剧情须说清自有/借用船与路线吃水，不能把所有可指挥船都写成自有 |
| [MingqiRuntime](../../game/runtime/mingqi_runtime.gd) | `configure(height_sampler, session=null)`；`command(input)`；`advance(frame_seconds)`；`snapshot()` / `render_snapshot()`；`export_save(utc)` / `save_checkpoint(storage, utc)` / `adopt_save(json, storage=null, utc)` | 提供真实原生上下文、暂停、快进、人员/船体同步和安全保存；UI只发意图 |
| [NearFieldBridge](../../game/runtime/near_field_bridge.gd) | `capture()`、`command_context()`、`near_ids()` 与权威投影/同步 | 真实海战结果进入领域；脚本不能伪造胜利、伤亡或抵达 |
| [MingqiInterface](../../game/ui/mingqi/mingqi_interface.gd) | `command_requested(intent)`；`apply_snapshot(packet)`；护粮、路线、战术、战利船、治伤、维修、纪事与存档面板 | 现有操作全部可复用，新增故事表现消费快照与收据 |
| [MingqiScene](../../game/scenes/mingqi/mingqi_scene.gd) | 接上述信号、运行时、保存/菜单生命周期 | 对话显示/暂停与关闭返回属于场景接线，不能另起模拟循环 |
| [SaveCodec](../../game/domain/persistence/save_codec.gd) | `encode(state, utc)` / `decode(json)`；严格v2结构/引用/收据关系验证 | 新剧情持久字段、债务变化和章节扩展必须同时更新验证与迁移 |
| [SaveCoordinator](../../game/persistence/save_coordinator.gd) | `read_checkpoint()`、`read_backup()`、`write_checkpoint(json)` | staged/flush/读回/rollback/备份，失败不采用新状态 |
| [GameRouter](../../game/runtime/game_router.gd) | `prepare_entry`、`prepare_recovery`、`commit_import`、`create_scene`；generation/nonce/operation | 保持1650与1661入口和槽位隔离，迟到回调不能跨航程落地 |
| [Legacy AdventureSession](../../game/domain/legacy/adventure_session.gd) | `snapshot`、`command`、`preview`、`advance`、`accept_quest`、`complete_quest`、`serialize`、`restore/from_json` | 已有1661主线和经济规则，可选迁移思路，不是1650同一session |
| [LegacyRuntime](../../game/runtime/legacy_runtime.gd) / [EncounterCoordinator](../../game/runtime/legacy_encounter_coordinator.gd) | 同步native、隔离候选命令、海战/遇敌暂停、投降确认、安全存档；四种遇敌实际模型的启动/行动/结算 | 后续若把遇敌带入1650，应定义1650权威适配，不能复用一份状态偷偷改两种存档 |

所有接口均由当前实际源码核查，不是猜测的网页层类名。没有独立统一 `story/quest/session` 新架构；1650的任务当前就在 Campaign，1661的任务就在 AdventureSession。

## 当前1650确实已有的故事状态与闭环

开局日期1650-01-01，船长出生1631；650两银、林家400两债、到期18000模拟秒。自有船为**继承商船承家号**，初始12名可用船员；操作旗舰是林家的**借用福船明旗号**，快船逐浪号也属林家。粮船甲乙各有管事，人与船分别保存。原生开局会把普通停泊的承家号从活跃海战对象中排除，仍留在领域状态；不要用“起步就拥有一支军舰队”掩盖这层区别。

首程 `convoy-001`：

1. 在厦门 `accept-convoy`，支付50两租费、厦门库存扣40粮、两粮船各装20；已支付租费进入收据。
2. `depart` 验旗舰权利、安全锚地、船况、最低船员与原生上下文，实际改变航程/帆速状态。
3. `choose-route` 在对应航程的真实路线中选择，按实际载货吃水拒绝过浅路线；深路/外路8米，浅路2.4米。两船满载20粮的吃水为1.6米；旗舰基础吃水3.2米，不能把浅路描述为整队无条件都能走。
4. 近场模拟提供真实位置、伤害与命中；远处航线数据推进。抵达25米内且速度≤0.75才实卸货物并记录 `shipment-arrived`，沉船则记录货损。
5. `claim-convoy` 只能在航程全部抵达/损失后结算。基础报酬为实际交粮×10；40粮全交、最后抵达不晚于1800秒、两管事存活，额外100两。满交可得500两；部分/迟到保留实际交粮报酬。
6. 结算改变 `merchantCredit`，奖金合格+5、存在交付但奖金不合格+1；实际收据保存粮食、伤员、死亡、人员转移、船况及管事存活。
7. 首程只要有实际交付，便创建 `convoy-002`。在金门安全锚泊、两粮船可用/空舱、港存粮足20后，可实装各10，复用已付租船运往近岸补给点；全量/准时/人物条件奖金50，满交250两。

此外已有买卖、修理、改装、治伤、接舷、押船人员分配、放俘、转移货物、弃船救人、售船/编队，以及 `chronicle` 的原因ID和去重收据。因此剧情可引用“这一次怎么赚到钱、失去了谁、夺到的船是否有人能开”，而不是一律套固定台词。

## 已有1661内容，保持独立

[Legacy catalog](../../game/domain/legacy/catalog.gd) 的主线为：**金门军粮 → 护航澎湖 → 东山剿寇 → 三岛密图 → 夺取航海密令 → 逐浪台湾**。最后一章包含鹿耳门守舰和岸上炮台，再回金门报告。`mainChapter` 随真实可结算任务推进，完成六章后仍可经营或退休。

`AdventureSession` 已有可重复委托、库存价格、补给/军饷、关系、军官、职业成绩和退休文字结局；`LegacyEncounterCoordinator` 拥有决斗、陆战、寻宝、宴会的实际模型，UI不能提交任意成功/奖励。已有“投降后损失和返港”的运行时事务，不等于1683的政治归顺结局已完成。

这些是当前已有系统；**郑成功去世后的长期章节、郑经/郑克塽阶段、1683不同政治结局与完整台湾复合战役仍不能宣布完成**。

## 需要补的故事闭环

- **1650章节尚不推进。** `chapterId` 当前只为 `opening-1650`；两段委托是业务链，没有开场、角色关系、剧情节点与阶段收束。
- **债务是显示状态。** 本轮在19个命令和推进逻辑中未见偿还/展期/催债结算；到期不会自动产生已实现的剧情。只能说已有债务背景，不能说已经可还债。
- **人物反馈不完整。** 两管事有存活字段，收据有伤亡明细，但没有基于这些结果的分支对话、旧账册线索、信任承诺或副船长提拔。people schema 虽允许 pilot/deputy，不代表已有招募/提拔闭环。
- **失败后的下一步缺少故事组织。** 首程完全零交付会失败且不解锁第二委托；需要给修理/治伤、商行态度、继续经营或安全读档明确出口，不能让玩家只剩灰色任务按钮。
- **自由贸易仍需诚实表达。** 当前1650货物枚举有12种，但实际首程主要围绕粮食；不要仅凭 GOODS 数组承诺已完成十二种商品的剧情与经济配置。
- **“已到达”与“玩家回港交差”应明确。** 当前交粮收据来自真实粮船抵达，而 `claim-convoy` 本身未强制玩家就在指定港。若剧情希望面见金门接粮官，应新增领域地点条件或让台词明确为海上信差/账单，不能只UI表演回港。
- **结算后的纪事有内容，玩家引导不足。** 当前面板能领取真实报酬、再接补给，但缺醒目的下一目标、人物后果与值得再次出海的理由。

## 存档边界：故事新增必须同时处理

v2 `SaveCodec._state_schema` 硬限制：chapter仅`opening-1650`；债务principal固定400、creditor固定house-lin、dueAt固定18000；contract仅convoy-001/002；纪事kind仅既有收据名单。额外字段也受结构限制。

因此有两条合理的实施层次：

1. **先做可派生故事表现。** 用已有状态/收据推导开场、起航、遭遇、交差、失败/成功后果，`story_projection(state)` 返回固定节点ID、正文、真实目标/结果、可发既有意图。不新增独立保存文件或写第二份任务状态。载入后按权威状态恢复相应故事阶段，历史收据用稳定ID识别。
2. **再做有实质后果的新选择。** 偿债、承诺、提拔、副船长或新的章节必须由 Campaign 新命令验证并写状态；同时明确扩展/迁移SaveCodec、旧v2可选字段默认、收据关联与防重复。UI按generation/revision发意图，失败保持原状态。新的保存信息只能随现有同一checkpoint事务提交。

不要为了赶剧情将严格存档验证关闭，或把故事进度写到用户设置/另一个JSON后形成两份权威。现有1650 `user://saves/mingqi-v2.json` 与1661 `user://saves/legacy-v1.json` 保持版本路由隔离。

## 推荐开局：《旧账新帆·四十袋军粮》

这是基于当前本作状态的新原创故事建议，不声称来自原《海盗》剧情或史料。

**第一场：账册与借船。** 厦门码头的林管事递来父辈账册：承家号归你，但400两旧债也归你。林家愿借明旗号与逐浪号做一趟护粮，50两是明确租费，不是买下军舰。两名管事各随一艘粮船，既核账，也让玩家记住需要保护的是人。

**第二场：装粮与选择。** 显示实际库存、两船各20粮、租费后的600两。提示深路、浅路和外路的取舍；领航建议是可理解的吃水/危险信息，依据真实地图与状态，不凭一句选项改变船物理。第一趟用现有 assisted 手感和可暂停战术，让玩家先学会保住粮船。

**第三场：商路成战场。** 实际敌炮舰接近后，短对话指出“追敌会暴露粮船”；提供可发既有意图的目标提示：护送/保持队形、让浅吃水船绕行、快船牵制，或旗舰迎击。胜利以粮食抵达为核心，可甩开敌人；故事观察实际事件，不在对话结束时直接删敌或交任务。

**第四场：交的是粮，也是人。** 从真实 convoy 收据生成三种反馈：全交且两管事存活，林家给500两并承认信用；部分/迟到，只支付实际交粮的钱并指出损失；零交付，保留真实伤员/损失，给修理、治伤和重新谋生的明确出口。新台词不得把存活人物写死，也不得让已死管事回来结算。

**第五场：下一次出海有理由。** 实际有交付后，金门提出20粮送近岸补给点的委托。账册中新添的不是抽象经验，而是一笔可核对的实收和一段人情。当前版本可以展示“已经赚到可用于偿债的钱”；真正偿债和下一章节属于上面的第二层领域扩展，不能先在字幕宣布债务消失。

开局的成就来自一次出航推动商业、战斗、人员与下一委托。时间目标应由实际走完测得；本审计不凭纸面承诺已达到30–60分钟。

## 建议最小独占实现单元与验收

- 故事领域专家：新 `game/domain/mingqi/opening_story.gd` 与对应数据；先用快照/收据派生，输出 `stageId/sceneId/text/objectives/outcome/allowedIntents`，不改模拟。
- 故事界面专家：新 `game/ui/mingqi/story_panel.gd`，消费派生结果，只发既有意图；既有UI命令防重复和generation围栏保留。它不能直接修改Campaign。
- 主 Agent：正式场景信号/暂停/返回接线；若需要新的实质选择，独占Campaign/Codec/Runtime事务修改。

至少覆盖：新局第一场、接受后的真实扣款/装粮、拒绝后的状态保留、重复回调不重复支付、部分/迟到/管事死亡/全失败、读档恢复正确节点、返回重进、完整首程与第二委托入口、保存失败原子性。验证必须用正式命令/实际抵达或原生事件；不得造一份“成功任务”快照当成完整试玩。

现有可复用测试包括 `test_mingqi_rules`、`test_mingqi_live_projection`、`test_mingqi_runtime`、`test_mingqi_ui`、`test_save_compatibility`、`test_save_coordinator` 及v1独立回归。本轮未运行这些测试或重新试玩，故不引用旧断言数作为新的剧情验收。
