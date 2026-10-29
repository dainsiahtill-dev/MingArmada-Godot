# 剧情示例 UI 与 1650 正式界面接入清单

日期：2026-10-27。前半为只读源码、JSON、文件存在性清点；末节记录随后完成的第一处真实 UI 接入及 headless 验证。没有修改剧情、业务、存档或原型。父任务已确认 CodeGraph 无索引，本清点使用 RTK 回退。清单中的“入口可达”表示源码路由与 consumer 连通；本文件未将 headless 结果当作 GPU 或用户操作实机验收。

## 当前有效的三套材料

| 材料 | 当前真实 artifact | 使用边界 |
| --- | --- | --- |
| 郑芝龙文学正文 | `docs/narrative/zheng-zhilong-story.json`，版本 `historical-reboot-illustrated-2026-10-24`；六部 22 章，canonical ID 为 `zzl_*` | 约 1623 至 1646 年；不是 1650 林船长生涯。阅读器镜像及导出位于 `docs/narrative/zheng-zhilong/`。当前 README 明确游戏场景稿尚未实现引擎任务、分支或过场。 |
| 当前正文插图 | `docs/narrative/zheng-zhilong/illustration-manifest.json`，44 条；44 个相对路径均有实际 PNG；位于 `images/illustrated-2026-10-24/`，每章两图，含 `sceneId`、`afterParagraph`、caption、alt、尺寸与哈希 | 当前消费者为阅读器 `app.js`。本次在 `game/**/*.gd`、`game/**/*.tscn` 没有找到正文 JSON、插图 manifest 或该图片目录的引用。文件存在不代表 Godot 演出接入。 |
| 游戏 UI 示例目录 | `docs/design/game-ui/systems.json`；30 系统、72 页、12 页面组、13 流程；实现位于 `prototype/`，72 个 `previews/<page>.jpg` 均存在 | `prototype/data.js` 实际登记旧版 `v4-maritime-illustrated-2026-10-22`、43 场及 `legacy-ui-simulation-not-new-mainline`。演示状态不读写 Godot 存档；不能将 72 页称为正式游戏 72 页。 |
| 原型专用图像 | `prototype/assets/` 中有 main-menu-v2、port-hub-v2、crew-portraits、fishing-ship、merchant-barque、zheng-portrait、fuchuan-inspection、sailing-background 共 8 个专用 PNG | 前 6 项来源在 `ui-art-adoptions.json`；福船与航行背景来源分别在 `ship-art-provenance.json`、`sailing-art-provenance.json`。记录声明渔船、商船、郑芝龙和福船图为透明底。该记录不替代本次 alpha 解码/边缘复核。 |
| 生产资源目录 | `assets/production/<分类>/<资产>/asset.json`、README、reference；例如人物图集、郑芝龙立绘、契约道具和海图参考 | 大量 `reference` 是原型 PNG、小说插图或 UI 截图副本；不是已完成原生 UI。`production-assets.json.twoDimensional` 的 13 类仍是旧 43 场建议预算，含“目标头像/纹理/图标”等待制作项，不能按 count 宣称现货。 |

`systems.md`、`prototype/README.md` 保留旧版/五幕版说明；当前正文已经六部 22 章。后续接入以实际 JSON、manifest、consumer 为准。不要重新构建原型来冒充剧情已同步：`tools/game-ui-story-baseline.mjs` 的版本分支还需单独审计，它只在 five-act-rewrite 时强制冻结旧 43 场；本报告未改该工具。

## 真实 1650 入口与剧情 consumer

主菜单 `mingqi` 请求经过 `game/runtime/game_router.gd`，装载 `game/scenes/mingqi/mingqi_scene.tscn`。场景创建 `MingqiRuntime` 和 `game/ui/mingqi/mingqi_interface.gd`；新航程在 `_ready()` 中默认 `open_panel("story")`。

正式剧情源为 `game/domain/mingqi/opening_story.gd`，与郑芝龙文学 JSON 独立：

- chapter：`opening-1650` / **旧账新帆**。
- `old-ledger`：**旧账与工钱**，许福；旧债与先结工钱/保留应急银。
- `pilot-plan`：**粮船走哪条路**，陈阿海；付费规划浅水路/深水外线，保留免费逐船选路。
- `first-return`：**第一趟交差之后**，林账房；读取真实首航交差后，选择分红、情报或留本。
- `second-return`：**第二趟交差之后**，`second_voyage_aftermath.gd` 在第二合同真实 claim 后投影；偿债目标/核验船员分红/留本。

`OpeningStory.project(state)` 生成 `story.chapter/objective/scenes/relations/history/debt/flow`；`MingqiRuntime._eligibility()` 给出安全港、锚泊与场景可执行性。UI `_build_story()` 消费投影，发送 `{type:"story-choice", sceneId, choiceId}`，偿债发送 `{type:"repay-debt", quantity}`。持久权威是业务回执、chronicle 与存档校验，贴图不得推动剧情、扣款、发奖或自行补出完成状态。

