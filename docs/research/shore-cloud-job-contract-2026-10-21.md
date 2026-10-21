# 岸浪与云的独占计算 jobs：下一课题实验合同

状态：**proposed，尚未实现、尚未验证线程安全或收益**。本文件只设计下一课题，不修改当前生产源码。当前正式静默整场为 98.238→93.466 ms（mean 改善 4.86%，约 10.7 FPS），距 16.67 ms 仍远；root 报告主 GPU 约 30 ms。下面的 CPU 重叠方案不能据此宣称整场达标，也不能消除 GPU 成本。正式结果以 root 的冻结输入和串行整场证据为准。

## 已知成本与问题

已接受的本轮变更及限制见 [shore evidence README](evidence/architecture-convergence-2026-10-21/shore/README.md)。本设计没有再运行 benchmark 或测试。

| 证据 | 当前测量 | 解释 |
| --- | --- | --- |
| `shore/baseline-01.json` | 1704 patches；每新 time 5112 dynamic material writes；full/omitted-submit mean 13.602/13.529 ms | 不能把 material setters 数量当作已证明的主要原因；调色板方案未实施 |
| `shore/world-detail-02.json` | p50 shore 14.287 ms，surface sync 1.410 ms，atmosphere 13.628 ms | 直接现有 World 方法的 headless 分段；nested timers 不能相加 |
| 同上 | cloud lifecycle 0.025 ms，ocean projection 1.546 ms，shadow apply 1.657 ms | 生命周期不是主要 CPU 热点，不为 threading 改其算法 |
| `shore/world-compiler-detail-01.json` | 每新呈现时间 438 curve samples、369 clocks、49 UV matrices；天空重算另有 161 minimum-Z | 该 run 内层计时有 observer 开销，只用于定位工作分布 |
| `shore/cloud-curve-green-03.json` | 九实例 compiler p50 6.634→5.601 ms；3228/0 | 已冻结的曲线预编译；本设计必须以此候选为新同步基线，不能重复计收益 |
| root quiet pair | 整场 mean 98.238→93.466 ms | 结构收敛与局部 CPU 改善没有证明目标帧率达成 |

优先新增 P0：先验证整岛保守视锥裁剪是否消除当前完全离屏岸浪的纯函数求值与材质提交。提出的 H1：把剩余岸浪纯数值计算从后段主线程移到六个独占 island owner jobs，并在同一帧内与 ship/crew 的主线程呈现重叠。H2：把天空/fog/weather 的编译计算交给一个独占 cloud owner job；生命周期、视锥与 Node/GPU 提交留在原主线程位置。H1/H2 jobs-only 比较保持原全部更新次数；P0 仅在证明完全离屏且无历史依赖后跳过纯求值，可见帧无降频，源数量和接受时间不变。

理论上能够隐藏的只是纯计算时间，受实际 main-thread 重叠窗口、最慢 island、线程池排队、CPU 核心与分配器争用限制。不得把 14 ms 岸浪与 13 ms atmosphere 全部视为可回收帧时；atmosphere 还含主线程提交。即使消除这些 CPU 段，也不能由 93 ms 推导出 16.67 ms。

## P0 优先：整岛视锥裁剪比 jobs 更小

**建议先研究 P0，再决定 H1/H2 的复杂度是否值得。** 当前六岛1704 patches全部参与CPU求值，但这里尚未测量每帧多少岛完全离屏，不能预报节省比例。既有 renderer 的 GPU frustum culling 不会自动停止 GDScript `apply_snapshot`。这一方案沿用当前同步owner，省去kernel搬迁、checkpoint、线程队列和join复杂度。

### 为什么生产岸浪可以直接重入当前时间

`compiled_shore_sampler.gd:58–82` 的 `_mapped` 是明确的 fresh/reset absolute-time clock；只读 prepared flags/frequency/phase/start/stop/span，没有 last/accumulated/started。`sample_into:127–139` 的依赖只有 immutable `_sources/_curves`、当前 `time`，先重写 translationU/scaleU/alpha，再计算phase/matrix；所有被读取的scratch均在本次写入。`_texture:102–118` 每次覆盖全部9个matrix元素。`natural_shore_surf.gd:218,229–241` 的 packet time、alpha envelope、frontDistance也只依赖当前输入。

