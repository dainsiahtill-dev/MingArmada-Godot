# 海上明旗：郑芝龙

[打开公开阅读页](http://8.138.113.205:18794/docs/narrative/zheng-zhilong/)。2026年10月24日全章插图版，六部二十二章，每章两幅ChatGPT生成插图，共44幅；从约1623年的平户谋生写到1646年父子分途。

本版：`historical-reboot-illustrated-2026-10-24`。保持精修版正文34827字符（含标点）、22章343个段项不变，添加44幅独立1536×1024 PNG，按实际场面放在对应段落后。插图为文学重建的视觉解释，不是历史现场或人物真容。没有回用重构以前的小说或旧图。

- [小说正文](novel.md)：连续阅读，不夹制作分析。
- [完整史注剧本](screenplay.md)：正文、对白、逐章依据与重建边界。
- [游戏场景稿](game-scenes.md)：目标、行动、结果及后续影响，尚未实现引擎任务、分支或过场。
- [剧本数据](zheng-zhilong-story.json)：与唯一源文件[../zheng-zhilong-story.json](../zheng-zhilong-story.json)逐字节相同。

新作中的阿旺是虚构水手，不冒称可考人物。新插图保存在[images/illustrated-2026-10-24](images/illustrated-2026-10-24/)，逐图章节、段位、尺寸与SHA见[illustration-manifest.json](illustration-manifest.json)。旧图片和旧源保留。43个zheng旧书签及20个yiguan旧书签仍转向相近历史阶段。带edition=11的旧入口也可继续使用，它不是旧版选择器。

## 来源与审读

[插图版交付记录](../illustrated-2026-10-24/DELIVERY.md)、[插图艺术方向](../illustrated-2026-10-24/ART-DIRECTION.md)、[插图因果索引](../illustrated-2026-10-24/CAUSE-CHAIN.md)。文学精修记录保留：[交付](../full-polish-2026-10-24/DELIVERY.md)、[补充史核](../full-polish-2026-10-24/HISTORY-CHECK.md)、[合卷修订](../full-polish-2026-10-24/ROOT-EDIT.md)。新作研究底稿：[早期](../reboot-2026-10-23/SOURCES-EARLY.md)、[战争](../reboot-2026-10-23/SOURCES-WAR.md)、[晚期](../reboot-2026-10-23/SOURCES-LATE.md)、[补充核验](../reboot-2026-10-23/SOURCES-SUPPLEMENT.md)。

逐章史注区分事件骨架、争议及文学重建。论文转引不等于本轮已核原档影像；对白、心理、私人现场和微观连接是创作。主编通读22章，独立审稿人先完整连读，再定点复读修改，见[最终审读](../full-polish-2026-10-24/FINAL-REVIEW.md)。未做真实读者试读或商业效果实验。

## 更新与验证

编辑唯一源JSON后依次运行（仓库根目录）：

```powershell
rtk proxy node tools/build-zheng-story.mjs
rtk proxy node docs/narrative/illustrated-2026-10-24/export.mjs
rtk proxy node tools/render-zheng-screenplay.mjs
rtk proxy node tools/build-production-resource-library.mjs
rtk proxy node tools/verify-zheng-story.mjs
rtk proxy node docs/narrative/zheng-zhilong/verify-reader.mjs
rtk proxy node tools/verify-production-resource-library.mjs
rtk proxy node --test tools/zheng-illustration-contract.test.mjs tools/zheng-story-contract.test.mjs tools/zheng-reboot-aliases.test.mjs tools/verify-zheng-literary.test.mjs tools/verify-zheng-story-cli.test.mjs
rtk proxy node docs/narrative/illustrated-2026-10-24/verify-http.mjs
```

本轮插图采纳顺序为prepare-candidate.mjs、decode-images.py、adopt.mjs，再执行上列生成与验证。adopt要求44个独立图、当前内容哈希的PNG解码记录，以及17+14+9+4四份逐图视觉检查记录。正文与史注锁定精修基线，只迁移一条“当前无新插图”的版本说明。后续改小说须另建编辑轮次，不能把本轮固定基线保护关掉。旧轮assemble、merge-revisions及full-polish/export不用于本版；旧export会清空插图清单，因此保留版本拒绝保护。

最终64项回归、926项源/插图/导出检查、937项阅读器静态检查通过。44 PNG经完整解码；公网44图和9个页面/数据/导出文件共53项均200且与本地相同。DOM逐章核对44图的段位、路径、alt及尺寸，343段正文一致；63别名、搜索、模式及JS触发放大图通过。浏览工具缺乏真实图片解码和可靠几何信息，并有文档级后代选择器限制；真实排版、打印、原生hash事件及跨刷新持久化未验收。完整证据见本轮DELIVERY。

已采用并公开发布的正式源SHA256：`8eedaf3ba504648f1630e4ffc1188bc388da820b199866d0e7328f68defba749`。
