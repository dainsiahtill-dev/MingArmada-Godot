# 火攻与损管：首版可玩合同

2026-10-29。用户已授权持续自主推进；本轮承接《武经总要》火攻／救焚、丰富兵器和船员、数值平衡要求。纯核、独立实验、原生实弹与公开菜单“火攻交锋”已实现；验证范围以[课题论文](../../../assets/research/papers/ship-fire-control.md)及原始证据为准。1650生涯采购／存档／登船劳动接线尚未完成。

上一目标轮为实质进展：真实货单／货损／漂流与视觉烟火已集成，正式入口GPU及24项定向文件通过，证据见28号交付档案。本轮改变权威玩法，沿独立研究、GPU、正式集成顺序执行。

## 玩家决策

火攻先提供一种不同于炮击的压力：短程投送火球，船上形成有限燃烧的火患，持续伤及船体、帆和人员。守方选择继续射击、提前备好损管人员、临时抽人处理或撤退；灭火不恢复已损部位。普通引火载荷与蒺藜火毬灵感载荷先只比较燃烧工时和成本，历史出处及创作边界见研究笔记，不提供现实武器制作内容。

不采用“看见火焰就扣血”的旁路。纯规则核返回伤害建议；正式Encounter在真实弹体碰撞及固定60Hz中持有状态、应用伤害、判沉。DOT不伪装普通hit，不触发逐tick扣货。人员占用不改变船员总数。

## 状态与接口

新纯模块 `modules/naval_simulation/combat/fire_control.gd`，独立于Nodes、画面、存档IO及游戏层。集中参数在同目录`fire_profile.gd`，版本`ship-fire-r1`。所有方法返回分离数据，不修改输入。

`initial(supplies:int=0)->Dictionary`，状态固定字段：version、heat[0,100]、fuelSeconds[0,72]、wetness[0,1]、crewDamageCarry[0,1)、assignedFirefighters整数[0,128]、pendingFirefighters整数[0,128]、transferTicks整数[0,120]、supplies整数[0,600]、workCarry人秒[0,2)。零储备时workCarry为0。

`valid(state)->bool`；`ignite(state,payload,wetness)->{ok,state,reason}`，payload为fire-ball/thorn-ball；`assign(state,crew,able)->{ok,state,reason}`；`reserved_crew(state,able)->int`；`step(state,context)->{ok,state,damage:{hull,sail,crew},reservedCrew,extinguished,workSeconds,suppliesSpent}`。context固定为able整数、maxHull/maxSail正有限数、maxCrew正整数、rain01[0,1]、flammableLoad[0,1]。每step仅1/60秒，外层负责暂停、接受时间及重放。

转岗120tick，途中零扑救；占用max(旧岗位人数,目标人数)，人员伤亡后裁剪，不制造人口。到位后实际工作消耗损管准备份：一份支撑2有效人秒，既包含备好的取水／工具和消耗品准备，不把海水说成无限现成损管，也不消耗饮用水货物。储备不足时工作按可用人秒限制；0储备无扑救。自动灭火后以120tick撤回，期间仍占用；显式待命可在起火前安排，但真实占人。

边界冻结：第120个完整step末到位，第121步开始工作。转岗途中改派先保留旧assigned/pending较大的实际占用，再设新目标；同目标重复命令不重启计时。热灭保留剩余燃料，但heat0不自行复燃。伤亡整数只扣现有able，岗位在同tick伤亡后再次裁剪；计数接受整数float以支持JSON恢复，拒绝bool和分数。

辅助投送候选独立`fireLauncher`：ammo中fire-ball/thorn-ball各0..60、cooldownSeconds[0,120]、operationSeconds[0,2]；旧setup无扩展不加键。命令launch-fire要求4名可用船员、真实活敌中心距≤70m及友船弹道通道清楚，speed28m/s、TTL4s、共用12s冷却；每次一枚，对应库存扣1，普通炮弹不变。投送后占4人2s，炮、扑救、登船均不能再用这4人。真实Sweep碰撞与水面TOI判命中；分别发fire-payload-launched/hit/splash，不能冒充普通fire/hit。

## 初始候选参数及数学

下列均是游戏参数，需实验，非史料伤害：两载荷初始heat均28，普通fuel18秒，thorn36秒；重复真实点燃加热／加燃料，分别封顶100／72。wetness降低新热量60%、燃料40%。无火时不因自然增长自行点燃。

每tick先推进湿润度`clamp(w+(rain*.10-(1-rain)*.02)/60,0,1)`；雨只经湿润度进入火势，不再叠雨伤害倍数。火势变化率为`2*(1+.75*flammableLoad)-6*wetness-1.5*effectiveFirefighters`。风首版只影响已声明烟迹，不伪造传播。

在本tick燃料、热量及工作预算允许的燃烧子区间，积分线性热量，船体损失=`heatArea*.00008*maxHull`，帆损失=`heatArea*.00022*maxSail`，船员损失先累计`heatArea*.00008*maxCrew`，只扣满1人的整数，余数持久保存。燃料耗尽或heat到0后停止DOT。不能在本tick提前灭火后仍收整tick伤害／工作费。

## 正式接线必须成立

1. 冻结旧native默认setup和三弹药oracle。扩展显式携带fireControl；新火球作为独立辅助投送，不借用普通炮弹hit的货损规则。真实未命中不点燃。
2. 状态贯通normalize、validated_update、snapshot、Campaign同步／setup与SaveCodec。Bridge逐tick重投不清火，远处活火及处理中的船不能退出权威后冻结。
3. 扑救减少可用炮组、后续齐射和登船余员；不得改变当前reload截止、延迟炮口due、总crew或凭空返弹。库存及采购有真实经济来源，旧档不免费补满。
4. 正式VFX只读heat和真实甲板锚点；灭火后余烟衰减，暂停、重建、读档及终局正确。UI能读懂起火、人员转岗、储备、灭火与代价。

## 验收与边界

先测纯核守恒／有限值／整数伤亡／资源枯竭／转岗／重复输入，再跑同初态人数、湿润、载荷、储备矩阵和敏感性。随后独立真实GPU观察火、烟、人员及暂停；之后接正式入口、原冷却、save、Bridge及伤亡回归。完整游戏平衡仍需同预算战斗、职责与长期经济，不以此局部核的支配检查代替。

暂缓相邻部件蔓延、毒性、权威烟幕遮视、真实热学、火药殉爆与火致货损。它们仍属于整体目标中的后续内容；本首版只建立可追溯火患／扑救循环。
