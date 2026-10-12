# 《海上明旗》参考效果融合 Implementation Plan

> **For agentic workers:** 使用 superpowers:subagent-driven-development 或 superpowers:executing-plans，按下列独立交付推进。用户已授权多专家实施；无需重新请求设计或执行确认。公共场景接线、最终冻结与真实 GPU 验收由主 Agent 集中负责。

**Goal:** 学习目标 EXE 和完整资源库中值得借鉴的贴图、算法、控制器与视觉组织，融合进现有 Godot 游戏，保留已经接受的好效果，逐项完成海域、战斗、人物、港口、界面与声音体验。

**Architecture:** `modules/contracts` 定义跨层数据；物理和海战模块拥有模拟权威；场景模块负责可复用地形、水面、粒子与天气；`game/presentation` 将本作快照和事件转换为表现；UI 发出指令，不能通过效果修改人员、伤害、货物或存档。原件、静态路径、教学适配与 Godot 实测分开记录。

**Tech Stack:** Godot 4.7.2、GDScript、Godot spatial/sky shader、现有 Jolt 与 authored GLB；只读 PNG/DDS/NIF/KF/KFM/原 shader 及限定数学证据。

**Spec:** 用户最新要求是“只取好的算法、贴图、实现”，并非原样复刻原作。视觉效果优先，不在本阶段以性能优化、质量降级替代效果实现。海岛细节、沙滩和浅蓝海水柔和过渡优先于粗白描边。整体继续保留船长操船、可暂停舰队指挥、贸易/护航/劫掠、历史冒险的原目标。

**最新分工补充：**海岛、岸线与海面参考逆向由外部 REA Agent 继续负责；本地团队转向剧情等其他方向。本文件作为当前覆盖快照冻结，不据此继续修改海域生产代码。W0 保留为外部海域成果到正式游戏的交接/验收合同；本地故事闭环审计可独立并行，不必等待外部重新分析完毕。外部原件与报告仍按下述证据层级择优吸收，不能自动覆盖本作已接受效果。

## 全局约束与证据锚点

目标原件为 `C:/Games/Pirates.Green.Edition-ALI213/Pirates!.exe`。本任务只读重新计算 SHA256，确认：

```text
0da87d60243280dea5965dbb23d099bcd0727db344de35886a5207e487a7e120
```

参考根为 `C:/Games/Pirates-REA-Reference-20261011`。完整 Pak0–Pak8 范围由 [提取清单](C:/Games/Pirates-REA-Reference-20261011/reports/extraction-manifest.json) 锚定，共 **9 FPK、15,109 条归档条目**；各归档的原 SHA 收入 [机器覆盖表](reference-effects-coverage.json)。这是完整搜索范围，不是全部条目已解析、导入或实现。本轮未重解包或重新计算九个大型归档的散列。

声音另在 `raw/loose/Assets/Sounds`，本轮观察到 **1,137 个 WAV**；它们不能被算作 FPK 内资源，也不能以文件数替代听感验收。

- 原参考目录保持只读。每次导入记录原件/预览 PNG/目标文件各自 SHA、实际 RGBA、单位与坐标转换；PNG 一致不等于原 DDS 字节一致。
- 原 EXE 的 REA 身份由主 Agent 已核验。本任务不重复打开分析数据库，不启动原游戏 UI；本机 REA native UI 对 Windows 的限制不妨碍读取已经取得的原件和数学证据。
- CodeGraph 已实际返回项目无索引，当前源码审查采用 RTK 定向读取。没有虚构索引、调用图或原帧。
- 正式海面继续使用权威五波与接受的模拟时间；效果不得另用墙钟、shader `TIME` 或独立粒子 process 推进游戏时间。
- 保留原有明亮水色、波面一致、船尾水花、可读水柱、3D 水手、真实击飞及本作舰船。不得因外部报告重建原 DX9 的指示而删除这些效果。

## 阅读新报告的正确方式

已读最新 [REPORT.md](C:/Games/Pirates-REA-Reference-20261011/REPORT.md)、[FIDELITY_AUDIT.md](C:/Games/Pirates-REA-Reference-20261011/FIDELITY_AUDIT.md) 和 [fidelity-rebuild 入口](C:/Games/Pirates-REA-Reference-20261011/fidelity-rebuild/README.md)、[外部 SPEC](C:/Games/Pirates-REA-Reference-20261011/fidelity-rebuild/SPEC.md)、[外部 PLAN](C:/Games/Pirates-REA-Reference-20261011/fidelity-rebuild/PLAN.md)。

