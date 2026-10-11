# 破损与船员：参考落地记录

日期：2026-10-11。范围：批准计划 Task 3；仅修改本作 `ming-armada`，参考目录只读。实现保持海战已结算 hull/sail/crew 为唯一数值权威，没有第二次命中、减员、救援收益或船体力学积分。

## 原作依据与本作选择

读取 `C:/Games/Pirates-REA-Reference-20261011/naval-study/deep/README.md`、`asset-details/DETAIL.md`、`event-bindings.json`、`timelines.json`、`battle-details/DETAIL.md` 以及 `battle_state.py` 的 `FallingObject/FallingPool`。

- 原作壳损材质：逻辑伤害夹 0..100 后按 20 取档；帆损：先按 6 量化，再根据 subtype 取档。本作将既有健康值除以 maxHull/maxSail 后转成损伤百分比，再采用相同档位映射；20/6 是无量纲材质阈值，未当作米、秒或伤害结算单位。 authored GLB 的主帆采用 subtype 0；全损 sail=0 得 q=96、stage=4。
- 原作 Sloop 毁船文本键：爆炸 0.25 秒，泡沫 1.41666793823 秒，clip end 4.125 秒；断桅文本键 0.041666984558 秒，end 2.66666698456 秒。`timelines.json` 中毁船根 translation 有 99 键。这里采用这些事件时刻和时间范围，**未逐键复刻原作加勒比船的位移/旋转**。
- 本作断桅是自身 `mast_01` 等完整 rig 的平方进度倒伏，围绕真实甲板枢轴施加同一模型空间矩阵；沉船是模型子节点的平方下沉与倾斜。属于明确状态驱动的有限表现 clip；ShipView 根节点保持模拟快照姿态。未声称实时任意网格断裂或原作真实刚体碎裂。
- 原作远景甲板人物是 billboard、双平面图集。水中人物另有 23 骨蒙皮和 flying/floating_on_plank/swimming_in_place KFM；40 槽 FallingPool 有入水、浮回、严格距离救援和独立回收。它们是学习依据，**不能作为原作 ragdoll 证据**。
- 本作保留自身真实 18 骨水手 GLB、6 个 authored 岗位 clip、18 个 Jolt RigidBody3D / 17 个 PinJoint3D 接管。同一皮肤从动画转移到物理池，动画停止后骨骼 override 才由 Jolt 写入；恢复时清 override 并回岗位。未换成 billboard。
- 本作独立 spatial shader 已接入原作现成破损 PNG 的 RGB/alpha 语义，保留自身 authored 顶点颜色、粗糙度；帆洞使用 discard、合法双面薄帆。原作贴图正常存在时为主要路径，缺少所选档位才退回程序化破损。程序化帆洞经 GPU 审阅修正为 4/6/8/11 个稀疏纵向裂口簇、双频不规则边缘和邻近焦痕，取代规则圆点格；第一档参数椭圆面积小于布面 2.5%，所有档小于 15%。每个实例/LOD 持有自己的 override，不修改 AssetLibrary 共享 mesh/material。

## 运行合同与预算

`ShipView.apply_snapshot(ship, wind, consumed)` 继续兼容；优先使用 `ship.time`，由主线程给船与船员相同的 `native.time`。旧调用缺少 time 时沿用 accepted consumed。helper 私有开始时间只在全损状态变化时建立；命中事件不会再扣健康或重启 clip。

首次载入已断桅/沉船的快照，按当前全损状态 seek 到末态，不补播过去的烟爆。回退 accepted time 清理旧 clip/标记；健康快照恢复原模型局部位置。无需新 simulation/snapshot/save 字段。全部 6 船型、3 LOD 更新相同阶段、倒桅和下沉；终态切换 LOD 不会复活船。

ShipView 输出 `presentation_event(event)`：

```text
type: mast-break | destruction-explosion | sinking-froth
id: shipId:type:scheduledTime
shipId, targetId: ship identity
time: true scheduled accepted birth time
position: {x, y, z} world anchor
```

跨越文本键的大步长只发一次，子效果交给主线程的有限 CombatEffects 系统，自身不建立另一个特效计时器。

船员保持已有近/中/远 24/8/2、单船最多 24、全球 standing 最多 120、1800 米外释放 standing。物理池全球最多 12 个 articulated rigs，已结算损失只决定 casualty 标记；预算满时拒绝表现生成。非致死恢复 1.25 accepted 秒，casualty 最长 7 秒；入水 wet 生命周期最多 1.2 秒。该短生命周期是本作预算选择，未引入原作 40 槽全量人物/炮架/桶收益系统。

