# 海上明旗 · 全游戏资源统筹与原画库

依据旧版43场剧本、72页网页UI、实际项目资源及原83基模预算，保留170项制作需求。资源需求保留自旧版六幕43场。链接只指向当前6部22章的相近历史阶段，不证明该物件或人物仍在新主线演出；逐项制作范围须另行复审。

马努埃尔、吉平、阿隆索、安东、依斯迈等旧稿独立海上奇遇人物已转为支线或后续候选；其既有原画与资料保留，不再因旧稿标注“演出”而宣称是新版主线必需角色。原人物26／演出18等数字是旧制作基线，并非新版主线演员统计。

[打开可筛选图鉴](index.html) · [下载CSV总表](resource-register.csv) · [机器可读总表](catalog.json) · [原画生成与采用记录](generated-art.json) · [验收记录](verification.json)

## 分类与数量

|分类|资源条目数|
|---|---:|
|剧情人物|26|
|NPC职业原型|28|
|船型|8|
|火炮与炮架部件|6|
|个人火器|2|
|冷兵器|3|
|弹药外观|4|
|建筑与构件|15|
|沿海设施|6|
|场景与地图|15|
|自然与材质条件|10|
|道具与货物|47|
|合计|170|

人物26个身份包括18个实际演出、8个仅提及。别名、年龄和换装不重复算人。28种NPC是职业原型，可以复用身体、服装和动作，不等于28个全新身体。

火炮6项包括3种炮身候选（轻型前装炮、佛朗机、红夷式重炮）及轮式炮架、叉式旋架、子铳3个部件。个人火器2项是长火绳枪和形制仍待证的短铳，不把炮算成个人枪械。

15项场景/地图分为4个共享母场景、9个地域/战场差异包、2份二维海图图层；没有把43幅剧情插图当成43张独立可玩地图。建筑15项也包括可复用构件和命名装配，不直接算15座新建筑模型。

优先级：P0 88项，P1 72项，P2 10项。

## 文件已准备到哪里

源资源根目录为 [assets/production](../../../assets/production/README.md)。按分类文件夹、稳定ID分别归档。每项目录有README与asset.json，可直接查图片、用途、变体、依赖、来源和旧基模映射。

```text
assets/production/
  catalog.json
  .gdignore
  characters/char-tagawamatsu/
    asset.json
    README.md
    concept/original-v1.png
    concept/art-provenance.json
    reference/原图名-内容哈希.png
  cannons/gun-folangji/
    concept/original-v1.png
    sketch/structure-v1.svg
  buildings/building-hirado-home/
    concept/original-v1.png
    sketch/structure-v1.svg
  maps/map-liaoluo-bay/
    sketch/structure-v1.svg
    reference/剧情情境图.png
```

实际去重图像内容211份：82份既有参考、21张新增ImageGen概念原画、108张可编辑SVG结构草图。它们形成393条资源关联；归档路径391个，重复引用和副本不当成新的原创图片。

新增原画包括12个人物身份、3个建筑对象、4张炮/枪图与2种刀具。现有6个人物身份使用已采用的一官立绘或经核对的人物图集分区，因此18个演出人物均有独立身份候选图。安东新增吕宋本地水手候选，旧图保留为迭代证据。

SVG是可编辑结构/布局草图：建筑构件与装配、码头桩梁、道具外观、地图浅滩与航路关系各自绘制；不冒充写实原画、实测工程图或真实历史地图。

## 后续Agent如何使用

1. 按中文名、ID、场景章节或UI页在图鉴检索，先阅读图像级别和历史边界。
2. 打开对应资源目录的asset.json；原图、结构草图、来源、复用和依赖均在条目内。
3. UI可从既有图/新概念导出适合用途的裁图；模型制作先补比例、正侧背、服装层次与挂点复核。原图不覆盖。
4. 建筑用构件装配，场景用母版＋差异包；地图示意不直接充当导航坐标数据。
5. 验证后的运行时资产再经项目既有引擎资产合同接入，避免生产参考原画全量导入Godot。

## 基模预算与制作边界

