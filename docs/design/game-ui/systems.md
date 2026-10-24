# 《一官入海》游戏系统与页面目录

日期：2026-10-22。交付对象：完整可点击网页UI原型与全部页面预览。此文件定义产品范围与页面职责；实际网页交互、视觉验收及Godot接入证据由各自交付记录说明。

## 唯一剧情来源

[郑芝龙剧本](../../narrative/zheng-zhilong-story.json)，版本 `v4-maritime-illustrated-2026-10-22`，六幕43场。已逐场核对正文、人物对白的正文表达、任务、戏剧决定与史料边界。未采用同目录旧稿作为当前剧情源。

源文件SHA-256：`29e7de2c9308548b37293630530a5f3f84187862ee290629dcd80eda5826e801`。

[机器可读目录](systems.json)包含30玩法系统、11底层系统、72页面、12页面组、13流程。每个玩法系统给出目的、机制、优先级、真实场景引用与页面归属；每页给出职责、布局意图、主操作和可预览状态。底层系统另列现有依据、设计目标、页面映射与验证边界。

## 本轮范围与优先级

72页都属于本轮网页UI交付，包括空状态、条件不足、受损、拒绝、在途和失败恢复等必要状态。P0／P1表示未来原生游戏实施顺序，不是本轮可省略页面的标志。

- P0共23系统：先形成可持续的接差、备船、出航、遭遇、战斗、救援、交割与安全恢复闭环。
- P1共7系统：实验室、史料编年、人物成长、深入招募、人情盟约、势力外交、家庭生活；同样需要本轮页面预览。
- 未增加P2系统。多人仅可作为另立范围的未来愿景，本目录不承诺联机功能。

这是由剧本推导的产品方案。目录出现某个页面，不表示Godot已实现相同业务。网页中的买卖、存档、装填、招募与关系变化使用独立演示状态，不能写入或冒充既有原生存档、库存或战役进度。

## 核心边界

1. 默认鼠标点海面定航向、易读风向与辅助转向；允许进阶微调，不将普通玩家锁在真实物理逆风中。
2. 粮水与载重以航段准备、风险提示和事件处理为界，不扩张为逐口饮水、硬核饥渴或全经济大模拟。
3. 船壳所有权、舰队指挥权、临时雇佣、盟友协作、托运货和争议原主分别记录。
4. 银两不混账：船用、工钱、分成、家用、旧损赔偿与待辨货有可回查去处。胜利和总收益不能抹去伤员、失援和未清赔付。
5. 人物态度依事件、诉求和未兑现承诺解释。阿旺、阿禾、杜七、田川氏、安东、依斯迈均可拥有独立决定，不能靠好感条一键归附。
6. 不设现代商城、抽卡、超自然技能和无来源传奇舰。家园是时代生活中的住所与家事，不在本轮扩张为领地建造。
7. 实验室沿用项目统一课题入口。静态参数图与网页预览不能作为真实GPU动态运行或正式游戏性能证据。

## 剧情与历史约束

当前43场的`choices`为空。行动安排页用于局部经营、战术执行与未来玩法方案比较，不能据此宣称已有分支战役；固定剧情步骤以“执行安排”呈现，不强造两个近义选项。

以下节点保持既定骨架：1624福松出生、1628正式受抚任游击、1630福松赴明、1633厦门受创与料罗湾、1635芝虎未归、1645赐姓改名与母亲赴明、1646父子分途及田川氏罹难。不得以一次失败、拒绝选项或关系数值将家变制造为惩罚分支。

阮老六、杜七、具体跨文化遭遇及1629湾口抗掠均含明确原创边界。湾口来犯者为混合掠夺团伙，不能把其身份等同所有日本人，也不能把原创战事宣称为确证郑氏抗倭战绩。同国籍商人、水手和武装集团按具体行为分别书写。

## 系统清单

