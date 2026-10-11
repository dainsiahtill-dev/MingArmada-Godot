# Godot 迁移：网页源码功能与资源盘点

调查日期：2026-10-11。调查方式：本地源码、Git 身份、清单与资源字节只读检查。未运行网页构建、安装、服务或浏览器；本报告不构成网页或 Godot 的运行验收。只新增本报告，未修改原网页。

## 1. 基线选择与完成边界

**迁移行为基线选开发工作树的已提交 `9ad6a44daecd4ec36a8172d83ff27493feffe5dd`，连同其固定依赖源码与资源。原主目录只作来源对照。**

| 对象 | 本次直接查到的身份 | 作用 |
|---|---|---|
| 原网页主目录 | `C:/Users/dains/Documents/Git/MingArmada`，HEAD `30b556d` | 较早网页；仅有 physics-core、scene-engine、realtime-client、shared、weapp-adapter 五个包；不能拿它覆盖后来新增的 naval/adventure 游戏 |
| 最新网页开发工作树 | `C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada`，HEAD `9ad6a44daecd4ec36a8172d83ff27493feffe5dd` | 本报告主要源码；包括当前 1650、1661 兼容、练习与 QA |
| 新 Godot 项目 | `C:/Users/dains/Documents/Git/ming-armada` | 独立目标；调查开始时有 `project.godot`、图标和 Godot 导入缓存 |
| 固定依赖来源 | `tools/workspace/source-lock.json` | 外层 Git 不足以表示三个独立依赖的完整源码，必须保存锁、完整源码清单和补丁 |

源锁文件本次 SHA256：`7842f18d67b5a03e93074bdbd96a7089e8cbc715068880afe4dcee902753a3f8`。

| 源锁包 | resolvedHead | sourceTree | 记录数 |
|---|---|---|---:|
| physics-core / SailingEngine | `c21948e1897151fbc7bd4e76aaf0f31e95f3c297` | `a4d9a62a9cb1af6d1206fe270d3e6aeb280a1b9f` | 50 |
| scene-engine / SeaBattleEra | `ce66b50c8a0c62c88920b5b6f796dc6dba03a752` | `fa368aef6698f44862726210728d71c46aa23509` | 31 |
| realtime-client / ArmadaClient | `471bb61a32d08ca62e3abb3d72ccc2d859e351c7` | `e704da4237b1fab92a510078be744d00d1786a4e` | 34 |

上表是当前源锁声明，本次没有重新重构依赖仓库验证；以后形成迁移快照时仍须比对实际源码及锁。直接文件哈希验证已确认：18 个船 GLB 与 3 个水手 GLB 全部符合各自 manifest。

当前网页工作区还有未提交内容：`MingqiScene.svelte`、`NavalSceneView.ts` 两个 tracked 文件，及 `MingqiShoreTransition*`、`NavalDeckSupport*` 等新增候选。它们须另行封存，**不混入已提交行为基线，不称作完整登岸玩法**。已提交 `3ef4d98` 的上岸场景接口报告明确说尚未接入上岸按钮、船长行走或跳板；本次入口搜索也未发现 `MingqiScene` 接入这些候选。`MingqiShoreGeometry/Walk/View` 文件存在，不等于玩家入口已完成。证据 R25、R26、R27。

Windows 下 `MingArmada` 与 `ming-armada` 因连字符不同，是两个独立目录；所有新源码、复制资源、测试、文档与工具都应落到后者。

CodeGraph 对开发工作树返回未建立索引，按规定使用 RTK 精确源码查询；未建立索引，未捏造 CodeGraph 结果。

## 2. 真实入口与支持状态

当前网页入口链为 `index.html` 的 `/src/main.ts`，再到 `App.svelte`、`GameEntry.svelte`、`MainMenu.svelte`。原主目录也走 Svelte 链，但缺少后来新增的规则包。旧 `main.tsx/App.tsx`、大量 React/TSX、Vue 经济面板、CombatHUD 同名副本，不能仅因存在就认定是当前游戏功能。证据 R01、R02、R03、R29。

| 玩家可达入口 | 当前源码行为 | Godot 迁移要求 | 证据 |
|---|---|---|---|
| 海上明旗新生涯 · 1650 | `MingqiShell`、`MingqiScene`、`MingqiRuntime`；厦金护粮开局 | 完整保留当前切片及规则边界 | R02、R03、R04、R05 |
| 继续海上明旗 · 1650 | 独立 v2 槽；缺失或读取受阻也可进入恢复/导入页 | 保留恢复入口，不能只在正常存档时展示继续按钮 | R03、R11、R12 |
| 旧版航程 · 1661 | `AdventureShell`、`AdventureRuntime`、`AdventureSession` | 全量兼容玩法，不能迁移时删除 | R02、R13、R14 |
| 继续旧版航程 | 存在 v1 槽时启用，载入仍要验证 | 保留 v1 JSON 路由与状态 | R02、R03、R14 |
| 单舰炮战 | 一个玩家对一个敌人，terminal 模式 | 真实操船、炮击、输赢、投降、重开 | R03、R16、R18 |
| 舰队遭遇 | 一个玩家对两个敌人 | 同上；不能以两条静态船模型替代 | R03、R16、R18 |
| 自由试航 | 无敌舰，风帆与操舵练习 | 原物理、水面、操船预设与设置 | R03、R16、R17 |
| 检阅船只 | 6 种船、3 个 LOD；加载 GLB 后旋转/检视 | 全部船型、LOD、帆装与控件 | R03、R19、R22 |
| 画面验收 | DEV 或 qa 构建才可达，真实模拟的重复场景 | Godot QA 等价入口；正式发行默认隐藏 | R03、R20 |
| 玩法验收 | DEV 或 qa 才可达；四种独立小游戏 | 四游戏都要迁移，练习不发放生涯奖励 | R02、R15、R21 |
| 旧联机、React、Physics Lab、地图编辑器、微信 | 保留源码或脚本，未纳入当前单人入口支持 | 明确保留/归档契约；不能宣称已有可玩 MMO | R28、R29、R30 |

