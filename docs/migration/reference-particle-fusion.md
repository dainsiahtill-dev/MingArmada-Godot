# 粒子融合：冻结的纯模型 WIP

用户最新优先级为剧情与经营玩法；海岛、海面与粒子对接等待 REA 后续补证。本任务已停止扩展，只完成已写纯模型的安全检查与交接。**没有创建 view 或 shader，没有接任何生产事件，没有打开 GPU 窗口。**

已落盘：

- [reference_particle_model.gd](../../modules/scene_engine/fx/reference_particle_model.gd)：`RefCounted` 纯状态/数学模型，读完整资源合同。
- [test_reference_particle_model.gd](../../tests/test_reference_particle_model.gd)：隔离 headless 检查。
- 完整资源导入与验收见 [reference-effect-asset-bindings.md](reference-effect-asset-bindings.md)，该部分已完成，独立于此 WIP。

模型 API：

```text
configure(definitions_path = complete definitions/systems.json, options = {}) -> bool
spawn(effect_name, event_id, born, world_position, world_basis, seed, options = {}) -> bool
set_time(accepted_time, wind = Vector3.ZERO) -> bool
set_emitter_transform(event_id, world_position, world_basis, at_time = accepted_time) -> bool
stop(event_id) -> bool
snapshot() -> Array[particle data]
diagnostics() -> Dictionary
dispose()
```

纯模型没有自己的 `_process`、delta、墙钟或物理计时。`set_time` 是唯一推进入口，晚到事件按 `born` 与当前 accepted time 采样；重复 ID 拒绝，回退时清空活动事件与 ledger，停止持续烟后粒子按寿命消失。持续烟的 emitter pose 历史由调用方按同一 accepted time 供给，粒子出生位置查询出生时的 pose，出生后不跟随船的当前位置平移。

现在可解析完整 276 系统、16 根效果，三种炮口烟各 11 层均参加采样；隔离测试还覆盖 impact、blowout、ship destruction、low/medium/high/sinking smoke。这里“层参加采样”不等于每层已正确渲染；不同时间窗和寿命会自然使一些层暂时没有活粒子。

已采用的部分：原字段线性发射率/active 短窗，解析积分求出生时间；完整静态 emitter TRS 与 Z-up 坐标转换；初始半径/寿命/速度/颜色；原生 GrowFade 公式；base/glow 真实图片路径；NiAlphaProperty 的 alpha/add 分类与阈值。snapshot 保留纹理、glow、UV descriptor、color、radius、position 等供未来 renderer 使用。

明确的本作适配（**不是原运行时等价**）：

- 均匀半区间 variation、球坐标角度约定与积分的 0.5 中点量化。
- color keys 按归一化寿命读取。
- 持续效果按 authored 正时间区间重复；负 start 字段仍在完整 DTO 中，模型不生成事件之前的粒子。
- planar gravity 按原对象轴形成常加速度；spherical gravity 使用出生时到源对象的方向和指数衰减。真实原引擎的 force/decay/turbulence 公式尚未补齐，此适配不能被写成原公式。
- wind 是当前输入的解析平移适配，未建立原引擎风力模型。
- `NiPSysSpawnModifier` 的后代、rotation modifier 动态行为、animated TRS、全部原 controller cycle evaluator、多父路径选择、原运行时 shader override 尚未实现。
- 明示本作 `particles_per_layer=128`、`births_per_cycle=512`，不拿 `data.fields.num_vertices` 当作已验证的原动态最大容量。source 模型保留全部字段，未修改导入资源。

不可把这一模型当作已交付的画面效果。未闭合项为：`reference_particle_view.gd`、alpha/add 图片 shader、实际相机 billboard 与镜像共享、UV 动画、生产事件桥接、材质/出生变换/烟密度的正式画面验收，以及 REA 补回语义后的修正。它们按用户指令暂停开展，已有文件保留，不回退、不删除。

安全检查：非有限 time/wind/尺寸参数、错误 source-origin 类型拒绝，并保持原状态；无效控制器区间不给出生记录。模型和测试 compile 清洁，最新 Godot 4.7.2 headless **59 checks / 0 failures**；包括 1ms active 窗口内解析产生 3 次出生、GrowFade 两端、恒定风的帧拆分一致、晚到年龄一致、world-space 不随船瞬移、停止/回退/去重/处置。测试结果见 [model-wip-verification.json](evidence/reference-atmosphere-resources/model-wip-verification.json)。没有声称原生数千组数学等价或 GPU 画面已验收。

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_reference_particle_model.gd --quit-after 20
```
