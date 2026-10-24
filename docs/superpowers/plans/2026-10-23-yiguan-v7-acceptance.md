# 《一官入海》第七稿图文验收计划

> For agentic workers: use parallel specialists for independent illustration generation and literary review; coordinator integrates and verifies actual outputs. Follow verification-before-completion. User has already authorized this remaining-work handoff; no new approval or Git commit is required.

**Goal:** 完成四幅延期插图、实际正文审读、README九项浏览器复验。

**Architecture:** 延续唯一剧情JSON、图片清单、经典JS数据与本地阅读页。保存接手时的第七稿，局部修正已坐实的连续性错误，不用新增篇幅掩盖问题。四张新图另存film-v7，保留旧图及旧来源。

**Tech Stack:** JSON / Node.js / HTML-CSS / built-in ImageGen / CUA browser.

**Spec:** 用户2026-10-23交接；V7-REWRITE-BIBLE.md；reader README九项检查。

## Global Constraints

- 5幕20场、43旧映射；291段及八张过程图锚点保留，另验语义。
- 不用自动规则声称出版质量；不改历史护栏和1626隐瞒／1628揭露的知情链。
- 图像两边均大于800px，记录原生成路径、实际prompt、哈希、尺寸与目视结论。
- 保留现有未提交文件，不提交或推送；本仓库CodeGraph无索引，使用RTK回退。

## Review Focus

1. 段数相同但事件已换位，图片接在错误的动作之后。
2. 仅出现关键词被误判为种收或知情逻辑成立。
3. 银钱、绳索、落帆、船只等有可见物理因果错误。
4. 工具、纸、铜扣、舟船的持有人或来源跳变。
5. 所有规则通过而扩写拖慢高潮，不能由机器计数替代编辑判断。

## Tasks

- [x] 核对实际第七稿与第六稿备份、三条现有检查的真实输出。
- [x] 并行通读二十场，记录具体段落问题；确认硬伤才做最小修正并留前后记录。已补修14段，291段保留。
- [x] 两名图像专家生成四幅延期图，另发现并补绘一幅断手穿帮过程图；协调者逐张目视、采纳后更新主源和manifest。共五幅新图、28项旧情境参考。
- [x] build/render后运行结构、规则、静态阅读与关联目录检查；维持旧图真实性边界。另修复文学段数校验漏检，独立CLI负控9/9。
- [x] 真实浏览器执行九项检查，记录每项通过／未测／失败，不借旧证据通过。六项完整通过、三项部分完成，见本轮QA报告。
- [x] 保存页面截图、输入哈希、审读记录和交付边界；最终报告实际文学判断。

## 未通过工具完成的验收

- 内置浏览器策略拒绝file协议；未绕过。
- 原生打印阻塞页面读取，已取消自建测试标签页；纸面预览与打印后恢复未目视确认。
- 未切换系统深色/减少动效偏好，只有相应静态CSS检查。
- 文学仍需一轮减法编辑，不以机器通过数声明出版或成片质量。

证据：`docs/research/evidence/yiguan-v7-2026-10-23/QA-NINE-CHECKS.md`。