## 3. 迁移 parity 清单

本节每项代表 Godot 交付时要补齐的迁移验收；空框均表示本次未验证 Godot。标记“源码现有”只表示网页存在真实实现/入口，不代表其旧报告中的画面或性能已由本次重新验收。

### 3.1 入口、公共 UI 与生命周期

- [ ] P01 主菜单、船长姓名输入/清理/长度上限/持久化，全部入口及返回菜单路径。源码现有；R02、R03。
- [ ] P02 分阶段加载、资源进度、失败说明、重试与返回菜单，避免重复入场残留旧 runtime。源码现有；R02、R04、R16。
- [ ] P03 暂停、失焦/隐藏/加载/错误暂停；恢复后释放旧按键意图、取消失效回调、资源释放。源码现有；R04、R05、R13、R16。
- [ ] P04 设置持久化：assisted/realistic、low/balanced/high、音效/音乐、各自音量、reducedMotion、cameraShake、cameraFollow、horizonStability。各面板实际可用设置须保留；R23。
- [ ] P05 中文可读字体、青绿海面、暖木与赭红帆、宣纸/黄铜 UI；键鼠焦点、Esc、禁用原因、结果提示和窄窗口滚动。源码现有视觉/交互基线；R03、R04、R13、R15、R16。
- [ ] P06 HUD：速度、航向、风、船体/帆/人员、帆面、弹药、两舷装填、靠港/目标/任务条件、船长身份。不能只画数值而不读取真实状态；R04、R16、R17。
- [ ] P07 练习、检阅和 QA 与生涯资源分开；退出/重开后不影响生涯财富、合同或旧存档。R02、R15、R19、R20。

### 3.2 航行、海战、物理与显示

- [ ] N01 六船型物理/数值：fuchuan、fisherman、merchant、voc、patrol、heavy；质量、尺寸、帆力、吃水、炮数和船员限制来自对应规则，模型不能充当规则权威。R18、R22、R24。
- [ ] N02 风向/风速、原海浪采样、浮力、纵摇/横摇、迎风减速、惯性、低速操舵、载货质量与动态吃水。保留数值含义，Jolt 接入不能变成恒速平移。R17、R18、R24。
- [ ] N03 键盘 W/S、A/D、箭头、手动调帆、R 自动调帆；UI 滑块与键盘读写同一控制状态。R04、R16、R17。
- [ ] N04 assisted/realistic 两预设；迎风/岸线脱困、收帆制动、手动接管自动航线。R17、R26。
- [ ] N05 自动航行、真实目标位置、船体尺度/地形/吃水参与湿航路绕障；导航失败退避、取消/重发/吃水变化失效。R18、R26。
- [ ] N06 左右舷炮击，solid/chain/grape 三弹种；弹药扣除、装填、齐射、实际弹丸轨迹、移动旋转目标碰撞、命中/落水事件。R04、R16、R18、R24。
- [ ] N07 船体/帆/人员实际伤损、沉船与战斗结束；战役损伤只结算一次；显示不另算伤亡。R06、R14、R18。
- [ ] N08 敌船自动航行、射位和开火；己方护航/战术 AI；中立背景船按真实身份/航程运行。R06、R14、R18。
- [ ] N09 实际加载的船 GLB、3 级 LOD、卷帆/鼓帆 morph、舵机、炮口与后坐、旗、帆损伤、尾流。R19、R22、R24。
- [ ] N10 真实水手 GLB/骨骼/动画；甲板岗位、舵手/拉索/炮手/巡行/瞭望与实际 crew/装填/航行状态相连。R22、R24。
- [ ] N11 炮击水手冲击：真实命中身份、击飞、甲板/船壳接触、落水、弱击恢复、死亡释放；暂停/换型/沉船/重置正确清理。网页现有纯 articulated 求解与 Three 适配，Godot/Jolt 需要新等价实现与实机验收。R24、R31。
- [ ] N12 原海面、水纹、泡沫、海岛/岸线/植被/分块、光照、天气/雾/风暴显示；画面与物理用同一波浪/地形描述。不要只迁移模型而丢海面与地形。R16、R17、R24。
- [ ] N13 船载追随/轨道镜头、驾驶/战术高位、晃动/地平线稳定/减少动态效果。R04、R16、R23。
- [ ] N14 开火/命中/落水/风浪/靠港/任务等音效及位置衰减，航行/战斗音乐切换、音量、静音与暂停释放。音效主要程序合成；不能只复制 MP3。R02、R24。

### 3.3 1650 当前护粮切片

当前规则港口只有 **厦门、金门、前线补给锚地三处**；当前初始角色为借用旗舰、继承商船、两粮船、雇佣快船、敌炮舰及背景粮船。初始历法 1650-01-01、出生年 1631、银 650、债务 400；人物为两名管事。来源 R06、R07。12 商品已进入类型/校验，但当前港口 UI 是粮食交易、港口生产消费也以 grain 为核心；不能按 schema 存在宣称十二商品完整经济已经实现。

