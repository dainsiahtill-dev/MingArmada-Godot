# 架构收敛验收记录 · 2026-10-21

当前：两批生产实现与独立审查已完成，数值/来源oracle、实验室和定向GPU验证已留证。第二批完整回归286/286通过，1098份冻结文件全程无变化。真实公开入口两轮平均帧间隔93.972→72.653ms，缩短22.69%；**16.67ms/60FPS未达标，性能验收仍开放**。

实际工程：`C:/Users/dains/Documents/Git/ming-armada`。旧`MingArmada`网页仓库不属于本轮。保留已有云生命周期、Godot4.7/Forward+/Jolt配置和其他用户工作。本代理未执行提交、推送、重置或发布；回归按文件内容hash而非Git HEAD是否变化验收。

## 已采用的工程规则

职责、所有权和时钟记录在[runtime-ownership](runtime-ownership.md)。每个系统只有明确的状态owner；通用能力进入引擎层，游戏层提供事件、输入和表现配方。固定tick保留数值权威；显示消费接受的数据和时间。活跃SceneTree/GPU提交归主线程，worker只拥有独占的计算状态；有界池/队列、generation失效、join与render-thread释放回执分别验收。

依据：[Godot CPU优化](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html)、[固定步与插值](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html)、[线程安全API](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)、[MultiMesh及整体裁剪限制](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)、[Object Pool](https://gameprogrammingpatterns.com/object-pool.html)、[Data Locality](https://gameprogrammingpatterns.com/data-locality.html)。根据真实变化点和测量选择结构；本轮没有采用全项目ECS重写、全局万能manager或未经验证的全GPU物理。

## 生产收敛包

| 包 | 已落实的边界 | 直接证据 |
|---|---|---|
| 船体物理 | physics_engine中的统一OceanAdapter；height-only优先scalar、旧sampler回退；内部step_in_place，公开step/snapshot仍detached | 六船×浅深水×600步，共7200组完整状态/浮力严格相同；完整tick地形查询25→5；独立CPU批次mean下降31.65% |
| 数值调度 | 无accumulator的固定tick接口；frame owner保留原预算、暂停、输入与事件顺序；内部tick/time/status读取不复制全世界 | fixed_tick合同及冻结旧frame实现配对；正式NavalPractice仍消费current detached snapshot，未新接入render_snapshot插值 |
| FX与渲染 | PreparedRigidShadow唯一实现下沉scene engine，旧game路径仅继承shim；DynamicSurfaceBuffer统一更新/格式/AABB；公开纹理依赖预热；失败纹理无Node泄漏 | native GPU动态surface8026/0；2701稳定RID复用及148拓扑变化；覆盖层隐藏旧尾迹跳过不可见投影/采样/上传而保留source历史，同刻恢复 |
| App与资产 | settings唯一加载、首次建图使用已确认质量；缓存immutable资源，各实例独立Node/Skeleton；资产provenance与dispose | settings load和首构建world各2→1；ownership与实际入口回归。imported-first因27模型顶点/动画不等价未采用 |
| 船与3D人物 | ShipView配置期角色缓存；Crew稳定allocation/LOD setter跳过重复整理，阈值/滞回/受击/恢复保留 | ShipView冻结旧pose oracle；Crew研究3233/0、正式236/0及10项不同相关回归。正常整场每一行35名可见3D人物 |
| 云曲线 | 预编译静态curve数据，保留原f32存储/时钟顺序；纯计算helper受层守卫约束 | 冻结旧compiler1584帧严格字节相同，3228/0；局部mean下降16.4%，不代替整场FPS |
| 岸浪 | 绝对时间CompiledSampler可延后离屏求值，未知/继承注入完整同步；actual main+mirror union，unknown fail-open；旧/新位移bound并集；accepted/evaluated/submitted分开 | 正式117/0；未改shader/几何/纹理/RNG/数量。研究同一视角1704→264采样，是工作计数。GPU05/06及实际整场另列 |
| 实验与架构守卫 | 首页既有实验室登记一个架构课题，六船/浅深水/full-scalar/固定步与显示插值；纯计算无Node/GPU/隐藏时钟；保留失败原件 | 实验室GPU1754/0、50PNG；layer helper RED4→GREEN0，29断言/153文件。所有权、容量、释放和兼容合同已文档化 |

局部收益的输入和范围不同，不能相加，也不能换算成全游戏帧率。完整索引与原件在[证据目录](../research/evidence/architecture-convergence-2026-10-21/README.md)。

## 实际 GPU 与正式入口

GPU06：1940/0，三个非空案例closeup、near-plane、same-time-reentry，主/真实反射的pure-redraw、同刻hold、candidate均零字节差。它明确隔离Crew/UI/六个forest roots，保留ground/ocean/depth/light/ships/compositor；不外推为full-world image exact。GPU05另有保留forest的两个非空有效案例，重入树叶的基线噪声保留为1907/2。GPU04虽然计数通过却缺可见贡献，root亲看后拒绝该视觉结论。详见[岸浪接线](../research/evidence/architecture-convergence-2026-10-21/shore/PRODUCTION_ADOPTION.md)。

正常整场性能保留所有默认人物和植被。Intel Arc130T、Godot4.7.2 Forward+、1600×900 balanced、seed1661、3船35名可见3D人物；每次10秒warmup+30秒采样，先A-B再B-A。

| 对照 | 原冻结生产 mean / p95 | 新版 mean / p95 | mean帧间隔缩短 |
|---|---|---|---|
| 正序 |94.242 /100.454ms|72.700 /78.156ms|22.86%|
| 反序 |93.702 /99.451ms|72.606 /77.966ms|22.51%|

按两次进程均值等权，93.972→72.653ms，缩短22.69%；按该均值计算约10.64→13.76FPS。每一行有焦点、正常推进，固定负载相同，源hash稳定；六份个人save/settings仍同之前hash。所有慢帧保留。它衡量相对最初生产的整个已接受变更集，不是culling-only独立归因，也不是所有硬件、炮战/大舰队或长期热稳定性结论。

candidate01一条main GPU query为18446739832832ms，原GPU均值不可用；原行与聚合未修剪，原因未确认。wall使用独立单调时钟，仍可单独验收；candidate02独立main GPU mean27.3085ms。不能把viewport GPU、wall interval和重复的一秒TIME_PROCESS最大值相加。首个失焦暂停尝试全组作废，随后四个进程有效。详见[原始双配对](../research/evidence/architecture-convergence-2026-10-21/live-second/COMPARISON.json)与[监测器口径](../research/evidence/architecture-convergence-2026-10-21/PERFORMANCE_INTERPRETATION.md)。

## 完整回归与发布边界

第一批284/284、1094文件无变化，是历史检查点。第二批增加Crew/shore正式合同和纯数值helper守卫后，共冻结1098份文件（game/modules/tests、project.godot及正式runner）；新版完整回归**286/286通过、0失败/超时/Godot ERROR**，运行22分50.818秒。开始/结束新增、移除、变化均0。[原始回执](../research/evidence/architecture-convergence-2026-10-21/full-suite-second.json)、[派生摘要](../research/evidence/architecture-convergence-2026-10-21/full-suite-second-summary.json)和source manifests保留。277份完成行明确335345 assertions；其他旧完成格式分开，不虚构总数。

另有85条WARNING，全部来自`test_reference_atmosphere_resources.gd`为核对原始RGBA直接使用Image.load。它们是“源图像直读不适用于导出”的提示，不是85个生产加载失败，也不是已通过导出验证。原始警告保留，canonical资产/导出gate继续开放。

以下仍未取得完成资格：

- 60FPS帧预算。新版约72.65ms，当前main GPU独立查询仍约27.31ms；剩余CPU呈现、局部水沫计算、云/阴影及提交成本须继续分项归因。
- Shore/cloud worker jobs与GPU batching。目前仅独立设计与成本研究；不得列为已实现。合批必须考虑实际细分网格、透明排序、主/反射视图和空间裁剪；worker必须保留stateful clock恢复、独占权与drain。
- Canonical离线模型烘焙及导出一致性。当前已接受source-authoring路径保留，不能将不等价的imported路径当发布成功。
- 大舰队/连续炮火的长时GPU压力与容量恢复，以及跨镜头、跨质量和热稳定性FPS验收。已有逻辑/生命周期检查不代替这类吞吐测量。
- 正常试航末帧可见近距船模交叠观感，旧、新版均存在；本轮未用实拍等价宣称船间碰撞壳与所有显示几何一致。

该接触边界已轻量核对真实路径：Encounter每个固定tick在船体step与岸校正后调用`_contacts()`，neutral/sail并未关闭它；采用core中心、heading、XZ速度和spec长宽做二维矩形SAT校正。Jolt只承担deck/crew视觉impact，不替代船体数值接触。当前接触代码与冻结旧生产逐字相同。

静态资产元数据表明fisherman数值矩形14×4.2m，而结构hull74实际宽4.5948m、纵向中心偏约−0.473m；显示集合还包含纵向更远的突出构件。此差异不等于整体缩放错误，也不能凭末帧PNG证明数值OBB仍有穿透。后续独立课题须在同tick记录contact前后pose、SAT残差并叠加数值壳/结构船壳/外伸几何，先定义各部位的接触保证；不能直接取全模型AABB或缩放资产来掩盖。参见`modules/naval_simulation/encounter.gd`、`modules/contracts/physics_types.gd`及`assets/data/fidelity_naval/ships-manifest.json`。

正式开发应继续沿现有owner/API扩展，所有新表现先登记实验问题、独立baseline/demo、数值及真实GPU验收后接线。性能未达标的状态必须保留；通过源码回归不等于性能门槛通过。

## 复现与后续变更

```powershell
rtk proxy node tools/verify-godot.mjs --output Temp/convergence-new-full-suite.json
rtk proxy node tools/run-research-proof.mjs Temp/shore-new-process.json '["--path",".","--script","res://tools/capture-shore-frustum-culling.gd","--","--capture=res://Temp/shore-new-gpu","--tick=30","--scope=shore-environment-no-foliage"]'
```

使用新输出目录，保留退出码、唯一完成marker、无ERROR、源码hash和实际PNG。正式frame interval测量须串行、同负载、有焦点正常推进；失焦或暂停不能自动反复resume后拼接。回退仅处理本轮明确seam，不reset仓库、用户存档或其他未提交工作。历史证据不覆盖；后续补充新来源和时间边界。
