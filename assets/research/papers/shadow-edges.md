# 阴影轮廓边索引：保序奇偶抵消与 CPU 热点修复

- 课题：`shadow-edges`；整理日期：2026-10-14；报告类型：既有优化的事后工程整理。
- 状态：目标刚性 hull/mast adapter 已有历史集成与 oracle 回执；本轮未新增独立 Demo。
- 摘要：用无向整数边到 slot 的索引替代线性扫描，同时逐元素保留原方向、奇偶取消和 swap-last/pop 顺序。
- 主要来源：[动态与性能修复报告](../../../docs/migration/hull-dynamics-2026-10-14.md)、[adapter 源码](../../../game/presentation/world/target_rigid_shadow_caster.gd)、[原 Math](../../../modules/scene_engine/fidelity_fx/source_shadow_math.gd)。

## 问题与假设

真实自由试航分段发现阴影 CPU 链均值约 83ms。目标 adapter 在 dirty silhouette 构建时，对每条面边调用原 Math 的线性查找取消；大量不抵消边导致最坏 O(E²)。

假设 H1：索引只替代查找位置，保留边数组的原始更新顺序，可以获得期望 O(E) 构建，同时保持提交到原 volume Math 的输入完全相同。

假设 H2：验证必须比较 ordered edges、caps、positions、indices、direction 与 counts；仅比较无向集合或最终阴影轮廓图会漏掉影响原输出的次序变化。

单位：CPU 调用耗时与 wall frame interval 为毫秒；位置为目标模型单位经世界 transform 映射到米；边 ID 为整数。Math 的 `1e9` 挤出常量是有限源构造合同，不解释为物理阴影距离。

## 方案比较

- 原线性 `toggle_edge`：顺序语义明确，适合 oracle；对每边遍历当前数组，最坏二次成本。
- 哈希集合计数后重建列表：可计算奇偶，但丢失方向和 swap-pop 顺序；不满足当前等价要求。
- 排序去重：可得到确定集合，却改变原次序，增加 O(E log E)；同样不满足。
- 无向 key 到原数组 slot 的 Dictionary：期望常数查询；删除时更新移入的 last 边索引，可原样保持数组语义。当前采用。
- 更换 shadow map/caster 数量：可能更快，却改变画面及场景政策，不是本次边查找优化。

这项优化发生在目标刚性 caster adapter；原 Math、volume 投影数量、renderer/compositor 与 caster 选择规则继续使用既有实现。

## 算法与实现

`_toggle_indexed_edge` 先将端点 `a/b` 按 `&65535` 归入 uint16；key 为 `(min(a,b)<<16)|max(a,b)`，存入 int64，无 float hash 精度丢失。

若 key 已存在，取得 slot，把 last 边移入该位置（当 slot 不是 last 时），更新移入边的 lookup，pop 并删旧 key；不存在则存新 slot 并 append 原方向 `[a,b]`。

```text
a = a & 65535; b = b & 65535
key = (min(a,b) << 16) | max(a,b)
若 lookup 存在 key：
    i = lookup[key]; last = edges.size - 1
    若 i != last：edges[i] = edges[last]; 更新被移入边的 slot
    pop edges；删除 lookup[key]
否则：lookup[key] = edges.size；append [a,b]
```

Dictionary 给出期望 O(1) 查询，整次构建期望 O(E)，额外空间 O(E)；不宣称哈希最坏情况的严格线性界。奇偶抵消适用于相同或反向出现，残留方向由当时 append 决定。

adapter 配置时对实际三角 mesh 做精确位置焊接，去除 authored UV seam，跳过退化面。每 caster 缓存 geometry revision 与 local light；变化时重建 edges/caps，退出清理 cache 并恢复原 shadow mode。

实际 mesh 的点数必须小于 32768，volume `1 + 2*edges + caps` 不超过 65535；非法值拒绝。对面朝向和 caps 次序的选择保留原目标规则，不通过“近似相同”放宽输出。

[SourceShadowMath](../../../modules/scene_engine/fidelity_fx/source_shadow_math.gd) 继续在 f32 存储边界构造 apex、面片与封口；[renderer](../../../modules/scene_engine/fidelity_fx/source_shadow_renderer.gd) 和 [compositor](../../../modules/scene_engine/fidelity_fx/source_shadow_compositor.gd) 保持 RD stencil 与提交合同。

## 实验设计

[ordered oracle 测试](../../../tests/test_target_rigid_shadow_edges.gd) 每步同时调用未改的 `Math.toggle_edge` 和索引版本，精确比较完整数组；独立以 `min*65536+max` 编 key，验证 lookup 的移入 slot。

输入包括取消/重现、反向、uint16 别名、负端点、跨边界端点，seed=9713 的 2048 步随机序列；实际船型姿态/LOD/移除/重现，以及 2048 个不相连三角形的大 mesh。