- [ ] M01 保留独立 campaignId/vesselId/voyageId/commandId、seed/randomState、版本/修订、ownership、合同和回执；画面对象不是这些 ID 的权威。R06、R07、R10。
- [ ] M02 厦金护粮实际接单、租赁/库存出库、每条粮船真实载粮、离港、深水/浅水/外海三航路、危险吃水拒绝。R06、R07、R08。
- [ ] M03 两粮船独立进度/损失/到港、关键管事存活、最低实收/奖金/租金/逾期等实际回执；报酬幂等。R06、R08。
- [ ] M04 第二合同 convoy-002：首次实交后的后续合同、金门实出20粮、前线补给、既有船/租赁状态延续。不能只实现一次护粮。R06、R07、R08。
- [ ] M05 近远场 `route/near` 实例切换、真实自主背景贸易、货物/人员/损伤/时间守恒和 Native 投影；同船身份不能双算。R05、R06、R09。
- [ ] M06 六战术命令 protect/intercept/keep-distance/focus/prepare-boarding/rally；选择可指挥船、目标/距离/集结点、暂停草案、恢复校验、拒绝原因/状态。R04、R10、R18。
- [ ] M07 所有权与已租赁授权、人员不足禁航、已有惯性/已发炮弹保留，恢复人员后恢复权限；不能把所有友舰都授予玩家。R06、R09、R18、R26。
- [ ] M08 真实安全靠泊/锚泊：55m内、低速、无近敌/待处理炮击/接舷，受指挥船队满足状态；离港与作业锁。R05、R08、R09。
- [ ] M09 粮食买卖、真实库存/报价、船容量；修船、仅帆装改造、人员治疗和俘虏释放，银/时间/伤员桶守恒。前线补给站服务能力与大港有差别。R06、R08、R09、R10。
- [ ] M10 1650 接舷三据点 bow/deck/helm，advance/hold/cut-lines、士气/人员消耗、胜负与俘虏状态。它与1661船长决斗是不同现有系统，都需保留。R06、R08、R10。
- [ ] M11 战利船派遣人员、取货、释放战利船、救人弃船、靠港售船/永久编入；俘虏/伤员/可战船员与 Native 退场原子结算。R06、R08、R10。
- [ ] M12 军事信任/商业信用/船员支持/威慑、情报来源/时效、chronicle/settlements 记录；当前切片字段和规则如实保留，不预填未来历史。R06、R07。
- [ ] M13 时间 0/.25/1/8 倍，已消费模拟时间唯一推进经营、航行与动画；危险/战斗/任务变化退出快进，暂停原因集合独立。R04、R05、R09。
- [ ] M14 五面板：旗舰、船队与海图、靠港贸易、接舷俘获、战术；驾驶/高位视角；条件禁用原因、请求结果、真实回执显示。R04、R08、R10。
- [ ] M15 v2 安全存档/继续/恢复/导出/导入全部契约，见第4节。R05、R11、R12。

**1650 上岸新玩法不在已提交可玩基线。** `MingqiShore*` 的几何/行走/显示与未提交过渡可作 Godot新实现的参考候选；需要明确接入、船岸坐标/碰撞支持、五次访问与实机验收后才能关闭相应任务。R25、R27。

### 3.4 1661 兼容生涯

六港为厦门、金门、泉州、澎湖、鹿耳门、东山。6种商品为粮食、木材、铁料、丝绸、瓷器、香料。势力为郑氏、清廷、VOC、海盗。主线实际6任务是金门军粮、护航澎湖、东山剿寇、三岛密图、夺取航海密令、逐浪台湾；最终任务为守舰与炮台的兼容剧情，不能称为新目标的完整五阶段台湾战役。R14。

- [ ] L01 新建/继续旧生涯：650两、22岁船长、旗舰、货物、补给、士气、名望/恶名、全部日志/目标/统计。R13、R14。
- [ ] L02 六港真实靠泊/出港、6商品动态市场/税/库存与买卖、 cargo 分舰管理。R13、R14。
- [ ] L03 修船、招募、三弹药补给、船体/炮/帆/设备升级、买/卖6种船、换旗舰。R13、R14。
- [ ] L04 船间船员/货物转移、容量/最低船员限制、每日粮耗/薪银、资源不足后果、军官待遇。R13、R14。
- [ ] L05 梁火生炮术官、林帆娘帆缆官、何灶安伙食官：聘用成本/每日工资/后续装填/帆力/粮耗效果。R14。
- [ ] L06 六主线任务顺序、实际运输/护航/海战/接舷/线索/陆战条件与期限/奖励；完成不得只靠按钮改完成状态。R14。
- [ ] L07 可重复 delivery/escort/bounty/explore/rescue 委托、目标身份、实际进度、过期/失败/再次生成。R14。
- [ ] L08 六港海图、航向标记、目标/交付港定位、自动航行及手动接管。R13、R17。
- [ ] L09 港口人物对话/贸易和势力说明/接交差事、四势力关系、攻击/获胜/放行影响。R13、R14。
- [ ] L10 五登岸站点：金门古祠、澎湖石灯、东山海洞线索、藏银湾寻宝、鹿耳门炮台陆战。现有为位置条件加面板小游戏，不是连续3D上岸世界。R13、R14、R15。
- [ ] L11 船长决斗与接舷成功后的 capture/plunder/release 三处置；船/货/人员/伤势、名望/恶名变化和幂等奖励。R13、R14、R15。
- [ ] L12 降旗投降：预览具体损失、token/battle/tick 约束、确认/取消、失船/丢货/失银/任务失败、返回厦门、结果确认、保存失败可恢复。练习投降与生涯投降分开。R13、R14、R16、R18。
- [ ] L13 晴/风/雾/风暴、时间/年龄/旧伤、补给/士气、海上群雄背景船与战斗。R14、R16。
- [ ] L14 分赃士气、伤势后果、战果/贸易/港口/宝藏/军衔统计、归航退休确认、真实评定/结局文本。R13、R14。
- [ ] L15 全部12页港内面板与海上可用页：市场、船坞、招募、军官、委托、人物、舰队、势力、海图、日志、存档、设置归航；I/M/F/B/ Esc 快捷键。R13。
- [ ] L16 v1 存档、JSON文件/粘贴导入、当前/已验证备份导出、写失败保留当前航程、保存校验后才退出。R11、R12、R13、R14。

