# 船体接水流沫：相对入水、贴壳轮廓与接受时钟

- 课题：`hull-contact`；整理日期：2026-10-14；报告类型：工程研究，既有工作事后整理。
- 状态：生产实现已有历史集成证据；本轮独立 Demo 的行为合同、真实 GPU 捕获与首页生命周期已验证。低位近拍的三角块和水沫辨识度仍是开放问题，不能称整体美术效果达标。
- 摘要：用船体与水面的相对间隙驱动短脉冲，用真实船壳的多高度截面构造低矮流沫，保留既有尾迹。
- 来源：[动态修复报告](../../../docs/migration/hull-dynamics-2026-10-14.md)、[初次重做报告](../../../docs/migration/hull-contact-redesign-2026-10-14.md)。下列历史结果不代称本轮新实验结果。

## 问题与假设

近船白沫若只随船速播放，会在抬起的船首悬空，停船后仍出生，转镜头时又消耗随机数。单一水线轮廓也不能适应船体升沉、俯仰和横摇。

假设 H1：同一接受时刻的船首世界点与真实水面的相对闭合速度，比船体独立垂直速度更能识别入水；共同升降不应产生冲击。

假设 H2：配置时缓存真实船壳的多高度轮廓，展示时迭代求左右接水线，可让短浪脊贴壳；已出生水滴使用世界坐标，可摆脱父节点浮动。

单位：世界位置与浪脊高为米，速度为米/秒，角度为弧度，接受时间为秒。6 节换算采用 `6 * 0.514444` 米/秒。这些是表现算法，不改变权威操船物理。

## 方案比较

- 速度驱动的大白沫 billboard：资源和提交简单，但约 3.2 米宽的旧局部白沫难以表达贴壳接水，遮挡容易形成白块。
- 任意三角网格每帧精确切水：连续几何依据强，但五波与姿态变化使查询、交点连接和退化面处理昂贵；本次没有采用，也没有声称已经实现。
- 多高度缓存环加接水迭代：配置成本可缓存，能复用真实船型；接受离散剖面误差，适合窄、低、半透明流沫。当前采用此方案。
- 完整流体模拟：可描述压力和体积守恒，但运行成本、边界条件与现有操船合同不匹配；本课题仅研究可验证的局部表现。

当前生产流沫与原尾迹由不同状态和材质负责。实验室开关对照是同一算法的可见/隐藏对照，不能称旧算法与新算法的比较。

## 算法与实现

[HullWaterlineProfile](../../../game/presentation/ships/hull_waterline_profile.gd) 从真实船壳三角形缓存 13 个高度截面，保留原 Y0 截面。[HullContactFroth](../../../modules/scene_engine/water/hull_contact_froth.gd) 根据完整 `hullToWorld` 姿态与海面采样，分别求左右接触范围。

对船首探针，记 `gap = probe.y - water_height(probe.x, probe.z, t)`，则 `closing = (previous_gap - gap) / dt`。只在连续接受时间 `0 < dt <= 0.25` 秒时求导；首次、回退、epoch 变化、瞬移与长跳跃清除导数状态。

闭合速度超过 0.35 米/秒、间隙绝对值不超过 0.5 米、轮廓覆盖超过 0.05 且位置属于海面时，可触发脉冲。强度按 `smoothstep(0.35, 4.0, closing)` 取值，用 `exp(-dt / 0.28)` 衰减，并用重新武装条件避免持续重复触发。

流纹累计真实行进距离；航向差除以时间得到转向量，乘 0.16 后限制在 ±0.18，并以 0.12 秒时间常数平滑。浪脊上限 0.22 米，水滴面片全尺寸上限 0.20 米，固定 48 槽。

```text
接受有效 packet 与同一 water(t)
若时间线不连续：清水滴、流距、间隙和航向历史
若是新接受时间：更新闭合脉冲、行距、水滴年龄与出生
按相机距离选择 48×5 / 24×3 / 12×3 网格（含迟滞）
可见顶点采真实水高；不可见顶点折叠；完全淡出停止几何采水
更新固定 ArrayMesh region；同时间相机重绘只更新展示
```

