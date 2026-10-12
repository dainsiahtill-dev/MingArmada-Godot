# 第二航程：进入浅边之前的上游控制审计

2026-10-12。只读产品/实际航程；使用已记录标量与冻结旧源码做零步分支探针。没有改产品、跑新完整航程、改用户存档或制造到港。

## 决策

优先修复 **相同导航目标、相同有效首航点、相同吃水的成功重规划，不应无条件撤销仍有效的换舷状态**。

已确认旧源码机制：30秒无5米进展时即使 Planner 重新给出同一条安全直线，`Encounter._autopilot` 仍 `ship.erase("tack")`。下一次 `_tack_course` 重新按当前位置/船艏选择一侧；正在从120°转向240°的船，尚未完成转弯时会重新选回较近的120°。高速状态同时关闭 `lowSpeedTurn`，不提供低速 Manual 转向，且按距离/速度继续开帆；因此两次重规划之间未完成的转弧可能反复被撤销。

这比等待陷入 `unsafe-endpoint` 后再 egress 更接近节奏问题源头。现有完整安全 egress 首个通过记录在2489.8秒，已经晚于1799.8截止；其通过不能证明第二航程玩法完成。

**历史因果边界：** 实际记录没有 `tack.side/settledTicks/legTicks` 或 `ship.previous`；不能声称已还原历史每次重规划/换舷的准确tick。下述实测是明确设定进行中 `tack=+1` 的一变量源码反例；实际舵量与之相容，但相容不是历史内部状态证据。最小修复仍须真实航程验证。

## 输入与可复现探针

