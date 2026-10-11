# Godot完整迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 原项目全部现有可玩功能迁移为Godot原生游戏，原网页版不变，并明确拆分物理、场景、海战、经营及UI。

**Architecture:** contracts共享单位和脱离运行对象的快照；physics/scene独立底层；naval_simulation和domain各自拥有规则；runtime单时间协调；presentation/UI只消费快照与发命令。资源先追溯复制，再经过Godot实际导入和画面验收。

**Tech Stack:** Installed Godot4.7.2、GDScript、Forward Plus/D3D12、Jolt、GLB和Godot原生Control。迁移开发工具可调用原JS产生参考fixture，成品无需Node或浏览器。

**Spec:** `docs/superpowers/specs/2026-10-11-godot-migration-design.md`

## Global Constraints

- 原网页目录只读；所有Godot产品文件写入用户指定独立目录。
- `modules/physics_engine`不得引用scene、game、UI；`modules/scene_engine`不得调用naval或domain；低层不得反引game。
- 同一五分量原波场、明确heading/GLB坐标适配、已消耗时间；不得暗改海面或船高。来源 Encounter 直接以 60 Hz 调用船只物理，迁移保留该步长；独立航行实验为 120 Hz，不能据此改变来源 Encounter。
- 保存、命令、伤亡、货物及receipt保持校验和守恒；不得以截图样机替代完整迁移。
- 所有shell/subprocess以rtk开头；Root负责Git、主项目设置、导入/导出、组合验证及真实画面验收。

## Review Focus

- GLB看起来正确但艏向/右舷/pitch符号错：姿态黄金样本和四方向炮击覆盖。
- shader墙钟与暂停物理波相位分离：暂停60秒再恢复的CPU/GPU截图时间合同覆盖。
- Godot数字/Dictionary恢复丢失ID或重复receipt：真实v1/v2、边界ID和重复导入覆盖。
- 资源存在却骨骼动画/共享材质损坏：实际18+3GLB、动画、重复退出和生命周期覆盖。
- 目录看似分层却依赖回环或UI直接改规则：静态依赖扫描与UI命令拒绝回归覆盖。

## Task1: 来源、资源与分层基础

**Files:** `tools/migration/import-assets.mjs`, `assets/migration-manifest.json`, `modules/contracts/simulation_contract.gd`, `tests/test_architecture.gd`, `tests/test_asset_manifest.gd`, `tools/run-tests.ps1`, 各模块README。
**Interfaces:** source文件只读；manifest记录sourceRoot/sourceHead/from/to/SHA256；contracts提供heading/坐标姿态适配及SIMULATION_STEP=1/60、PHYSICS_STEP=1/120，不依赖业务。

- [ ] 先测试低层反向依赖被拒绝、四方向姿态合同、21GLB及原图/音频hash匹配；写真实断言RED。
- [ ] 实现只读导入及合同、模块说明；不生成占位模型，不复制node_modules/dist/.env。
- [ ] 原生解析及聚焦测试GREEN；Root完成实际Godot导入、模型/动画来源核验，独立review。

## Task2: 原波场和地形合同

**Files:** `modules/physics_engine/ocean/wave_field.gd`, `modules/scene_engine/terrain/height_field.gd`, `tests/fixtures/ocean-terrain-reference.json`, `tests/test_ocean_terrain.gd`, `tools/migration/export-ocean-terrain-reference.mjs`。
**Interfaces:** WaveField.sample(x:float,z:float,time:float)->Dictionary{height,gradient,normal}；HeightField.sample_height(x:float,z:float)->float，configure_ports(Array[Dictionary])；shader通过descriptors消费相同五波数据。

- [ ] 从原oceanWaves和mingqi geography只读导出多位置/时间黄金数据；有限/非法坐标、坡度/法线/浅滩和三港真实坐标测试RED。
- [ ] GDScript移植原数学，不调用墙钟，不引用game。地形用注入ports和原公式，后续旧1661地形独立配置。
- [ ] CPU黄金对照GREEN、模块依赖GREEN，独立review；Root验证shader同相位之前不宣称水面完成。

## Task3: 原生世界与海面