它们纠正了旧资料中过强的“原版已经恢复”结论，值得采用其证据纪律。它们要求平面替换几何波、重建原 DX9、移除教学近似等内容属于**外部逆向工作区的任务**，不会自动成为本游戏的实施指令。我们的选择标准是实际效果、可读性、游戏性和当前架构合同。

| 证据类型 | 能证明什么 | 本项目如何使用 |
| --- | --- | --- |
| 原件/解析 | 身份、几何、UV、RGBA、控制器、声明槽 | 优先复用合适原件，验证实际通道和本作尺寸 |
| REA/直接 IDA 静态路径 | 特定函数、分支、状态、参数关系 | 采纳有益规则，记录地址/工具；不冒称当时帧实际执行 |
| 限定原生数学 | 指定输入下的指定函数输出 | 作为移植回归；不扩称全引擎/全战斗等价 |
| 教学适配 | 新算法、新 shader、新调度可运行 | 好的实现可以借鉴，但标明选择、倍率和省略项 |
| Godot CPU | 资源接线、真实 API、数学与生命周期 | 做小范围有效回归；不能代替像素/动画验收 |
| Godot GPU | 当前场景/相机/时间的真实截图或读回 | 主 Agent 亲自查看，关联冻结源码与完整入口 |
| 原游戏运行帧 | 原作当时真实行为/画面 | 当前未完整取得；不作为本游戏完成的虚假前提 |

旧 `deep/demo`、`island-water/demo`、`atmosphere-fx/demo` 包含新的 Gerstner、Fresnel、随机云、代理动画和调度。浏览器验证只证明那些学习实现。新的 `fidelity-rebuild/shore` 已有原短浪片/UV/控制器回放；`atmosphere/native-semantics.mjs` 已增加 CRT、云 update、控制器和部分 modifier 语义，但完整 `generateParticles()` 仍显式拒绝未知的原出生调度。不能把“最新入口”或“53 纹理/276 系统参数”写成 Godot 已实现全部效果。

## 覆盖清单：所有值得借鉴的类别

以下状态是当前源码与留存证据的快照。“已有”表示功能代码存在；新冻结批次最终 GPU 和导出验收仍由主 Agent 负责。每项的准确源码入口、原资料入口、缺口和证据见 [reference-effects-coverage.json](reference-effects-coverage.json)。

| 类别 | 当前本作情况 | 借鉴/下一交付 |
| --- | --- | --- |
| 海面色层、水纹、微光、白浪 | 已有正式融合和一次原微光调用 | 保留好水色；最终微光尺寸/覆盖复拍 |
| 倒影、折射、透明层 | 已有共享世界平面镜像与深度光学 | 天气/烟接入后逐类验证透明排序和镜像 |
| 海岛地形、沙滩、浅滩 | 三种原轮廓已适配 | 本作尺度明确；角色选型与新构图验收 |
| 森林、岩簇、草地、渔业细节 | 实际坡肩/支持脚点布置已完成 | 森林美术层次、房屋实际避让与港口生活 |
| 动态岸浪、羽化边缘 | 薄浪沫及浅蓝过渡已接入 | 保留自然断续；不画粗白圈 |
| 湿沙、海底渐变、焦散 | 当前本作光学与程序材质已有 | 区分程序适配与未知原焦散绑定 |
| 船首/船侧泡沫、转弯尾迹 | 运动历史带和原 alpha 已有 | 保留转弯轨迹与水面一致，不再重做旧白方块 |
| 炮弹水花、水环、雾滴 | 七原网格/八系统已叠加原强反馈 | 真实炮弹事件到视觉；原调度未知项明确 |
| 炮口火光、分层炮烟 | 当前短闪加六灰球 | 用原 RGBA、发射窗、父 TRS 和分层烟替换简化表现 |
| 弹种外观与烟迹 | 通用球弹已有 | 链弹/葡萄弹可读区别；保留权威弹道 |
| 木材受击、火星、碎屑 | 当前棕球反馈 | 有方向的纹理/网格碎片及甲板/水面分流 |
| 持续伤烟、船火、余烬 | 尚无持续桥 | 真实损伤阶段驱动，出生后烟脱离移动船 |
| 毁船爆炸与残骸 | 文本键和灰球已有 | 分层火团/烟/碎屑；容量、结束、回收有证据 |
| 天空、飘云、云倒影 | 程序天空已有，独立纹理云未接 | 原云几何/alpha＋连续风移的本作改进 |
| 海雾、地雾、距离雾 | 基底距离雾已有 | 原雾片/曲线；全表现只雾化一次 |
| 晴天/夕阳/风雨/雷电/风暴 | 参考场景预设已有，完整天气未接 | 连续天气过渡与有用途风暴事件 |
| 舰船与帆装、壳/帆损伤 | 六船/三 LOD、十一张现成损伤图已用 | 保留中国船；帆洞裁剪和壳损不透明语义正确 |
| 断桅 | 真桅杆、帆、索具和旗帜一起倒下 | 保留原触发键；后续补断木/落水表现 |
| 沉船 | 模型下沉、倾斜、表面泡沫已用 | 补持续烟/浮木，终态载入不补播历史爆炸 |
| 甲板人物动画 | 3D 骨骼与岗位动作已有 | 借人数/岗位调度，不退回 billboard 替代3D水手 |
| 击飞、落水、浮木和拾救 | 真 Jolt 击飞/入水已有 | 游泳/浮木/救援属于缺口；收益必须 domain 结算 |
| 港口、岸防、据点与生活 | 码头/建筑/摊位/木舟已有 | 明朝港口、荷兰要塞与岸防职能有区别 |
| 海图、小地图、射界和导航 UI | 古海图、真实轮廓、任务/舰队标记已有 | 新火情/天气/救援/据点状态清晰接入 |
| 声效 | 合成音、音乐、距离混音已有 | 精选原炮声、木裂、帆风、水花、雷声，实际耳听 |
| 操船、炮击、碰撞与游戏性 | 辅助操船、五波/物理、炮击已有 | 借惯性/极线经验；不机械复制原整数单位 |

