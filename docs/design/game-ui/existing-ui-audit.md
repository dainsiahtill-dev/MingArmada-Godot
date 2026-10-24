# 现有 UI 与可复用资产审计

审计日期：2026-10-22。范围：现有 Godot 源码、项目美术、既有截图。只读分析，未运行游戏；源码存在不等于本次实际运行通过。CodeGraph 无索引，沿主任务已确认的 RTK 回退路径检查。此文只记录 UI 设计依据，不构成完整玩法交付声明。

## 现有界面与功能边界

| 入口 / 页面 | 当前来源 | 可继承内容与边界 |
| --- | --- | --- |
| 主菜单 | `game/ui/menu/main_menu.gd` | 全屏厦门港插画、左侧旧纸面板、船长姓名、新生涯 1650、继续航程、单舰炮战、舰队遭遇、自由试航、实验室、船只检阅、设置。1661 旧航程与开发验收入口仅开发权限可见。 |
| 1650 生涯 HUD | `game/ui/mingqi/mingqi_interface.gd` | 左上深青半透明航行状态，右侧操作面板；旗舰、船队海图、港口贸易、接舷俘获、战术、航海日志共六页。船长、银两、借债、航速、风速、目标、暂停、时间速度、镜头、操船与齐射均有源实现。 |
| 旗舰与操船 | 同上 `_build_ship` | 船体、帆装、船员三条状态，帆面、舵、帆角、自动调帆、双舷齐射、三弹种和装填。当前用郑氏船长小立绘，不存在独立旗舰插画资产。 |
| 船队与海图 | 同上 `_build_convoy` | 护粮委托、船舶状态、逐船货舱和吃水、航路、舰船选择。点击海图只填航位，须战术页确认航行。当前地域厦门、金门、近岸补给点；不能称现有完整东亚世界。 |
| 港口与贸易 | 同上 `_build_port` | 靠泊、粮食买卖、修理、帆装改造、释放俘虏、治伤与工期记录。虽然 GOODS 列有 12 种商品名，当前该页交易只接粮食。原型扩展商品市场属于设计目标。 |
| 接舷与俘获 | 同上 `_build_boarding` | 接舷目标、推进 / 守住 / 断缆、调拨押船员、取实有货物、释放、救人弃船、出售与编入战利船。 |
| 船队战术 | 同上 `_build_tactics` | 护航、拦截、保持距离、集火、准备接舷、集结；选舰与指定航位。 |
| 航海日志 | 同上 `_build_story` | 当前章节、下一步目标、故事场景与选择、往航和结算、借债与还款。存在正式 UI 与领域输入，但本次不声称完成任意长篇剧情。 |
| 暂停 / 存档 | 同上 `_build_menu` | 保存安全航程、保存返回、设置、导入 / 导出当前与备份存档、错误和条件提示。 |
| 独立海战 / 自由试航 | `game/ui/naval_practice.gd` | 船体帆装水手、航向航速、风速、帆、双舷装填、实心 / 链 / 葡萄弹、海图、暂停、投降及战斗终态。独立模式不能当完整生涯流程。 |
| 1661 兼容航程 | `game/ui/legacy/legacy_interface.gd` | 港口市场、船坞、招募军需、军官、委托、人物、舰队、势力、六港海图、日志、存档和设置。可作未来设计参考，但不能把旧版覆盖自动归入现有 1650 生涯。 |
| 小玩法 | `game/ui/encounters/encounter_interface.gd` | 船长决斗、登岸交锋、孤岛寻宝、港口雅宴。与旧版和验收场景相关，不能据此称 1650 已整合完整陆战 / 人际系统。 |
| 船只检阅 | `game/scenes/ship_book/ship_book.gd` | 六船型、六观察角、帆面部署、环视缩放、火炮后座。当前活动 provider 映射临时西式帆船原版参照外观，代码和 manifest 明确不声明中国船舶历史重建。 |
| 实验室 | `game/research/catalog.gd` / `assets/research/catalog.json` | 独立研究目录、论文、实验、参数与证据。已集成 / 独立验证 / 研究中为不同状态；实验参数面板不应进入玩家日常主界面。 |