**Files:** `modules/scene_engine/world/world_view.gd`, `terrain/terrain_chunk.gd`, `ocean/ocean_view.gd`, `ocean/original_water.gdshader`, `assets/asset_library.gd`（归scene_engine），`tests/test_world_lifecycle.gd`。
**Interfaces:** world.configure(height_sampler:Callable,wave_descriptors:Array)->void；world.apply_snapshot(snapshot:Dictionary,consumed:float)->void；只创建/清理自己拥有的Nodes，资源库缓存PackedScene而不共享活动Skeleton。

- [ ] RED同一sampler决定岛形/浅滩与碰撞、反复创建释放、暂停波相位、迟到加载不接入。
- [ ] 移植原水shader绿色/透明/反射意图、岛地形/植被/码头、LOD与资源加载；用原GLB，不能换平面方块船。
- [ ] Root实际渲染和截图，CPU/GPU波合同及生命周期GREEN；独立review。

## Task4: 舰船受力与操船

**Files:** `modules/physics_engine/ships/ship_physics.gd`, `ship_parameters.gd`, `manual_handling.gd`, `tests/test_ship_physics.gd`, `tests/fixtures/ship-reference.json`。
**Interfaces:** configure(spec:Dictionary,terrain:Callable,waves:RefCounted)；step(delta:float,controls:Dictionary)->Dictionary；get_snapshot()->Dictionary，波四点浮力、前进/低速舵/均衡与真实模式保留。

- [x] 原source导出120Hz四方位、顺逆风、低速转舵、帆速、吃水/搁浅及水线RED黄金轨迹。
- [x] 逐函数移植原核心参数/受力/积分，Jolt适配不改变浮力合同；非法输入全拒绝不污染状态。
- [x] 数值/稳定性/原生画面GREEN；Root真实W/S/A/D手感及原波水线截图，独立review。

## Task5: 海战、导航与舰队

**Files:** `modules/naval_simulation/encounter.gd`, `navigation/wet_route_planner.gd`, `tactics/order_controller.gd`, `combat/cannon_system.gd`, `combat/projectiles.gd`, `tests/test_naval_simulation.gd`。
**Interfaces:** command(Dictionary)->Dictionary；step(1/60)；snapshot()->Dictionary；drain_events()->Array；reconcile(Array,policy:Dictionary)->Dictionary，原5+1舰身份、六战术、保留来源 Encounter 的直接 60 Hz 船只积分。

- [x] 炮数/弹药/装填、真实/均衡、六命令、AI、路径失败/有界采样、禁航AI漏炮及惯性黄金反例RED。
- [x] 移植弹道/碰撞/伤害/沉没、wet route、tack/避碰/重试、原子reconcile，不用电影动画代替实弹。
- [ ] 规则/守恒GREEN；Root三船/六船实际交战/绕障及性能，独立review。

## Task6: 水手与击飞

**Files:** `game/presentation/ships/ship_view.gd`, `crew/crew_view.gd`, `modules/physics_engine/impacts/articulated_impact.gd`, `game/presentation/effects/sea_combat_effects.gd`, `tests/test_crew_impacts.gd`。
**Interfaces:** 同一个naval snapshot/event决定活动人数、岗位/装填、碰撞与Jolt冲量；LOD切换保持伤亡，不保存表现刚体。

- [ ] RED实际18bones/六clips、炮手岗位、最多12impact active、暂停/落水/非伤亡返回、late资源及重复dispose。
- [ ] 接入已有三水手LOD、甲板支持/障碍/动画和Jolt关节击飞，保留实际人员伤亡生产者。
- [ ] Root实际炮弹击飞和动画截图/守恒/资源GREEN；独立review。

## Task7: 1650经营与近远场

**Files:** `game/domain/mingqi/campaign.gd`, `convoy.gd`, `port_work.gd`, `boarding.gd`, `prizes.gd`, `traffic.gd`, `navigation.gd`, `game/runtime/mingqi_runtime.gd`, `near_field_bridge.gd`, `tests/test_mingqi_rules.gd`。
**Interfaces:** 原v2 canonical状态、command/advance/serialize/restore和nativePolicy；Runtime唯一时间，命令与桥接原子拒绝。

