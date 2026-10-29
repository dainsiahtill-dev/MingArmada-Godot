# 火攻与损管 Implementation Plan

> 使用executing-plans / TDD，独立范围并行，主线程顺序运行引擎。现有dirty checkout包含用户当前成果，继续在原工作区做有边界的修改，不提交、不推送、不重置。

**Goal:** 火攻、岗位取舍和有限损管储备组成真实、可保存、可反制的战斗选择。
**Architecture:** 纯FireControl核先验证；Encounter持有实际命中与固定时步，Campaign/Bridge保存与同步，VFX/UI仅投影。默认旧native合同保留。
**Tech Stack:** Godot4.7.2、现有Encounter、SaveCodec、ShipView、原创烟火纹理。
**Spec:** docs/design/2026-10-29-naval-world/29-fire-control-loop.md。

## 全局约束

- 各shell均rtk；无.codegraph索引，精确RTK源码回退。
- 新算法独立课题ship-fire-control，先论文/实验/CPU/GPU，再正式接线；保留基线和失败。
- 人口、原冷却、弹药、真实库存、暂停、epoch和既有存档兼容必须有证据。
- 古籍只支持名称和功能类别，游戏数值明确原创；不发布真实武器制作内容。

## 任务

1. [x] 新增纯核测试`tests/test_ship_fire_control.gd`，主线程确认有效RED；再实现`modules/naval_simulation/combat/fire_profile.gd`及`fire_control.gd`，验证转岗、人秒预算、分数伤亡余量和提前熄灭积分。
2. [x] 建七节论文`assets/research/papers/ship-fire-control.md`及独立Demo`game/research/demos/ship_fire_control_experiment.gd`；参数人数0/2/4/8、普通/蒺藜灵感载荷、雨湿、可燃货与储备明确。注册统一实验室。
3. [x] 固定时步和预算做候选矩阵，真实GPU连续画面检查，记录未测的完整对局／人工体验范围。
4. [ ] native扩展真实辅助弹体碰撞、统一伤害及FireControl推进；新命令走原队列与权限，配置/快照/业务同步不丢状态；先RED再接线。
5. [ ] Campaign/Bridge/SaveCodec贯通新状态、人员占用、采购和旧档零赠送；活火远船pin、靠港/保存门槛明确；先RED再接线。
6. [ ] 真实heat驱动活船火烟、人员工作与HUD可读操作；正式新游戏/战斗入口可用，保持默认静音。
7. [ ] 正式入口GPU和相关回归，独立审查，更新设计／论文／交付缺口。整体世界与玩法目标继续active。

## Review Focus

## 执行账 2026-10-29

- 任务1–3：纯核700项通过；独立真实GPU已归档gpu-01（263PNG、252样本、3000步），只证明受控实验。144格矩阵943008断言通过，未做长期经济/胜率推断。
- 任务4：有效native RED后应用真实弹体扩展，native-green-01通过；旧test_naval_simulation在native-legacy-01通过。追加AI扑救/实投、胜利不冻结余火、炮组可用人数提示；skirmish-native-red-01为9断言7失败，green-01为9断言0失败。
- Ruling: 先交付公开菜单可进入的火攻交锋，再接1650 Campaign持久化 — 登船现为整秒端点采样，直接减availableCrew会双用工时；必须先建立逐tick劳动回执 — 代价是本阶段火攻只在独立海战入口可玩，采购、远场、存档不宣称完成。
- 火攻交锋mode=fire：双方福船，初始中心距60m，各24份损管、2普通+2蒺藜灵感载荷；不改原duel/fleet/sail原初态。训练物资随重开恢复，不能流入生涯奖励/贸易。
- UI遵循既有Maritime主题，底部仅增火攻/损管切换入口，详情为可收起侧栏，保留3D船与海面；目标和下令均取点击时最新权威快照。实际命中、反击、转岗、物资消耗、暂停、重开、窄屏及离场需要正式GPU证明。
- 正式gpu-01已通过110PNG/91样本/1080接受步、双方实火、有限储备、暂停、重开、两窄屏hover、离场；它只做信号激活，不覆盖选目标后真实按键。保留完整证据，未覆盖处不追补成“已测”。
- Final: fixed 目标选择后OptionButton持焦点，以及低于4名存活操作员时撤回被误禁 — test_fire_skirmish_input在regression-01真实场景6断言4失败，skirmish-input-green-01为6/0；第二轮regression-02共32文件通过，冻结源未变。真实popup/W/相机输入追加正式GPU采集，不替代为静态方法调用。
- Final: Ruling: 审查未判的Campaign/Save/Bridge/远场/采购/登船人秒属于下一生产合同 — 原1650未开放新火攻，草案移至docs/design/2026-10-29-naval-world/fixtures，不混进当前可发现测试；代价是生涯仍不能使用本轮装备。
- Final: Ruling: 审查未判的长期经济、胜率、历史性能、整游戏FPS、其他硬件、人工长局、无关dirty工作与全面艺术验收不归并为通过 — 当前只有明确参数实验、相关回归及指定硬件脚本GPU；代价是仍需后续同预算战斗、实际人工体验和美术迭代。
- 正式gpu-02是真实输入新增RED，4失败、112图，已保存；发现自有目标PopupMenu的窗口焦点转移被误判blur。采集器也存在PopupMenu.push_input绕过Window原生处理的问题，核读官方4.7源码后改root事件转发；正式Scene改自有popup焦点验证，仍保留真正外部失焦需手动继续。不得把此次失败记为完整通过。
- 正式gpu-03的113图/91样本/1080步通过真实popup、全程notpaused、选择后W与相机；继而按住W开popup的held夹具为7断言1RED，修复为7/0。通过Simulation原set_held(false)路径逐键释放，保留已排队战斗命令/持续航向，追加第8断言验证队列保留；最终GPU将单独检查开popup且尚未发送keyup时held已空。
- 最终gpu-04为113图/91样本/1080步，通过held-before-popup、keyup前已释放、弹窗全程notpaused、后续W及镜头。regression-04为32/32，当前输入8/0。汇总fire-skirmish-delivery.json核GPU/回归/当前枚举源码一致，原用户目录未变。任务4/6/7的native+独立海战部分已达成；涉及Campaign、岗位动画与其正式验收的余项仍未勾为完成。

- 每tick少量crew伤害不得经floor投影放大成人数灾难。
- 灭火不回血；无储备不免费工作，途中及返回不重复占两个岗位。
- DOT不触发原货损，每个真正投送弹仅一命中／一次点燃。
- 取消扑救不缩短已存在冷却，不重排待发炮口。
- 远船、读档、重复同刻和终局不清火／复制／永久冻结。
