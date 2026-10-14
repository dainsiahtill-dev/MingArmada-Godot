# 实验室研究与集成工作流

所有新的算法、表现改进与性能优化，先研究问题、实现独立 Godot Demo、取得可复现验证，再接入正式游戏。论文是工程报告，不宣称学术发表或同行评审。写计划、保存笔记、登记条目均不等于执行实验。

普通主菜单的“实验室”读取 [catalog.json](../../assets/research/catalog.json)，论文位于 [assets/research/papers](../../assets/research/papers)。本目录保存工作规范和仓库证据；打包阅读不依赖 docs、浏览器、HTTP 服务或外部 C 盘目录。

## 一条课题的最小交付

1. 独立 ID、可证伪假设、单位、方案比较和预先写定的接受标准。
2. 按 [TOPIC_TEMPLATE](TOPIC_TEMPLATE.md) 写完整七段论文，保存在 `assets/research/papers/<id>.md`。
3. 在 `game/research/demos/` 实现隔离 Demo，复用生产 seam；在 `game/research/catalog.gd` 的显式 `DEMO_PATHS` 登记，再在 JSON 设置对应 demo ID。报告路径固定在资源目录，不能执行文档内代码。
4. 独立实验的原始日志、状态序列、GPU 原帧及 manifest；按类型分开结论。
5. 候选冻结后再接正式入口，并保存接线回归、实际场景与回退方法。

状态映射与目录字段由 [Catalog](../../game/research/catalog.gd) 校验：`proposed` 提议、`researching` 研究中、`validated` 独立验证、`integration-ready` 待集成、`integrated` 已集成、`parked` 搁置。只有独立验证与接入回归都完成，才能标 `integrated`。

已有工作允许 `integrated-retrospective` 与 `retrospective: true`，明确历史集成、事后整理和未验证的新 Demo。没有 Demo 的条目使用空 demo；实验按钮应禁用。已有旧学习台不能因登记论文自动获得新验证状态。

## 后续 Agent 的执行顺序

1. 读取根与更近的 AGENTS、论文及 scope，记录工作区已有改动；只编辑自己的文件。索引探索先用 CodeGraph，未索引时 RTK fallback，不自行建索引。
2. 查实际入口、packet、权威时间和状态所有者；读取 primary source、fixture 与 manifest。未知字段写明未知，不从展示标签猜规则。
3. 复制模板，定义一个主假设和反例；列出基线/候选、输入域、阈值与失败判据。先记录基线源码 SHA256，禁止事后按结果改变接受标准。
4. 注册课题、报告与隔离 Demo。先实现 configure/advance/reset/pause/inspection/dispose，证明重置确定与状态可观察，再添加因子。
5. 固定 seed、初态、接受时间步、操作序列、地形、船型、相机、分辨率、quality、资源版本。进行基线/候选成对运行；确认两者只差声明因子。
6. 保存 CPU 合同、真实 GPU、连续场景生命周期与性能的分别回执；逐条检查接受标准。失败保留并解释；不以一句“测试通过”代替矩阵。
7. 独立验证通过后冻结 source/hash/inputs，标 `integration-ready`；接生产 seam。正式入口、重建、暂停、回退/恢复与释放全部验证后才标 `integrated`。
8. 更新论文结果与目录证据链接，保留失败、旧候选及回退路径；交接注明本轮执行命令、实际结论和仍未测项。

## 独立 Demo 合同

实验在独立 SubViewport/World3D 中，不读写航程存档、船长设置、生产 session 或网络。宿主唯一负责 advance，Demo 不再自动 `_process` 推进。切换或退出显式 dispose，释放自己的实例、材质、镜像和 GPU 资源。

控制因子至少可重置、暂停、选择固定相机及开关实验因素。开关只改变声明内容；船体首批对照隐藏 contact 载体，同时保持同一 runtime、contact 时间线及尾迹。它不代表旧算法。

每次重置返回完整初态/接受诊断。inspection 至少包含接受时间、tick、种子或 RNG 状态、对象/资源计数及实际输入。连续重置同输入应可比较；暂停转镜头可以刷新展示，不能推进权威时间、随机数、出生或历史。

## 证据与 manifest

新记录放 `docs/research/evidence/<id>/<run-id>/`，run-id 使用 UTC 时间加可读版本标识；临时测试可放 `Temp/research/`。历史 `docs/migration/evidence` 保持原目录与语义，不覆盖原 RED、早期失败或最终冻结结果。

manifest 是人工可审计数据合同，首批工具可能有自己的 JSON schema。不能把下面的推荐字段误称已经由所有工具自动输出；缺失字段应补记，未知值写 `unknown` 并说明影响。

```json
{
  "schemaVersion": 1,
  "topic": "topic-id",
  "runId": "new-unique-run-id",
  "recordType": "planned",
  "scope": "independent-demo",
  "hypothesis": "declared-before-run",
  "baseline": {"sources": {}, "inputs": {}},
  "candidate": {"sources": {}, "inputs": {}},
  "environment": {"engine": "unknown", "cpu": "unknown", "gpu": "unknown", "driver": "unknown", "backend": "unknown"},
  "controls": {"seed": "unknown", "initialState": {}, "stepSeconds": 0.03125, "camera": {}, "viewport": {}, "quality": "unknown"},
  "commands": [],
  "acceptance": [],
  "artifacts": [],
  "verdict": "not-run",
  "limitations": []
}
```

