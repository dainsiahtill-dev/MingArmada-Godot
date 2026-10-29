# 首航齐射命中回执可读性

- 课题 ID：`broadside-receipt-readability`；版本 0.1，2026-10-27。
- 类型：前瞻工程研究；状态：研究中。正式游戏未接入。
- 摘要：研究以只读炮弹事件建立短暂反馈，区分命中与单枚未命中；独立实验室固定步 GPU 原帧已复核，真实游戏与玩家手感尚未验证。
- Demo：`res://game/research/demos/broadside_receipt_experiment.gd`，由实验室登记。
- 来源：仓库 `modules/naval_simulation/encounter.gd`、`modules/naval_simulation/combat/cannon_system.gd`、`game/runtime/mingqi_runtime.gd`、`game/scenes/mingqi/mingqi_scene.gd`、`game/domain/mingqi/campaign.gd`；SHA 与实际运行记录绑定，源代码即项目内部来源。
- 证据：`docs/research/evidence/broadside-receipt-readability/`，新运行独立目录；历史首航参考 `docs/migration/evidence/opening-story/gameplay-current-20261027/RUN-BOUNDARY.md`。

## 问题与假设

真实 1650 HUD 有两舷射界、装填状态及视觉炮击，但无简短的旗舰炮弹结果文字。默认静音时，常规船距能否看清结果尚未知。H1：按旗舰发出的 projectile ID 关联真实 hit 或 splash，再用短文本区分敌、非敌与单枚未命中，能提供不虚构结果的可读信息。H2：对混合结果优先保留命中，避免较晚未命中遮蔽命中。可证伪：无火炮 fire 对应的 hit 不应显示；友船不应被称敌船；先命中再出现未命中不应变成仅未命中。H1 的玩家可理解性须后续真人测试。

输入为独立固定事件夹具：事件 id、battle epoch、源/目标船 id、弹丸 id、fire side；敌我使用同战斗的 hostileTargets 与 capturedShipIds。事件时间和回执寿命单位为接受秒，固定步 1/32 秒，短文本寿命暂设 3 秒；这些是研究参数而非现有玩法规则。运行时的真实事件由 Encounter 创建并通过 Simulation 与 Runtime drain；正式场景有普通和 local-fire 两消费路径，尚无本课题生产接线。

## 方案比较

1. 无回执基线：保留现有射界与视觉效果；零新增状态，但不能由文字区分命中和落水。
2. 每弹直接覆盖：低成本，却在同一轮混合命中/落水时丢失较重要结果；保留反例。
3. 弹丸关联与短时优先：只读 projection 以字典关联真实发射及对敌 policy；在有效期内命中高于未命中，不改射击或战役状态。选此研究候选，仍待画面和玩家实测；当前夹具的字典没有生产级容量与淘汰策略，不得直接接入长航程。

## 算法与实现

记录本旗舰的 fire 对应弹丸和舷侧；只接受同一 epoch、相同 source 和已登记 projectile 的 hit/splash。`Encounter._advance_projectiles` 在碰水或者弹丸 TTL 到期时均会发 splash，故只描述“该枚炮弹未命中”，不声称落水或整轮全失。葡萄弹每门有五个弹丸，fire 事件只包含其中首枚 ID；其余弹丸不建立虚假的舷侧关联，覆盖率有限。已确认的 hit 以目标是否属于 policy 的 hostileTargets、且未 captured 分类；没有明确 policy 时只用不宣称敌我的中性标签。一个固定 3 秒显示期内 hit 高于 splash；相同优先级使用后到事件。事件 id 去重，回放同一事件不能延长显示；过期清除，重置 epoch 清空缓存。该实验对实时顺序事件建立假设；丢包、跨帧乱序与离线载入在正式接线前单独验证。UI 不含可交互控件、暂停不推进权威时间、不读取或写入玩家存档。

## 实验设计

固定船为旗舰、敌船、友船和未知目标；固定 seed 不适用、时钟 1/32 秒，事件夹具包含四炮、hit 后 splash、友军、未知来源、重复事件及过期；基线关闭回执而保留同一事件与时钟。CPU 接受标准：输入不变；仅合法关联产生反馈；命中优先；舰队归属准确；重复不延长生命周期；暂停、重置、释放正确；相同输入重放完全一致。保留逐弹覆盖导致命中丢失的混合反例与原始日志。