所以对已知 PreparedSampler 有 `state(t | t0,t1,...历史) == state(t | 直接一次求值)` 的源代码依赖证明，跳过离屏纯函数求值不遗漏controller/history；它本来没有这些持久状态。该证明**不适用于注入 sampler**：保留旧 `sample()`/自定义 `sample_into` 同步调用与side effects，也不推广到cloud persistent clocks、wake、particles或RNG系统。实现前仍须以frozen source逐字节验证连续轨迹与任意离开/重入轨迹。

### 保守可见性输入

- 主线程配置时取实际全部patch几何的world XZ并集，保留原patch数量、布局和拓扑。不要用岛中心点、地形bounds或一条近似圆代替，实际浪带会伸出陆地边界。owner transform变动使该bound失效并重算。
- 岸浪vertex shader `natural_shore_surf.gdshader:20–23` 把world Y替换为 `surface_tide + reference_game_height + 0.055`。`integration_wave_functions.gdshaderinc:42–47` 只把 configured wave height乘[0,1]衰减。因此用当前实际wave_components的有效amplitude绝对值之和包住Y，再加当前tide、0.055与明确的数值保护margin；不能只取原mesh近零厚度AABB，也不能硬编码默认3.5。wave/tide/transform改变均更新bound；未知或非法数据一律当可见。
- 只有该AABB**同时**在当前主view和启用的reflection view之外才判离屏；AABB跨任一plane/视锥边缘就当可见。使用8角/plane保守测试及epsilon，不做遮挡、距离、screen-size或alpha推断。
- 当前reflection camera在 `reference_island_water/ocean_renderer.gd:104–137` 根据当前主camera/tide同步。第一版在原 `World.apply_snapshot:392` ocean projection之后、400 natural world提交之前获取两套视锥，避免用上一帧反射camera错误裁掉刚进入镜头的浪。视图集合不完整、camera/viewport无效、第三方共享world view无法登记时，关闭这一优化并当全部可见。

### 接受时间、同刻重入与surface参数

owner保留 accepted_time 与 evaluated_time/submitted_time 两种事实。离屏时只接受最新time、视图与surface输入；不推进假delta，不更新RNG，不伪造已计算的states。Visible时在原提交位置用当前time求值完整patch，再提交全部实际需要的材质值。不能沿用当前 `apply_snapshot:211` 的“time相同就直接return”覆盖重入路径：即使accepted_time相同，只要evaluated/submitted仍旧，就必须补齐。

不仅动态matrix/alpha/metres可跳，`sync_surface_state:243–259` 对离屏岛也可只保留最新desired surface snapshot/revision，跳过逐material广播。保持 desired 与已提交revision分开，重新可见时强制完整补交wave/time/tide/texture/bounds参数，不能因 `_surface_state` 已等于desired而误认为旧材质已更新。GPU resources/materials仍只在main，不借出mutable material状态。

公开 diagnostics若承诺当前source states，必须在读取时同步求值当前time并返回detached结果；这可以产生数值工作，但不得为了diagnostics把离屏材质也全部写一遍。记录 `evaluated_time`/`submitted_time`/visible/skip counters，不能把旧 `_states` 冒充当前time。默认没有显式完整view输入的standalone/旧caller保持原全部求值，避免暗改现有注入协议。

建议单独冻结P0同步候选，统计每帧可见owner/patch、sampler调用、matrix生成、surface/dynamic setters，比较主视图外但反射可见、极低镜头/大浪/涨潮、同刻转头、teleport、viewport缩放、reflection开关、rewind/epoch/重配和diagnostic拉取。离开任意时长后当前输出必须与连续frozen source完整字节相等；可见patch每个接受time仍执行原计算，任何可能可见的岛都不能跳。只有确认大部分实际工作可被保守排除，才能报告收益。

P0与早发jobs组合需要额外决策：early begin时反射camera可能未同步，不能拿旧视锥当当前证据。首版P0采用late同步测试；若以后需要early dispatch，要么用与当前mirror完全等价的纯数值projection输入，要么early视图不确定即保守dispatch，再由late视图决定提交。不得提前移动原ocean/GPU提交来制造重叠。

