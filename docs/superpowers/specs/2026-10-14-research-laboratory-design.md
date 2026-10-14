# 实验室与可复现课题

用户要求：每个新的算法或表现改进先独立研究、实现 Godot Demo、验证，再引入游戏；首页有“实验室”，以论文式说明和证据帮助后续 Agent 理解。

## 范围

建立普通首页可访问的实验室。一个注册目录管理课题，不继续增加首页独立示例按钮。首批纳入船体水沫、海面、岸浪、天气云影、阴影优化五项已有研究；船体水沫提供新的独立交互实验。其他项先准确登记为文献整理，不能凭登记宣称已有独立 Demo 或完成科学验收。

论文式记录是工程研究报告，不宣称学术发表或同行评审。既有工作注明“事后整理”，新工作遵循先研究后集成。

## 架构与合同

- `game/research/catalog.gd` 读取 `assets/research/catalog.json`，仅接受固定资源目录和本地注册 Demo。报告保存在 `assets/research/papers/*.md`，使打包后的游戏也能阅读。
- `game/research/laboratory.gd` 为 Control，有 `main_menu_requested`、`startup_options`、`startup_receipt`、`activate_entry()`、`dispose()`。通过现有菜单与 router 的 generation/nonce 生命周期进入和退出，不写入航程存档或船长设置。
- 页面左侧课题列表，右侧研究全文；“运行实验”仅对有已注册 Demo 的课题开放。实验在独立 SubViewport/World3D 中，退出或切换课题释放实例。
- `game/research/demos/hull_contact_experiment.gd` 为 Node3D，复用生产 Ship/Crew/Ocean/WaterPacket/WakeRenderer 与 SailingRuntime，不改动生产效果。固定 32Hz 时间步，提供 cruise/slow/turn/stop/reentry、六船型、side/front/high 相机；暂停、重置、船体水沫开关对照。
- Demo 接口：`configure(options: Dictionary) -> Dictionary`；`advance(delta: float)`；`reset_experiment(options: Dictionary = {}) -> Dictionary`；`set_paused(value: bool)`；`set_contact_enabled(value: bool)`；`set_camera_mode(value: String)`；`inspection_snapshot() -> Dictionary`；`dispose()`。实验宿主负责 advance，Demo 不独立自动 process。
- 对照是“启用／关闭船体接触水沫”，保持同一状态和尾迹；不得伪称为旧版算法对照。重入水项的 2m 抬升为显式压力测试。为近距离观察采用均匀平面承载生产海面材质，报告明确与游戏投影网格的区别。
- Markdown 阅读只处理标题、段落、列表、代码块和安全本地引用；不执行命令，不依赖 HTTP 服务、绝对 C 盘路径或浏览器。
- export include_filter 增加 `assets/research/papers/*.md`；JSON 沿用原 include。docs 不打包，论文保留通往仓库实现与证据的来源说明。

## 研究规范

七部分：问题与假设、方案比较、算法与实现、实验设计、结果与证据、局限与失败、集成与复现。必须记录单位、种子／初态、时间步、相机、硬件／引擎版本、操作或运行命令、对照条件、接受标准、来源与许可证边界。未知项写明未知，计划与实测分开。

生命周期：提议／研究中／独立验证／待集成／已集成／搁置。只有真实独立验证和接入回归都完成，才能标为已集成；已有工作允许按事实注明历史集成与事后整理。测试检查报告关键段和目录唯一性，不强迫无关效果采用某种算法。

## 验收

普通首页按钮与返回路径；不写入存档／设置；五项报告可读且资源存在；无 Demo 的项目清楚禁用运行；船体实验确定性重置、暂停不推进、切换无资源残留、对照保留尾迹；真实 GPU 主菜单、论文与实验截图；现有菜单／router／水沫回归通过。发布过滤覆盖报告与 Demo，不引用 docs 内运行代码。

## 决定

在现有用户工作区执行，保留已有未提交更改。并行任务按文件所有权划分，不创建新架构依赖、不安装体素库、不提交或发布。用户本轮已明确要求实施入口与持续规范，直接完成可审查结果。

实际截图暴露均匀海面载体的近拍局限，增加一个隔离的载体密度对照：1200m 与 384m 均用 512 细分，重置同一初态后比较；不改正式海面。先做真实三角插值误差测量，保留否证结果，再做 GPU 对照，不能仅凭更密网格宣称水沫遮挡问题解决。近场载体覆盖 ±192m，元数据记录实际范围与网格间距。
