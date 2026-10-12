# 当前剧情与玩法验收阶段

源码冻结时间：2026-10-12 01:56:38 UTC。此文件为进度记录，不是最终验收报告。

当前阶段继续验证开局两趟真实护粮航程，以及第二趟返航后的分红、独立偿债、保留本金三个选择。海岛、海面、粒子与性能工作保持此前的优先级安排。

冻结范围为 260 个产品、测试及正式数据文件，114 个测试脚本，14 个完全不变的 QA 源文件。相比原剧情阶段，仅更新 Encounter、SaveCodec 和一处旧兼容性测试的独立数值 oracle；新增舰队停泊回归与数字往返回归。

- Source freeze SHA256：`ff1bb6be3ce3cdd09156c9007f68679bbc7bb730a697b5cde8bba76b31f48312`。
- QA freeze SHA256：`b4f00fdc8c77e7cf8efc91fbd8c9d527427a83ffb9a90651fdadabdbbebcb409`。
- Codec SHA256：`842aba8c5af25a182bf4da823a6b6784f3d6486e20b0fa793785784106114f52`。
- Root 亲自运行数字回归：138 项、0 失败；兼容性测试 PASS (0)。独立审查无 P1/P2；真实旧存档的 855 个数字和全部非数字材料精确往返。
- 完整 114 脚本回归 exec session `74624` 已退出 0：`GODOT_VERIFICATION selected=114 passed=114 failures=0`。已独占保存 `all-tests-verified.json`，SHA256 `a1ef439174636cdf60037beb4c434dd90d9337c99a615e1134aef8d4870a7d06`，并记录真实进程结果。260 个源码与 14 个 QA 哈希复核一致。
- 新第一趟航程 exec session `59515` 已退出 0：`OPENING_STORY_JOURNEY_COMPLETE assertions=51 failures=0 writeOk=true`。实际 40 粮、581.6 安全回金门并全舰队停稳，915 两、旧债 400，原始正常存档与最终 campaign 精确一致。`journey-first.json` SHA256 `92594ef187ed23be996473a2351b98198a237a738eeca8f30e2667105eaa80ff`；对应真实进程记录已保存。
- 第二趟接续在运行前的记录读取阶段失败 28/1、退出 1（exec chunk `dd9a8f`）：脚本用普通 JSON reader 解码第一趟元数据，再与精确 Codec 状态比较，引入同一数字偏差。失败报告 SHA256 `f04cd4391e986110cb5080666a2f02540cc880bbad689a1f213f6dce676b3247` 与进程记录保留，未运行航程步骤。正在审查 QA intake 的精确读取修正；产品 260 文件与完整套件结果不变，第一趟执行代码不变，仅其未执行的 continued QA 引用将变化。
- 第二趟成功证据、45 张原生 GPU 截图、artifact selection 与最终验收记录仍未产生。后续使用独立 QA 阶段及明确继承来源，不覆盖本阶段任何原始冻结或失败记录。

此前 `fleet-stop-and-aftermath/journey-second.json` 是被保留的真实失败记录：20 粮、0 损失、250 两，舰队在 2501.2 返回厦门并停稳，但精确存档校验 84 项中有 1 项失败，进程退出 1。失败源于 Godot 读错计时余数及旗舰位置数字的浮点末位。本次只按原始完整精度文本的唯一邻值匹配恢复可证明的数字，不添加数值容差、不改写该旧报告。未匹配的旧解析边界仍走原路径，不能声称通用十进制解析已全部恢复。

后续顺序：完整回归 → 新第一趟 → 新第二趟 → 正常 UI 三分支 Save/Continue → Root 逐图验收 → 严格汇总。大型游戏目标继续有效；“第一笔自己的生意”仍为下一阶段设计提案，尚未实现或验证乐趣。
