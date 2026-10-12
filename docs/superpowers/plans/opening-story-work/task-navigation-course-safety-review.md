# Navigation course safety 独立审查

2026-10-12。Spec + Quality审查；产品/测试只读。范围仅本次三个文件：`modules/naval_simulation/encounter.gd`、`tests/test_navigation_course_safety.gd`、`tests/test_port_approach_recovery.gd` 的授权wind断言小范围改动。未审同期开工的Campaign/SaveCodec剧情改动，未重跑完整suite或航程。

## 结论

**Spec通过；Quality未发现本次差异中的可行动阻断问题。** 新比较器正确优先湿侧；固定90°避浅不再无条件生成禁航航向；没有增加推力、改变风向约定或拓宽Approach/Egress/Rally权限。旧进港测试的断言收窄有独立数值依据，不是把真实no-go失效改成通过。

这个结论只允许进入组合冻结与后续真实玩法验证。它不证明甲能够解除末态空route，也不证明完整返厦/全船save成功。原始77/2失败航程仍是目前真实完整返航结果。

## 审查身份与范围核对

- Baseline Encounter：`5a86e578f41846b90ccd21c74f89518c6994441ce9beb2018bcfefc5fe7698e9`，`build/port-approach-work/navigation-course-safety/encounter.preedit.gd`。
- Candidate Encounter：`0910d581c7a5f4642edc9d3ddcb826a9b42f5936655be441f1527458526c9df9`；独立短测与最后核验时均一致。
- 实际返航fixture：`92b76d0daa85d64cf0ff5c2cecdd4f80e3accd3feecf8843ddbe34fd58a310e4`，原`wet-route-egress/journey-second.json`。
- 新测试源SHA：`9b439b9b0786aabe8a37f34a9e7feb069970f071e5d79d24a38168578032a85c`。
- 读取并逐段审查 `task.patch`、实现报告、unit/green证据及old/new assist-kind源码/结果。产品差异只有23条新增/删除行，限Encounter的选侧、checked shore helper和blocked收帆归舵；三文件patch没有隐藏物理或业务改动。
- 独立核对当前Physics、ManualHandling、ApproachClearance、WetRouteEgress和NavigationContract SHA均与上一phase `source-freeze.json` 一致。

## Spec核对

**湿侧比较器两种方向均正确。** 当前比较器在湿状态不同时返回`wet(a)`。`a干/b湿`返回false，不把干a放在湿b前；`a湿/b干`返回true，湿a优先。两边同湿则仍按与当前heading的较小角差排序。新测试覆盖dry side±1 × nearer side±1的4种排列，以及两侧都湿的2种近向选择，独立运行通过。

**blind+90根因被实际调用路径替换。** `_autopilot` 现在先把 `_tack_course` 的结果交给 `_shore_course`。该helper对原选方向检查原no-go+fade安全角及0/15/30/45米完整九点船体；不通过时，quarter-turn两方向和两条tack方向都经原 `_feasible` 的风、湿深与peer门槛，再选较近者。无候选返回`ok=false`，调用者在未获得既有合法Approach恢复时立即舵0/帆0/恢复帆进度0。不存在原来“120干，固定+90成210、30°禁航而仍满帆”的未校验直通路径。

**未把注释当证明。** 独立运行真实末态重建：120°不湿、240°湿的旗舰/乙实际自动舵选+1并离开210°；原生力探针对210°仍为0、240°仍大于40kN；已有干tack也不会继续静止于210°。全方向地形阻断保持中性收帆；peer候选反例没有进入原peer排除方向。

**权限没有扩张。** 差异未改 `_approach_authorized`、`_egress_authorized`、`_keep_tack_after_replan`、订单取消或manual controls入口；实际20秒fixture中乙Rally仍active且没有取得Egress。真实navigate清导航再设置手动舵/帆后，下一步保持用户控制。旧“Rally不允许Egress”限制仍在，不因本次测试正帆力而视为整趟返航已解决。

## 旧wind no-go断言收窄

原断言 `request(e).is_empty()` 把“禁止直接末端Approach”与“禁止一切普通抢风转向”混在一起。授权改动保留完全相同fixture和`e.wind.direction={x:0,y:1}`，只把预期细分为目标禁航、Approach拒绝、无恢复owner、合法普通tack及预算。