| 系统ID | 系统 | 未来实施顺序 | 页面数 |
| --- | --- | --- | --- |
| career | 生涯与起航 | P0 | 3 |
| preferences | 设置与无障碍 | P0 | 2 |
| laboratory | 实验室与图鉴预览 | P1 | 2 |
| narrative | 六幕章场与剧情演出 | P0 | 5 |
| history | 编年与史料注 | P1 | 2 |
| navigation | 航行与海图 | P0 | 4 |
| weather | 风向潮候与航次风险 | P0 | 1 |
| encounters | 海上遭遇与临场交涉 | P0 | 1 |
| ships | 舰船状态、改装与维修 | P0 | 3 |
| fleet | 船队编组与协同 | P0 | 1 |
| cargo | 货舱与装载 | P0 | 1 |
| inventory | 背包、装备与重要物件 | P0 | 3 |
| character | 人物经历与能力 | P1 | 2 |
| crew | 船员名册与个人处境 | P0 | 2 |
| recruitment | 招募与雇用约定 | P1 | 1 |
| stations | 岗位与值守 | P0 | 1 |
| morale-pay | 士气、工钱与承诺 | P0 | 1 |
| gunnery | 海战炮击与船队号令 | P0 | 3 |
| boarding | 接舷与夺船 | P0 | 1 |
| damage-rescue | 战损、救火与海上救援 | P0 | 1 |
| settlement | 航次结算与分利账房 | P0 | 4 |
| port | 港口与锚地活动 | P0 | 1 |
| trade | 市场交易与隐蔽销货 | P0 | 3 |
| contracts | 委托、合货与契约 | P0 | 2 |
| dock-services | 船坞交易与出航补给 | P0 | 2 |
| journal | 任务日志与情报 | P0 | 4 |
| relationships | 人情、旧恩与盟约 | P1 | 1 |
| factions | 势力、外交与海令 | P1 | 5 |
| household | 家园、家书与下一代 | P1 | 6 |
| session-guidance | 暂停、存档、教程与失败恢复 | P0 | 4 |

## 底层系统与实现状态

另列11类底层系统于`underlyingSystems`，不增加第73个页面。它们提供30个玩法系统所需的输入、运动、渲染、调度、数据、保存、声音、路由和资源能力，通过`mappedPages`映射已有页面。

每项同时记录`existingImplementation`、`designTargets`、`evidenceDocs`与`verificationBoundary`。现有状态仅采用当前架构、研究与验收文档能支持的表述；“文档记录已有”不等于本轮重新运行验证，也不等于完整郑芝龙战役已经接入。设计目标不写成实现事实。

| 底层系统ID | 系统 | 当前依据状态 | 未来优先级 |
| --- | --- | --- | --- |
| foundation-input-camera | 输入、操船辅助与镜头 | 文档记录已有基础 | P0 |
| foundation-navigation-physics | 航行运动、海水采样与碰撞 | 文档记录已有实现与有限验收 | P0 |
| foundation-render-world | 海面、天气、地形与世界渲染 | 文档记录已有实现，验收范围有限 | P0 |
| foundation-fx-pools | 粒子、尾迹与短生命效果资源 | 文档记录已有独立池与批处理 | P0 |
| foundation-ai-fleet | 船只AI、导航与舰队调度 | 文档记录已有海战基础，新战役调度为目标 | P0 |
| foundation-story-events | 任务、对话、事件与战役数据 | 已有剧本数据与旧战役基础，新战役接入待实施 | P0 |
| foundation-save-recovery | 存档版本、原子保存与恢复 | 文档记录已有事务与Codec修正，新profile待设计 | P0 |
| foundation-audio | 音乐、环境声、对白与战斗声音 | 文档记录声音适配职责，完整音频覆盖未核验 | P1 |
| foundation-ui-localization | UI路由、文案、本地化与无障碍 | 原生路由与设置已有文档，72页整合和本地化为目标 | P0 |
| foundation-streaming-performance | 资源加载、LOD、生命周期与性能预算 | 文档记录已有缓存、LOD与裁剪，整场性能仍未达标 | P0 |
| foundation-laboratory-evidence | 实验室、研究登记与证据管理 | 已有研究宿主与登记合同，单项状态按证据区分 | P0 |

统一粒子与尾迹能力指共同的事件、接受时间、容量、诊断及销毁合同；各效果仍保留自己的资源所有者。禁止以一个总管混合炮火粒子、船员、伤害和水面历史。

资源加载、LOD和性能分别验收。2026-10-21架构验收记录中，特定正式场景平均帧间隔为72.653ms，16.67ms目标未达；这是历史文档记录，本轮没有性能复测，不能外推72页网页、新战役或大舰队。新增流式方案、worker或GPU合批也不能只因出现在目录里而称为已实现。

## 游戏主循环

玩家先在日志、家书或港口取得当前目标与委托，核对承担者、条件和未清事项；随后检查人、船、货、银，完成岗位、配载、补给与航路筹划。海上按已知风潮航行，遇船后辨认、交涉、规避或应战；海战与海险均要处理救援、损船、伤员和撤离。

