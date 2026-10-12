# 剧情与玩法当前验收进度

本阶段延续开局两趟护粮及第二次返航后的资金决策。产品源码已稳定；当前执行真实第二趟航程，之后验收正常界面与保存/继续游戏。

保留上一阶段原始时间、进程与字节的证据：260 个产品/测试/正式数据文件、114 脚本完整回归（74624，114/114，退出 0）、第一趟实际航程（59515，40 粮、581.6 安全回金门、全舰队停稳、915 两、旧债 400，51 项检查零失败）。执行第一趟的代码及所有产品文件完全不变。继承记录由 `artifact-inheritance.json` 明确绑定原路径与 SHA；并未重新生成历史结果。

- Product freeze SHA：`ff1bb6be3ce3cdd09156c9007f68679bbc7bb730a697b5cde8bba76b31f48312`，保留原 2026-10-12 01:56:38 UTC。
- 114-suite SHA：`a1ef439174636cdf60037beb4c434dd90d9337c99a615e1134aef8d4870a7d06`。
- First voyage SHA：`92594ef187ed23be996473a2351b98198a237a738eeca8f30e2667105eaa80ff`。
- Fresh QA freeze SHA：`4eda78cae9fc400f600821c491456c0fbdd882b7daebbd28933595ec0f77a315`，实际新时间 2026-10-12 02:38:18 UTC。
- Inheritance manifest SHA：`17b290adc46a84735cf10cd548f3bd332a7ea0ff2b11f3f7af81f804ffefcf4a`。

QA 仍为 14 个文件；仅 continued、base return、aftermath 三个入口改用已验证的精确 JSON 读取并检查错误。所有材料、钱款、货物、历史回执、sourceHash、港口与失败航程守卫不变。只允许第一趟未执行的 continued 引用按既有 upstreamQaContext 规则记录新 hash；已执行依赖不变。独立审查无 P1/P2，实际 QA 类回归 28/0；读第一趟原始记录的独立数字 oracle 759 项一致。原 28/1 入口失败记录保留，属于诊断历史。

第二趟正在 exec session `61297` 执行：已实际恢复 581.6 的正常第一存档、装载 20 粮并正常离港。`journey-second.json` 仅在进程完成后写出；不要因暂时没有文件而重启航程。等待真实完整交付、领取报酬、全舰队回厦门停稳及正常存档结果。

之后按当前 QA 冻结运行 11 张开局、17 张第一次返航/续约、5/7/5 张分红/偿债/本金分支原生 GPU 截图。Root 必须逐张亲自查看所有 45 张图，再写真实进程/图片记录和最终验收。当前无本阶段 GPU、artifact selection 或最终验收记录。

后续经营提案为互斥的宽限小单与急运大单：让资金占用与时间风险成为可理解的选择。仍未实现，利润须按真实港价计算，急运期限候选 600 秒须正式航程实测；不声称乐趣已经得到玩家验证。海岛/海面/粒子工作按既定分工继续等待逆向交接。

## 当前更新：真实第二航程通过，界面验收未完成

第二趟 exec `61297` 实际退出 0：`CONTINUED_VOYAGE_COMPLETE assertions=85 failures=0 writeOk=true`。20 粮全部交付、损失 0、报酬 250，2501.2 时整支受控船队在厦门停稳并可正常保存。第二记录 SHA `792c623fc57f3665b9ad6f07a6edea3c0e186402806e9489bccb3f276819a33b`；原最终 checkpoint 精确等于最终 campaign，第一 checkpoint 原串不变。进程见证已单独保留。

本阶段开局 GPU `26255` 实际退出 1，11 张截图、99 检查、2 失败。离港点击未产生业务指令，所谓海上图仍在厦门，因此不能接受为成功开局截图。失败文件保留，Root 已逐张查看这 11 张图；未写通过的视觉验收。只读诊断见 `build/second-aftermath-work/opening-departure-capture-diagnosis.md`。

首次返航 GPU `42377` 进程观测退出 0，但未取得最终控制台标记、完整17图或 capture-result，属于不完整运行，不能接受。原有图与输入文件保留。三个资金分支尚未运行；无45图整体通过或最终 artifact selection/acceptance。

独立第二证据核验确认航程22源与QA14源均匹配；整体260源核对发现 `project.godot` 单行删除 `renderer/rendering_method="forward_plus"` 的漂移，未由本次只读核验恢复。故不以历史114测试或局部航程通过声称当前全仓冻结通过。

用户随后明确要求全量吸收新版 `fidelity-rebuild/island/`。当前转入新的海岛整合阶段；本阶段仅保留已取得的真实证据和未完成事项，不更改历史freeze、失败记录或宣称本阶段完整结束。REA 已收到直接交接消息，参考源码与正式边界另按最新交接核对。