入口为 [SourceWaterPacket](../../../game/presentation/world/source_water_packet.gd) 与 [SourceWakeRenderer](../../../modules/scene_engine/water/source_wake_renderer.gd)。独立 [foam shader](../../../modules/scene_engine/water/hull_contact_foam.gdshader) 和 [spray shader](../../../modules/scene_engine/water/hull_contact_spray.gdshader) 处理透明写深度海面与不透明船壳遮挡。

## 实验设计

历史动态 GPU 序列采用真实 Ship/Crew/Packet/renderer 与 SailingRuntime，五组生产波浪和材质；每组 321 个接受样本，外层时间步 1/32 秒。海床为 -20 米，初始速度巡航 3.086 米/秒、低速 0.8 米/秒，航向 0.45 弧度，风向输入 `(-1, 0.3)`、风速 14 米/秒。

历史载体为 1200×1200 米、512 细分均匀 PlaneMesh，避免低位约 22° 相机下旧投影网格的近端覆盖空隙；生产海面材质、镜像、折射与深度仍启用。此控制与正式投影网格不同。

本轮独立 Demo 复用该载体与默认 `fuchuan/cruise/side`，航行 sail trim 默认 0.8 弧度。宿主固定 32Hz；原生 SailingRuntime 保留自身 120Hz 子步。接受时间读取 runtime，展示时间记录 `tick/32`，不能把两者隐式混用。

生产 packet 的 seed 来自 `absi("player".hash()) % 2147483647`；本轮实际值为 351953554。回执保存相机矩阵/投影、轨道角/缩放、分辨率/画质、seed 和 64 位 RNG 十进制文本。同一版本、初态、命令与镜头序列下重置应重现；未做跨引擎 RNG 等价保证，也未实现任意时刻粒子池的完整载入。

- 因子：六船型 `fuchuan/fisherman/merchant/voc/patrol/heavy`；cruise/slow/turn/stop/reentry；side/front/high 相机。
- 再入水：明确附加 2 米抬升，在 3.85–4.30 秒下降，属于压力姿态；不能当自然航行行为。
- 开关对照：只隐藏接触载体，继续相同 runtime、contact 时间线和尾迹；重置后按相同步数比较原始 snapshot。
- 接受标准：重置确定；暂停不推进 tick、出生、RNG、年龄、尾迹；共同升降无误脉冲；停船停止新出生；退出释放；无非有限顶点；尾迹逐项不变。
- 图像标准：固定分辨率、镜头与时刻，观察贴壳、遮挡及退场；隐藏船壳图只作诊断。性能另记 CPU p50/p95，不能用测试断言或静态图替代。

## 结果与证据

历史 [DELIVERY_VERIFY.json](../../../docs/migration/evidence/hull-dynamics-2026-10-14/DELIVERY_VERIFY.json) 记录 13 组最终序列、176 张 PNG；[连续查看页](../../../docs/migration/evidence/hull-dynamics-2026-10-14/review.html) 为可选辅助，直接 PNG/JSON 也可阅读。六船型已覆盖；早期 diagnostics 与隐藏载体误恢复图不作为最终通过证据。

历史 [四脚本回执](../../../docs/migration/evidence/hull-dynamics-2026-10-14/regressions.json) 为 dynamics 39、LOD 19、froth 399、真实 sailing/battle 尾迹 integration 4555 项，失败均为 0。这是既有回执的整理，本报告没有重新执行这四项。

foam/spray 历史深度检查各 3 项，共 6 项；可见载体的 Vulkan vertex/UV 读回与上传缓冲匹配，alpha 允许 RGBA8 量化误差。完全 dry 的隐藏载体可能保留旧 GPU 面，不能强行恢复它来评判。

历史 [GPU arena 比较](../../../docs/migration/evidence/hull-dynamics-2026-10-14/performance/comparison-gpu.json) 的 contact CPU p50：单船 35 米 9.718→7.240ms，3 船 75 米 28.778→7.907ms，10 船 180 米 97.967→14.137ms。仅包括隔离 Ocean、模型与 contact；没有 crew/world/source stencil。

单船 arena wall p50 为 16.310→16.707ms，说明 CPU 局部下降未必提高帧率。正常入口 240 帧间隔、完整世界与阴影分段属于另一个测量范围；正式游戏未达到 60FPS，不能由此推导全游戏达标。