## 当前调用与真实 owner

所有行号对应 2026-10-21 冻结源码，实施时需复核。

- `game/presentation/world/naval_world_view.gd:363–408`：371 完成 `_update_camera`，374 `effects.begin_snapshot`，384–394 ship/crew 主线程呈现，397 `effects.finish_snapshot`，403 wakes，404 World，405 interactive water，406 source shadows。当前 ship/crew **不是 WorkerThreadPool jobs**；现有 source particle worker 与这一主线程段重叠。
- `modules/scene_engine/fidelity_fx/presentation.gd:219–245,251–299,636–644`：现有可借鉴协议为 Script-bound static compute、私有 provider、拷贝 camera data、main-thread join 后 `_render`，dispose 只 join/丢弃，不渲染旧 payload。
- `modules/scene_engine/world/world_view.gd:362–410`：370–379 接受时间/风；391 同步 surface state；392 ocean projection；400 natural world；410 atmosphere。必须保留这些 GPU、反射与生命周期提交顺序。
- `modules/scene_engine/terrain/natural_world.gd:77–84`：当前实景持有六个 `_dynamic_shore` owner，逐个 `apply_snapshot`。每个岸浪实例在 `natural_shore_surf.gd:47` 创建自己的 PreparedSampler，不能把一个 sampler 分给多个线程。
- `modules/scene_engine/terrain/natural_shore_surf.gd:207–241`：纯采样与 material setters 混在一个循环。每 patch 读取 packet、写自己的 `_states[i]`；231/232/234 才触及 ShaderMaterial。243 起 surface sync 读写材质，必须继续留在主线程。
- `modules/scene_engine/fidelity_island/compiled_shore_sampler.gd:5–10,127–139`：`_rounding`、`_matrix`、`texture_matrix`、`alpha_phase` 都是可变 scratch；一个岛内仍按原 patch 顺序串行，采样后立即保存该 patch 的 matrix/phase，不能等循环结束再读最后一份 scratch。
- `modules/scene_engine/fidelity_fx/atmosphere.gd:267–345`：接受时间、epoch、reduced motion、ring layout、天空 camera key、fog controller restore 与实际提交混合。381–413 的 weather 路径还要读取主/反射视锥、更新 lifecycle、写云影高度。
- `modules/scene_engine/fidelity_fx/cloud_render_compiler.gd:9–14,302–314` 与 `cloud_curve_sampler.gd:14,32–34`：compiler 与每条 curve 都含可变 rounding store；graphs 含 mutable ControllerClock。**不得把同一个 `_render_compiler` 或同一个 compiled graph 同时用于九个 jobs**。`WeatherState._compiler`（`modules/environment_engine/weather_state.gd:28`）是另一独立 owner，不能借走 producer 的 compiler。

## 推荐切分与接入时序

在P0独立验收后，jobs第一版只做两个可单独切换的 adapter：shore jobs，以及 cloud 单 job。不要同时引入 shader table、geometry batch、native extension 或新调度总管。

1. 主线程在 NavalWorldView 完成 `_update_camera` 后，调用 `world.begin_snapshot(_world_packet(native), consumed)`。这一步只准备只读值、处理必须先发生的 owner 重建、发起 jobs；不改变原 ocean shader time、光照、world transforms 或 lifecycle 的提交时刻。
2. NaturalWorld 发起六个 island job；每个独占该岛的纯数值 kernel。数量来自实际 `_dynamic_shore`，六是当前输入而非新硬编码容量。首轮可用 group 的六个 elements、显式 `tasks_needed=2`，而不是为 1704 patches 建 1704 tasks，也不默认占满全部 worker。2 只是待比较的实验参数，不是性能结论。
3. Atmosphere 准备一个 cloud job，独占自己的 compiler、五个天空原型 graphs、六个 fog graphs、三个 weather graphs及数值 cache。内部先保持原遍历顺序，不再细拆并发。它可与 shore group、现有 particle jobs 同时排队；所有 job 都用普通优先级，避免改变 source effect 的优先级合同。
4. 主线程继续原 ship/crew、effects finish/events 与 wakes 顺序。不要在这段查询 pending kernel 的 diagnostics、sampler scratch、clock 或中间状态。
5. 到原 `world.apply_snapshot` 位置执行 `world.finish_snapshot`：保留原 ocean time/wind/surface sync/projection 顺序。natural shore 到原位置才 join 并提交 material values；cloud 到原 atmosphere 位置才 join 并提交 cloud/fog/weather。需要时 main 等待，不能丢本帧、降频或使用上帧代替。
6. `_apply_weather` 的 lifecycle、主/反射 clipping、baked shadow placement 保留在 cloud join 之后、原 World 的 ocean projection 之后。主 camera 的数值 basis 已在 begin 捕获；reflection frustum 仍在 finish 时读最新实际 Camera3D。Worker 不得自己读取 Camera3D、Viewport、Node transforms。