原83基模ID已全部映射，可继续追溯 [上一轮模型预算](../../design/game-ui/production-assets.md)。170是资源工作包数量，不能直接宣布需要170个独立模型。角色身份深化可能增加头部/服装制作工时；模型总数还需在角色定型、比例和复用策略确认后复算，83仍是基线预算而非全部模型已经完成。

所有新ImageGen图均为创作概念候选，非历史肖像或文物精确复原。普通剧情图只标情境参考；8位仅提及人物没有借别人的脸冒充专用肖像。旧原版提取模型和贴图仍是参考资料，未由此获得商业发行授权。

旧稿资源出处覆盖43/43场；当前主线22章。旧资源链接转向相近历史阶段，仅作导航，不能用此宣称新作实体需求已经逐项复核。当前58/72个UI页面有旧实体/场景需求关联。以下页面尚未建立本次物件需求关联，不据此虚增模型：main-menu、load-game、settings、accessibility、experiment-detail、pause-menu、save-game、chapter-select、decision、quest-journal、chronicle、bounty-board、defeat、notification-log。

## 全量逐项清单

### 剧情人物 · 26

|ID / 名称|阶段|当前首选图像|资源说明|
|---|---|---|---|
|`char-zheng-zhilong` · 郑芝龙|P0|既有独立原图候选|[目录与图片](../../../assets/production/characters/char-zheng-zhilong/README.md)|
|`char-tagawamatsu` · 田川氏|P1|新概念原画候选|[目录与图片](../../../assets/production/characters/char-tagawamatsu/README.md)|
|`char-zheng-chenggong` · 郑成功|P1|新概念原画候选|[目录与图片](../../../assets/production/characters/char-zheng-chenggong/README.md)|
|`char-lin-awang` · 林阿旺|P0|既有独立原图候选|[目录与图片](../../../assets/production/characters/char-lin-awang/README.md)|
|`char-lin-ahe` · 林阿禾|P0|既有独立原图候选|[目录与图片](../../../assets/production/characters/char-lin-ahe/README.md)|
|`char-chen-tian` · 陈添|P0|既有独立原图候选|[目录与图片](../../../assets/production/characters/char-chen-tian/README.md)|
|`char-duqi` · 杜七|P1|新概念原画候选|[目录与图片](../../../assets/production/characters/char-duqi/README.md)|
|`char-ruan-laoliu` · 阮老六|P1|新概念原画候选|[目录与图片](../../../assets/production/characters/char-ruan-laoliu/README.md)|
|`char-huang-cheng` · 黄程|P0|新概念原画候选|[目录与图片](../../../assets/production/characters/char-huang-cheng/README.md)|
|`char-manuel` · 马努埃尔|P1|新概念原画候选|[目录与图片](../../../assets/production/characters/char-manuel/README.md)|
|`char-kippei` · 吉平|P1|新概念原画候选|[目录与图片](../../../assets/production/characters/char-kippei/README.md)|
|`char-alonso` · 阿隆索|P1|新概念原画候选|[目录与图片](../../../assets/production/characters/char-alonso/README.md)|
|`char-anton` · 安东|P1|新概念原画候选|[目录与图片](../../../assets/production/characters/char-anton/README.md)|
|`char-ismail` · 依斯迈|P1|既有独立原图候选|[目录与图片](../../../assets/production/characters/char-ismail/README.md)|
|`char-zheng-zhihu` · 郑芝虎|P1|既有独立原图候选|[目录与图片](../../../assets/production/characters/char-zheng-zhihu/README.md)|
|`char-cai-shanji` · 蔡善继|P1|新概念原画候选|[目录与图片](../../../assets/production/characters/char-cai-shanji/README.md)|
|`char-tagawamatsu-younger-son` · 田川氏幼子|P1|新概念原画候选|[目录与图片](../../../assets/production/characters/char-tagawamatsu-younger-son/README.md)|
|`char-awang-daughter` · 阿旺的女儿|P1|新概念原画候选|[目录与图片](../../../assets/production/characters/char-awang-daughter/README.md)|
|`char-li-dan` · 李旦|P2|情境参考|[目录与图片](../../../assets/production/characters/char-li-dan/README.md)|
|`char-yan-siqi` · 颜思齐|P2|情境参考|[目录与图片](../../../assets/production/characters/char-yan-siqi/README.md)|
|`char-xiong-wencan` · 熊文灿|P2|情境参考|[目录与图片](../../../assets/production/characters/char-xiong-wencan/README.md)|
|`char-xu-xinsu` · 许心素|P2|情境参考|[目录与图片](../../../assets/production/characters/char-xu-xinsu/README.md)|
|`char-li-kuiqi` · 李魁奇|P2|情境参考|[目录与图片](../../../assets/production/characters/char-li-kuiqi/README.md)|
|`char-zhong-bin` · 钟斌|P2|情境参考|[目录与图片](../../../assets/production/characters/char-zhong-bin/README.md)|
|`char-liu-xiang` · 刘香|P2|情境参考|[目录与图片](../../../assets/production/characters/char-liu-xiang/README.md)|
|`char-hans-putmans` · 普特曼斯|P2|情境参考|[目录与图片](../../../assets/production/characters/char-hans-putmans/README.md)|

