# 破损细节：2026-10-13 当前源码审计

本轮只读生产源码，新增本审计；主线程确认旧纹理用例 RED 后，仅修 `tests/test_reference_damage_textures.gd` 的发现/检查逻辑。范围：当前 `C:/Users/dains/Documents/Git/ming-armada` Godot 工程；旧 `MingArmada` Web 工程不作为接入证明。主线程已确认 CodeGraph 未索引，依派发要求使用 RTK fallback，不建立索引。本子线程未启动 Godot、REA 或浏览器，未运行测试。本文新增明确区分主线程本轮实际证据与当前断言覆盖范围；旧报告仅用于查找命令，未采用其通过数或旧截图作为当前完成证明。

## 当前接入及其边界

| 细节 | 当前源码证据 | 本轮判定 |
| --- | --- | --- |
| 船壳损伤层 | `ship_model_provider.gd:54-75,120-126` 给来源 hull/sail 标语义，绑定 hull 的 player/upgrade/UV2；`ship_damage.gd:30-89,110-136` 创建独立材质并按 hull 损伤每 20% 换档；`ship_damage_surface.gdshaderinc:62-74` 以原 UV2/alpha 优先级混合颜色层，壳保持不透明。 | 已接入。属于纹理/颜色破损，没有壳体几何缺口、贯穿孔、碎裂剥离。 |
| 帆洞、焦边 | `ship_damage.gd:111-114,128-142` 按 sail 健康换档；`ship_damage_surface.gdshaderinc:34-59` 原图 alpha `<160/255` 裁剪并局部染焦边，缺图用有界不规则裂口。 | 已接入。命中位置没有进入破损纹理；整船同档、各帆纹理损伤同步。 |
| 断桅 | `ship_damage.gd:115-157` sail 全损触发 2.666667 秒倒伏，对全部 mast 用同一个 `Basis(Vector3.BACK, progress²*1.45)`；真实 mast 子树带帆/横桁/木料，flag/rig 跟随。 | 已接入游戏自定义倒伏适配；不是来源动画轨道重放。没有单桅独立 HP、指定桅杆断裂、断木脱离、自由落体或漂浮残骸。 |
| 沉船 | `ship_damage.gd:117-168,289-293` hull 全损触发 4.125 秒下沉倾斜，+0.25 秒爆炸，+1.416668 秒泡沫，结束隐藏所有船模型；`ship_view.gd:118-121,259-265` 发事件并防止 LOD 复活。 | 已接入表现器；**主线程已在正式 Mingqi 回调链复现终局冻结，见下文 CPU 证据**。 |
| 命中/断桅碎片 | `combat_effects.gd:91-101,121-126` 使用同一种 `BoxMesh(0.24,0.18,1.0)`，6/8 个固定方向小块；位置=origin+velocity*age，渐大渐隐。 | 有简化木屑；没有角速度、重力、碰撞、真实断件形状、落水/漂浮生命周期。 |
| 爆炸烟 | `combat_effects.gd:127-129` 实际 destruction 事件产生 1 个 0.18 秒 flash +8 个 3 秒原 DDS 烟贴图。 | 有有限爆炸烟；不是来源 `fx_ship_destruction_explosion` 完整控制器/粒子层接入。 |
| 燃烧烟/火灾 | `reference_particle_model.gd:218` 支持 burning smoke 连续模型；当前唯一产品无关用例 `test_reference_particle_model.gd:37-74` 手动 spawn/stop 烧船烟；`combat_effects.gd:109-133` 实际事件表没有 burning smoke 分支。 | 底层有数据/采样能力，正式游戏未接起火、持续燃烧、灭火。 |
| 修理恢复 | `campaign.gd:916-944,961-987` 有定价、工期、到期 hull/sail 恢复；`ship_damage.gd:119-142,143-162` 每帧健康恢复能清旧倒伏/沉船与材质档位。 | 规则已接入，表现器具备恢复路径；缺真实港口服务结束到原材质/立桅的同场景联合验收。 |

引用路径：上表 `ship_damage*`、`ship_view.gd` 位于 `game/presentation/ships/`，`combat_effects.gd` 位于 `game/presentation/combat/`，`ship_model_provider.gd` 位于 `modules/scene_engine/assets/`，`campaign.gd` 位于 `game/domain/mingqi/`，`reference_particle_model.gd` 位于 `modules/scene_engine/fx/`。

