# 航行输入与暂停后的操控连续性

- 课题 ID：`sailing-handling`；版本：2026-10-14，T2。
- 类型：既有操控算法的历史集成事后整理；新增暂停/手势失败夹具与修复研究。
- 状态：研究中，CPU 反例和回归已验证；真实 GPU/原生鼠标验收待 root。原航行、casual 助力和相机早已集成，本轮不补造先实验后集成历史。
- 摘要：修复暂停丢失已接受推进归属、旧延迟释放吞掉新点击。既有推进与相机公式保持；CPU 回归全部通过。
- Demo：`res://game/research/demos/sailing_handling_experiment.gd`，由统一目录登记。真实 Encounter、SailingSimulation、ShipView、ShipCameraController；蓝色平面/网格仅用于运动诊断。
- 源码：`game/runtime/sailing_simulation.gd`、`modules/naval_simulation/controls/casual_sailing.gd`、`game/scenes/common/mouse_course_projection.gd`、`game/presentation/world/ship_camera_controller.gd`。仓库既有代码，无新增第三方资产或外部算法。
- 基线：`42761b71e73c1174eecf5a34e524d80475c06df3`；[本轮 manifest](../../../docs/research/evidence/sailing-handling/2026-10-14T103333Z-controls/manifest.json) 含精确源码 SHA256、原基线源码、命令、退出码及原始日志。

## 问题与假设

H1：暂停清理临时输入时错误丢弃已接受的 casual 推进所有权，恢复仅重建 mouse course；直接帆量、控件或按键操作会在恢复后失去逆风推进。反例用真实 Encounter + SailingSimulation，向 +X 迎风航行两秒，暂停后再接受四秒，与连续六秒比较。

H2：raw LMB release 无条件安排延迟清理；同一帧中新手势 press 发生在旧清理执行前，新手势被旧清理取消。比较原生产 scene callback 序列，不能只测试替代事件分发器。

坐标 XZ 米、heading 弧度、速度米/秒；固定 60Hz accepted simulation step。Encounter 唯一拥有运动，adapter 只保留输入意图。相机渲染时钟不推进航行时间。没有新增随机算法，native seed 1661。

## 方案比较

暂停恢复重新注入按键：会产生未授权持续转舵和升帆，拒绝。恢复已接受的操控所有权并重新检查船舶权限：保留帆量，清除 held keys；无额外物理力或回放时间，拟采用。

鼠标在 raw release 立即取消：会吞掉随后正常 unhandled click，拒绝。无条件延迟取消：现有基线，存在跨手势风险。延迟清理只匹配发起清理时的手势版本：保留正常 world click 与 GUI release 取消，拟采用。

## 算法与实现

不改 casual 的目标速度、加减速上限、rudder 响应及相机指数平滑公式。修复限于状态边界：暂停清 held keys、queued actions、native assistance，保留可验证的 accepted manual ownership；恢复前重新检查身份/权限。手势取消仅对同一版本有效，后续 press 增加版本。

输入取消 O(1)，暂停边界 O(1)，无额外每帧轮询。`set_paused()` 暂停仍清 native assistance，但保留 adapter 的已接受 manual owner；重新检查 player/battle identity、sailing permission。外部权限变化、模式切换仍能撤销归属。`cancel_gesture_after_dispatch()` 捕获 gesture id，后续 press/cancel 增加 id；延迟清理只匹配原 id。

实验由 host 推进。`pause-resume` 在实验 tick121 暂停、181 恢复；420 个实验 tick 对应6秒 native accepted time。宿主暂停冻结实验时间；镜头输入只使用 camera input clock。同条件重置重建真实 native owner，并保留所选镜头目标；显式镜头预设改变则重新选镜头。实验不读写 career、用户设置或存档。

## 实验设计

固定福船、满状态、无货物、深水 -80m、无波、heading 0、speed 0、风向 +X、12m/s；seed 1661、step 1/60s。基线源码为上述 commit。输入含 sail API、queued controls、W、mouse-course；每例先2秒、冻结2秒、再4秒接受时间。

预先接受标准：暂停全 native snapshot 不变；恢复后同接受时间 visual 与连续基线完全相同；六秒前进速度 >=1.5m/s，航向误差 <5度；暂停期间输入不生效；原 held W/D 不在恢复后持续升帆/转舵；权限撤销不能恢复助力。手势同帧 release/press 后须只接受新 click 一次，GUI 释放后无新 press 不得产生幽灵 click。