### NPC职业原型 · 28

|ID / 名称|阶段|当前首选图像|资源说明|
|---|---|---|---|
|`npc-deck-sailor` · 普通甲板水手|P0|情境参考|[目录与图片](../../../assets/production/npcs/npc-deck-sailor/README.md)|
|`npc-helmsman-rower` · 轮值舵手与划艇人|P0|情境参考|[目录与图片](../../../assets/production/npcs/npc-helmsman-rower/README.md)|
|`npc-lookout` · 瞭望与传旗水手|P0|情境参考|[目录与图片](../../../assets/production/npcs/npc-lookout/README.md)|
|`npc-gunner` · 炮手与炮组长|P0|情境参考|[目录与图片](../../../assets/production/npcs/npc-gunner/README.md)|
|`npc-shipwright` · 船匠与木匠|P0|情境参考|[目录与图片](../../../assets/production/npcs/npc-shipwright/README.md)|
|`npc-medic` · 随船医护|P0|情境参考|[目录与图片](../../../assets/production/npcs/npc-medic/README.md)|
|`npc-cargo-porter` · 货栈伙计与码头搬运|P0|情境参考|[目录与图片](../../../assets/production/npcs/npc-cargo-porter/README.md)|
|`npc-merchant-captain` · 普通唐船船主|P0|情境参考|[目录与图片](../../../assets/production/npcs/npc-merchant-captain/README.md)|
|`npc-market-trader` · 货主与锚地行商|P0|情境参考|[目录与图片](../../../assets/production/npcs/npc-market-trader/README.md)|
|`npc-portuguese-dock-merchant` · 澳门葡商|P0|情境参考|[目录与图片](../../../assets/production/npcs/npc-portuguese-dock-merchant/README.md)|
|`npc-voyage-manager` · 随船管事与接洽人|P0|情境参考|[目录与图片](../../../assets/production/npcs/npc-voyage-manager/README.md)|
|`npc-pirate-toll-collector` · 收银副手与登船刀手|P0|情境参考|[目录与图片](../../../assets/production/npcs/npc-pirate-toll-collector/README.md)|
|`npc-portuguese-speaking-raider` · 葡语索费武装者|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-portuguese-speaking-raider/README.md)|
|`npc-voc-cargo-officer` · VOC管货职员|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-voc-cargo-officer/README.md)|
|`npc-chinese-shipping-agent` · 集团华商代理船主|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-chinese-shipping-agent/README.md)|
|`npc-dutch-working-sailor` · 荷方普通水手|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-dutch-working-sailor/README.md)|
|`npc-company-armed-guard` · 公司护卫与巡船兵|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-company-armed-guard/README.md)|
|`npc-recruit-informer` · 卖消息的新伙计|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-recruit-informer/README.md)|
|`npc-ming-clerk-envoy` · 招抚使者与文吏|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-ming-clerk-envoy/README.md)|
|`npc-ming-deck-guard` · 官船守船兵与接舷队|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-ming-deck-guard/README.md)|
|`npc-japan-waterfront-worker` · 平户供水者与邻里|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-japan-waterfront-worker/README.md)|
|`npc-family-escort` · 平户亲属与送子随行者|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-family-escort/README.md)|
|`npc-tutor` · 教读先生|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-tutor/README.md)|
|`npc-fishing-household` · 沿岸渔户与获救居民|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-fishing-household/README.md)|
|`npc-civilian-child` · 普通儿童与被掳少年|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-civilian-child/README.md)|
|`npc-mixed-raiding-swordsman` · 沿海混合掠船刀手|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-mixed-raiding-swordsman/README.md)|
|`npc-domestic-servant` · 家中仆役与守门人|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-domestic-servant/README.md)|
|`npc-courier-herald` · 报信人、传令人与筹粮来人|P1|情境参考|[目录与图片](../../../assets/production/npcs/npc-courier-herald/README.md)|

