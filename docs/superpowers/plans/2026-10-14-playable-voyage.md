# Playable Voyage Implementation Plan

> 2026-10-14 用户中途调整优先级：先完成画面／渲染／表现，尤其船尾水流，旅程工作暂停。T2/T3 已有实现保留冻结，不继续旅程扩展或将其宣称完整验收。当前活动课题为 `assets/research/papers/wake-flow.md`，视觉接线/动态验收由 root 负责。此前“原尾迹保持不变”已被这次用户明确的尾迹改进要求替代；原版源数学保留作对照。

> **For agentic workers:** Use superpowers:subagent-driven-development for isolated tasks; root owns integration and real GPU evidence.

**Goal:** 完整落地正式试航验收、视觉缺陷收尾、顺畅操控反馈及现有首航的可玩闭环。
**Architecture:** 保留现有Godot生产所有者。独立领域按文件分工；共用接口/注册只由root整合。新算法复用统一实验室。
**Tech Stack:** Godot4.7.2/GDScript/shader、Node严格回归、Windows原生GPU/Computer Use。
**Spec:** docs/superpowers/specs/2026-10-14-playable-voyage-design.md

## Global Constraints
RTK shell；无提交/推送/重置；操作当前Godot ming-armada而非旧MingArmada；原尾迹/五波/3D船员保留；最新羽化0.6/0.55保留；新run不覆盖历史证据；GPU由root串行执行；有用户存档时使用隔离槽位。

## Review Focus
- 渲染低位/掠射角与视口变化，不能只修静态俯视。
- 鼠标按下海面后在UI松开、暂停/菜单/失焦，不能产生幽灵航向或重复炮击。
- 对风航行、反打、停船，保持可控且与源motion authority一致。
- 首航部分损失/阵亡/重复命令/旧存档，奖励与作业不得重复或凭空完成。
- 连续炮击的事件/对象寿命与帧尾释放，不能以削减人口/特效伪造提速。

## Tasks
- [ ] T1 视觉：owner modules/scene_engine/ocean/projected_ocean.gd及相关shader/terrain；现有ocean/shore实验与对应论文。复现低位、远景色块、异常细线；先RED与候选，再经生产接口修复。交付精确文件/故障/命令/root GPU复拍脚本或参数。
- [ ] T2 操作/反馈：owner sailing/manual/casual runtime、鼠标投影和ship_camera_controller及相关tests；审核真实输入链与headwind/反打/停船/暂停门禁，修已复现问题；独立课题由文件导出，catalog交root。不得改T1 shader或T3剧情。炮火/水沫新发现回报root协调。
- [ ] T3 首航：owner game/domain/mingqi/opening_story.gd及必要mingqi runtime/UI/相关tests；先审计现有flow，修阻碍完整游玩的目标、节奏、分支反馈与保存Continue缺口。记录正确RED/GREEN，提供真实命令路径与无状态注入的验收驱动；研究论文/独立fixture必须落盘。
- [ ] T4 root正式实机与性能：普通sail入口，实际/可标识合成输入连续航行/运镜/开炮，基线与修后帧时序；定位热点并用既有课题验证候选，统一CPU/GPU/资源生命周期。
- [ ] T5 root整合：更新统一catalog/宿主与论文，首航完整通路、旧8失败当前审计、受影响回归、必要整合回归、PCK、独立review、最终原帧/manifest和交付说明。

## Execution ledger
Ruling: 用户已批准并要求全量实施，持续执行，无重复审批。当前现场工程由用户编辑器使用，保留本工作区并以文件边界隔离；禁止git提交/重置。三条独立领域并行，实际GPU/桌面输入串行。
Ruling: CodeGraph返回无索引，按工具要求本session不再调用，使用RTK读取；不擅自建索引。