独立重新执行old/new零步探针结果：

| 检查 | baseline5a86 | candidate0910 |
|---|---|---|
| 目标bearing | 79.164534122° | 相同 |
| 来风 | 90° | 相同 |
| 目标对风夹角 | 10.835465878°，禁航 | 相同，禁航 |
| side -1 / side +1湿 | false / true | 相同 |
| 选tack方向 | 30°（干） | 150°（湿、对风60°） |
| 显式final approach clearance | false | false |
| Approach / Egress owner | 均无 | 均无 |
| assist | 空 | 普通Manual转向 |

新assist精确是原商船/20可用船员/30maxCrew/完整船体和帆预算：targetYaw `-0.06981317008rad/s`（-4°/s）、maxYawAcceleration `0.13962634016rad/s²`（8°/s²）、powerFraction2/3、responseRate6、brakeDeceleration0、帆0。`coastInNoGo=true` 是原Manual属性，容许有界转向中的惯性滑行，不产生推进力，也没有令目标79°成为合法末端Approach。

新断言允许assist为空或等于该既有budget；这符合其安全性质，不强行要求获得额外权限。fixture中的wind变化是原unit policy设置，不是完整物理回放；本审查不把零步ordinary assist当成实际到港证据。

审查认可本次语义收窄。伴随patch的旧断言baseline明确是反转授权hunk重建，未伪称预编辑capture。实现阶段早先97/1及缺失domain preload的编译错误仍应保留为NOT PASS，不能被后续结果抹去。

## 独立执行证据

为避免覆盖builder原`unit.json`/assist-kind证据，本审查复制其脚本到`build/port-approach-work/second-voyage-audit/navigation-review/`，**仅替换结果输出路径**；产品和测试源文件没有写入。

1. `test_navigation_course_safety.review.gd`：独立执行exit0，**54 assertions / 0 failures**；native段确实推进20秒，仅隔离fixture。
2. `approach-assist-kind.review.gd`：独立执行exit0，产生上述old/new零步区分；没有编译错误。
3. 阅读builder `approach-green.log`：136/0、实际隔离到港47.766667秒、40.016667秒timeout仍存在；该整项136/0没有由本审查重复执行。tack35/0同样是builder已报回归，不伪称独立重跑。

独立20秒native结果：

- 旗舰从旧210°转至heading10.396605801rad（规约约235.68°），位置`(-44.499521,309.573536)`、速度分量`(-0.930298,-1.551029)`；实际帆力为正。
- 乙至heading4.098007045rad（约234.80°），位置`(-61.639337,312.548910)`、速度分量`(-0.325537,-1.162346)`；实际帆力为正。
- 1200个native步骤内两船九点湿深全部通过；乙Rally持续active且无Egress。

记录/入口：

- `build/port-approach-work/second-voyage-audit/navigation-review/unit.json`
- `build/port-approach-work/second-voyage-audit/navigation-review/approach-assist-kind.json`
- 同目录两个`.review.gd`复核入口。

实际fixture使用记录的水平标量、重建的tack/previous和无波浪隔离环境；不能称历史exact replay、完整campaign、GPU或性能证明。此次独立执行未出现并行剧情源码造成的临时编译错误。

## Quality边界与后续验收

没有发现需要本次修复前解决的新增缺陷。以下是保留的范围边界，不应在交付陈述中省略：

- `_shore_course`对原本清晰方向不额外扫描peer，继续由现有“当前船艏前方peer”避让处理；替代方向走原 `_feasible` peer门禁。该补丁没有建立任意未来航向的动态避碰保证。
- 0/15/30/45米湿深检查与原native接触处理共同工作；它不是完整连续轨迹/制动证明。短测的船体保持湿，不意味着任意风况和拥挤几何都无碰撞。
- corrected comparator与安全fallback没有解除甲的active Rally权限/末态干转弧问题；单靠这项修复不可宣布全船返厦完成。
- 下一步由主线程组合冻结后验证真实20粮按时交付、claim、厦门全船dock、正常完整save；不能复用旧77/2作为新成功证据，也不能将本次54/0升级成全套或整趟验收。