### 船型 · 8

|ID / 名称|阶段|当前首选图像|资源说明|
|---|---|---|---|
|`ship-lighter` · 敞口接驳驳船|P0|情境参考|[目录与图片](../../../assets/production/ships/ship-lighter/README.md)|
|`ship-fast-junk` · 小型武装快船|P0|情境参考|[目录与图片](../../../assets/production/ships/ship-fast-junk/README.md)|
|`ship-merchant-junk` · 中型海商货船|P0|情境参考|[目录与图片](../../../assets/production/ships/ship-merchant-junk/README.md)|
|`ship-fuchuan` · 福建武装福船|P0|既有独立原图候选|[目录与图片](../../../assets/production/ships/ship-fuchuan/README.md)|
|`ship-rescue-skiff` · 接应与救援小艇|P0|情境参考|[目录与图片](../../../assets/production/ships/ship-rescue-skiff/README.md)|
|`ship-european-merchant` · 早期近世欧式商船|P1|既有独立原图候选|[目录与图片](../../../assets/production/ships/ship-european-merchant/README.md)|
|`ship-european-warship` · 重炮欧式战舰|P1|情境参考|[目录与图片](../../../assets/production/ships/ship-european-warship/README.md)|
|`ship-regional-craft` · 区域商路轻舟|P1|情境参考|[目录与图片](../../../assets/production/ships/ship-regional-craft/README.md)|

### 火炮与炮架部件 · 6

|ID / 名称|阶段|当前首选图像|资源说明|
|---|---|---|---|
|`gun-light-muzzle` · 船载轻型前装炮炮身|P0|新概念原画候选|[目录与图片](../../../assets/production/cannons/gun-light-muzzle/README.md)|
|`gun-folangji` · 佛朗机炮身|P1|新概念原画候选|[目录与图片](../../../assets/production/cannons/gun-folangji/README.md)|
|`gun-hongyipao` · 红夷式重炮炮身|P1|新概念原画候选|[目录与图片](../../../assets/production/cannons/gun-hongyipao/README.md)|
|`gun-deck-carriage` · 轮式木炮架|P0|新概念原画候选|[目录与图片](../../../assets/production/cannons/gun-deck-carriage/README.md)|
|`gun-swivel-mount` · 佛朗机叉式旋架与甲板座|P1|结构草图|[目录与图片](../../../assets/production/cannons/gun-swivel-mount/README.md)|
|`gun-folangji-chamber` · 佛朗机子铳|P1|结构草图|[目录与图片](../../../assets/production/cannons/gun-folangji-chamber/README.md)|

### 个人火器 · 2

|ID / 名称|阶段|当前首选图像|资源说明|
|---|---|---|---|
|`firearm-matchlock` · 鸟铳与长火绳枪|P1|新概念原画候选|[目录与图片](../../../assets/production/firearms/firearm-matchlock/README.md)|
|`firearm-short-matchlock` · 短铳（暂定短火绳枪形制）|P1|结构草图|[目录与图片](../../../assets/production/firearms/firearm-short-matchlock/README.md)|

### 冷兵器 · 3

|ID / 名称|阶段|当前首选图像|资源说明|
|---|---|---|---|
|`weapon-sabre` · 随身短刀与刀鞘|P0|新概念原画候选|[目录与图片](../../../assets/production/melee-weapons/weapon-sabre/README.md)|
|`weapon-spear` · 守船长枪|P1|结构草图|[目录与图片](../../../assets/production/melee-weapons/weapon-spear/README.md)|
|`weapon-longblade` · 雇佣刀手长刀|P1|新概念原画候选|[目录与图片](../../../assets/production/melee-weapons/weapon-longblade/README.md)|