CPU 用 strict `tools/verify-godot.mjs`，成功需退出0、唯一完成标记、failures=0且无 Godot ERROR。GPU/原生界面证据由 root 执行；未执行不能以 headless 冒充。无性能优化宣称，不由 demo 估算正式 FPS。

## 结果与证据

全部文件在 [本轮证据目录](../../../docs/research/evidence/sailing-handling/2026-10-14T103333Z-controls/manifest.json)。Godot4.7.2 headless，严格 runner 检查退出码、唯一完成标记和 ERROR；不代表图形后端执行。

- 基线已有 sailing 5/5、camera 3/3 通过，但未覆盖新增边界。
- H1 RED：`t2-red-sailing-pause.json`，26断言/6失败。sails/controls/W 在恢复后速度均0；连续对照分别2.34949/2.34949/2.89934m/s。mouse-course 对照原本正确。
- H1 GREEN：`t2-green-sailing-all.json`，6文件、411断言/0失败；其中新增 pause48断言包含原生 free-sail runtime 的 player/menu/blur/loading/chart 五个门禁。恢复后 native visual 与连续同接受时间完全相同；旧按住键清除，撤销 sailing permission 不恢复助力。
- H2 RED：`t2-red-gesture-generation.json`，75断言/1失败；原场景旧 GUI release 清理吞掉同帧新 sea press。GREEN `t2-green-both-scenes-final.json`79断言/0失败，覆盖 Practice 与经真实接单/离港后的 Mingqi。无新 press 的 GUI release 仍清理原手势。
- 独立实验先有缺资源 RED，再有真实推进 RED；修后 `t2-green-demo-final.json`22断言/0失败。重置、非法输入、同条件确定性、镜头与 native 时钟分离、五序列及显式释放均通过。
- 新反打测量 `t2-handling-trajectory-2.json`152断言/0失败：空载满状态福船从2.488m/s反向180度，0.5/2/8/24/32秒分别转1.40/12.24/57.01/172.10/179.59度。最大60Hz步进航向0.002252rad；最大rudder步0.15352。180度转向具有惯性，不能把8秒尚未掉头称为卡死。
- 同轨迹收帆：从约4.04m/s，0.5/2/8秒速度3.454/2.054/0.00102m/s；30秒接近0。未改变力/转矩公式。
- 当前 hull-contact 4文件5012断言/0失败：升沉、共同运动、局部入水/衰减/重新入水、转向偏置、停船与 LOD、尾迹逐项不变。只复验，无相关代码改变。

同时保留新增测试编写中的非产品失败：`t2-handling-trajectory.json` 是插入函数位置错误的 parse failure，已纠正；`t2-green-both-scenes*.json`/diagnostic 的旧 menu pause 为扩展 fixture 的残留门禁，使用公开 owner API 清理后才检验手势，不据此宣称生产暂停 bug。

## 局限与失败

独立深水控制实验不证明岸边避障、碰撞、GPU 水沫或完整游戏 FPS。真实 GUI 消费、视口像素、硬件鼠标需原生入口验收。CPU 场景测试直接分发 callback，明确区别于 OS 输入。实验不含海面、船员、水沫负载；蓝色平面不是正式海水算法。heavy/voc 的某静态测试姿态没有 droplets 是真实 contact 门禁的结果，不能仅据此认定视觉缺失。

## 集成与复现

正式入口为自由试航和明旗航程，共用 SailingSimulation 与 mouse_course_projection；两场景 raw left release 已接新 method。root 负责 catalog、GPU与PCK集成，详见 [实机验收步骤](../../../docs/research/evidence/sailing-handling/2026-10-14T103333Z-controls/native-itinerary.md)。

复跑示例：`rtk proxy node tools/verify-godot.mjs --filter sailing_pause_ownership --output Temp/research/new-run-pause.json`；鼠标用 filter `camera_scene_input`，实验用 `laboratory_handling`。始终换输出路径，不覆盖历史证据。回退仅恢复 baseline 中对应 ownership/gesture seam；不删除证据或用户文件。真实GPU与原生入口尚未闭合，因此当前状态保持研究中。