独立调用者仍可用 `apply_snapshot`，由同一 owner 内部 `begin+finish` 完成；无异步依赖的新假时钟。`apply_settings`/单独 World refresh 等现存入口不能绕过 drain。

## Shore kernel 的值合同

拟新增 `modules/scene_engine/terrain/shore_snapshot_kernel.gd`，`RefCounted`，由一个 NaturalShoreSurf 私有持有；不继承 Node，不持有 Material/Mesh/Texture/RID/Camera 或绑定 Node 的 Callable。

- 配置输入：该岛不可变 packets、PreparedSampler 和预分配 patch states；全部主线程配置后交给这个 kernel。采样不需要 field/terrain/water，因为运行期 `sample_into` 只依赖预编译曲线、packet 与绝对 time。
- 帧输入：已验证 finite absolute shore time，以及 generation/frame key；完整保留 `time*clockSpeed+clockOffset` 的 double 表达式与源 f32 stores。无 wall time、delta clock、RNG 或随机重新布局。
- 帧输出：每 patch 的 Basis matrix、double alpha、double packet metres 和完整 source diagnostic state。复用有限、按 patch 预分配的数组；每次采样立即复制 Basis 值，alpha/metres 不提前量化成 f32。主线程最终 setter 自己完成原有 uniform 转换。
- 独占期：worker 可原地写 kernel 的 states/scratch，主线程不读这些数组。materials/Node 数组始终只在主线程 owner 中，不进入 job payload。finish 后才允许 diagnostics 产生 detached snapshot；公开方法不能借出 pending mutable state。
- 当前可注入的旧 `sample()` sampler 可能含 side effects 或 Node 访问，不能凭 `has_method` 判定线程安全。只有已知 PreparedSampler adapter 或显式纯数值 kernel 才走 worker；旧注入 seam 保持同步，并保持其调用顺序与副作用。
- 同步 adapter 与 worker adapter 调同一个 `kernel.evaluate(frame)`，不得复制两套算法。新 kernel 是计算深模块，不接管材质、布局、场景或其他效果。

## Cloud kernel 的值合同

拟新增 `modules/scene_engine/fidelity_fx/cloud_snapshot_kernel.gd`，先只给 Atmosphere 私有使用。编译器与 compiled graphs 在同一 owner 内独占，不共享给 producer 或其他 viewport owner。

- 主线程 begin 处理现有 accepted-time validation、rewind/epoch/reduced-motion 决策与必要的 `_install_ring_layout` Node 重建。所有旧 job 先 drain，才可重编译/替换 graphs。把与本次计算有关的环境值、ring rotations、camera basis、source controller packets、fog phase 复制成不含 Node/Resource 的输入；不要为整个 native 世界再做一次 deep copy。
- Worker 仅进行现有天空 transforms/minimum-Z、fog/weather 的 controller restore、`render_states`、曲线/UV计算，以及数值 cache staging。保留原 restore→persistent advance→sample 的顺序；时间来自原 `acceptedTime`、`sky.appTime`、fog phase、`packet.appTime`，不能统一替换成一个简化 clock。
- `_time`、`_cloud_time`、`stateTime`、cache key 的“输入已接受”与“结果已提交”分开；pending 不是成功 cache hit。只有完整 receipt 成功后才安装新的 cache/stateTime。main 不能在 pending 时调用同一 compiler 的 `_transform_vector` 或 `controller_snapshot`，因为其 `_float_store`/clock 正被 worker 使用。
- Worker 输出完整原 source render dictionaries与本帧数值 sky lower bounds。主线程负责所有 `_update_group`、材质值、Node transform/visibility/custom AABB、光照、布局重建及 container meta。
- `_weather_radius`、`WorldCloudLifecycle.advance` 和视锥判断第一版继续主线程。其总量与已测成本很小，保持这里可以避免改变显隐/可见区不能回收的合同。
- 编译时的 source arrays 视为只读。两线程可保有引用，但当前 job 独占 mutable clocks/scratch。不能 shallow-copy graph 后误以为获得新 clock/curve owner；拆多个 cloud jobs 必须明确独立 compiler、ControllerClock 与 CurveSampler，属于后续独立课题。