### 弹药外观 · 4

|ID / 名称|阶段|当前首选图像|资源说明|
|---|---|---|---|
|`ammo-solid` · 实心炮弹|P0|既有独立原图候选|[目录与图片](../../../assets/production/ammunition/ammo-solid/README.md)|
|`ammo-chain` · 链弹|P0|既有独立原图候选|[目录与图片](../../../assets/production/ammunition/ammo-chain/README.md)|
|`ammo-grape` · 葡萄弹包|P0|既有独立原图候选|[目录与图片](../../../assets/production/ammunition/ammo-grape/README.md)|
|`ammo-firearm-shot` · 个人火器弹丸袋|P1|结构草图|[目录与图片](../../../assets/production/ammunition/ammo-firearm-shot/README.md)|

### 建筑与构件 · 15

|ID / 名称|阶段|当前首选图像|资源说明|
|---|---|---|---|
|`building-warehouse-front` · 货栈门面模块|P0|新概念原画候选|[目录与图片](../../../assets/production/buildings/building-warehouse-front/README.md)|
|`building-warehouse-wall` · 货栈墙体模块|P0|结构草图|[目录与图片](../../../assets/production/buildings/building-warehouse-wall/README.md)|
|`building-pitched-roof` · 货栈坡屋顶模块|P0|结构草图|[目录与图片](../../../assets/production/buildings/building-pitched-roof/README.md)|
|`building-timber-wall` · 木构住宅墙体模块|P1|结构草图|[目录与图片](../../../assets/production/buildings/building-timber-wall/README.md)|
|`building-plaster-wall` · 灰泥住宅墙体模块|P1|结构草图|[目录与图片](../../../assets/production/buildings/building-plaster-wall/README.md)|
|`building-residence-roof` · 住宅屋顶模块|P1|结构草图|[目录与图片](../../../assets/production/buildings/building-residence-roof/README.md)|
|`building-door` · 独立门扇|P0|结构草图|[目录与图片](../../../assets/production/buildings/building-door/README.md)|
|`building-window` · 独立窗扇格栅|P1|结构草图|[目录与图片](../../../assets/production/buildings/building-window/README.md)|
|`building-macau-warehouse` · 澳门华商货栈|P0|新概念原画候选|[目录与图片](../../../assets/production/buildings/building-macau-warehouse/README.md)|
|`building-warehouse-berth` · 货栈铺位与养伤小间|P0|结构草图|[目录与图片](../../../assets/production/buildings/building-warehouse-berth/README.md)|
|`building-hirado-home` · 平户邻里小木屋|P1|新概念原画候选|[目录与图片](../../../assets/production/buildings/building-hirado-home/README.md)|
|`building-fujian-residence` · 福建郑氏居所|P1|新概念原画候选|[目录与图片](../../../assets/production/buildings/building-fujian-residence/README.md)|
|`building-shore-sickroom` · 闽海岸上养伤屋|P1|结构草图|[目录与图片](../../../assets/production/buildings/building-shore-sickroom/README.md)|
|`building-settlement-shelter` · 受抚前后临时安置屋|P1|结构草图|[目录与图片](../../../assets/production/buildings/building-settlement-shelter/README.md)|
|`building-inspection-room` · 交验与官署热点空间|P1|结构草图|[目录与图片](../../../assets/production/buildings/building-inspection-room/README.md)|

### 沿海设施 · 6

|ID / 名称|阶段|当前首选图像|资源说明|
|---|---|---|---|
|`coastal-wood-pier` · 木码头段|P0|结构草图|[目录与图片](../../../assets/production/coastal/coastal-wood-pier/README.md)|
|`coastal-stone-step` · 石堤与踏步段|P0|结构草图|[目录与图片](../../../assets/production/coastal/coastal-stone-step/README.md)|
|`coastal-market-stall` · 港市摊棚|P0|结构草图|[目录与图片](../../../assets/production/coastal/coastal-market-stall/README.md)|
|`coastal-shipyard-cradle` · 船坞修船支架|P0|结构草图|[目录与图片](../../../assets/production/coastal/coastal-shipyard-cradle/README.md)|
|`coastal-fishing-hamlet` · 无名湾岸渔寮组|P1|结构草图|[目录与图片](../../../assets/production/coastal/coastal-fishing-hamlet/README.md)|
|`coastal-luzon-battery` · 吕宋近岸炮台剪影|P1|结构草图|[目录与图片](../../../assets/production/coastal/coastal-luzon-battery/README.md)|