### 3.5 四小游戏与 QA

- [ ] E01 决斗：高/低/突刺、上/下防/招架/闪避，敌方起手预告、时间窗、体力/连击/冷却、血量、真实人员/士气 context、胜负/伤势、撤退/重试。R15、R21。
- [ ] E02 陆战：网格城墙/掩体，刀兵/鸟铳手选择、移动/攻击范围、视线、回合、敌方决策、胜负/伤势/撤退。R15、R21。
- [ ] E03 寻宝：雾区/地形、移动、守卫/生命、线索、挖掘次数/位置、藏银、胜负/伤势/撤退；siteId不得串错。R15、R21。
- [ ] E04 宴会：方向节拍/命中窗口、完美/失误/连击/分数/结果，生涯收费30两/三日冷却/士气/势力/名望真实结算；练习重试不收费/发奖。R13、R14、R15、R21。
- [ ] E05 QA15种视觉场景：六船尾流、受损帆与三弹、沉船、击飞、2%弱击恢复、三舰benchmark、岸线脱困、渔船/巡哨原海浪浮态、六船型水手实测。全部调用真实模拟。R20。
- [ ] E06 DEV/qa 控件：uint32 seed、重开/倍速、诊断导出、存档写入失败一次性注入；发行入口隐藏。R03、R04、R13、R20。
- [ ] E07 基准诊断：20秒预热+60秒真实墙钟采样、暂停帧剔除、平均FPS/p95、draw/triangle/memory、机器/构建身份与不完整窗口说明。旧55FPS/p95≤25ms是网页既有验收目标，不是Godot本次已达成值。R16、R20、R31。

## 4. 存档与版本兼容契约

| 项目 | 网页现有契约 | Godot要求 |
|---|---|---|
| 1661 v1 | localStorage `ming-armada-adventure-v1`；序列化 `{version:1,state,meta}`；state含seed、舰队/市场/主线/关系/生涯/天气/弹药等；meta含目标、序号、战斗epoch、seenEvents、已结算目标、线索/宝藏/陆战/冷却等 | 真正支持原JSON导入、候选完整验证、继续旧模式；meta不可丢，否则重复奖励/任务失真 |
| 1650 v2 | 槽 `ming-armada-mingqi-v2`；`{version:2,campaignId,mode:'mingqi-1650',savedAtUtc,simulationSeconds,state}` | 独立槽和模式；UTC为实际保存时刻，模拟时间独立；不得读取v1就伪造1650章节 |
| v2校验范围 | chapterId只接受 `opening-1650`；合同只接受 `convoy-001/002`；birthYear1631、当前债务身份等明确限定；字段/关系/回执/资源上限一致性检查 | 迁移时按兼容版本处理，扩展章节必须显式新版/兼容规则，不能放宽校验后称旧存档有后续历史 |
| v2输入防护 | 16MiB、深度32、节点250000、4096事件/实体、128船/epoch；拒绝未知字段、重复JSON键、不安全键、NaN/Infinity、伪回执和无效引用 | FileAccess/JSON平台变更后仍要保持这些输入与事务边界，不能仅 `JSON.parse` 成功就采用 |
| 安全保存 | 旗舰可用、在真实安全港位置、无活跃接舷/待输入/待炮击/近敌、受指挥舰队不在航行且锚泊/无活跃订单 | UI禁用原因与写入实际检查一致；原子临时文件替换并读回验证；明确当前/备份/不确定磁盘状态 |
| 导入 | 完整候选规则与Native投影先验证，保存/读回成功再替换；失败保留当前runtime和上次已验证checkpoint | 不先销毁当前场景/航程；离开/新导入使旧异步结果失效 |
| 继续 | 验证并采用原字节，不补算离线时间 | 继续后不额外推进贸易/合同/战斗；暂停/控制历史按现有语义恢复 |
| 恢复导出 | 当前安全JSON、上次已验证checkpoint、原始待恢复字节分开；首次失败无验证备份不可宣称备份存在 | 三种出口/描述都保留，失读/配额/读回不一致/回滚失败都有可见状态 |
| 设置/姓名 | `ming-armada-settings-v1`，`ming-armada-player-name` | 转为Godot独立设置文件并保留schema含义；导入生涯不顺带覆盖用户设置 |

上述契约源码分别见 R05、R06、R11、R12、R13、R14、R23。浏览器 localStorage 无法由桌面 Godot 自动跨来源读取；迁移方式为网页现有 JSON 导出，再由 Godot 导入。原网页与原槽不得自动清空或修改。

## 5. 资源与作者工具