现有六个正式 panel 为 `ship/convoy/port/boarding/tactics/story`。清点时该 consumer 仍直接使用旧郑氏船长图和厦门港小图；没有找到许福、陈阿海、林账房专用素材。不要用郑芝龙、阿旺或旧六人头像图集冒充这三位 1650 NPC。

## 72 页到正式 consumer 的映射

下面是可承接职责的映射，不是已经复制对应原型页面。每组完整页面 ID 仍以 `systems.json.screenGroups` 为准。

| 原型页面组 / 页数 | 代表页面 ID | 当前真实承接点 | 缺口 |
| --- | --- | --- | --- |
| 起航与系统 / 9 | main-menu、new-career、load-game、settings、laboratory、pause-menu、save-game | 正式主菜单、设置、实验室、Mingqi 航程菜单与存档恢复 | 无障碍、独立新生涯等原型页不是逐页原生实现。 |
| 章场与叙事 / 6 | chapter-select、scene-briefing、dialogue、decision、history-notes、ending | `story` 的上述四个 1650 场景、选择与历史回执 | 无 `zzl_*` 22 章任务/过场；无整部章场选择或郑芝龙终章。 |
| 航行与海图 / 6 | sailing-hud、sea-chart、destination-detail、route-plan、weather-wind、sea-encounter | HUD、`convoy` 实时海图与逐船选路，厦门/金门/近岸补给点 | 完整东亚、潮候预测、原型海上交涉等未接；不得画出虚构可用航路。 |
| 舰船与货舱 / 6 | ship-overview、fleet、ship-refit、ship-repair、cargo-hold、shipyard | `ship`、`convoy`、`port` 的船况、货物、修理、帆装改造 | 无原型整套船坞买卖/新船生产。 |
| 物品与人物 / 5 | inventory、item-detail、equipment、character-profile、character-growth | 尚无同等独立正式页面 | 随身背包、人物装备与郑芝龙成长不能从货舱/船务推定存在。 |
| 船员与生计 / 5 | crew-roster、crew-detail、crew-recruit、crew-assign、crew-morale | 人员桶、关键人物与剧情关系投影，治伤/工钱/分红 | 完整个人名册、招募、雇期、岗位与自主离队页面尚缺。 |
| 海战与救援 / 7 | battle-hud、battle-orders、ammo-loading、boarding、battle-damage、battle-result、prize-distribution | `ship` 炮击、`tactics`、`boarding` 与真实伤亡/俘获回执 | 原型页的完整戏剧战役、特定搜救与分利条件不能整体推定已接。 |
| 港口与贸易 / 7 | port-hub、market、trade-order、contract-board、contract-detail、black-market、supplies | `port` 靠泊和粮食买卖；`convoy` 两份护粮合同 | 多商品市场、黑市、街巷/独立补给页未接。 |
| 日志与见闻 / 5 | quest-journal、quest-detail、chronicle、intelligence、relationships | `story` 当前目标、记录、三人立场；一次真实粮食情报 | 完整任务/编年/关系图/多来源情报系统未接。 |
| 势力与海令 / 5 | factions、faction-detail、diplomacy、sea-permits、bounty-board | 剧情声望字段与现有阵营政策为有限依据 | 没有对应五页的完整外交、通行证与悬赏玩法。 |
| 家园与家书 / 6 | home、family、child-growth、letters、letter-detail、send-letter-remittance | 1650 六页无同等 consumer | 均属后续新领域合同；不应在首批仅换皮时开放虚假寄信/家用。 |
| 结算与辅助 / 5 | voyage-result、accounts、tutorial、defeat、notification-log | `story.flow`、真实交差账单/旧债、反馈与航程恢复 | 家用、赔付、争议货等完整分账尚缺；真实现银、伤亡与到账范围必须继续明确。 |

## 首批三处：服务当前 1650 航程

统一美术基准为 `assets/ui/ming_maritime/menu-painting.png`。新图使用同一港景绘画、木/布/墨色和光线，生成透明 PNG 后与真实 Control 组装。正文、金额、禁用理由、航线、完成态由代码绘制；装饰 `MOUSE_FILTER_IGNORE`。不得把界面截成一张白色程序面板或把按钮/文字烘焙进图。