## 当前源码的额外独立审查

1. [ReferenceGeography.options](../../game/scenes/common/reference_geography.gd) 将厦门分配给宽海湾 `coastal2`，金门用狭长 `cat_island`，补给点用 `virgin_islands`；业务选择在 game 层。`HeightField` 只做数据校验和适配，不嵌入港口名称，分层正确。
2. [WorldView._build_ports](../../modules/scene_engine/world/world_view.gd) 只在脚点验证并实际创建房屋后记录位置/半径，传入 `IslandDetails.existing_buildings`。空数组明确表示没有旧房；旧失败房屋不再形成“幽灵地块”。
3. **待补的视觉避让合同：**旧 [VegetationLibrary.populate](../../modules/scene_engine/assets/vegetation_library.gd) 当前调用只传港口，仍以港口中心 65 米避让，不消费实际旧房脚点列表。港外成功房屋附近仍可能长出源树。这是静态可确认的缺少合同，尚未声称截图已发生重叠。最小修复为可选附加房屋 footprint 排除，保留旧默认调用；主 Agent 已接管此项。
4. 源植被 `gradient² ≤ 0.49`，新 canopy 用实测干地与独立坡度门槛。实际森林密度、树种和冠层颜色是美术验收内容，不能仅凭坡度测试称已达到参考密林。
5. [正式海面](../../modules/scene_engine/ocean/reference_game_water.gdshader) 已有 `reference_sparkle_fusion` include、一次 `reference_original_micro_sparkle(...)` 调用和实际 PNG 绑定；只读审查未发现重复叠加。其接受时间和原五波合同保持一致。

核查时当前 shader SHA 为 `412006c0...f6b231`，现存 [GPU 数学记录](evidence/reference-world-integration/gpu-math-probe.json) 的 shader SHA 为 `fa2e844d...00a7ec`。现存记录确实 `gpuExecuted=true`、10,131/0、五波/RF 读回，但仍是它所记源码的证据；主 Agent 最终批次应刷新源码哈希。实际 GPU/RF CPU 最大差约 0.0000299 米，权威 CPU 高度最大差约 0.0276 米；这不证明最终光栅插值或羽化观感。

## 实施顺序与可并行所有权

### W0：当前正式海域冻结与真实验收

**Owner:** 海域参考逆向为外部 REA Agent；正式交接与验收为主 Agent。本地团队当前不执行海域生产修改。**Files:** 现有 `WorldView`、`NavalWorldView`、正式海面和地形接线；新报告/截图放 `docs/migration/evidence`。

- [ ] 完成实际旧房避让、森林类型及业务层地形美术参数，保留纯模块无业务港名。
- [ ] 冻结实际 shader/网格/图像/数据依赖，刷新 GPU 数学记录的哈希。
- [ ] 实际菜单进入航海、海战、舰队、1650 港区、1661 旧航程；拍船长/战术/低近岸/远岛/直航/转弯/炮弹落水及暂停对比。
- [ ] 亲自查看原 PNG 与连续时刻，确认绿海底硬边、森林/屋脚/码头、微光、薄浪沫、船不被浪淹没、旧好效果保留。不要以联系表或数学通过替代逐项判断。