GPU 方案固定相机、viewport 1280×720 和 1600×900、字体、夹具与时钟，对照 baseline/candidate 的逐固定步原帧并审阅遮挡；由脚本打开 MainScene 实验室并单步，不是人工游戏输入或实时帧率测试。性能与正式入口另测。非目标：不改变伤害、控制、AI、存档、敌军生成、战斗数值或默认静音；无用户研究不得声称更好玩。

## 结果与证据

先前固定模型事件投影通过 11/0；固定夹具 Demo 通过 16/0；接入新条目后的目录 135/0、实验室入口 31/0，均在 `catalog-green-01` 见证。随后发现 splash 的 TTL 语义和葡萄弹单 ID 限制，已修订标签与补充反例，上述旧轮次不代表修订后的最终测试。实际 Encounter 的静海 4 炮固定夹具产生 4 fire、4 对敌 hit、4 条正确关联，见 `native-01`；这不是首航或人工体验。修复后 headless 结果见 [索引](../../../docs/research/evidence/broadside-receipt-readability/README.md)。

2026-10-27 [首轮 GPU](../../../docs/research/evidence/broadside-receipt-readability/capture-gpu-20261027-01/process-result.json) exit 0、452 张原帧/226 对状态比较/0 自动失败，但人工复看 [1280 命中帧](../../../docs/research/evidence/broadside-receipt-readability/capture-gpu-20261027-01/frames/1280x720-candidate-016.png)发现浅纸面板下边框与投影被实验视口裁切，因此不通过画面验收；自动状态比较不证明可见范围完整。裁切复现及最小研究 Demo 修复见 [布局记录](../../../docs/research/evidence/broadside-receipt-readability/LAYOUT-FIX-20261027.md)。

[第二轮 GPU](../../../docs/research/evidence/broadside-receipt-readability/capture-gpu-20261027-02/process-result.json) 在 Godot 4.7.2、Forward+、Intel Arc 130T 上 exit 0、452 张原帧/226 对/0 自动失败。独立复核了全部 PNG 的 SHA256 和尺寸、全部事件时序、投影外扩与逐对状态；标明的 27 项直接源在拍摄前后和本次文档更新前均一致，原 12 槽前后一致并匹配首航前基线。实验输入 hash 为 `02312b287942dcf07a94e12e41b76ea13665cf2c3b6349ed2847313427745032`。本段、研究目录摘要与证据索引在 GPU 采集后更新，故论文与 catalog 当前哈希有意不同于拍摄时记录；源码清单不是递归依赖闭包。

第二轮按 1/32 秒的固定步逐帧采集：`e5` 命中在 tick 16（0.5 秒），`e6` 未命中在 tick 20（0.625 秒）未覆盖命中；tick 112（3.5 秒）回执到期。独立目视检查 1280 与 1600 的基线、命中、混合事件和到期各一张，共 8 张：深青面板与细金边、投影在实验视口内，抽查文字可辨。实验室外层仍是浅色纸面，说明尚未在真实深青游戏海战画面验证。示例：[1280 命中](../../../docs/research/evidence/broadside-receipt-readability/capture-gpu-20261027-02/frames/1280x720-candidate-016.png)、[1600 混合事件](../../../docs/research/evidence/broadside-receipt-readability/capture-gpu-20261027-02/frames/1600x900-candidate-020.png)。

## 局限与失败

夹具不是完整海战，固定步图片不证明实时帧率、正式场景投影、完整动态表现或实际玩家理解。事件来自已知顺序与固定 epoch 的简化输入；葡萄弹非首颗弹丸的正确归属不能由当前 fire 事件推出。真实 Runtime 切换、pause、snapshot 重载、目标失效时序、缓存的有界生命周期仍待单独对照。不会给伤害值或击沉结论。拍摄时目录摘要曾写“尚待 GPU”，已在采集之后更正；历史原帧与运行时 catalog 哈希保持不变。

## 集成与复现

复现时先校验源码和夹具 SHA、重放独立 headless 合同，以新的 run-id 重拍实验室真实 GPU 基线与候选；独立实验结果不自动批准正式集成。接下来仍需设计正式两条 drain 路径的接线、去重及有界缓存，测试正常入口、开炮与相同原生回执、暂停恢复、存档隔离，并做真人可理解性验证。正式入口尚未接入；取消候选只需保持它未接线。禁止覆写旧证据。