返港以后依次交割、辨明战利所属、核算净余、分利、赔付、支付工钱与寄回家用。新资源、新风险和已经发生的人情后果进入下一航；安全保存后推进章场。全程可以查编年与史料，不能以利润、胜利或好感一次清除已经发生的损失。

不同幕改变主循环的权责：早年先求别人的船位，中段与独立盟船协作，受抚后承担官旗与商路责任，末年面对家庭与组织分流。主循环保持相通，人物立场和可支配资源不自动恢复到初态。

## 实施顺序与当前交付

- 当前阶段只做网页原型：30玩法系统、11底层系统的解释与映射，以及72页的导航、布局、关键状态、可点击流程和全部页面预览。所有页都要可评审，不能因P1而省略。
- 未来第一阶段先收敛输入、路由、事件、存档和唯一时间合同，再完成澳门起航、一个港口、备船、航行、遭遇、返港、交割与正常Continue的最小原生闭环。
- 未来第二阶段扩展舰队、炮击、接舷、救援、争议货和人船结算，逐场接入剧本真实任务凭证，保留固定剧情后果；新算法先按研究流程建立独立对照。
- 未来第三阶段补齐P1的人物成长、深入招募、关系、势力外交、家园家书与编年体验，逐一验证人物自主和未清承诺。
- 每一原生阶段都单独过GPU、资源释放、导出和同负载性能门槛；大舰队、长时炮火和完整战役验收不由本轮网页演示代替。


## 全部页面

`kind`用于表达页面语义与布局需求，不是要求把所有页放进同一套换标题模板。海图、船体、舰队阵位、货舱、名册、装填、接舷、账册、家书和家园应有不同主体；共用导航、色彩、字号和交互反馈仍保持一致。

### 起航与系统（9页）

- `main-menu` — 一官入海 · 主菜单
- `new-career` — 新生涯
- `load-game` — 载入生涯
- `settings` — 航行与声音设置
- `accessibility` — 无障碍与阅读
- `laboratory` — 航海实验室
- `experiment-detail` — 实验课题与对照
- `pause-menu` — 暂停
- `save-game` — 保存生涯

### 章场与叙事（6页）

- `chapter-select` — 六幕章场
- `scene-briefing` — 章场简报
- `dialogue` — 人物对话
- `decision` — 行动安排
- `history-notes` — 史料与创作边界
- `ending` — 未回的船 · 终章

### 航行与海图（6页）

- `sailing-hud` — 海上航行
- `sea-chart` — 东洋航海图
- `destination-detail` — 目的地与靠泊
- `route-plan` — 航路筹划
- `weather-wind` — 风信与潮候
- `sea-encounter` — 海上来船

### 舰船与货舱（6页）

- `ship-overview` — 舰船总览
- `fleet` — 船队编组
- `ship-refit` — 舰船改装
- `ship-repair` — 船坞维修
- `cargo-hold` — 货舱装载
- `shipyard` — 船坞与船型

### 物品与人物（5页）

- `inventory` — 随身行囊
- `item-detail` — 物件与来处
- `equipment` — 装备与工具
- `character-profile` — 一官 · 人物经历
- `character-growth` — 本领与阅历

### 船员与生计（5页）

- `crew-roster` — 船员名册
- `crew-detail` — 船员与约定
- `crew-recruit` — 招募与雇期
- `crew-assign` — 岗位与值守
- `crew-morale` — 士气与薪酬

### 海战与救援（7页）

- `battle-hud` — 海战态势
- `battle-orders` — 令旗与舰队指挥
- `ammo-loading` — 弹药与装填
- `boarding` — 接舷争夺
- `battle-damage` — 战损与救援
- `battle-result` — 海战结果
- `prize-distribution` — 战利与分利

### 港口与贸易（7页）

- `port-hub` — 港口街巷
- `market` — 港口市场
- `trade-order` — 成交清单
- `contract-board` — 货栈委托
- `contract-detail` — 约定与交割
- `black-market` — 隐蔽锚地与销货
- `supplies` — 出航补给

### 日志与见闻（5页）

- `quest-journal` — 航海日志
- `quest-detail` — 任务与后果
- `chronicle` — 海上编年
- `intelligence` — 情报与航路见闻
- `relationships` — 人情与旧约

### 势力与海令（5页）

- `factions` — 海上诸势力
- `faction-detail` — 势力与来往
- `diplomacy` — 交涉与盟约
- `sea-permits` — 令旗与通行凭据
- `bounty-board` — 追索与悬赏