新增池级 target/event/slot 去重（256 条有限缓存）、重复 accepted phase 不重复老化、回退释放旧物理与皮肤、每帧损失预算不向后串账。入水状态第一次被真实 Jolt contact 观察到时只发一个 `crew-water-entry`，包含 body_id/target_id/event_id、Vector3 world position、accepted time。18 个骨骼碰水不产生 18 次水花。主线程负责连接该事件。

ImpactPool 的真实甲板三角形现在随 active ship model.global_transform 更新，包含沉船子模型的下沉/倾斜，避免不可见甲板仍留在 ShipView 根位置。暂停/回退/退出保留刚体冻结与幂等 dispose；没有 standing 动画和物理骨骼同时写姿态。

## 测试记录

全部直接运行指定 `Godot_v4.7.2-stable_win64.exe --headless --path ... --script ...`，不启动 GUI，不运行 `tools/verify-godot.mjs`。

| 测试 | RED 证据 | GREEN 结果 |
|---|---|---|
| `tests/test_reference_ship_damage.gd` | 初始 2 断言 / 1 失败：缺少 state driven damage diagnostics；帆洞簇扩展曾 RED 缺少 bounded cluster 数据 | 扩展后 235 断言 / 0 失败；6 船型 × 3 LOD、壳损档位边界、有限稀疏帆洞簇/面积递增、单次事件/真实 birth time、根姿态不变、下沉/终态/回退/释放 |
| `tests/test_reference_dismast_assembly.gd` | GPU 截图指出静态索具/旗帜仍直立；新增真实全网格高度/旗帜枢轴检查初始 243 断言 / 42 失败 | 243 断言 / 0 失败；6 船型 × 3 LOD 的全部 rendered mesh 顶点最高高度落至健康值 60% 以下，旗帜精确随桅杆枢轴倒伏，帆/横桁子树局部 attachment 不变，暂停无累计变换、回退恢复完整 rig |
| `tests/test_reference_damage_textures.gd` | 初始 2 失败：缺少原字节来源清单，真实材质未绑定原作 PNG | 1900 断言 / 0 失败；11 张源/目标 SHA、6 船型 × 3 LOD 每档绑定、完整档不绑定、全损主帆选择080、mipmap、私有材质与健康船隔离、缺图回退 |
| `tests/test_reference_crew_lifecycle.gd` | 初始 11 断言 / 7 失败：重复物理生成、缺少单次入水事件、重复 phase 老化、回退未清理；追加 sinking deck 断言再 RED 1 失败 | 13 断言 / 0 失败；真实 18 骨 Jolt 生成、去重、入水事件、回退预算/皮肤、甲板随 sinking model offset |
| `tests/test_crew_impacts.gd` | 已有真实回归，先审核并保留 | 578 断言 / 0 失败；真实骨骼 clip、6 船型/3 LOD 脚部支持、动画停止/接管/恢复、terminal hit、全局 cap、暂停、甲板碰撞、落水、生命周期/释放 |

已有 Jolt 回归直接读数：躯干 x 从 0 增到 1.333492；暂停前后位置一致；甲板 minimum_y=0.0501064，max_anchor_error=0.0376947；入水 wet=0.45，minimum_y=-0.125322。证明实际 native 物理路径，未以字符串检查代替运行。

`rtk git diff --check` 无错误。全项目回归、GPU 实际截图与品质审核由主线程统一执行，局部报告不将其声明通过。

## 真实未验收部分

- 本子任务仅 headless；GPU 上帆洞轮廓、焦痕对比、薄帆背面、重型船沉没覆盖与 shader 实际观感尚需主线程真实截图。
- 战斗主场景中连续炮击、低/远 LOD、终态与用户暂停/重新载入的交互验收由主线程完成。
- 尚未实现任意壳体几何 fracture、完整原作 KF 每条旋转/位移、原作人物图集替换、23 骨 KFM 导入、浮木/原地游泳、40 槽炮管/炮架/桶/救援收益。当前本作保留真实 3D 水手和有限物理击飞，并按本作权威快照与生命周期完成回收。

Ruling: 沿用既有骨骼/Jolt 模块，仅补真正缺口，避免重复构造影响池；无 authority rescue 写入，因为参考救援收益不等于用户授权改变本作战斗数值。Ruling: 首次终态加载直接 seek 结束，不猜测缺失的历史开始时间，也不添加第二时钟。

## GPU 反馈后的结构修正

主线程实际 `mast-break-mid.png` / `mast-break-end.png` 证明初版仍留下高位直立索具与旗帜，不能凭材质或旋转单个节点宣称断桅验收。已读取这两张图并追到实际 authored exporter/GLB：sail 与 yard 已是 `mast_XX` 子树，shrouds/ratlines 则以 rope 顶点色合并进根级 `fittings_trim`，`flag_01` 也是根级兄弟。