`apps/game-client/public` 本次文件统计：PNG18、MP3 2、JPG1、GLB21、JSON3、prompt.md14。PNG18包括14张游戏美术、foam和3张旧assets图；JPG为waternormals。数字按实际文件枚举，不含截图、dist或node_modules。

| 类别 | 实际资源 | 用途与迁移注意 |
|---|---|---|
| 船 | `models/ships/{fuchuan,fisherman,merchant,voc,patrol,heavy}-lod{0,1,2}.glb`，ships-manifest.json | 18文件；GLB米制、+Y向上、船艏+Z、右舷-X、水线y0；全部hash符合manifest |
| 船控制骨架/节点 | sail_XX 的 furl/inflate morph0/1；rudder_pivot rotation.y；cannon_port/starboard_XX、barrel后坐、flag_01、socket_wake | Godot导入后检查实际节点/morph映射；当前框架专属控制代码重写，不能靠静态GLB保留行为 |
| 水手 | sailor-lod0/1/2.glb、sailors-manifest.json、validation-report.json | 3文件；18骨骼、normalized skin、无root motion、顶点色棉布/无外部纹理；idle/helm/haul/load-cannon/walk/lookout六动画；3个hash均匹配 |
| 港口背景 | art/ports/xiamen-harbor-v1.png及prompt | 主菜单背景，保留接受的美术来源 |
| 人物 | zheng-captain、voc-captain、pirate-captain、merchant-woman 的v1 PNG/prompt | 4角色肖像，对话/决斗/宴会使用；不代表历史人物完整叙事已实现 |
| 商品图 | grain/wood/iron/silk/porcelain/spices v1 PNG/prompt | 6张，匹配1661商品；1650额外6商品没有对应新图，不得说已有全部12商品图标 |
| 弹药图 | solid-shot/chain-shot/grape-shot v1 PNG/prompt | 3张；HUD/补给图 |
| 水纹 | textures/waternormals.jpg、foam.png | 原海面法线与泡沫；WebGL Three shader不能直接当Godot shader，需保留波形/尺度/色调且实机对照 |
| 音乐 | 大明逐浪.mp3、破浪赤焰.mp3 | 航海/战斗；当前按设置乘基准音量播放 |
| 旧图片 | assets/map.png、cover.png、button.png | 保留来源；不是当前海图全部采用这张静态图的证据 |
| 程序资源 | SailingAudio、WakeTexture、CombatVisuals、WeatherVisuals、scene-engine资产/地形/植被 | 实时合成音效/尾流/炮击/天气/环境，迁移逻辑与视觉参数，不能遗漏因其没有独立音频/纹理文件 |
| 作者/验证工具 | tools/ship-models、tools/sailor-models：build/export/validate/test、船模preview/evidence | 源程序与manifest哈希一并封存为可追溯作者工具；Godot版新增导入/节点/骨骼验证，不覆盖原网页输出 |

船 LOD0 的 manifest 尺寸（长×宽、吃水，米）：福船32×9/2；渔船14×4.2/1；商船36×10/2.8；VOC40×11/3.2；巡哨24×6/1.4；重型52×14.5/4.2。manifest 每舷模型炮数为6/0/0/6/3/8。1661船务 catalog 的数值炮数不同于部分模型炮数，迁移必须审查实际runtime来源，不能把模型可见炮数覆盖旧规则数值。证据 R14、R18、R22。

## 6. build、服务与联机边界

当前支持的网页工作空间为 game-client 与 physics/naval/scene/realtime/shared/adventure/encounters。根构建实际先 `ensure-built-packages` 验证/构建四个活动TS包 physics、naval、adventure-core、adventure-encounters，再构建Svelte；scene-engine通过Vite别名加载src。已编译dist不是源码基线，历史dist-qa/dist-foundation/dist-assisted等目录不是当前版本通过的证据。R29、R32。

| 网页检查 | 现有范围 | Godot等价验证 |
|---|---|---|
| `rtk proxy npm run build` | 四活动TS包+Svelte发行构建 | 原生/目标平台导入与导出，完整场景/脚本依赖，不运行网页构建代替Godot构建 |
| `rtk proxy npm test` | physics/naval/scene/adventure/encounters纯规则回归 | contracts/physics/naval/domain对应数值与命令回归 |
| `rtk proxy npm run test:game` | 当前simulation/physics/Svelte生涯面板 | runtime/presentation/UI集成、存档失败、场景反复进出、实际引擎物理 |
| `rtk proxy npm run check:game` | Svelte入口类型与组件 | 全Godot脚本解析/静态检查、引擎无头测试 |
| `rtk proxy npm run models:validate` | 船模型结构/hash | Godot导入后节点/morph/材质/骨骼/动画+尺寸验证 |
| `rtk proxy npm run test:realtime-client` | 保留SDK独立测试 | 如保留协议，单独记录接口兼容状态；不据此标记联机可玩 |

保留的 realtime-client 是 Colyseus客户端，含连接generation、join状态、重连退避/抖动、token/name/spawn、控制seq、插值、serverClock、审计。其 `protocol.ts` 包含 world/snapshot/spawn/despawn/audit、角色player/admin、wind、players/visual pose，控制消息使用rudderAngleDeg与sailAngleRad。`physicsServer.ts`另有原生WebSocket hello/control/wind/config/localConfig/ship/world实验消息。两路径不可混成一个“已运行的服务器协议”。R28、R30。