本轮 [实验室回执](../../../docs/research/evidence/laboratory-2026-10-14/regressions.json) 四脚本全部通过：Demo 89 项，UI 21 项，另有目录与真实 Main 的进入、返回、重入和取消检查；[生产水沫回归](../../../docs/research/evidence/laboratory-2026-10-14/hull-regressions.json) 四脚本 5012 项、0 失败。相机参数遗漏的独立审查问题已修复，保存其失败与复验记录。

[本轮 GPU 回执](../../../docs/research/evidence/laboratory-2026-10-14/GPU_VERIFY.json) 在 Godot 4.7.2 / Intel Arc 130T / Vulkan Forward+ 下，从普通首页进入实验室，记录 43 张整窗口 PNG 与额外 1 张原生实验截图、五组各 161 步时间线、六船型、三个观察视角、暂停开关和载体配对；失败 0。它验证捕获与状态合同，不等同于水沫已达艺术目标。原帧检查发现低位图仍有明显平面/三角视觉形状，水沫较弱；此失败观感明确保留，不调整图像或强行加白。

新 [载体测量](../../../docs/research/evidence/laboratory-2026-10-14/carrier-study.json) 每种载体采集 1,318,912 个近船样本。1200m/512 最大水高插值误差 9.201mm、p95 6.431mm；384m/512 为 0.949mm/0.660mm；256m/512 为 0.410mm/0.292mm。原载体保守连续几何界为 20.246mm，仍小于接触偏移 45mm，因此“几何插值足以吞掉全部水沫”的假设被否证。法线、深度、光学与遮挡需要分别研究，不能凭网格更密宣称根因已解决。

实验室提供 1200m 基准与 384m 近场的同初态对照，保持 512 细分与相同生产材质。配对原生船姿、时间和尾迹一致；384m 缩小覆盖为 ±192m。其 GPU 原帧接水表现仍较轻，没有作为正式海面的替换方案。

## 局限与失败

- 高度环与接水迭代不是完整流体，也不是任意网格连续切割；任意高度相对原三角形的误差尚未全量量化。
- 正常巡航冲击可很轻，某些姿态不出生水滴；不能为“每船持续喷水”放宽接水判断。
- 不同船数、地理路径和接受调用比例不可混合求性能；fresh source call 与 camera-only 必须分开。混合 p50 不是每船新计算成本。
- 历史 uniform carrier 验收不证明正式 projected grid 覆盖；正常菜单入口、实际镜头与独立控制场景需分别保留。
- 3D 甲板人物、海面与权威操船需共同保留，不通过隐藏它们来声称等价提速。

模型、贴图与源学习资料的来源见仓库既有迁移记录；外部 `C:/Games/Pirates-REA-Reference-20261011` 只是研究来源。此论文不要求外部目录存在，也不授予原资源再分发许可。

## 集成与复现

按 [研究工作流](../../../docs/research/README.md) 保存源码散列、种子、相机和原始证据。先导入 `project.godot`，从普通主菜单进入实验室；选船体课题，依次重置、播放、暂停、转镜头、开关、切换船型与返回。

在仓库根目录，先将本机 Godot 4.7 可执行文件配置为 `GODOT_EXE`；验证命令写入新的 Temp 回执：

```powershell
rtk proxy node tools/verify-godot.mjs --godot $env:GODOT_EXE --filter hull_contact --output Temp/research/hull-contact-tests.json
rtk proxy $env:GODOT_EXE --path . --script res://tools/verify-laboratory-gpu.gd -- --output=res://docs/research/evidence/laboratory-2026-10-14
```

第二条是本轮实验室 GPU 工具的复现入口；运行后仍需检查实际截图和 JSON，未运行不能填“通过”。新复跑应改为自己的独立输出目录。

旧 `tools/verify-hull-dynamics-gpu.gd` 固定写历史目录，`profile-hull-contact.gd` 也按 phase 写固定性能目录；先归档证据，在项目副本复跑。不能覆写旧回执后仍引用旧源码散列。

未来改算法：先新增课题版本、论文与独立 Demo，固定基线并过接受标准，再接游戏入口；复验 tail、packet、router、深度、六船型及真实场景。失败保留原始日志和基线，回退该 seam，不能清空旧证据。