对每个实际 caster，用原线性 Math 重新生成 edges/caps，比较 ordered 输入与完整 volume 输出。此测试使用目标 mesh 的相同几何，不宣称原未知 classifier/skinning 已闭合。

历史真实世界 profiler 经正常 Main/router 进入自由试航，保留所有对象；诊断冻结自动回调后，按 1/60 秒推进实际 runtime，暖机 12 帧，采集 12 个 fresh 分段。源 call 为 32Hz，不能把混合 contact p50 当 fresh 成本。

- 接受标准：oracle 所有数组逐元素相等，lookup 正确；缓存失效、移除/重现、gate 与释放不回归；任何失败先阻止集成。
- 性能对照：保持船数、帆装/LOD、画质、相机、光方向、地形、操作序列；记录源码与工具 SHA256。
- 指标：dirty compose、submit、shadow wrapper、world、实际 frame interval 分别给 raw samples、均值、p50/p95；父子计时不重复求和。
- GPU 接受：实际 stencil 初始化、画质切换、清理与最终截图另测；CPU oracle 不证明 GPU 像素或 draw duration。

## 结果与证据

历史 [shadow-regressions](../../../docs/migration/evidence/hull-dynamics-2026-10-14/shadow-regressions.json) 五脚本无失败；新增 edge 测试为 5498 项，450 个真实/大 mesh caster，83,339 个 volume vertex。ordered edges/caps 与完整 positions/indices/direction/counts 精确匹配原 Math oracle。

真实世界 [修改前 CPU 分段](../../../docs/migration/evidence/hull-dynamics-2026-10-14/performance/world-cpu.json) 与 [修改后分段](../../../docs/migration/evidence/hull-dynamics-2026-10-14/performance/world-cpu-after-shadow.json) 的阴影 wrapper 12 样本均值为 82.9955→22.1387ms；后值 p50=21.755ms、p95=24.536ms。

修改后 compose 均值 7.630ms，submit 均值 14.459ms，完整 world 均值 31.034ms。submit 包含 renderer CPU volume refresh、纹理平面对账及 compositor 提交；不是 GPU draw 或 GPU readback 的测量。

历史正常入口的 240 帧 wall 间隔 p50 为 133.840→83.346ms；前后模拟区间和可见位置不同，只说明那些运行的间隔，不能算严格同画面的稳定提速比例。正式自由试航仍未达 60FPS。

硬件/后端来源：Godot 4.7.2、Vulkan Forward+、Intel Arc 130T。CPU 型号与温度/电源策略未在摘要中充分报告；重新比较要补全，不假定其他硬件复现相同数值。

本轮仅读取源码和历史回执；未重新执行 edge 测试、世界 profile 或 GPU。当前课题没有新的独立实验室 Demo，历史结果不能直接填到新 run manifest。

## 局限与失败

- 优化只解决 adapter 的线性取消热点；剩余 submit/world 与其他 GPU/CPU 开销仍存在。
- 精确位置焊接与刚性 hull/mast 是目标政策；原 actor classifier、light producer、skinning 和全部场景资格尚无等价证据。
- uint16/signed edge scope 是有限边界，不支持任意大 mesh；不能截断过大 mesh 后称等价。
- 12 个样本不能证明长期稳定性；p95 接近极端值，重复实验需更长稳定窗口与成对原始样本。
- 不把阴影集合相等、无截图错误、微基准下降或历史 GPU 路径存在提升为整场 60FPS。

源字节 provenance 和有限 CPU oracle 散列见 [shadow manifest](../../../modules/scene_engine/fidelity_fx/source_shadow_assets/manifest.json)。外部研究目录是可选来源，当前 oracle 与实现均在仓库；不扩大源资源的使用或再分发许可。

## 集成与复现

先核对 [研究流程](../../../docs/research/README.md)，配置 `GODOT_EXE`；新回执写入独立目录：

```powershell
rtk proxy node tools/verify-godot.mjs --godot $env:GODOT_EXE --filter shadow --output Temp/research/shadow-contracts.json
rtk proxy $env:GODOT_EXE --path . --script res://tools/profile-hull-dynamics-world.gd -- --output=res://Temp/research/world-shadow-current.json
```

第二条需要真实图形后端，测的是诊断 CPU 调用，不是原生自动回调的完整帧性能。保留 raw records、源码散列和 scope；实际帧间隔另走普通菜单入口记录。

要重建前后比较，在独立副本加载保留的基线 adapter，并保持同一场景输入；不修改原 Math oracle、不覆盖历史目录，不从不同 run 的低点挑值。

未来任何边结构或 caster 政策改动先创建独立实验、注册论文/Demo，过 ordered oracle 与实际 GPU/lifecycle 验证，再集成正式 seam。失败回退 adapter，恢复原 shadow mode 与 cache 释放，保留失败回执及基线。