### W1：源粒子、炮烟、受击与持续烟火

本阶段可与 W2 的**独占新文件**并行，正式公共入口仍由主 Agent 顺序接线。

**Files:** 新建 `tools/import-reference-atmosphere.mjs`、`assets/data/reference_atmosphere/definitions.json`、`assets/textures/reference_atmosphere/*`；新建 `modules/scene_engine/fx/reference_particle_model.gd`、`reference_particle_view.gd`、`reference_particle_alpha.gdshader`、`reference_particle_add.gdshader`；新建 `game/presentation/combat/reference_combat_fx.gd`。主 Agent 修改 `combat_effects.gd` 和 `naval_world_view.gd`。

**Interfaces:** 新桥 `configure(definitions: Dictionary, camera: Camera3D, water_sampler: Callable) -> bool`、`apply_snapshot(native: Dictionary) -> void`、`apply_events(events: Array) -> void`、`diagnostics() -> Dictionary`、`dispose() -> void`。消费原快照时间与真实 fire/hit/终态事件，输出视觉节点和诊断；无伤害写入。一次性事件采用出生时世界变换；持续发射器记录接受相位中的船姿态，新生粒子采用当时姿态，已经出生的烟继续在世界空间演化。

- [ ] 资源专家读取完整合同与原件，转换到自有 schema。逐系统记录 `source_asset/block`、原 SHA、父层级、单位、坐标、启用窗口、速率、容量、寿命、颜色/GrowFade/Gravity/UV、实现或适配/未知原因。
- [ ] 粒子专家用实际字段/数学边界写失败测试，再实现纹理 alpha/additive 分层、有限出生/死亡/回收与世界变换。借用已证 modifier；未知原调度使用明确本作实现，不冒称恢复。
- [ ] 先把真正左右炮口 fire 的火闪/烟做出来，再加入受击木片/火星、持续伤烟/船火、毁船爆炸/余烬/残骸。保留现有炮弹、水花、事件 ID 去重、迟到年龄、暂停/回退清理。
- [ ] 测试 active 结束后旧烟仍活至寿命、移动船留下烟而非拖烟、未来事件拒绝、重复不重生、回退/载入不补播历史爆炸；覆盖负 start、非零 phase、不同 modifier 顺序和原 alpha。
- [ ] 主 Agent 截左右炮口、船/岛前后遮挡、运动船烟轨迹、不同伤情、爆炸峰值/消退与暂停。透明水面深度必须实测，不能只引用 `hint_depth_texture` 存在就称软交界完成。

### W2：云、地雾、天空与天气

**Files:** 新建 `modules/scene_engine/atmosphere/reference_weather_model.gd`、`reference_weather_view.gd`、`reference_cloud.gdshader`、`reference_ground_fog.gdshader`；天气定义放 `assets/data/reference_atmosphere/weather.json`。主 Agent 统一修改天空绑定、海/地形 fog 开关与镜像接线。

**Interfaces:** `configure(camera: Camera3D, options: Dictionary = {}) -> bool`、`apply_snapshot(native: Dictionary, accepted_delta: float) -> void`、`diagnostics() -> Dictionary`、`dispose() -> void`。消费实际风、接受时间与主相机；输出共享 World3D 的云/雾节点。天气视觉不拥有物理风、伤害或游戏钟。

- [ ] 核对原 cloud/groundfog/skydome/storm 资源层级与 RGBA，列明新 native update 和旧教学风移的取舍。
- [ ] 先写改风连续/暂停/回退/重建测试，再实现云层、真实 alpha 与主/镜像共用同一接受帧。Billboard 朝向不能在镜像 pass 再更新为另一份几何。
- [ ] 接入地雾与一套距离雾。开启统一雾前关闭原海/地形基底重复雾；零雾时所有路径均无残余雾化。
- [ ] 做晴天/夕阳/雾/风雨/雷电的平滑过渡，随后补原 storm KF/事件中值得借鉴的部分。原天气完整调度未知继续标未知。
- [ ] 主 Agent 截主视角/倒影同相位、改风前后连续、镜像裁切、战术上视 billboard、港口雾遮挡、零雾/一次雾化及天气过渡连续帧。

### W3：损伤、断桅、沉船、人物和救援增强

**Files:** 保留 `ShipView`、`ShipDamage`、`CrewView`、`ImpactPool`；W1 新桥挂接额外表现。若增加救援，新建 `game/domain/mingqi/rescue.gd` 与对应 runtime 指令适配，不在视觉模块结算收益。