## 同刻、epoch、释放和失败

统一 key 至少含 scene generation、owner revision、接受时间，以及对该 kernel 有效的 camera/native environment/graph revision。key 是数值身份，不含 ShaderMaterial 或活跃 Node 引用。

- 同 key 的重复 begin 是幂等；finish 可以重复且不再次计算或再次推进 clock。same-time camera refresh：shore 不重采样；天空按原 camera basis key 失效；fog/view-independent部分按原合同复用；weather lifecycle 同刻不能推进/回收。
- 不允许跨帧积压：不同 key 到达时先 join 当前 job，再按原调用顺序处理新 key。同帧必须 finish。无超时后使用旧帧、无后台补算、无接受时间外插。
- 新 epoch、rewind、quality/configure、reset、reduced-motion 切换和 dispose 都先 drain。撤销只撤销“发布资格”，不是取消仍在运行的工作。WorkerThreadPool 没有本设计可用的强制取消路径；每个 task/group ID 必须 wait 一次后释放。
- dispose：禁止新 begin→join（不发布旧结果）→清 task/result/kernel→释放 Node/GPU→清 assets。幂等；不得靠 `call_deferred` 晚到回调重新创建旧场景。
- dispatcher 拒绝发起：在 main 直接同步执行同一 kernel，提交当前接受帧。
- worker 运行失败或 receipt 不完整：先 join，确认独占权返还，再同步回退。Shore 使用绝对时间、无持久 controller accumulation，可重算相同输入；不能从 partially written states 假定完成。
- Cloud 是 stateful，**不能在失败后直接再运行一次**。kernel 在 dispatch 前保存一份最小 mutable controller checkpoint（各 clock 的 last/accumulated/started，外加需要提交的 stateTime/cache revision）；新的数值 caches/results staging，成功才替换。失败时先恢复 checkpoint，再按相同 controller packet/输入执行同步路径；任何每帧 checkpoint 开销必须计入实验。若无法可靠恢复，维持同步 adapter，不能为“fallback”吞掉或双算 accepted time。
- 对 worker 的运行错误、非 finite/结构损坏输入、ThreadPool 排队、重复 finish、dispose 中 pending 分别测试。不能关闭 Godot thread safety checks 来使测试通过。

## 能否复用现有 worker 协议

可以复用 existing source effect 的 **协议**，暂不把 ParticleRuntime、shore、cloud 合并为一个 manager。计算内容、clock恢复和GPU发布仍归各 owner。当前可复用的真实共同点是：同 key 幂等、唯一 pending slot、Script/RefCounted compute、main join、generation 失效、dispose drain、同步 executor 和 worker executor 的可替换 seam。

只有 shore/cloud 两个 adapter 已验证需要同样的生命周期实现时，再考虑 `modules/scene_engine/jobs/owned_frame_task.gd` 这个 owner 私有的深模块，公开 Interface 可压到 `begin(key,kernel,input)`、`finish(key)->receipt`、`drain()`。内部隐藏 task ID、pending 状态机、wait 清理和 thread/inline executor；不列举场景、不分配全局效果、不拥有 accepted clock、material、RNG、camera 或 asset cache。domain checkpoint/restore 留在 kernel。现有粒子 worker 可后续逐个迁入，不能为第一版先重构全部 FX。