### 家园与家书（6页）

- `home` — 两岸家园
- `family` — 家人与彼此的路
- `child-growth` — 福松、森与成功
- `letters` — 家书匣
- `letter-detail` — 一封家书
- `send-letter-remittance` — 寄信与家用

### 结算与辅助（5页）

- `voyage-result` — 一航之后
- `accounts` — 船上账房
- `tutorial` — 掌船手册
- `defeat` — 航次受挫
- `notification-log` — 船上消息

## 流程覆盖

- 澳门首航：接差、配载、抢潮与货损：`main-menu`、`new-career`、`chapter-select`、`scene-briefing`、`dialogue`、`contract-detail`、`cargo-hold`、`crew-assign`、`route-plan`、`weather-wind`、`sailing-hud`、`battle-damage`、`voyage-result`、`quest-detail`、`save-game`。
- 到港经营：交割、交易、补给与再出航：`port-hub`、`contract-board`、`contract-detail`、`market`、`trade-order`、`cargo-hold`、`supplies`、`ship-repair`、`route-plan`、`sailing-hud`、`voyage-result`、`accounts`。
- 借他的旗：索路、反制、夺船与争议货：`sea-encounter`、`dialogue`、`decision`、`equipment`、`battle-hud`、`boarding`、`battle-result`、`prize-distribution`、`ship-overview`、`inventory`、`item-detail`。
- 聚众与生计：雇用、岗位、分利与自主离队：`crew-recruit`、`crew-detail`、`crew-roster`、`crew-assign`、`crew-morale`、`accounts`、`relationships`、`dialogue`。
- 护粮失援：船队调度、损船与未清赔付：`fleet`、`contract-detail`、`battle-orders`、`battle-hud`、`battle-damage`、`battle-result`、`voyage-result`、`crew-detail`、`accounts`、`relationships`。
- 跨文化航路：来船、凭据与互利脱险：`sea-chart`、`destination-detail`、`intelligence`、`sea-encounter`、`dialogue`、`diplomacy`、`sea-permits`、`crew-morale`、`ship-repair`、`accounts`。
- 两次受抚与同旗纠纷：`factions`、`faction-detail`、`diplomacy`、`dialogue`、`sea-permits`、`bounty-board`、`sea-encounter`、`boarding`、`battle-result`、`relationships`、`chronicle`。
- 湾口救援：截击、停火、接舷与接回人质：`history-notes`、`scene-briefing`、`sea-chart`、`fleet`、`battle-hud`、`battle-orders`、`ammo-loading`、`boarding`、`battle-damage`、`battle-result`、`ship-repair`、`accounts`。
- 料罗湾：集结、候风、火攻与兑现接应：`scene-briefing`、`intelligence`、`fleet`、`ship-refit`、`supplies`、`weather-wind`、`battle-orders`、`battle-hud`、`ammo-loading`、`battle-damage`、`battle-result`、`relationships`、`chronicle`。
- 两岸有家：通信、家用与下一代成长：`home`、`family`、`letters`、`letter-detail`、`item-detail`、`send-letter-remittance`、`accounts`、`child-growth`、`dialogue`、`chronicle`。
- 1646分途：各人的决定与未回的船：`chapter-select`、`scene-briefing`、`family`、`dialogue`、`relationships`、`fleet`、`crew-detail`、`accounts`、`ending`、`history-notes`。
- 学习、暂停与恢复生涯：`settings`、`accessibility`、`tutorial`、`sailing-hud`、`pause-menu`、`save-game`、`defeat`、`load-game`、`notification-log`。
- 实验室：可见对照与证据边界：`main-menu`、`laboratory`、`experiment-detail`、`settings`。

## 结构验收记录

2026-10-22执行JSON解析及交叉引用检查，结果通过：

- 玩法系统ID唯一30个，底层系统ID唯一11个，页面ID唯一72个，页面组12个，流程13个。
- 每页恰好归属一个系统；系统页面清单与页面上的`systemId`双向一致。
- 所有系统、页面、流程中的`storyRefs`均来自唯一剧本的真实场景ID；页面引用覆盖43／43场。
- 所有流程页面均存在；页面职责、主操作、状态与布局语义字段完整。
- 底层系统全部映射已有页面；所有证据文档路径存在，并将已有实现与设计目标分别记录。
- 未新增或执行原生游戏业务；本记录不代替网页实际点击、屏幕截图及视觉检查。