执行后把 recordType 改为实测类型，并填开始/结束 UTC、退出码、唯一完成标记、ERROR 检查、断言及失败数、工具/source/fixture/artifact SHA256；每张图绑定接受时间、镜头及 raw snapshot。推荐类型为 `cpu-contract`、`gpu-capture`、`performance`、`integration`，另有 `historical`。

原帧不得修饰后称原始截图；隐藏船壳、改纯色材质、抬升姿态等诊断要单独标记。HTML 查看页只是可选辅助，PNG/JSON 自身可审阅。第三方源路径与许可证单独记 provenance；不要求读者具有 `C:/Games/...`。

## 性能方法

先写测量范围：纯算法微基准、隔离 GPU arena、真实 runtime 的 CPU 分段，或正常入口的实际 frame interval。GPU 环境中的 CPU 时间仍是 CPU 时间；renderer submit 不直接称 GPU draw duration。

固定硬件、电源策略、引擎/driver/backend、画质、分辨率、对象数和输入；充分暖机后保存所有样本。报告样本数、均值、p50/p95、min/max、失败和排除规则；优先交替成对运行基线/候选，避免温度和缓存变化只落在一组。

说明 quantile 算法：默认先排序，以 `ceil(q*n)-1` 的 nearest-rank 取 p50/p95；如果现有工具不同，写实际方法，不混合表格。更长运行分窗口报告；12 样本的 p95 只能描述该小样本。

fresh source call、cache hit、camera-only 分开，父子分段不重复相加。报告 raw wall interval 时记录真实 accepted 秒与场景位置；不同区间/镜头不得算严格稳定提速百分比。保持船数、3D 人物、粒子、物理与遮挡，不通过删功能提高等价指标。

CPU 微基准下降与整场 FPS 是不同结论。60FPS 若作为接受标准，必须在预先声明场景的实际整场 frame time 中验证约 16.67ms 预算及 p95；不能从局部平均数反推。当前历史自由试航尚未达标。

## 本机复现入口

在 PowerShell 中将本机 Godot 4.7 可执行文件路径配置为 `GODOT_EXE`；Node.js 和 RTK 需可用。每条 shell 命令以 RTK 开始，输出选择新路径：

```powershell
rtk proxy node tools/verify-godot.mjs --godot $env:GODOT_EXE --filter hull_contact --output Temp/research/hull-contact-tests.json
rtk proxy $env:GODOT_EXE --path . --script res://tools/verify-laboratory-gpu.gd -- --output=res://docs/research/evidence/laboratory-2026-10-14
```

第一条是严格 headless 合同 runner，检查退出码、Godot 错误和唯一完成标记；第二条需要真实图形后端，执行后还须检查 PNG/JSON。命令写在文档中不会自行执行。重新复跑第二条应更换输出目录，不覆写旧记录。

无需终端时用 Godot 打开 `project.godot`、F5，从普通主菜单进入实验室并选择课题。目前 hull-contact、ocean-surface、shore-surf、weather-shadow 四项拥有独立 Demo；shadow-edges 仍只有论文。既有生产效果从正式场景另行验证，不把这种入口改名为独立实验。

环境课题通过 `control_spec()` 声明选择、开关与数值因子，统一宿主负责显示与参数回读。暂停后“单步 1/32 秒”只推进一个接受步；“同条件重置”保留当前观察镜头。窗口尺寸改变只刷新投影，不推进时钟或 RNG。需要改变初态的预设必须明确返回 `reset_required`，宿主只覆盖该项后重建。截图等待期间切换参数、镜头或课题，会取消过期截图。

岸浪实验增加“水岸羽化（垂直米）”：0 是原硬边基线，正值是局部覆盖率候选，必须比较同刻原帧。此数值不是水平沙滩宽度，浅坡的水平过渡更宽；不要把它误当泡沫宽度。天气的无光照网格是云影诊断接收面，明确区别于正式海面。

旧工具若固定输出到历史路径，先归档证据，在项目副本复跑；不能仅改 phase 标签后覆盖旧候选。GPU 首帧、正常入口与控制 arena 的结论分别写明。

## 集成与回退门槛

集成前：所有独立接受项有本候选新证据，sources/inputs 已冻结；权限、资源、时间和导入来源边界明确。算法可以不同，但每项变化需独立理由与测试，不能在共享重试/渲染接口里暗改业务政策。

集成后：检查真实入口、画质重建、暂停/重复时间、换场景/epoch、恢复、生命周期、存档/设置未被实验改写、包内报告可读；完整回归与定向复验的覆盖方式必须如实区分。

回退保留原 seam 和源码/fixture/原帧基线。失败时移除本候选接线，恢复资源/gate 状态，不删除个人存档、不重写历史证据、不把未完成标成通过。搁置要写失败机制和下一次最小验证动作。