修正保持原 GLB/exporter 只读：加载实例时按真实三角形连接分量（顶点按 0.1mm 焊接处理 cap/seam）、rope 顶点色、桅杆邻域/高度分离出各 mast 的索具批次；保留低位栏杆/艏楼/甲板 fittings 与全部原颜色/normal/UV。每桅杆最多增加一份索具 mesh，LOD2 原本没有 shrouds 时不创建空 mesh。旗帜归最近桅杆枢轴。每帧从 rest 重新组成 `fall * intact-trim`，不逐 Euler 累加，不改变帆 deployment/blendshape；索具和旗帜使用同一个 model-space fall-about-pivot。统一下沉模型变换仍在其外层。

原测试检查 `rotation.z` 会漏掉 Euler 分解后的实际姿态，已改成桅杆 basis.up 与模型 up 的夹角；新增整船渲染顶点高度检查能捕获“桅杆已倒，但索具仍站立”。修正后的 GPU 截图仍由主线程重新运行，局部 headless 不冒充该视觉复验。

## 原作现成破损贴图接入

按用户明确要求，从参考目录 `preview/images/fpk` 直接复制已解码的 11 张 PNG 到 `assets/textures/pirates_damage_reference`，未重新编码、改色或修改参考源文件。`assets/provenance/pirates-damage-reference.json` 逐文件记录绝对源路径、Pak、目标路径、源与目标 SHA-256、字节数、尺寸、实际 RGBA 通道范围和绑定规则；11 对 SHA 均相等。PNG 共 76,804 字节；它们是上游已解码 DDS 的现成 PNG，未把 PNG 校验误写为原始 DDS 的校验。

| 表面 | 现成档位与来源 Pak | 当前绑定 |
|---|---|---|
| hull | 000/Pak6、020/Pak4、040/Pak7、060/Pak3、080/Pak6、100/Pak1 | stage0 保留完整材质，不绑定000；stage1..5依次020..100 |
| sail | 020/Pak3、040/Pak7、060/Pak6、080/Pak1、100/Pak7 | subtype0的stage1..4依次020..080；满损q96仍为stage4，100保留供其他subtype映射使用 |

实际读取全部 PNG 通道后，结合 `naval-study/SHADERS.md` 7.4/8.1、`PSShipHull_11.psh`、`SailShader.NSF` 判断语义。hull000 为 4×4、RGBA 全0；其余壳损为256×64，RGB范围0..255/0..251/0..255，alpha0..255。壳损alpha只混合损伤RGB层，不作为透明度或洞；本作采取 `mix(authoredColor, damageRGB * authoredColor, alpha)` 保留自身木材色盘，这是原作层语义在本作的适配。shader 没有给壳体写 ALPHA，也没有对壳体 discard。

帆损全部256×256，RGB恒为74/64/57，alpha0..255；原作 alpha test 阈值160/255。本作相同阈值裁洞，完整布面继续使用自身顶点色，恒定棕色仅沿透明度邻近边缘作局部焦痕。020/040/060/080/100中alpha<160的像素分别818/2439/5996/15492/31223，初档是稀疏裂口，随档位增加。RGB并非整帆覆盖贴色，alpha也不能套到整船材质。

实际 authored exporter 的 hull UV0 为纵向ring/周向arc归一化坐标，sail UV0为面板u/v；全部6种船及3 LOD沿用同一0..1参数域。贴图在各表面按该UV0直接取样，未修改GLB、deployment或blendshape；这是原作遮罩对本作参数域的适配，**不是原加勒比船原始UV/撞击坐标的等价复刻**。壳损在周向完整参数域出现的位置及薄帆背面仍由主线程GPU复验。

所有导入采用lossless mode0、生成mipmap、normal_map=0、关闭premult_alpha与fix_alpha_border；sampler使用source_color、clamp和linear mipmap。原作clamp/linear min-mag、point mip与本作三线性mip之间的差异明确保留为距离稳定性适配。贴图仅加载时建立有限资源缓存，同一不可变纹理可共享；只有每船/LOD私有ShaderMaterial改动参数，档位不变时不重复绑定。

本次接入后直接重跑五项局部测试：贴图1900、船损235、整rig断桅243、船员生命周期13、既有物理578，均0失败。导入通过headless `--editor --import --quit`完成。原作贴图路径已为主要路径，缺图仍有有机裂口回退；GPU真实渲染、打包加载和主场景验收由主线程继续验证。