### 场景与地图 · 15

|ID / 名称|阶段|当前首选图像|资源说明|
|---|---|---|---|
|`map-world-nautical-chart` · 区域航海与势力底图|P0|结构草图|[目录与图片](../../../assets/production/maps/map-world-nautical-chart/README.md)|
|`map-tactical-water-chart` · 海战与接舷态势底图|P0|结构草图|[目录与图片](../../../assets/production/maps/map-tactical-water-chart/README.md)|
|`map-open-sea-mother` · 可航行外海母场景|P0|结构草图|[目录与图片](../../../assets/production/maps/map-open-sea-mother/README.md)|
|`map-shipboard-mother` · 甲板与有限船舱共享场景|P0|结构草图|[目录与图片](../../../assets/production/maps/map-shipboard-mother/README.md)|
|`map-macau-harbor` · 澳门货栈与接驳泊区差异包|P0|结构草图|[目录与图片](../../../assets/production/maps/map-macau-harbor/README.md)|
|`map-hirado-kawachi-harbor` · 平户川内浦港巷与石堤差异包|P1|结构草图|[目录与图片](../../../assets/production/maps/map-hirado-kawachi-harbor/README.md)|
|`map-taiwan-southwest-anchorage` · 大员附近与台湾西南锚地差异包|P1|结构草图|[目录与图片](../../../assets/production/maps/map-taiwan-southwest-anchorage/README.md)|
|`map-fujian-hidden-anchorage` · 闽粤隐蔽锚地与夜市差异包|P1|结构草图|[目录与图片](../../../assets/production/maps/map-fujian-hidden-anchorage/README.md)|
|`map-fujian-working-harbor` · 福建工作港与厦门泊区差异包|P0|结构草图|[目录与图片](../../../assets/production/maps/map-fujian-working-harbor/README.md)|
|`map-hirado-home-scene` · 平户家居共享剧情空间|P1|结构草图|[目录与图片](../../../assets/production/maps/map-hirado-home-scene/README.md)|
|`map-fujian-household-scene` · 福建居所与岸上生活共享空间|P1|结构草图|[目录与图片](../../../assets/production/maps/map-fujian-household-scene/README.md)|
|`map-nearshore-channel` · 福建暗岸、岛岸与厦门口航道差异包|P0|结构草图|[目录与图片](../../../assets/production/maps/map-nearshore-channel/README.md)|
|`map-unnamed-rescue-bay` · 无名湾口抗掠救人差异包|P0|结构草图|[目录与图片](../../../assets/production/maps/map-unnamed-rescue-bay/README.md)|
|`map-liaoluo-bay` · 1633料罗湾火攻与接应差异包|P1|结构草图|[目录与图片](../../../assets/production/maps/map-liaoluo-bay/README.md)|
|`map-tianweiyang-search` · 田尾洋战后锚地与搜索差异包|P1|结构草图|[目录与图片](../../../assets/production/maps/map-tianweiyang-search/README.md)|

### 自然与材质条件 · 10