真实 `apps/server/src/index.ts` 导入 `./rooms/SailingRoom.js` 并注册`sailing`房间；相应 `SailingRoom.ts` 是“Add to SailingRoom class”片段，顶层private字段/方法，缺完整导出类。其 predev/prebuild引用缺失的 `scripts/tools/ensure-packages.mjs`。旧服务不能被本次宣称可直接运行。当前单人入口不加载联机SDK，Godot默认本地单人。R28、R29、R30。

shared/boarding消息及旧combat/port-investment模块是保留契约与实验；没有当前Svelte入口消费证明，就不能迁移成“已有在线接舷/港口投资”。地图编辑器、微信包装、Physics Lab均是独立旧入口，未纳入支持流程；Physics Lab另有无效 `</full>` 文件结束标记。Godot游戏迁移可记录归档/替代，但这些遗留工程的存在不增加单人产品已完成功能。R29。

## 7. 尚未实现的长期产品范围

旧goal中“继续Three.js”是当时选择，用户最新Godot指令取代引擎选择；历史/玩法交付边界仍须如实记录。本节是后续产品工作，不能让迁移前后一个护粮场景替代全游戏，也不能把未实现章节写成已经迁移完成。

| 长期目标 | 本次能证明的当前范围 | 尚缺 |
|---|---|---|
| 1650十九岁至1683五十二岁完整生涯 | 新v2仅opening-1650；旧v1六任务独立兼容 | 完整1661–1662战役、1662后郑经/1681权力变动/1683两终章、资产人物去向 |
| 10核心港口、远航目的地 | 1650三规则港；1661六港 | 安平/打狗/南澳/澳门等新世界及远航经营整体 |
| 12商品、战争与贸易持续世界 | 12商品schema；1650粮食核心；1661六商品经济 | 12商品完整供应/消耗/战局用途、全面情报和战争响应 |
| 第一切片30–60分钟完整闭环 | 合同/航路/交付/修理/改造/后续合同源码 | 当前普通入口完整护航成功和失败、实际船队靠泊、登岸访问、存档/画面/性能逐项亲验 |
| 五阶段台湾战役与两种收束 | 1661兼容末任务守舰+炮台 | 基地/运输/封锁/援军/外围压力/谈判或攻取等完整战役，不可合为炮台血条 |
| 人物成长、信任/人情、后辈军官 | 当前少量管事/旧军官/信誉字段 | 全历史阶段的实际人物/关系/选择后果 |
| 连续3D上岸/港口行动 | 旧面板探索+小游戏；新上岸seam与未提交候选 | 玩家可达按钮、过渡、行走、场景交互和当前构建实机证据 |
| 完整可玩成品 | 本次仅源码盘点 | 所有parity、后续内容、资源/视角/声音、存档兼容、性能与交付矩阵 |

来源为goal明确目标与未完声明、README支持范围、现有严格save schema以及源码验收报告；R06、R25、R26、R29、R31、R33。

## 8. Godot模块归属建议

以下是迁移目录与依赖建议，未创建产品实现。物理引擎与场景引擎必须独立；不能把GameScene搬成包含全部业务的一份Godot脚本。

| Godot目录 | 应归属的职责 | 网页来源 | 依赖边界 |
|---|---|---|---|
| `modules/contracts/` | 米/秒/kg/弧度、坐标/轴/姿态、detached snapshot、命令/结果/事件及只读接口schema | physics types/visual、naval types、海浪/地形描述 | 不依赖UI、SceneTree或game domain；共享数据定义，不写伤害或经营 |
| `modules/physics_engine/` | math/ocean/hydro/terrain collision/projectile/cannon、质量/吃水、Jolt impact/接触/冲量适配 | physics-core math/ocean/index/terrain/projectile/collision/dynamics | 只依赖contracts；不导入场景引擎、UI、合同或历史规则；可注入地形/水面/接触查询 |
| `modules/scene_engine/` | terrain/oceanShader/LOD/chunk/vegetation/assets/render通用能力、加载/释放 | scene-engine World/Island/Water/Assets/QuadTree | 可依赖contracts；不import game domain/UI/naval规则；使用数据/回调设置地形水面，禁止推进经营或另算伤亡 |
| `modules/naval_simulation/` | 60Hz模拟组合、船只控制、航路/AI/六命令、弹药/装填/战斗事件/损伤权威 | naval-core、SailingSimulation、ManualSailingAssist | 依赖contracts+physics_engine；不依赖UI或scene_engine；输出detached state/event |
| `game/domain/` | 1650/1661经营、合同/任务/人物/舰队/交易/作业/接舷/俘获/信誉、四encounters、存档校验 | adventure-core/encounters | 依赖contracts；以注入adapter调用海战权威；不依赖Godot图像/Control/GLB对象 |
| `game/runtime/` | composition、唯一时间消费、近远场Bridge、Native投影事务、pause reasons、存档存储与候选替换 | MingqiRuntime、AdventureRuntime、NearFieldBridge、Storage | 组合physics/naval/domain；向presentation/UI提供状态与命令口；不把经营规则写进显示适配 |
| `game/presentation/` | ship/crew模型、节点/morph/骨骼/岗位/受击表现、真实状态到HUD/镜头/音频的adapter | NavalSceneView/SailRig/SailorDeckView/SailorImpactPhysics/Weather/Audio/Presentation | 依赖contracts+scene_engine；可读runtime facade；命中损失只消费权威事件，Jolt冲击结果不重复扣业务crew |
| `game/ui/` | 主菜单、加载/恢复、HUD、港口/船队/战术/接舷、旧12页、四encounters、结果/设置/QA | 当前可达Svelte组件 | 只用runtime/呈现ViewModel，不直接更改domain或PhysicsBody |
| `game/scenes/` | 菜单/1650/1661/练习/检阅/QA场景装配 | GameEntry/GameScene/MingqiScene | 薄装配；每场景明确启动/销毁owner，不能聚集所有业务 |
| `assets/` | art/audio/models/textures/manifests/来源说明 | public、作者工具输出 | 原网页资源复制到新项目；保留来源/hash/单位/节点映射 |
| `tests/` | contracts/physics/naval/domain/runtime/presentation/UI/存档fixtures与Godot实机验收 | 各包与客户端既有测试 | 原值/事件/损失/暂停/恢复/释放行为oracle优先，不能写仅镜像实现的自证测试 |
| `tools/` | 来源快照/hash、GLB导入验证、资源/架构检查、运行/打包/QA记录 | source-lock/ensure-built-packages/models工具 | 不调用原网页生成输出或修改原项目 |

