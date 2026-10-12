# Egress全套回归失败：test-only提案独立审查

2026-10-12。**Spec PASS / Quality PASS，无阻断发现。** 认可提案按当前冻结产品的正确安全行为修正测试；产品、原测试和QA均未由本审查修改。提案尚未apply，主线程负责授权应用、最终测试冻结和新一轮全套结果。

## 为什么可以修改旧预期

原全套112项中111通过、1失败的记录仍有效：`all-tests-initial-failed.json` 中 `test_wet_route_egress.gd` 为61/1。错误预期是“原船队夹具在300tick后仍必须unheld”；它把原旗舰停滞的控制器行为当成固定背景。

核对调查源码、旧/新结果及tick8的实际输入：

- 基线5a86的旗舰仍选坏抢风侧，300tick内甲egress未hold。
- 当前0910让旗舰真实转向并改变速度；甲初始connector本来通过，**tick9**新检查才得到 `predicted-peer / mingqi-1650-flagship`。
- tick8测得旗舰速度`(-0.0004934655,0.0297453323)`、yawRate`0.0202358193`。既有259秒保守预测将其角位移包络扩至约43.5554米；它与甲connector终点附近的预测船体相交。
- 同一输入的SAT结果为259秒true、5秒false、0秒false；仅把速度或仅把yaw置零的各自**孤立算术对照**也为false，支持组合运动包络解释。
- 当前甲全300tick真实九点船体湿，最大速度`0.0004415011m/s`；末态owner仍存在但holding=true、舵0、帆0。安全守卫按原设计工作，不应放宽预测范围使旧预期通过。

以上移动同伴调查来自 `build/second-aftermath-work/egress-suite-audit/audit.gd/json/log`；本审查读其完整首次hold输入/调用，没有另跑第二个船队5秒段。259秒是保守数值范围，**不是已经发生的5秒碰撞**，更不是未来必然碰撞概率。

## 提案检查

审查对象：`test-only-proposal.patch` / `proposed_test.gd`。候选测试SHA256：`90928fa70fa0000fbc5a77a981c12d25aafcd33ca3af871cf9ac56d024c08661`。

1. **原船队场景保留。** 不删除旗舰、不停其控制器、不擦velocity/yaw。只把不再成立的unheld预期替换为准确的holding + predicted-peer + 对应peerId，并增加舵0/帆0与零时域实际船体不重叠检查；仍检查本船湿深和授权目标不变。
2. **正向场景明确独立。** `safe_fixture()`先在初始化阶段选取同一记录粮船，创建只有该船的新Encounter，再恢复该船原水平position/velocity/heading/yaw、state、previous。船员、船体、帆、货重、吃水、风、正式地形及目标相同。单船必须以自身为player并只列自身controllable，这是构造合法单船fixture所需的配置变化；不伪称完整原船队重放。
3. **无运行中删除同伴。** 原recorded fixture没有step；新实例在第一次step之前已定义为单船。恢复水平标量是初始fixture构造，不是正在运行campaign的teleport、消碰撞、清同伴速度或改权。
4. **正向断言仍有实际执行。** 先确认egress owner有效且peers为空，执行300个1/60秒native步骤，再要求owner未hold、fresh clearance.ok、每步实际船体湿、最终目标不变。只证明安全短转弯和持续校验，不宣称32米connector已走完、到港或存档。
5. **原安全边界未删弱。** 用字节比较确认从`for seconds in [1049.8,1064.8]`到文件结尾完全一致：早期危险姿态拒绝、移动peer穿越、干目标、大yaw、细小干角补丁、manual/tactical/crew/sunk/service/disabled/captured/navigation/draft撤权、travel取消/手动接管/reconcile、fresh depth hold与移除危险后仍锁住帆，均原样保留。原61中被替换的是这个错误的unheld期望，其他原边界保留；新增断言总数68。

没有产品/力学/预测horizon/地形/到港/订单授权修改。测试分开“应该hold”和“安全时可以继续”，不会把真实危险改成成功。

## 独立执行及证据身份

只独立执行一个**300tick / 5.0秒**单船probe，未跑全68候选、全suite或完整航程。入口是调查`single-boat.gd`的复制版本，只更换新输出路径并增加loaded resource path及结束源码hash元数据；原测试/产品不写入。

入口/输出：

- `build/second-aftermath-work/egress-suite-peer-review/single-boat.review.gd`
- `build/second-aftermath-work/egress-suite-peer-review/single-boat.json`
- `before-hashes.json`：审查前产品、原测试、旧mutable scratch与不可变初始失败记录校验值。

实际结果：exit0；`ticks=300`、motion.time=5.0；peerCount0；每步湿深true；末态owner未hold、clearance.ok=true；heading由2.778460172到3.064460172，yawRate0.0620102175。位置只由native积分改变为`(14.305817222,431.149980977)`，最大速度与船队安全等待案例同为`0.0004415011`。

加载身份明确为`res://modules/naval_simulation/encounter.gd`；开始/结束hash均：

- Encounter `0910d581c7a5f4642edc9d3ddcb826a9b42f5936655be441f1527458526c9df9`。
- Egress未改：`9b63a8ec7cb2dfa115c8f0d411f6e65e1010f53d3a909e72f9f2b7b93b9ee586`。
- 原测试仍为`241a2dc9bc15a962cd0b4523423d77c84b3b4a857c8e8b51656d257782f57486`，与frozen copy一致。
- 记录fixture `0092a8c59c2235ccef226292d8d1a3f7bae09208612b99da42d9fce664b74dc5`。

审查前一次复制脚本的shell引号错误，随后启动因文件不存在退出；两者没有进入模拟。改用保存的Python准备脚本后完成上述唯一5秒运行。这些准备失败不计为测试通过，也不归因于产品。

## 红绿证据与之前覆盖事件

调查方fresh standalone `candidate.gd` 是正式proposal仅替换report路径，已逐字核对；`candidate-old-body.gd`明确加载5a86并改用其真实hash来源。其新路径结果是当前0910 **68/0**、旧5a86 **68/2**；旧失败针对新定义的真实移动peer hold/中性控制，不能描述为本审查独立重跑。

首次误写旧mutable `build/port-approach-work/wet-route-egress/unit.json` 的68/2带错误当前disk hash产物已经声明不可信。本审查不引用它证明任何通过；使用新audit路径及明确loaded body，且独立probe只写新的peer-review目录。不可变`all-tests-initial-failed.json`继续保留112项111/1事实。

## 应用后的范围要求

建议主线程仅应用本条测试差异，再建立新的最终测试freeze：原258文件集合中只允许这一个测试文件hash发生变化，产品及22项实际runtime artifactSources不受影响。新全112验证必须有新时间戳、保存实际输出；不能把旧失败文件覆写成通过。现有实际首航/第二航程和GUI分支验收由主线程独立继续，本审查不对其完成状态作结论。