|ID / 名称|阶段|当前首选图像|资源说明|
|---|---|---|---|
|`nature-broadleaf` · 沿岸阔叶树|P0|结构草图|[目录与图片](../../../assets/production/nature/nature-broadleaf/README.md)|
|`nature-shore-tree` · 风塑矮岸树|P0|结构草图|[目录与图片](../../../assets/production/nature/nature-shore-tree/README.md)|
|`nature-palm` · 区域棕榈树|P2|结构草图|[目录与图片](../../../assets/production/nature/nature-palm/README.md)|
|`nature-shrub` · 沿岸灌木|P1|结构草图|[目录与图片](../../../assets/production/nature/nature-shrub/README.md)|
|`nature-grass` · 岸边草簇|P0|结构草图|[目录与图片](../../../assets/production/nature/nature-grass/README.md)|
|`nature-rock` · 岩礁石簇|P0|结构草图|[目录与图片](../../../assets/production/nature/nature-rock/README.md)|
|`nature-island-terrain` · 岛岸与浅滩地形母版|P0|结构草图|[目录与图片](../../../assets/production/nature/nature-island-terrain/README.md)|
|`nature-ocean-sky-profile` · 海天与风雾昼夜条件集|P0|结构草图|[目录与图片](../../../assets/production/nature/nature-ocean-sky-profile/README.md)|
|`nature-shore-materials` · 岸线干湿石砂材质集|P0|结构草图|[目录与图片](../../../assets/production/nature/nature-shore-materials/README.md)|
|`nature-ground-materials` · 内岸草土地表材质集|P1|结构草图|[目录与图片](../../../assets/production/nature/nature-ground-materials/README.md)|

### 道具与货物 · 47

