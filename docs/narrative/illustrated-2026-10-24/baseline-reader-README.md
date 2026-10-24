# 海上明旗：郑芝龙

[打开公开阅读页](http://8.138.113.205:18794/docs/narrative/zheng-zhilong/?edition=11#top)。2026年10月24日全卷精修，六部二十二章，从约1623年的平户谋生写到1646年父子分途。

本版：`historical-reboot-polish-2026-10-24`。以本轮新查史料独立重构的新作为基线，逐章精修人物行动、关系、节奏与因果；未回用重构以前的小说情节。正文34827字符（含标点），22章、343个段项，段项包含视点分隔线。篇幅数字不作为文学质量证明。

- [小说正文](novel.md)：连续阅读，不夹制作分析。
- [完整史注剧本](screenplay.md)：正文、对白、逐章依据与重建边界。
- [游戏场景稿](game-scenes.md)：目标、行动、结果及后续影响，尚未实现引擎任务、分支或过场。
- [剧本数据](zheng-zhilong-story.json)：与唯一源文件[../zheng-zhilong-story.json](../zheng-zhilong-story.json)逐字节相同。

新作中的阿旺是本轮创作的虚构水手，其去留表现普通船员的利益，不冒称可考人物。当前为文字版；旧图片和旧源归档保留。43个zheng旧书签及20个yiguan旧书签转向相近历史阶段，并显示重编说明，不表示旧故事继续有效。URL中的edition=11保留作原入口参数，页面内容以当前源与构建为准，不是旧版选择器。

## 来源与审读

[本轮交付记录](../full-polish-2026-10-24/DELIVERY.md)、[本轮补充史核](../full-polish-2026-10-24/HISTORY-CHECK.md)、[合卷修订](../full-polish-2026-10-24/ROOT-EDIT.md)、[因果索引](../full-polish-2026-10-24/CAUSE-CHAIN.md)。新作研究底稿：[早期资料](../reboot-2026-10-23/SOURCES-EARLY.md)、[战争资料](../reboot-2026-10-23/SOURCES-WAR.md)、[晚期资料](../reboot-2026-10-23/SOURCES-LATE.md)、[补充核验](../reboot-2026-10-23/SOURCES-SUPPLEMENT.md)。

逐章史注区分事件骨架、争议及文学重建。论文转引不等于本轮已核原档影像；对白、心理、私人现场和微观连接是创作。主编通读22章，独立审稿人先完整连读，再定点复读修改，见[最终审读](../full-polish-2026-10-24/FINAL-REVIEW.md)。未做真实读者试读或商业效果实验。

## 更新与验证

编辑唯一源JSON后依次运行（仓库根目录）：

```powershell
rtk proxy node tools/build-zheng-story.mjs
rtk proxy node docs/narrative/full-polish-2026-10-24/export.mjs
rtk proxy node tools/render-zheng-screenplay.mjs
rtk proxy node tools/build-production-resource-library.mjs
rtk proxy node tools/verify-zheng-story.mjs
rtk proxy node docs/narrative/zheng-zhilong/verify-reader.mjs
rtk proxy node tools/verify-production-resource-library.mjs
rtk proxy node --test tools/zheng-story-contract.test.mjs tools/zheng-reboot-aliases.test.mjs tools/verify-zheng-literary.test.mjs
rtk proxy node docs/narrative/full-polish-2026-10-24/verify-http.mjs
```

分稿编辑时，先运行本轮candidate.mjs，再完整审读实际候选；adopt.mjs仅在当前源等于基线或同一候选、审读报告识别该哈希时才可采用。不能用这个身份检查替代审读结论。旧轮assemble、merge-revisions、export及verify-http不是本版更新入口，不应重跑以覆盖现稿或旧轮证据。

最终检查结果以本轮DELIVERY及其链接证据为准。公网验证先要求阅读目录镜像、正文导出与正式源一致，再比较八个公网文件。浏览工具的几何数据、刷新持久化和hash事件路径不足以验证真实浏览器行为，未宣称视觉、移动布局或阅读进度持久化验收。

已采用并公开发布的正式源SHA256：`ff49298756869eb372fac8503a9a246eff213d7db592fc06bd2361b18d4ce53a`。证据及限制见本轮交付记录。