| 顺序 | 原型借鉴 / 正式落点 | 精确内容锚点与 consumer | 建议生图资产 | 验收动作 |
| --- | --- | --- | --- | --- |
| P0-1 | dialogue、decision、relationships；正式 `story` | `OpeningStory._scene_text()` 中 `old-ledger` 的第 1–2 条、`pilot-plan` 第 1–2 条、`first-return` 实际结果后对白；`project().scenes[].npc/text/status/choices`；`MingqiInterface._build_story()` 的 `story_scene_<id>` | 许福、陈阿海、林账房各一幅独立透明半身立绘；小块绢布/书案边件。保留完整头手与可读轮廓，人物不压正文/操作区。`second-return` 是账单，避免强配人物。 | 主菜单新航程直接见旧账；接单后见领航谈话；首航 claim 后见林账房。逐一检查 locked/available/completed，扣银与回执只发生一次；离港仍可读日志，但危险或未锚定不可付款。 |
| P0-2 | voyage-result、accounts；正式 `story` 的往航与二航账册 | `first-return` 的 `_scene_text()` 首条；`VoyageFlow.project().settlements`；`SecondVoyageAftermath.project().bill/scene`；UI `_story_bill()`、`_voyage_bill_text()`、`_build_voyage_flow()` | 透明摊开账簿、算盘/系绳钱袋等有限物件与账页框；数据区保留安静底色，不生图文字与金额。使用真实现银/本金/受益人数和回执日期状态。 | 首航全交/部分交付/失败；二航 20 粮 claim 后比较分红/留本/偿债目标；验证“本次仅承运船”范围、旧伤为当前伤员，非本航新增；重复打开和存档恢复后金额/选择不变；未核验人员不能分红。 |
| P1-3 | contract-board、contract-detail、route-plan、scene-briefing；正式 `convoy` | `pilot-plan` 第 1–2 条；`OpeningStory._supply_plan()`；`MingqiInterface._build_convoy()` 的 `contract_accept_<id>`、`contract_claim_<id>`、逐船 `choose-route`；`story.objective` 跳转 | 透明货栈告示/委托纸签、粮袋和小型红帆船剪影。真实海岸、港位、船位与航线继续由 `mingqi_chart.gd` 绘制；不生图虚假地理。 | 源头两份合同与当前状态一致；45 两规划与免费逐船选路同时可理解；过浅路线被真实吃水限制；未接受/装载中/在途/待交差/损失可区分；第二合同仅由实际首航结果开放。 |

## 文学插图的后续接入锚点

44 幅现图宜用于后续独立的“郑芝龙史传”阅读/回顾 consumer，或在明确实施对应历史场景时使用。不要插进 1650 原创谈话并改称林船长经历。可优先审阅这些已有图与正文因果：

- `zzl_a1_s1` 唐船来处：`zzl_a1_s1_01` 在第 2 段后，`_02` 在第 13 段后；卸货、译钱与不能擅许船期。
- `zzl_a2_s1` 破桅归港：`zzl_a2_s1_01` 在第 3 段后，`_02` 在第 10 段后；船损、借欠与船员应得所得。适合未来船务/账房叙事，但不是现有 1650 欠薪事实来源。
- `zzl_a3_s2` 别人的甲板：第 6/12 段后两图；交割条款、独立船主与离队。适合未来契约界面，不能把旧图中的荷方交易当当前护粮合同。
- `zzl_a6_s2` 粮走不到的地方：第 1/16 段后两图；运输、欠饷、拒助与安置。属于 1645–1646 文学剧情，不能借图片存在宣称陆路运输或家庭安置玩法已实现。

接入每一处时，独立确认：使用哪个图、哪个当前场景 ID、谁消费、何时可达、数据来自哪个权威 snapshot、动作送往哪个原生产合同。真实入口 GPU 连续画面、窄屏阅读/滚动、焦点、遮挡、透明点击和存档恢复需在实施后执行。本清点只确定实施位置与验收合同。

## 第一处已接入：许福的旧账谈话

P0-1 **部分实现**：`game/ui/mingqi/mingqi_interface.gd::_build_story()` 通过 `_story_portrait_header()`，真实消费 `assets/ui/ming_maritime/painted/portrait-xufu.png`。素材为 1086×1448 RGBA，实读 alpha 0–255；本轮已目视独立原图。来源与人物解释边界见本目录 `ASSETS.json` / `ASSETS.md`。陈阿海、林账房及账册/委托后续落点仍未实现。

展示条件是 `old-ledger`、状态 `available`、当前原生 `npc.name == "许福"` 同时成立。完成态和锁定态没有这张当前谈话立绘；同一 generation 内姓名变化也会及时隐藏，恢复真实姓名后重新显示。图高 156px，与原生姓名/身份组成小头部，正文和选择继续占原阅读区完整宽度，未扩大原 440px 阅读框。图像和头部 `MOUSE_FILTER_IGNORE`，图像不获焦点、不连接命令。原 `story_npc_`、`story_dialogue_`、选择名称、`_story_choice_ok`、回执与 runtime 资格合同未改。

专用测试 `tests/test_mingqi_story_portrait.gd` 先 RED：17 断言、2 失败，失败仅为尚无许福立绘；实现后最终 GREEN：**27 断言、0 失败**。覆盖真实 PNG/alpha、紧凑高度、透明边缘点击无命令、320×480 横向可达、同 generation 改名、locked/completed、unsafe 付款门禁，以及原按钮通过真实 Runtime 支付 80 两后生成完成回执。既有 `test_opening_story_ui.gd` **59/0**、`test_opening_story_ui_runtime.gd` **39/0**。本次未重复运行全 195 项 UI 测试。

命令使用 `rtk proxy node docs/design/2026-10-25-parchment-ui/run-check.mjs --headless --script res://tests/<测试名>.gd`。本地日志位于 `Temp/story-portrait-red.log`、`Temp/story-portrait-green.log`、`Temp/story-portrait-opening-ui.log`、`Temp/story-portrait-runtime.log`。GPU、真实 MainScene 进入后的构图、操作系统输入及原存档恢复仍由主任务统一验收；这些边界不由上述 headless 测试代替。