必须冻结的跨模块契约：

1. GLB船艏+Z，与当前物理heading的+X朝+Z不同；现有 `physicsVisualToPose` 用 `yaw=PI/2-heading`、`pitch=-pitch`。Godot统一轴后必须有显式转换与八方位测试，禁止静默改旧存档heading。R18、R22、R24。
2. v2货物单位100kg，Native cargoMass为kg；当前航行60Hz、articulated120Hz；模拟已消费秒/墙钟/动画时间不得混算。R06、R17、R18、R31。
3. runtime snapshot需要深拷贝/不可借用可变内部引用；Native状态、渲染插值状态分开；UI使用detached快照。R05、R14、R17、R18。
4. 业务伤亡唯一来自海战事件；Jolt人物冲击负责受击身体/接触/恢复表现，不再结算合同crew损失。按battleId/tick/controlsSequence/projectileId/eventId去重。R06、R09、R18、R24。
5. 海浪/地形描述由contracts共享或runtime注入，场景engine不被naval反向import。当前SailingSimulation深导入scene-engine/oceanWaves，应改为独立描述契约。R17。
6. domain命令带expectedRevision/commandId、报价只读、实际提交再检查；旧图像节点/按钮禁用不能代替权威校验。R06、R08、R10。

## 9. 直接源码证据索引

除R00外，以下都位于开发工作树 `C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada`。行号为本次读取的本地文件定位；迁移冻结快照后应随快照保留。

