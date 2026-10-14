# 船首、船侧水沫动态与实际性能修复

2026-10-14。现有 Godot 游戏路径中落地船首相对入水、转向流沫、距离细节与固定上传缓冲。尾部源历史/几何/材质保持原样，海面与权威操船规则保持现有实现，甲板人物继续使用3D。没有增加玩家菜单入口。

## 实装行为

- 同一接受时钟的船首世界点与真实水面高度求间隙，再计算闭合速度。船下压或浪峰上升可触发；共同升降不误触发。
- 接水附近且剖面有效时产生短脉冲，约0.28秒衰减；首次、退时、epoch变化、瞬移、长时间跳跃及相机重绘不会制造入水反馈。
- 局部浪脊最多0.22米；水滴满边最多0.20米，固定48槽。流纹使用真实行进距离驱动，转向外侧/内侧增益限制为±18%。
- 近/中/远分别48×5、24×3、12×3，距离切换有迟滞。暂停缩放只更新展示细节，不推进流纹、RNG、水滴年龄或冲击。
- 独立 ArrayMesh 缓冲与 region upload；可见顶点逐点查询水高。不可见顶点折叠至已采水点，完全淡出后停止几何采水。未出生水滴槽不再把远处船的包围盒拉到世界原点。

实现：[hull_contact_froth.gd](../../modules/scene_engine/water/hull_contact_froth.gd)、[foam shader](../../modules/scene_engine/water/hull_contact_foam.gdshader)、[water packet](../../game/presentation/world/source_water_packet.gd)。

## 实际图像验收

[连续原帧验收页](evidence/hull-dynamics-2026-10-14/review.html)包含13组、176张最终PNG，六种真实船型，巡航、低速、转向、停船、再入水和多个视角。每组321个接受时间样本；每张图片保留时间、速度、冲击和转向诊断。

低视角验证使用现有海面材质、五组波浪、反射/折射/深度，与原生 SailingRuntime 和真实 Ship/Crew/Packet/renderer。为避免既有 projected grid 在22度接水视角出现近端视锥覆盖空隙，**控制验收使用1200米、512细分的均匀载体网格**；这是GPU材质与局部效果验收，不能冒称正式海面投影或整场景FPS证明。正式投影另由正常主入口观察。

再入水压力场景明确额外抬高船体2米，在3.85–4.30秒下降；强脉冲最大1.0。其他控制场景使用原生姿态，正常巡航的冲击可以很轻；不强制所有船型持续喷水。

可见载体的Vulkan vertex与UV读回匹配提交缓冲；alpha仅有RGBA8量化误差。完全dry载体保留旧GPU面并隐藏，读回旧面并不是错误。验收工具最初错误地恢复隐藏载体，已修正并重拍全部最终序列；`diagnostics`与早期目录不作为最终通过画面。

普通主菜单/router进入自由试航的[实际画面](evidence/hull-dynamics-2026-10-14/actual-entry/main-free-trial.png)、[240帧记录](evidence/hull-dynamics-2026-10-14/actual-entry/VERIFICATION.json)独立保留。Computer Use实际进入该窗口并验证滚轮拉近；[现场截图](evidence/hull-dynamics-2026-10-14/live/02-zoom.jpg)保留。工具返回后窗口失焦会暂停，没有把海面点击后的静止截图当成连续鼠标操船证据。动态变化由控制GPU序列和正常入口时间推进记录验收。

## 性能根因与结果

实际自由试航的CPU分段发现阴影链平均82.9955ms，世界完整更新36.1993ms；局部水沫在fresh source call的全舰队平均9.8975ms，camera-only平均0.4432ms。混合p50不能当每船fresh成本。

根因：target rigid caster adapter对每条阴影边调用线性取消，dirty silhouette构建最坏O(E²)。改成无向uint16边→slot索引，保留原方向、奇偶取消、swap-last/pop顺序与缓存失效。native Math、投影数量、renderer/compositor和caster选择规则保持原样。

[target_rigid_shadow_caster.gd](../../game/presentation/world/target_rigid_shadow_caster.gd)的索引版本对450个真实/大网格caster、83,339个volume vertex，完整ordered edges/caps/positions/indices/direction/counts逐元素匹配原Math oracle。

本机Godot4.7.2 / Vulkan Forward+ / Intel Arc 130T GPU的测量：

| 测量范围 | 修改前 | 修改后 |
| --- | ---: | ---: |
| GPU运行环境，单船35m局部contact CPU p50 | 9.718ms | 7.240ms |
| GPU运行环境，3船75m局部contact CPU p50 | 28.778ms | 7.907ms |
| GPU运行环境，10船180m局部contact CPU p50 | 97.967ms | 14.137ms |
| 真实自由试航CPU阴影链，12个fresh样本均值 | 82.9955ms | 22.1387ms |
| 真实自由试航240帧wall间隔p50 | 133.840ms | 83.346ms |

前三项是相同输入/种子/剖面/五波的隔离Ocean+模型+contact arena，不含crew/world/source stencil，不是全游戏FPS。单船GPU arena wall p50为16.310→16.707ms，说明contact CPU下降不自动变成帧率提升；3船45.137→23.898ms，10船148.576→64.557ms。

阴影优化后compose均值7.630ms，submit均值14.459ms，world均值31.034ms。真实自由试航仍未达到60FPS，剩余热点明确保留；submit是renderer CPU刷新与compositor提交，不直接称GPU绘制时间。正常入口前后观察的模拟区间/可见位置不同，不能当严格相同画面的稳定提速百分比。

[12对CPU矩阵](evidence/hull-dynamics-2026-10-14/performance/comparison-cpu.json)、[3对GPU arena](evidence/hull-dynamics-2026-10-14/performance/comparison-gpu.json)、[实际世界修改前](evidence/hull-dynamics-2026-10-14/performance/world-cpu.json)、[修改后分段](evidence/hull-dynamics-2026-10-14/performance/world-cpu-after-shadow.json)包含原始样本和源码散列。早版其他五船型CPU证据明确标记pre-hotpath；最终GPU已覆盖六船型。Legacy native sampler矩阵使用reference geography，与当前自由试航natural geography不同，不把那组数据代称当前入口。

## 回归与交接

- Root最新4个hull脚本通过：dynamics39、LOD19、原froth399、真实sailing/battle尾迹integration4555。
- Root最新5个shadow脚本通过；新增indexed-edge测试5498断言，原math/renderer/lifecycle/gates也通过。
- foam/spray各3项真实GPU深度检查，共6项通过。
- 13组最终图像、六船型、原样尾迹5文件散列与输入匹配通过统一[交付校验](evidence/hull-dynamics-2026-10-14/DELIVERY_VERIFY.json)。

剖面仍是离散高度环与迭代接水展示，不是完整流体/任意网格切割。本次没有更改操船物理，也没有把演示压力姿态当成自然航行效果。所有修改保留在现有工作区，没有提交、暂存或推送。