|ID / 名称|阶段|当前首选图像|资源说明|
|---|---|---|---|
|`prop-crate` · 木货箱|P0|结构草图|[目录与图片](../../../assets/production/props/prop-crate/README.md)|
|`prop-barrel` · 淡水大桶|P0|结构草图|[目录与图片](../../../assets/production/props/prop-barrel/README.md)|
|`prop-cloth-bale` · 布匹货包与布卷|P0|既有独立原图候选|[目录与图片](../../../assets/production/props/prop-cloth-bale/README.md)|
|`prop-grain-sack` · 米粮袋|P0|既有独立原图候选|[目录与图片](../../../assets/production/props/prop-grain-sack/README.md)|
|`prop-porcelain-jar` · 瓷货罐|P0|既有独立原图候选|[目录与图片](../../../assets/production/props/prop-porcelain-jar/README.md)|
|`prop-basket` · 货物竹篮|P0|结构草图|[目录与图片](../../../assets/production/props/prop-basket/README.md)|
|`prop-rope-coil` · 盘索与备用缆绳|P0|结构草图|[目录与图片](../../../assets/production/props/prop-rope-coil/README.md)|
|`prop-cargo-net` · 货网与吊货网|P0|结构草图|[目录与图片](../../../assets/production/props/prop-cargo-net/README.md)|
|`prop-bollard` · 缆桩|P0|结构草图|[目录与图片](../../../assets/production/props/prop-bollard/README.md)|
|`prop-lantern` · 船灯与提灯|P0|结构草图|[目录与图片](../../../assets/production/props/prop-lantern/README.md)|
|`prop-bench` · 坐凳与长凳|P0|结构草图|[目录与图片](../../../assets/production/props/prop-bench/README.md)|
|`prop-table` · 木桌|P0|结构草图|[目录与图片](../../../assets/production/props/prop-table/README.md)|
|`prop-bedding` · 床铺与被褥|P1|结构草图|[目录与图片](../../../assets/production/props/prop-bedding/README.md)|
|`prop-chest` · 衣物行李箱|P0|结构草图|[目录与图片](../../../assets/production/props/prop-chest/README.md)|
|`prop-bucket` · 提水小桶|P0|结构草图|[目录与图片](../../../assets/production/props/prop-bucket/README.md)|
|`prop-pot` · 锅具|P1|结构草图|[目录与图片](../../../assets/production/props/prop-pot/README.md)|
|`prop-bowl` · 饭碗与小碗|P1|结构草图|[目录与图片](../../../assets/production/props/prop-bowl/README.md)|
|`prop-letter` · 家书纸张|P1|结构草图|[目录与图片](../../../assets/production/props/prop-letter/README.md)|
|`prop-chart` · 船图、针路簿与水程笺|P1|结构草图|[目录与图片](../../../assets/production/props/prop-chart/README.md)|
|`prop-tally` · 缺口木筹|P0|结构草图|[目录与图片](../../../assets/production/props/prop-tally/README.md)|
|`prop-toolbox` · 阿旺工具箱|P0|结构草图|[目录与图片](../../../assets/production/props/prop-toolbox/README.md)|
|`prop-drying-rack` · 渔网晾晒架|P2|结构草图|[目录与图片](../../../assets/production/props/prop-drying-rack/README.md)|
|`prop-wreck-timber` · 破船木段|P0|结构草图|[目录与图片](../../../assets/production/props/prop-wreck-timber/README.md)|
|`prop-toolbelt` · 旧工具带|P0|结构草图|[目录与图片](../../../assets/production/props/prop-toolbelt/README.md)|
|`prop-shipwright-axe` · 船匠断索斧|P0|结构草图|[目录与图片](../../../assets/production/props/prop-shipwright-axe/README.md)|
|`prop-polehook` · 长钩与篙钩|P0|结构草图|[目录与图片](../../../assets/production/props/prop-polehook/README.md)|
|`prop-grapnel` · 接舷挠钩与钩索|P0|结构草图|[目录与图片](../../../assets/production/props/prop-grapnel/README.md)|
|`prop-boarding-plank` · 接舷过板与跳板|P0|结构草图|[目录与图片](../../../assets/production/props/prop-boarding-plank/README.md)|
|`prop-oar` · 长橹与应急长桨|P0|结构草图|[目录与图片](../../../assets/production/props/prop-oar/README.md)|
|`prop-punt-pole` · 撑船篙|P0|结构草图|[目录与图片](../../../assets/production/props/prop-punt-pole/README.md)|
|`prop-compass` · 铜制罗盘|P0|结构草图|[目录与图片](../../../assets/production/props/prop-compass/README.md)|
|`prop-medicine` · 随船药囊与裹伤布|P0|结构草图|[目录与图片](../../../assets/production/props/prop-medicine/README.md)|
|`prop-receipt` · 损货回单|P0|结构草图|[目录与图片](../../../assets/production/props/prop-receipt/README.md)|
|`prop-contract-document` · 托运、合货与委托纸|P0|结构草图|[目录与图片](../../../assets/production/props/prop-contract-document/README.md)|
|`prop-official-document` · 官身与通行文书|P1|结构草图|[目录与图片](../../../assets/production/props/prop-official-document/README.md)|
|`prop-red-thread-pouch` · 红线袋|P1|结构草图|[目录与图片](../../../assets/production/props/prop-red-thread-pouch/README.md)|
|`prop-money-pouch` · 家用与交银钱袋|P0|结构草图|[目录与图片](../../../assets/production/props/prop-money-pouch/README.md)|
|`prop-money-set` · 钱串与小银块|P0|结构草图|[目录与图片](../../../assets/production/props/prop-money-set/README.md)|
|`prop-command-flag` · 保护旗、官旗与号令旗|P0|结构草图|[目录与图片](../../../assets/production/props/prop-command-flag/README.md)|
|`prop-gong` · 停火铜锣|P1|结构草图|[目录与图片](../../../assets/production/props/prop-gong/README.md)|
|`prop-torch` · 火把|P1|结构草图|[目录与图片](../../../assets/production/props/prop-torch/README.md)|
|`prop-paper-lantern` · 平户手糊纸灯|P1|结构草图|[目录与图片](../../../assets/production/props/prop-paper-lantern/README.md)|
|`prop-timber-stock` · 修船木料|P0|既有独立原图候选|[目录与图片](../../../assets/production/props/prop-timber-stock/README.md)|
|`prop-iron-stock` · 铁料货组|P0|既有独立原图候选|[目录与图片](../../../assets/production/props/prop-iron-stock/README.md)|
|`prop-spices` · 香料货包|P0|既有独立原图候选|[目录与图片](../../../assets/production/props/prop-spices/README.md)|
|`prop-scissors` · 剪刀|P1|结构草图|[目录与图片](../../../assets/production/props/prop-scissors/README.md)|
|`prop-matchcord` · 备用火绳|P0|结构草图|[目录与图片](../../../assets/production/props/prop-matchcord/README.md)|

## 分册审查与重建

[人物审计](characters-audit.md) · [环境审计](environment-audit.md) · [装备审计](equipment-audit.md) · [独立总审查](independent-review.md)

```powershell
rtk proxy node tools/build-environment-resource-sketches.mjs
rtk proxy node tools/build-equipment-resource-sketches.mjs
rtk proxy node tools/build-production-resource-library.mjs
rtk proxy node tools/verify-production-resource-library.mjs
```
