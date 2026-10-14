# 实验室交付 · 2026-10-14

普通首页已增加“实验室”。课题目录、论文式说明和独立 Godot 实验统一在游戏内，未来算法遵循先研究、独立验证、再接入游戏的流程。

## 使用

重新运行 `project.godot`，首页选择“实验室”。左侧选择课题，右侧可读研究全文、查看登记来源，或运行已注册实验。Esc 从实验返回论文，再按 Esc 返回首页。普通返回按钮沿用主场景 lifecycle。

首批五项为船体接触水沫、近/远海水面、岸线推进浪、天气云影、阴影边索引。船体课题提供独立 Demo，其余四项准确标为历史集成事后整理，独立实验尚未迁入，运行按钮禁用。没有将旧学习台改名后宣称完成新的独立验证。

船体 Demo 提供六船型、巡航/低速/转向/停止/重入水五工况、侧面/船首/高位相机、右键环绕、滚轮缩放、暂停、同条件重置、接触水沫开关和截图/参数保存。开关只改变局部接触可见性，尾迹与原生姿态仍推进。重入水有显式 2m 抬升压力叠加，不能当自然航行；均匀载体与正式游戏投影网格不同。

另有 1200m/384m 载体同初态对照。它是隔离研究变量，没有接回正式海面；384m 覆盖仅 ±192m。所有船员继续使用生产 3D 模型。

## 研究与交接

- [工作流](README.md) 与 [课题模板](TOPIC_TEMPLATE.md)：七段报告、单位、原件来源、可证伪假设、基线、接受标准、失败记录、复现与回退。
- [项目约定](../../AGENTS.md)：后续 Agent 修改新算法前阅读研究流程，维护同一课题，避免重复示例和无证据集成。
- [目录数据](../../assets/research/catalog.json)：唯一 ID、状态、论文、本地 Demo allowlist、源码与证据。
- 论文保存在 `assets/research/papers/`，JSON 与 Markdown 随游戏资源包提供。完整仓库日志不打包，论文内保留其路径与范围。来源只读，不执行报告中的命令或任意代码。

截图参数包含接受时间/tick、原生状态、实际相机矩阵/投影、轨道/缩放、分辨率/画质、具体 seed、64 位 RNG 十进制文本及图像散列。任意历史相机操作需保存并按输入序列重放，当前回执不是完整粒子池存档。

## 本轮实测

[四组实验室回归](evidence/laboratory-2026-10-14/regressions.json) 全部通过，共 208 个断言：目录 70、Demo 89、真实首页/主场景生命周期 28、UI 21。覆盖实际存档/设置字节不变，generation/nonce 取消，重复进入/返回，暂停，相同输入对照，重置与释放。

[GPU 捕获](evidence/laboratory-2026-10-14/GPU_VERIFY.json) 失败 0：43 张整窗口原帧、五组各 161 个接受步、六船型、三观察角、相同暂停时刻水沫开关和载体配对；另保存一张原生实验截图及参数。[最终文档 UI](evidence/laboratory-2026-10-14/UI_VERIFY.json) 另有 7 张原帧，绑定最终页面源码。实际后端为 Godot 4.7.2 / Intel Arc 130T / Vulkan Forward+。这证明捕获与行为合同，不是全游戏 FPS 或整体美术验收。

[包内验证](evidence/laboratory-2026-10-14/PACK_VERIFY.json) 在空工作目录只使用新导出的 PCK：16 项全部通过。五份论文、目录、普通首页路由、独立 Demo 资源和返回均可用。最终 export/pack 原始日志无 SCRIPT ERROR/ERROR；先前冻结到中间版本的预检包被拒绝，记录保存在 [PREFLIGHT_PACK_REJECTED](evidence/laboratory-2026-10-14/PREFLIGHT_PACK_REJECTED.json)，没有按退出码 0 错报成功。没有宣称 Windows EXE 或发布包 GPU 验收。

[载体研究](evidence/laboratory-2026-10-14/carrier-study.json) 每种载体 1,318,912 个误差样本：1200m/512 最大 9.201mm、p95 6.431mm；384m/512 为 0.949/0.660mm；256m/512 为 0.410/0.292mm。原载体连续保守几何界 20.246mm 小于接触偏移 45mm。因此仅靠几何插值不能解释接触水沫弱或被吞掉；该否证保留，法线、深度、遮挡和光学仍待分别研究。

[独立审查](evidence/laboratory-2026-10-14/independent-review.md) 的可重放镜头/随机元数据缺口已修复。最终来源、图像与包 SHA256 见 [DELIVERY_VERIFY](evidence/laboratory-2026-10-14/DELIVERY_VERIFY.json)。源尾迹五文件与原表面散列保持原值；这轮只接入实验室，没有替换正式海面或操船。

## 失败与范围

实际低位原帧仍显示平面/三角块，水沫辨识度较弱。均匀载体精度变好没有直接证明视觉根因解决；课题与界面明确“近拍效果待改进”。没有隐藏船员/船壳或加白来宣称通过。

全项目 [229 脚本审计](evidence/laboratory-2026-10-14/full-regressions.json) 为 221 通过、8 未通过，未作为本功能全部通过的证据：

- `test_fidelity_vegetation_population`：Cat 岛 90 株，52×1.75 的接受标准为 91；植被、地理与测试文件相对 HEAD 未变化，单独复跑仍失败。
- `test_reference_peak_orientation`：Cat 岛码头 2.1m 着陆高度断言失败。
- `test_tack_route_replan`：测试脚本 `Layout` 未声明，解析失败。
- `test_legacy_ui`：保存失败后的重复/重入保护及恢复重试两项失败。
- `test_legacy_geography`、`test_legacy_scene`、`test_legacy_startup`、`test_visual_qa_clock`：达到严格 runner 的 60 秒上限；这是未通过，不推断功能失败或擅自延长来掩盖。

除了已经查明的植被差一棵与 unchanged-HEAD 证据，其余异常本轮只保留日志，不声称已闭合根因或修好。未修改这些算法或放宽接受标准。它们应各自按研究流程建立/更新失败夹具，再修复。

## 复验

```powershell
rtk proxy node tools/verify-godot.mjs --filter laboratory --output Temp/research/laboratory-tests.json
rtk proxy $env:GODOT_EXE --path . --script res://tools/verify-laboratory-gpu.gd -- --output=res://Temp/research/laboratory-gpu-new-run
rtk proxy $env:GODOT_EXE --headless --path . --script res://tools/study-laboratory-carrier.gd -- --output=res://Temp/research/carrier-new-run.json
rtk proxy node tools/verify-laboratory-delivery.mjs
```

GPU 和载体复跑使用新目录，保存原始失败与既有证据；交付验证工具检查本轮固定目录，不是任意新运行的自动接受器。本轮没有 stage、commit、push 或发布。