未发现独立“背包格子”正式 UI。已有逐船货物、弹药、船务和俘获管理；全新背包 / 人物装备 / 大世界港口页要注明为原型扩展。

## 视觉与排版继承

- 当前主菜单：旧纸 `#f1e6cb`，墨青 `#183e3c`，铜金 `#b89a60`。按钮纸色 `#e7ddc4`，悬停 `#f9edcc`，按下 `#ccb789`；主入口土金 `#c9ad73`。港景左侧叠深青遮罩，文字集中在安静水域。
- 当前 1650 HUD：面板 `rgba(11,36,40,.95)`；铜框 `#a88b54`，按钮 `#264d49` / 悬停 `#3b6256` / 按下 `#806b43`。正文 `#eee6d4`，标题金 `#e3c88d`，次级青灰 `#a9c3bd`，反馈浅金 `#ffd99a`。直边、1px 框、低圆角，不能转成现代 SaaS 圆角卡片后台。
- 旧版 theme：面板 `#123b3d`，铜框 `#c5a059`，文字 `#f2e9d0`；与新版方向一致。
- 主菜单标题字体 `SimSun` / `Songti SC` / serif，54px；正文 `Microsoft YaHei` / `Noto Sans CJK SC` / sans-serif，17px。旧版正文 16px，HUD 有 13–24px层级。未发现 `assets` 内捆绑字体文件，网页须系统回退或另行获得字体。
- 地图墨 `#423b29`、旧金 `#b3944f`、金舟旗舰 / 青舟同盟 / 朱舟敌舰；地图纸纹只做材质，航线、海岸、港口、舰船为真实绘制层。
- 新原型宜保留晚明东亚叙事：大幅港景、红帆、旧纸日志、墨青海图、铜金框、朱红印与少量状态色。功能很多也应按游戏场景分布，避免常驻侧栏加数据卡片总览。

## 可直接复用的美术

下列绝对根路径均为 `C:/Users/dains/Documents/Git/ming-armada/`。PNG 尺寸由文件头读取；透明性用 Pillow 实读 alpha 范围确认。原型位于 `docs/design/game-ui/prototype/` 时，引用前缀为 `../../../../assets/`，无需复制大图。

| 完整文件路径 | 尺寸 / 类型 | 用途 |
| --- | --- | --- |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/ports/xiamen-harbor-v1.png` | 1672×941 RGB PNG，2.61 MB | 主菜单、港口场景全屏背景。右侧传统红帆中国海商船、码头；左侧安静水面留 UI。已目视。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/maps/ming-nautical-chart-v2.png` | 1448×1086 RGB PNG，3.62 MB | 深青旧海纸、金线海纹、云纹四角框。没有陆地、港名、船位。已目视。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/maps/ming-nautical-land-paper-v2.png` | 1254×1254 RGB PNG，2.99 MB | 均匀金赭纸纹，无文字图形；可用于海图陆地或日志纸面。已目视。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/maps/ming-nautical-chart-v1.png` | 1448×1086 RGB PNG，3.28 MB | 旧版回退海纸。优先 v2。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/characters/zheng-captain-v1.png` | 1145×1374 RGBA，alpha 0–255，2.17 MB | 郑氏水师船长，蓝巾甲胄，半身透明立绘。已目视。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/characters/merchant-woman-v1.png` | 1145×1374 RGBA，alpha 0–255，0.89 MB | 行商掌柜透明立绘。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/characters/voc-captain-v1.png` | 1145×1374 RGBA，alpha 0–255，1.01 MB | 荷兰商船代表透明立绘。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/characters/pirate-captain-v1.png` | 1122×1402 RGBA，alpha 0–255，1.76 MB | 海盗船长透明立绘。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/goods/grain-v1.png` | 1254×1254 RGBA，alpha 0–255，1.12 MB | 粮食货物。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/goods/wood-v1.png` | 1254×1254 RGBA，alpha 0–255，0.87 MB | 木材货物。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/goods/iron-v1.png` | 1254×1254 RGBA，alpha 0–255，0.98 MB | 铁料货物。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/goods/silk-v1.png` | 1254×1254 RGBA，alpha 0–255，0.64 MB | 丝绸货物。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/goods/porcelain-v1.png` | 1254×1254 RGBA，alpha 0–255，0.93 MB | 青花瓷瓶与碗。已目视。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/goods/spices-v1.png` | 1254×1254 RGBA，alpha 0–255，0.86 MB | 香料货物。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/ammo/solid-shot-v1.png` | 1254×1254 RGBA，alpha 0–255，0.82 MB | 实心弹。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/ammo/chain-shot-v1.png` | 1254×1254 RGBA，alpha 0–255，0.55 MB | 链弹。 |
| `C:/Users/dains/Documents/Git/ming-armada/assets/art/ammo/grape-shot-v1.png` | 1254×1254 RGBA，alpha 0–255，0.94 MB | 葡萄弹。 |