如果共享类只剩 `add_task/wait` 两个转发而所有状态检查仍散落调用者，就先保留两个私有实现与共同测试合同，避免增加浅层转发。最初真实替换 seam 是同一 kernel 的 synchronous 与 WorkerThreadPool executor。

## 下一实验的通过条件

1. 先冻结本轮候选的同步全帧输出、材质实际值、source states/clocks、event 顺序、accepted input sequence、layout/arrays 与数量。不能回到更早 scalar compiler 基线重复计算已接受的收益。
2. 对同步和 jobs adapter 比较完整字节结果，而非 approximate transforms。覆盖同刻、相机转动/平移、暂停/恢复、rewind、epoch、quality重建、多个 SubViewport owner、dispose pending、旧注入 sampler 与失败后同步重算。
3. 增加可数工作：每 owner dispatch/join、每 patch samples、curve/clock次数、main setters、pending 峰值、fallback 次数；最终 queued=joined、pending=0。jobs-only相同输入下1704 patches与438 curve samples次数不能减少；P0仅可减少有完整离屏证明的岸浪纯求值/提交，单独记录skip原因、visible/evaluated/submitted时间与重入补交。不能把减少可见工作或隐性降频记作threading收益。
4. 验证 worker 输出完全不含 Node/Material/Texture/RID/SceneTree Callable；同 kernel 不能同时有两个 pending jobs；主线程提交只能发生在 join 之后。测试必须能通过 inline executor 与真实 pool 两种 adapter。
5. 计时分开报告 enqueue、纯 job compute、主线程 overlap window、join wait、main submit、checkpoint/拷贝/分配成本。记录每岛 patch/work分布，识别最慢 owner，不假设六等分。
6. 后续允许测量时，由 root 串行固定输入比较 sync、shore-only、cloud-only、both；至少两轮 alternating whole-game quiet pair，报告完整样本/p50/p95、CPU与GPU、startup与steady。比较 group `tasks_needed=1/2/3` 和与既有 particles 的争用；不能在全 suite/GPU测量旁并行跑 microbench。
7. GPU近/远/岸线/镜头运动/反射/云边界/海影截图及动态过程等价。Worker化不改变 drawcall、透明排序、色彩、alpha、波浪、数量或源时钟，仍需实际验证错误帧/晚帧没有进入画面。
8. 保留候选须有可重复的整场 frame-time 与 p95 改善，不能只报告隐藏了多少 CPU 毫秒。对当前93ms差距不预先承诺结果；没有收益就保留独立实验并继续同步默认。

## 其余可能更大的方向，暂不实施

- 1704 shore MeshInstance/material 的提交与透明绘制仍在，CPU jobs 不解决主 GPU 约30ms。可另立几何提交研究，但不能直接全岛合并：`natural_shore_surf.gdshader:2` 使用 `blend_mix, depth_draw_never`，合并会改变跨patch透明排序、局部裁剪与AABB；每patch拓扑/UV/阈值也不同。需要实际 pass/drawcall/overdraw证据后再选有空间粒度的 batch，原数量与几何必须保留。
- 若 shore jobs 的 join/争用吞掉收益，精确 scalar kernel 的 native/GDExtension adapter 才是下一候选，必须保留 binary32 store 与double表达式树，不启用改变语义的 fast-math，并对同一 frozen source逐字节验证。这一方向当前没有性能证据，也不属于本 jobs 课题。
- ocean projection约1.5ms、lifecycle约0.025ms现有分段不足以解释主要差距，暂不扩大这些算法。GPU需要独立pass级归因，不能从source代码量或shader setter数量猜测。

## 官方 API 依据

[Godot thread-safe APIs](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html) 明确活跃 SceneTree 不支持线程访问，并提醒避免在worker直接触GPU；共享可变 Resource/容器尺寸变化需要同步。本设计使用完全独占的数值状态，不把文档允许部分并发容器操作误当成整个复合采样线程安全。

[WorkerThreadPool](https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html) 提供普通/group任务及显式wait；每个任务必须wait以回收其资源，过小任务可能变慢。只在main等待独立jobs，不让worker相互wait，避免任务依赖死锁。官方类名是 `WorkerThreadPool`。