## 正式终局与 QA 的差异（优先复现）

1. Mingqi：`game/runtime/mingqi_runtime.gd:208-231` 在舰队旗舰 hull<=0 的同一 accepted tick 设置 `result` pause；`:210,217` 暂停后不再推进 native time。`game/scenes/mingqi/mingqi_scene.gd:133-166` 将这个 native time 送给 `NavalWorldView`。破损器刚把 `_sink_start=now` 记录完，未来的 0.25/1.4167/4.125 秒可能永远不被接受；应实测是否停在 sinking_age=0，而非把独立 ship 测试当正式终局通过。
2. 普通 duel/fleet：`game/runtime/naval_practice_runtime.gd:94-102` 在 victory/defeat/surrendered 设置 result pause；`modules/naval_simulation/encounter.gd:1055-1072` 最后一艘敌船 sunk 的同一 tick 结算 victory。`game/scenes/naval_practice/naval_practice.gd:53-57` 仍把冻结的 native snapshot 送 sea，最后靶船的沉船尾段同样可能冻住。
3. QA：`game/runtime/visual_qa_runtime.gd:153-170` 只对 wave/benchmark 自动暂停，不对胜败暂停。`tests/test_visual_qa_runtime.gd:35-45` 证明 scope 是 QA 实弹打到 0HP/sink 事件；不能证明普通 duel/fleet 或 Mingqi 的终局尾段。

主线程本轮 **CPU 复现已确认 Mingqi 旗舰终局冻结**：`Temp/audit-terminal-sink.gd:21-31` 用公开且已验证的 `encounter.update_ship_stats(id,{"hull":0.0})` 放置终局健康 fixture，调用真实 Mingqi `_physics_process/_process`，再请求 50×0.1 秒回调。`Temp/terminal-sink-audit.json:12-37` 记录：初次和最终 native.time 均 `0.0166666666666667`、pauseReasons 都为 `["result"]`、最终 sinking_age=`0.0`、ended=`false`、模型 Y=`0.0`、visible=`true`、foundFreeze=`true`。这是实际产品 Scene/Runtime/ShipDamage 回调的终局状态诊断，**不是实弹飞行命中、GPU 帧或 FPS 证据**。普通 duel/fleet 同类问题仍是上文源码判断，尚无本轮运行确认。

主线程 `Temp/damage-detail-audit-verification.json:179-260` 保留本轮原始测试证据：旧 texture 用例在 `_run:30` 访问 null `material_override`，60 秒 watchdog 超时，没有 completion marker；`test_reference_ship_damage` 为 `844 assertions/0 failures`，`test_ship_damage_materials` 为 `18 assertions/0 failures`。3项中2通过/1失败，不称整组完成。纹理用例只修改测试，换为全部语义网格+逐material slot的安全检查，扩大同型健康隔离至六型三LOD，保留11张SHA/档位/mips/缺图fallback合同；修改后的运行结果由主线程另行保存，原 RED 证据不覆盖。

## 独立伤损字段仍是保留数据

`game/domain/mingqi/campaign.gd:38` 初始化 `mast/portGuns/starboardGuns=100`、`fire/flooding=0`；`game/domain/persistence/save_codec.gd:265` 允许存储这些字段。全项目当前写入/消费搜索仅发现火灾与进水用于靠港/战利品安全拒绝 (`campaign.gd:134,1035`、`game/runtime/native_readiness.gd:23`)。

实战 setup `campaign.gd:1120-1127` 只投 hull/sail/crew；native state `modules/naval_simulation/encounter.gd:127-131` 和命中扣血 `:471-482` 也只有 hull/sail/crew。不存在把单桅或炮组健康降为破损的命中链路，也不存在起火/进水增长、持续 HP 流失、救火/排水或修复其数值的业务链路。

## 事件细节及视觉边界

- `ship_view.gd:118-120` 把所有 mast-break/destruction/froth 的 position 设为当前 ship global position。没有按断桅节点设置木屑出生位置；大步跨键也没有用该 scheduled birth 的历史船位。时间键准，但位置细节仍简化。
- `game/presentation/world/naval_world_view.gd:165-166,198-230` 创建真实 Ship，连 `presentation_event` 到 CombatEffects，每次给 native.time、native.wind；因此破损并非只存在于图鉴/独立测试。
- provider `:30-45,254-255` 的三 LOD 是三个独立节点但共用同一来源 lowend (`same_source_lowend`)；不要把“三 LOD 断言”解读为三种真实源细节网格已全部迁移。