- R00 [原目录App.svelte](C:/Users/dains/Documents/Git/MingArmada/apps/game-client/src/App.svelte:1)：原网页仍为Svelte入口。
- R01 [index.html](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/index.html:10)、[main.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/main.ts:1)：真实HTML入口。
- R02 [GameEntry.svelte](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/GameEntry.svelte:14)：stage/mode、1650/1661/练习/检阅、音乐、v1导入路由。
- R03 [MainMenu.svelte](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/MainMenu.svelte:39)：全部主菜单模式、继续与DEV/qa gate。
- R04 [MingqiShell.svelte](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/adventure/MingqiShell.svelte:337)：HUD、五面板、时间、视角、弹药、菜单/存档。
- R05 [MingqiRuntime.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/simulation/MingqiRuntime.ts:24)：时间/暂停/Native/安全保存/候选导入。
- R06 [mingqi/types.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-core/src/mingqi/types.ts:17)、[campaign.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-core/src/mingqi/campaign.ts:112)：真实领域对象、命令、开局及提交权威。
- R07 [mingqi/catalog.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-core/src/mingqi/catalog.ts:21)：三港、四航路、当前角色/船型。
- R08 [convoy.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-core/src/mingqi/convoy.ts:3)、[boarding.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-core/src/mingqi/boarding.ts:21)、[port-work.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-core/src/mingqi/port-work.ts:13)、[prizes.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-core/src/mingqi/prizes.ts:1)：护粮/接舷/作业/战利船。
- R09 [NearFieldBridge.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/simulation/NearFieldBridge.ts:1)、[navigation.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-core/src/mingqi/navigation.ts:36)：近远场、质量/吃水、Native对接。
- R10 [TacticalPanel.svelte](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/adventure/TacticalPanel.svelte:30)、[MingqiPortPanel.svelte](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/adventure/MingqiPortPanel.svelte:23)、[MingqiBoardingPanel.svelte](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/adventure/MingqiBoardingPanel.svelte:1)：真实业务UI。
- R11 [MingqiStorage.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/adventure/MingqiStorage.ts:4)、[CareerStorage.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/adventure/CareerStorage.ts:6)：槽/字节/读回/回滚/故障注入。
- R12 [mingqi/save.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-core/src/mingqi/save.ts:9)、[MingqiSaveEntry.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/adventure/MingqiSaveEntry.ts:1)：完整安全校验、v1/v2分流。
- R13 [AdventureShell.svelte](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/adventure/AdventureShell.svelte:535)、[AdventurePanel.svelte](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/adventure/AdventurePanel.svelte:58)、[DialoguePanel.svelte](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/adventure/DialoguePanel.svelte:54)、[CareerSummary.svelte](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/adventure/CareerSummary.svelte:37)：旧生涯可达UI。
- R14 [adventure types.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-core/src/types.ts:78)、[catalog.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-core/src/catalog.ts:58)、[session.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-core/src/session.ts:46)、[AdventureRuntime.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/simulation/AdventureRuntime.ts:26)：1661规则/任务/保存/战斗/投降。
- R15 [PracticeInspector.svelte](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/adventure/PracticeInspector.svelte:6)、[EncounterPanel.svelte](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/adventure/EncounterPanel.svelte:12)：四小游戏入口/交互/结果。
- R16 [GameScene.svelte](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/GameScene.svelte:322)：实际试航/炮战/舰队/旧生涯、设置、QA、生命周期。
- R17 [SailingSimulation.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/simulation/SailingSimulation.ts:1)、[ManualSailingAssist.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/simulation/ManualSailingAssist.ts:1)、[SailingHUD.svelte](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/adventure/SailingHUD.svelte:56)：真实控制/海浪/插值/HUD。
- R18 [naval types.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/naval-core/src/types.ts:14)、[encounter.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/naval-core/src/encounter.ts:40)、[tactical-orders.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/naval-core/src/tactical-orders.ts:14)、[route-planner.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/naval-core/src/route-planner.ts:1)：Native状态/命令/事件/AI/航路。
- R19 [ShipViewer.svelte](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/components/adventure/ShipViewer.svelte:27)：实际GLB检阅。
- R20 [VisualScenarios.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/simulation/VisualScenarios.ts:5)、[FrameDiagnostics.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/simulation/FrameDiagnostics.ts:1)：15真实QA场景/诊断。
- R21 [encounters types.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-encounters/src/types.ts:1)、[duel.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-encounters/src/duel.ts:1)、[land-battle.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-encounters/src/land-battle.ts:3)、[treasure.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-encounters/src/treasure.ts:1)、[banquet.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/adventure-encounters/src/banquet.ts:1)：全部小游戏规则。
- R22 [ships-manifest.json](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/public/models/ships/ships-manifest.json:1)、[sailors-manifest.json](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/public/models/sailors/sailors-manifest.json:1)、[export-ships.mjs](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/tools/ship-models/export-ships.mjs:12)、[export-sailors.mjs](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/tools/sailor-models/export-sailors.mjs:13)：资源/作者/哈希/节点/轴。
- R23 [GameSettings.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/simulation/GameSettings.ts:3)：实际设置schema与存储。
- R24 [physics index.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/physics-core/src/index.ts:350)、[articulated.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/physics-core/src/dynamics/articulated.ts:1)、[NavalSceneView.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/simulation/NavalSceneView.ts:39)、[SailorDeckView.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/simulation/SailorDeckView.ts:150)、[SailorImpactPhysics.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/simulation/SailorImpactPhysics.ts:56)、[SailingAudio.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/simulation/SailingAudio.ts:14)、[physicsPose.js](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/scene-engine/src/utils/physicsPose.js:1)、[World.js](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/scene-engine/src/engine/world/World.js:32)：物理与场景显示分层来源。
- R25 [上岸接口源码报告](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/docs/superpowers/reports/2026-10-11-mingqi-shore-engine-source-acceptance.md:3)：接口已准备，玩家上岸尚未接入。
- R26 [航路绕障源码报告](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/docs/superpowers/reports/2026-10-11-mingqi-navigation-source-acceptance.md:3)：源码与实机验收边界。
- R27 [MingqiShoreTransition.ts候选](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/simulation/MingqiShoreTransition.ts:20)、[MingqiShoreWalk.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/src/simulation/MingqiShoreWalk.ts:17)：未提交过渡/已有行走参考；不是可达入口证明。
- R28 [realtime protocol.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/realtime-client/src/protocol.ts:3)、[physicsClient.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/realtime-client/src/physicsClient.ts:55)、[shared boarding-messages.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/packages/shared/src/boarding-messages.ts:1)：保留联机契约。
- R29 [README.md](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/README.md:1)、[package.json](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/package.json:1)、[架构审计](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/docs/superpowers/reports/2026-10-11-architecture-and-git-audit.md:35)：当前支持入口/旧实验边界。
- R30 [server index.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/server/src/index.ts:1)、[SailingRoom.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/server/src/rooms/SailingRoom.ts:46)、[server package.json](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/server/package.json:7)、[physicsServer.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/server/src/physicsServer.ts:13)：不完整服务与另一路WebSocket实验。
- R31 [articulated物理重构报告](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/docs/superpowers/reports/2026-10-11-articulated-physics-refactor.md:3)：旧源码回归证据与实机/FPS未验收声明。
- R32 [source-lock.json](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/tools/workspace/source-lock.json:1)、[ensure-built-packages.mjs](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/tools/workspace/ensure-built-packages.mjs:10)、[game-client package.json](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/package.json:6)、[vite.config.ts](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/apps/game-client/vite.config.ts:10)：活动构建与源码身份。
- R33 [goal.md](C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada/goal.md:3)：1650–1683长期范围、M1–M5及明确未完成边界。

## 10. 本次验证与下一阶段出口

本次直接完成：两目录入口/Git身份对照，开发树dirty候选边界，现有domain/native/runtime/UI源码盘点，三依赖锁身份/记录数读取，public资源枚举，21 GLB的SHA256逐文件校验，完整parity与分层归属文档。未执行网页测试/构建/安装、服务、浏览器、Godot编译/运行、远程Git写入。

迁移出口必须包含：上述全部现有parity逐项通过/失败/未测、两个独立生涯与存档兼容、全部练习/小游戏/船型/资源、真实物理与视觉/声音、Godot运行/导出/长期场景释放与实机性能；长期未实现历史内容仍单列开放。只有引擎基础或护粮场景可运行，不足以声称整款游戏迁移完成。