- [x] 原原子拒绝、幂等、两合同货物/人员、近远场交接、八方位水深、治疗时间、损伤保留、卖船立即退役RED。
- [x] 逐模块迁移，不将状态写进Node/UI，不用随机任务替代原合同；UI全语义另接Task10。
- [ ] 黄金规则/实际救治俘获/护航循环GREEN；独立review。

## Task8: 1661生涯与四类遭遇

**Files:** `game/domain/legacy/adventure_session.gd`, `encounters/{duel,land_battle,treasure,banquet}.gd`, `tests/test_legacy_adventure.gd`。
**Interfaces:** 保留原六港/六主线、经营/装备/退休/投降、四遭遇规则和v1状态。

- [x] 原已实现选择、收益/损失、任务解锁、退休和四遭遇真实样本RED。
- [x] 原生移植全部现有规则；不把未实现历史规划编成新玩法以代替迁移。
- [x] 状态机/真实流程GREEN，独立review。

## Task9: 原生保存及网页兼容

**Files:** `game/domain/persistence/save_codec.gd`, `game/runtime/persistence/save_coordinator.gd`, `tests/test_save_compatibility.gd`, 真实且脱敏必要的已有游戏JSONfixture。
**Interfaces:** user://独立槽位；导入网页v1/v2、Godot新版本；validate/read/write/export备份保持原始bytes及稳定ID，nooffline advancement。

- [ ] RED真实继续、pending care、未知版本、uint32极值、重复导入、写入失败及旧bytes不变。
- [ ] 写临时/验证/提交/恢复，校验成功后才换Runtime；继续船上初始化，UI显示真实失败。
- [ ] Root真实导入/保存/退出/继续GREEN，独立review。

## Task10: 原生UI、镜头、声音与全部入口

**Files:** `game/ui/{main_menu,sailing_hud,port_panel,fleet_panel,tactics_panel,boarding_panel,save_menu,settings_menu}.gd/.tscn`, `game/scenes/*.tscn`, `game/presentation/{camera,audio}/*.gd`, `game/runtime/game_router.gd`。
**Interfaces:** UI发意图给对应Runtime，所有显示从只读快照派生；8个原入口/验收工具齐备。

- [ ] RED双击命令/旧panel回调、输入框按键/失焦/菜单暂停、镜头独占、音频开关及迟到加载。
- [ ] 原生Control重建原美术风格、关键状态清晰、游戏设置和大小适配；别把迁移内部细节塞进玩家HUD。
- [ ] Root全部UI亲验截图、模式进入退出、输入与资源GREEN；独立review。

## Task11: 在线协议及原开发工具对应

**Files:** `modules/realtime_client/*.gd`, `game/scenes/network_lab.tscn`, `tools/editor/*.gd`, `tests/test_realtime_protocol.gd`。
**Interfaces:** 保留现有可恢复client控制协议与快照语义，连接服务器为外部可选依赖，离线成品正常运行。

- [ ] 真实已有wire fixture/断线/重连/controlSeq/owner fence RED。
- [ ] 原生WebSocketPeer适配、物理/地图/船只检阅及验收工具按inventory迁移；旧不可运行服务器明确保留外部状态。
- [ ] 可用协议端到端验证；不可用外部状态如实记录，不伪造MMO成功，独立review。

## Task12: 完整验收与Windows交付

**Files:** `export_presets.cfg`, `tools/{run-tests,verify,export-windows,capture}.ps1`, `docs/migration/acceptance-matrix.md`, `README.md`。

- [ ] 全模块原生测试、依赖检查、资源清单、源码parse/import及场景启动；逐入口真实成功和失败路径。
- [ ] 原海面、八向航行、水线/船尾/水手、炮火击飞、港口/修理/贸易、所有小游戏、两代真实存档，Root截图验收。
- [ ] 三/六船20s预热+60s性能、重复加载释放、无缺失依赖；导出Windows包并实际启动。
- [ ] 对完整inventory逐条PASS/FAIL/未测，未完成项继续；原网页Git和文件身份核验不变。完整通过才能宣布迁移完成。