## 当前测试确切支持什么

| 用例 | 当前断言 | 不支持的完成说法 |
| --- | --- | --- |
| `tests/test_reference_ship_damage.gd:31-119` | 六型 shader 参数、健康档位；手工 time 驱动倒桅/沉船，键去重、scheduled time、LOD 隐藏、载入 terminal seek；time 倒退回 healthy。 | 普通战斗/生涯终局尾段；真实港口修理恢复；来源预制完整动画；GPU 帆孔/焦边观感。 |
| `tests/test_reference_damage_textures.gd:15-134`（本轮测试修复后） | 原11张PNG/SHA合同；全部 `damage_surface` hull/sail 网格（legacy同生产名字fallback）；逐 `get_active_material` surface 检查 ShaderMaterial/档位/图谱路径/mips；六型三LOD同型健康实例隔离及不污染；legacy+当前source缺图fallback。 | GPU图层/帆洞像素观感；当前版本的通过结论需主线程新GREEN证据。旧固定node名版本轮已RED，未隐去。 |
| `tests/test_reference_dismast_assembly.gd:16-69` | 六型每 LOD rendered mesh 高度<原高60%、masthead flag deck pivot、附件 local transform、固定尾旗、暂停、回退恢复。 | 物理断件、单桅独立损伤、正常时间向前修理完成恢复、正式终局。 |
| `tests/test_ship_damage_materials.gd:10-44,51-66` | 合成多材质网格 albedo/UV 保留、dispose 恢复材质；合成固定尾旗不随桅落。 | 六种实际来源船材质 GPU 像素完整等价。 |
| `tests/test_combat_particle_visuals.gd:11-34` | 手动 destruction 事件生成9个贴图Quad、去重、mips、透明材质、按 accepted age 衰减并释放。 | 完整来源爆炸粒子、正式致命炮击事件/终局、烟的GPU遮挡层序与观感。 |
| `tests/test_reference_particle_model.gd:37-74` | 手动 spawn 多种 source effects，包括burning smoke，世界空间烟不随船瞬移，stop 后释放。 | 产品有起火状态/燃烧烟接线。 |
| `tests/test_mingqi_rules.gd:24-45,77-84` / `tests/fixtures/mingqi-reference.json` portSteps | 以合成 native context 跑 dock/repair/refit/advance120，比较全部业务状态和存档。 | 真正 Native Sea+ShipDamage 的修理视觉恢复。 |
| `tools/capture-native-qa.gd:59-76` | 全QA场景截图，sink点击开炮后发现 sailors.impacts.active>0 就截图；只impact-weak另推130tick。 | sink在+0.25/+1.4167/+4.125的逐阶段验收；当前脚本不专门等沉船结束。 |

## 主线程建议测试/截图

本子线程不执行，以免占用主线程 GPU。当前已知本机运行器路径见 README `:30`。短测可逐项直接执行，避免整套耗时和旧证据覆盖：

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_reference_ship_damage.gd
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_reference_dismast_assembly.gd
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_reference_damage_textures.gd
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_combat_particle_visuals.gd
```

建议新增 `Temp/` 独立审计 probe（不改生产）再按相同 `--script res://Temp/...gd` 跑：

- 同一实例先healthy、真实致命炮击，再逐1/60推进5秒；分别正式 duel 最后敌船、Mingqi旗舰、QA sink。输出 runtime.pauseReasons/time、damage_diagnostics、模型visibility/Y、CombatEffects event IDs。核对终局模式是否有尾段。
- 正常时间向前，真实 dock→repair→work-completed；读取 ship shader damage_stage/use_reference_damage、mast basis 与模型高度，核对复原和不重放mast-break。
- GPU只录当前 audit目录，沉船0/0.3/1.5/4.2秒分别截图；healthy/damaged壳与帆近景、断桅半程/终态、六型至少受损远近对照。不要沿用capture脚本固定旧目录，也不要把已经冻住的native.time人为改大后称正式完成。