`assets/art` 各人物、货物、炮弹与港景有同名 `.prompt.md`；地图来源与限制在 `docs/migration/nautical-chart-v2-art.md`。生成素材可作项目既有视觉沿用；此处不额外推定未读取的第三方许可证。

## 舰船图像与现存 3D

未找到可直接用作角色卡的独立整船透明侧视 PNG。`assets/models/fidelity_naval/*_transparent.png` 是约 512×256 的 UV 材质贴图，不是完整船舶肖像，不可用作网页主图。

存在旧 authored 船模：`assets/models/ships/{fuchuan,fisherman,merchant,voc,patrol,heavy}-lod{0,1,2}.glb`，LOD0 约 0.85–2.08 MB。当前活动 provider 为 `modules/scene_engine/assets/ship_model_provider.gd`，读取 `assets/data/fidelity_naval/ships-manifest.json`，映射：

- 郑氏福船使用 `assets/models/fidelity_naval/barque.glb`，1.22 MB。
- 其余活动外观来自同目录 `sloop1.glb`、`ship_merman.glb`、`frigate.glb`、`ship_brigantine.glb`、`treasure_galleon.glb`，约 1.69–2.32 MB。
- manifest scope 明确临时西式原版参照外观，未声称中国历史船舶重建；船鉴亦显示该限制。网页设计可以有中国船型目标形象，但应独立说明概念性质。
- 若首版网页不引入 3D，船型剪影 / SVG 示意更稳妥。港口背景内已存在中国红帆船，可作为电影感场景的一部分，不能替代可旋转 3D 的实现声明。

## 截图证据使用注意

- `build/windows-acceptance/20261011-copy/evidence/release-mingqi-1650.png`，1600×900，目视为旧时点的明旗 HUD；当前源码已经新增日志 / 目标 / 操作改进，所以不能据此描述全部当前版式。
- 同目录 `release-shipbook.png` 目视实际也是明旗操船 HUD，不能作船只检阅证据。
- `docs/research/evidence/laboratory-2026-10-14/ship-merchant.png`，1600×1000，目视为实验室水线近景及参数面板，不是纯底船模展示图。
- `docs/migration/evidence/legacy/six-port-chart.png` 等仅旧版截图；六港旧图不等于 1650 当前航区，更不等于东亚全地图。
- 海图正式绘制层来自 `game/ui/charts/nautical_chart.gd`，按真实高度采样生成陆地 / 浅滩 / 海岸，叠加港口和舰船；海纸图片没有隐藏的地理数据。网页复现交互需自己的设计数据。

## 后续正式开发交接约束

网页原型能证明页面结构、视觉、导航与本地模拟交互。不能把可点页面、示例数量、模拟炮击、示例货物成交、假船队状态、历史旧版覆盖、独立研究 demo 或美术截图，称为已经连接 Godot 正式玩法。

正式开发应逐页标明：已有运行合同可接入、需新增领域合同、仅设计提案。优先保留意图 / 状态快照分离：当前 Godot UI 发 command intent，并消费权威 snapshot，不自行计算奖励或推进世界。