- 实际记录：`docs/migration/evidence/opening-story/port-approach-and-voyage-clarity/journey-second-corrected.json`，SHA-256 `0092a8c59c2235ccef226292d8d1a3f7bae09208612b99da42d9fce664b74dc5`。
- 固定旧源码：`build/port-approach-work/wet-route-egress/encounter.preedit.gd`，SHA-256 `51f6ba1eca84b5c925000c5db7d8a33b2718f9d770613263f9548e28c7d68faf`，与该航程记录的 Encounter 一致。没有用后续 egress 实现冒充历史。
- 入口/结果：`build/port-approach-work/second-voyage-audit/upstream.gd` / `upstream.json`。
- 8个真实阶段：944.8、959.8、974.8、989.8、1004.8、1019.8、1034.8、1049.8。
- 每阶段所有船的真实 pose、velocity、yawRate、dimensions、crew、hull、sail、stats 从 `nativeDiagnostics` / `navigationDiagnostics.motion` 读入只读 SnapshotCore；地形使用正式 HeightField / reference geography，物理参数由原 Encounter 构建。没有 `step` 或 campaign 实例。
- 历史 `previous` 缺失，明确用 `position - velocity/60`、`heading - yawRate/60` 作局部线性近似；因此 `rudderUsingSnapshotYaw` 与实录舵量有一帧级微小差别，不能做逐tick回放声称。
- 分支枚举：无tack、side±1计时未满足、side±1计时已满足；之后执行真实 `_tack_course`，依源码验算45米单点避浅、船首避船、舵量、帆和低速转向。
- 另直接调用冻结源码 `_autopilot`：保持同一实际姿态、假设中的 `tack=+1`、同一target/point/draft，**只改变 route.checked 是否过期1801tick**。route.distance 都取当前距离，故过期案例满足“30秒未前进5米”分支。没有改变真实原始文件。

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://build/port-approach-work/second-voyage-audit/upstream.gd
```

执行成功输出 `READ_ONLY_UPSTREAM rows=8 acceptedSeconds=0`。

## 实际阶段与可观察控制

| 时间 | 甲坐标 x,z | 船艏 rad | 速度 | 实录舵 / 帆 | 目标对风夹角 | 与源码分支相容的解释，非历史内部证明 |
|---|---|---:|---:|---|---:|---|
| 944.8 | 106.85089,253.61786 | 1.59682 | 1.70054 | +0.902656 / 1 | 1.24° | side -1，期望120°；近似舵+0.902010 |
| 959.8 | 103.63486,294.08486 | 1.80114 | 2.95993 | +0.449160 / 0.458922 | 15.08° | side -1；近似舵+0.448822 |
| 974.8 | 90.97515,337.06304 | 2.03306 | 3.00246 | -0.005138 / 0.566029 | 29.97° | 接近120°，side -1近似舵-0.004274 |
| 989.8 | 69.45363,371.22090 | 2.35298 | 2.13583 | +1 / 1 | 43.12° | side +1期望240°、误差105.18°；side -1应得负舵 |
| 1004.8 | 50.52219,387.72245 | 2.52409 | 1.33745 | -1 / 1 | 51.25° | side -1加乙船前方避让，唯一合格候选60°，误差-84.62° |
| 1019.8 | 37.68623,400.06169 | 2.25232 | 1.33874 | +1 / 1 | 56.94° | side +1误差110.95°；side -1应得负舵 |
| 1034.8 | 24.76846,417.56712 | 2.35429 | 1.38762 | +1 / 1 | 63.17° | side +1或重新直指目标均需大角正转 |
| 1049.8 | 11.16292,429.06448 | 2.82349 | 1.00067 | 0 / 0 | 56.88° | 已空route；方向选择分支提前不可达 |

实际船艏从120°附近缓慢变化，而速度始终把船带向较大的z；到1049.8已进入起点圆不安全区。这个路径事实不依赖假设中的tack值。

## 一变量反例：重规划抹掉换舷

下面都是**同一个真实阶段上的孤立源码计算**。假设进行中的tack为+1，初始计时均0；仅改变route.checked：

| 实际阶段 | 不到重规划时机 | 到重规划时机，结果路线相同 | 两者帆 / Manual |
|---|---|---|---|
| 974.8 | side +1，rudder +1 | side -1，rudder -0.004274 | 0.566272 / 无 |
| 989.8 | side +1，rudder +1 | side -1，rudder -0.570321 | 1 / 无 |
| 1004.8 | side +1，rudder +1 | side -1，rudder -1 | 1 / 无 |
| 1019.8 | side +1，rudder +1 | side -1，rudder -0.267938 | 1 / 无 |
| 1034.8 | side +1，rudder +1 | 清tack后目标角已63.17°，不重新起tack；rudder +1 | 1 / 无 |

源码链：

1. `_autopilot` 在route非空、`tick-route.checked>1800`、`distance>route.distance-5` 时重新规划。
2. 无论route target、draft、有效first point是否变化、结果是否成功，都执行 `ship.erase("tack")`。
3. `_tack_course` 在目标对风角<60°时重新建tack。两侧都湿时，用较小的当前船艏转角选择一侧。989.8当前船艏134.82°，旧120°更近，故未完成的240°目标丢失。
4. `_tack_course` 另要求连续2秒对准、速度≥1.2，再据45秒腿长或朝目标负进展换舷；重建会重置计时。944–974对准旧120°之后，朝真实西南目标的瞬时进展仍为负；这提供触发另一侧的条件，却没有保证大转弧能在下一轮规划前完成。
5. 速度≥1.2时无条件 `lowSpeedTurn=false; sailRecovery=1`。此时 `_navigation_steerage` 也直接返回空；大误差的原生舵不伴随收帆/刹车阶段。989、1004、1019、1034均实际满帆，这使“保留一项进行中转向”成为比延迟浅边脱困更小的第一修复。

## 被排除的首要解释

**不是证据已证明的45米单点干浅 `desired += PI/2`。** 944.8–1034.8 对side±1的两条航向，正式地形45米中心点全部在水下，均未触发该修正；同阶段 `_wet_ahead` 两侧0–150米九点船体检查也全部通过。不能把“代码看起来危险”写成这段实际航程已执行该分支。

**60°起tack与50°物理no-go差异不构成符号错误证据。** 当前逻辑另有70°退出阈值；1004.8目标对风51.25°已超过物理50°，但保留tack仍符合60/70滞回策略。独立改变这组角度会改变航行策略，且无法解决重规划销毁进行中状态。优先保持原阈值。

**1004.8存在真实船首交通，不应删避船。** 乙在约50.88米、相对船艏0.30458rad；side-1方案会把唯一定义为合格的避让航向选为60°，side+1则为300°。两种假设得出相反舵量；不能通过忽略乙船来强制保持轨迹。保留tack必须仍尊重每帧原有peer和湿深检查。

**circle-safe原route并不保证任意自动操纵都留在安全域。** Planner验证从当前位置到目标的几何路径；tack和避船输出是另外的航向，真实惯性又使船在转向中继续前进。此处应修控制状态连续性，不应扩张planner可通区域。

## 最小实现边界

建议只保留既有、仍安全的tack：

- 同navigation target；同draft；旧route与新plan均成功且有效首航点相同。比较被控制器实际使用的first point，不能仅比较最终港口。
- 保存原tack对象、side和计时；不重新制造或无限续期。风变化、目标对风超过原70°、航点切换、目标变化、draft变化、规划失败都按原权限/逻辑撤销。
- 保留的side需要通过当前正式地形 `_wet_ahead`；不能将“此前安全”当作此刻安全。真实航路变化时应重新选择/等待，不能强守过时side。
- 每帧正常避船、native shore/contact、船员/船体/风/操纵预算保持。保留tack不授权穿过peer，不更改25米/0.75到港规则，不给新推力，不改货损、回执或存档。

这项最小改动已直接交 builder 与 reviewer。父线程负责后续实际航程验证。当前只证明旧机制和修复方向，不声明保tack一定能在截止前交付。

如果保tack后真实native短段仍显示持续大角转弯带满帆、继续逼近不安全边界，再单独验证在仍circle-safe时的有界收帆/中性刹车、随后原Manual转向的控制状态；该策略需完整停车/转弧/peer扫掠证明，不能把它顺手叠加成未经验证的新力学。本审计没有进行该物理段运行，也没有用几何通过冒充它。

## 验证与残余限制

最低回归：同goal/firstpoint/draft的无进展成功replan保留现有安全+1；goal变化、firstpoint变化、draft变化、风变化/原70°退出、当前side变浅、规划失败应撤销或安全重新选择。用真实989.8/1004.8标量构造原失败反例，同时检查未改帆/转速/推力预算与peer处理。

然后冻结新候选、重跑真实完整第二航程：从同一首航完整checkpoint接单，20粮实交回执、截止内奖励资格、真实claim、厦门全船dock和正常Codec保存；不得拿晚到egress成功替代截止内玩法。原始67/5航程须保持不可变。

支线记录，不纳入当前最小修复结论：1049.8孤立调用“无tack”分支时 `_wet_ahead(-1)=false`、`_wet_ahead(+1)=true`，冻结 `_tack_course` 却选-1，显示现有sort comparator的湿侧排序值得单独修验。但**该真实阶段已空route提前return**，不能据此说本轮当时执行了该坏选择，也不把它混入保tack单变量验证。

另，实际QA的route诊断未deep-copy，`checked/distance`可能被后续tick更新。本报告没有据这些别名字段推断历史准确重规划时间。必须在下一轮证据中深拷贝并记录tack/previous/有效desired/重规划理由，才能把当前相容机制提升为逐tick历史因果证明。
