# 云层CPU最小等价优化交接

用户已改优先级为画面/渲染/表现及尾部水流。T3首航此前完成的代码冻结；本任务没有继续首航或扩大岸浪研究。

## 当前归因

新`tools/profile-world-components.gd`复用普通sail启动和真实native推进，以完整`sea._world_packet(native)`执行现有World顺序，拆分首次接受时间调用。32样本atmosphere p50=22.712ms、岸浪16.259ms，1704短片；森林0.143ms。旧diagnose只传time，会进legacy天气fallback，不能作本链路归因。内部timer40步TRS compose243481us为主要候选，scalar108779us，minimumZ17851us；嵌套父子值不相加。

## 唯一生产改动

`modules/scene_engine/fidelity_fx/cloud_render_compiler.gd`的三个私有矩阵/向量函数，委托新`cloud_transform_kernel.gd`。保留原每项double表达式顺序，`PackedFloat32Array`集中执行最终binary32 stores，再返回独立普通Array。没有减少计算项、容量、频率，没改RNG、时钟、controller、曲线、TRS合成、shader、地形、world/atmosphere生命周期。

实验原循环保存在`game/research/demos/cloud_transform_trial.gd`；现有weather实验增加`cpu_transform_batching`toggle，默认true，false重现旧循环。宿主/catalog不变。旧weather控件数断言5改6，新toggle有暂停/重置/完整输出6项验证。

## 结果

- 独立36云/雾组交替配对32样本完整输出byte equal，p50 14.226→12.436ms（-12.6%），p95 16.589→14.116ms。CPU局部编译，不是FPS。
- 新kernel位、alias、极值、真实production dispatch7173/0。
- 原atmosphere8/8、43208/0，包括原资源完整state、cache、pause、rewind/epoch及NavalWorld。
- weather85/0、newlab6/0、parameter11/0。
- 完整candidate World测量与其它回归并行，所有热点同时变慢；保留混杂结果，不称加速证明。

全部日志/RED/失败/基线和finalhash：`docs/research/evidence/weather-transform/20261014/`。论文已更新`assets/research/papers/weather-shadow.md`。没有GPU进程，没有存档写入，没有commit/reset。目前无仍运行的子进程。

## root剩余

正常GPU同条件帧复拍与全量suite/PCK由root整合；不要用局部12.6%替代正式帧率。若回退，仅恢复Compiler三方法原循环，实验baseline仍保留；原始资产与场景无变化。新共享模块需纳入最终source freeze/PCK。