- [ ] 用现成十一张损伤 PNG 与真实分档回归，保护船壳不透明、帆洞160/255、全部索具/旗帜跟桅倒下的现有行为。
- [ ] 增加断木/浮木/沉船烟和有限残骸；入水事件使用同一波面和岸线过滤。
- [ ] 保留真实3D水手和Jolt击飞，增强衣着、岗位/装炮动作与受击反馈。原 billboard 作为人数调度参考，不作为降低现有3D效果的理由。
- [ ] 若加入游泳/拾救，先测试存活、容量、距离、重复拾救和存档；domain 命令返回结算事件，再由视觉展示。不得仅因参考池有40槽就改变本作人员/奖励。
- [ ] 主 Agent 对六船/三LOD拍真实命中、断桅中段/末段、沉没/重进、击飞/落水/回收/救援及暂停。

### W4：港口、据点、UI与导航

**Files:** 海岛专家独占新沿岸模型与布置；界面专家独占 `game/ui/charts/nautical_chart.gd`、产品 HUD/港口面板的具体新增反馈，公共场景只由主 Agent 接线。

- [ ] 港口区分贸易码头、军需据点、渔村和荷兰要塞；可借原布局/尺度组织，建筑与生活美术保持明朝设定。
- [ ] 沿实际可支持干地加入仓储、船坞、岸炮与工事，保留上陆通道和真实航路，不以装饰修改导航地形。
- [ ] 新火情、烟/进水、天气、救援、射界与据点状态接入真实快照；海图继续显示实际地理/舰队/航线，不粘贴原加勒比地名。
- [ ] 主 Agent 验港区远近构图、屋脚和岸炮、海图与真实3D轮廓一致、窄窗可读与快捷键/暂停/返回路由。

### W5：精选声效融合

**Files:** 新建声效选择清单 `assets/provenance/reference-audio.json` 和按用途精选的 `assets/audio/reference_effects/*`；维护 `sound_palette.gd`，保留 `game_audio.gd` 生命周期合同。

- [ ] 先试听并记录 `common/CannonShot-*`、`WaterCannonHit-*`、`SailWind-*`，`sbattle/Cannon3Shots-*`、`Cannon6Shots-*`、`CannonReload-*`、`ShipCannonHit-*`、`SailTear-*`，`sailing/Thunder-*`。名称只是候选，最终内容以实际波形/听感确认。
- [ ] 选适合本作炮重、距离和节奏的非语言声，不批量导入1137 WAV；保留本作音乐、中文/明朝人物设计与现有提示音。
- [ ] 接稳定 event ID、事件位置、距离混音、暂停/静音与自然结束，测试同一齐射不失控叠响、重复事件不重播、换场不泄漏。
- [ ] 使用真实设备实际耳听炮声/木裂/水花区别、风帆背景和雷电同步；PCM/混音捕获可补证，不能替代听感。

### W6：全入口与完整冒险继续推进

- [ ] 新烟火、天气、港口和声音都通过 `NavalWorldView` 等正式入口融合，不能只存在于独立 demo。
- [ ] 验证菜单进入1650/1661、开航、贸易、护航、追击/撤退、炮击/俘获、修理、保存/加载、返回/重进的完整一轮。
- [ ] 逐项保存 final source SHA、场景/相机/接受时间、真实 PNG/连续帧、命令及测试结果；主 Agent 给明确已验/待验/未实现。
- [ ] 继续原完整产品中的台湾战役、政治关系、后续章节与结局；视觉覆盖通过不等于历史主线、商业网络和全游戏已完成。

## 完成与复审标准

每个效果只有同时具备**当前生产接线、行为/生命周期验证、实际画面或声音验收、明确来源与适配边界**，才能关闭该项。仅有贴图、参数、代码、独立教学截图或局部通过不关闭整类效果；不得再用一次海面验收宣布全部迁移完成。

已有 [60张旧 Godot 手工视觉记录](evidence/reference-implementation/manual-visual-verification.json) 支持船损、击飞、水花、海图等早期基线；它明确有旧屏幕空间光学局限，不能自动覆盖当前镜像/新海岛/细闪点/羽化代码。新冻结批次由主 Agent 单独记录。

Review Focus：不同相机/镜像透明排序；移动船已出生烟的世界空间；迟到/重复/回退/终态载入；不同港口轮廓和真正房屋footprint；全部产品入口与存档/人员权威。这五类均在上述所属工作流中安排实际验证，不以字符串检查代替运行。

本任务只更新本计划与覆盖 JSON、核查当前源码；未改生产、未开 GPU、未重新分析原游戏或做性能工作。当前整体目标保持进行中。
