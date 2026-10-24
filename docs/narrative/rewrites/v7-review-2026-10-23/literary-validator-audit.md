# 文学校验器段数漏检审计与修复

日期：2026-10-23。范围：`tools/verify-zheng-literary.mjs`、独立CLI回归测试与本报告。正文、主JSON、圣经、第六稿存档和UI未由本任务修改。CodeGraph查询返回项目无索引，源码审计改用RTK定点读取。

## 已证实的缺陷

圣经第35—42行是每行四组“场次／段落数”的横排表，最后一行前四个单元格为空。旧代码只筛首格为`aN_sN`的行，仅取每行前两格，先漏掉其余三组与末行；得到的键还是`a1_s1`，正文查询却用`yiguan_a1_s1`。`if (specCounts[tag])`因此二十场全部跳过，原来的2965项检查中，**按圣经要求核段数为0项**。

负控先于生产修复运行：复制真实CLI、真实正文、圣经及第六稿存档到独立临时目录；将两段中段合为一段，正文每个字符和无换行词根命中均保留，仅减少一段。首列、第二列、第三列、第四列和末行空格前缀处分别注入：`a1_s1`、`a2_s2`、`a3_s3`、`a5_s1`、`a4_s4`。五个错误全部仍退出0并报2965/2965；删除一条规格、追加重复规格、同步减少正文和圣经段数也全部被放过。测试结果为**1通过／8失败**，失败原因均为CLI错误地退出0。

## 最小修复

- 遍历所有Markdown表格行及每对单元格；保留空单元格，覆盖末行；场次统一为`yiguan_aN_sN`。
- 拒绝重复规格、非正整数规格；确认规格恰有20场。
- 每个当前场次无条件断言规格存在与段数一致；不再以真值分支静默跳过。
- 读取现有`baseline-v6-2026-10-22/story.json`独立比对：版本正确、20个唯一场次、5×4规范场次均存在、圣经各场段数与归档第六稿一致。正文与圣经同步误改不能互相证明正确。
- 第六稿存档操作前后SHA256均为`e68057bf6ff98f0cbbd0d3bed3029e059afbd85b2df46aa11a004b74dc0e88dc`。本次把归档文件作为独立输入；未把其散列硬编码为生产规则。

当前有效正文新增**123条断言**，2965变为3088：

| 断言 | 新增数量 |
|---|---:|
| 20条规格的唯一性、正整数 | 40 |
| 基线版本、基线20场唯一性、规格20场 | 3 |
| 20场基线存在、圣经与基线段数一致 | 40 |
| 当前20场规格存在、段数一致 | 40 |
| 合计 | 123 |

原文学词根、对白、比喻等规则与阈值均未修改。

## 验证结果

- `rtk proxy node --test tools/verify-zheng-literary.test.mjs`：**9/9通过**。包括当前数据正控、五个表格位置少一段负控、缺规格、重复规格、正文与圣经同步误改的基线保护。
- `rtk proxy node tools/verify-zheng-literary.mjs`：**3088/3088通过，0警告，退出0**。
- 两个修改的JS文件分别`node --check`：退出0。
- `rtk proxy node --test`自动发现全仓测试：**40项，15通过，25失败**。本次文学9项全部通过；以下25项来自`assets/provenance`归档副本，运行时缺依赖或归档内脚本，未在本任务中补装或修改。

全仓失败项目：

1. `assets/provenance/tools/sailor-models/export-validation.test.mjs`：缺`three`。
2. `assets/provenance/tools/sailor-models/sailor-models.test.mjs`：缺`three`。
3. `assets/provenance/tools/ship-models/ship-models.test.mjs`：缺`three`。
4. `ensure-built-packages.test.mjs` — real TypeScript builds use content and artifact identities, preserve successful output on failure, and propagate dependencies。
5. `ensure-built-packages.test.mjs` — Windows directory read handle blocks directory rename but generated-file promotion still succeeds。
6. `ensure-built-packages.test.mjs` — Windows blocked generated-file replacement rolls back earlier writes and creations without a fresh record。
7. `setup-singleplayer.test.cjs` — CLI omitted WorkspaceRoot reaches preservation preflight in the script repository。
8. 同文件 — CLI omitted WorkspaceRoot uses the script repository when launched from another directory。
9. 同文件 — CLI explicit WorkspaceRoot preserves the chosen workspace rather than the script repository。
10. 同文件 — CLI explicit drive root is rejected before workspace writes。
11. 同文件 — CLI explicit nonexistent workspace is rejected without creating it。
12. 同文件 — CLI refuses a junction workspace while preserving its source。
13. 同文件 — CLI reuses locked source with untracked generated output node_modules/.vite/vitest/da39a3ee5e6b4b0d3255bfef95601890afd80709/results.json。
14. 同文件 — CLI reuses locked source with untracked generated output dist/game.js。
15. 同文件 — CLI reuses locked source with untracked generated output dist-ssr/server.js。
16. 同文件 — CLI reuses locked source with untracked generated output coverage/coverage-final.json。
17. 同文件 — CLI reuses locked source with untracked generated output node_modules/cache with spaces/asset.js。
18. 同文件 — CLI refuses tracked source edit even alongside untracked generated cache。
19. 同文件 — CLI refuses staged source edit even alongside untracked generated cache。
20. 同文件 — CLI refuses untracked source file even alongside untracked generated cache。
21. 同文件 — CLI refuses nested source node_modules file even alongside untracked generated cache。
22. 同文件 — CLI refuses similar output prefix source even alongside untracked generated cache。
23. 同文件 — CLI refuses tracked output edit even alongside untracked generated cache。
24. 同文件 — CLI still checks actual locked file hashes in a marked package with generated cache。
25. 同文件 — CLI still rejects untracked source in a marked package with generated cache。

第4—6项路径为`assets/provenance/tools/workspace/ensure-built-packages.test.mjs`，失败证据是缺`assets/provenance/node_modules/typescript`。第7—25项路径为`assets/provenance/tools/workspace/setup-singleplayer.test.cjs`，失败输出中报告缺`assets/provenance/scripts/setup-singleplayer.ps1`。

## 真实能力边界

1. **段数现可核实，语义锚点仍需人工。** `verify-zheng-story.mjs:260`另有`afterParagraph`正整数且不越界校验；它不能判断某张图放在“正确情节之后”。段数不变也不能自动保证原图情节匹配，本次没有给文学脚本增加图意评分。
2. **种收仅是指定场次里的词根存在性。** 例如“名单”“那一袋”“那截木”等宽匹配不能证明是同一器物、同一主人或真正完成因果回收，也不证明“每场只种一件”。本次保留其机器线索性质。
3. **知情链仅靠同场词串共现。** “看见旗”和“承认”不必出自同一句、同一说话人；否认、转述及指代也可能误判。另一种措辞的提前知情可能漏掉。不能把此项通过当作人物知识状态审定。
4. **感官项是全场不同词根数。** 没有核验六个具体感官事件、不同段落分布，或与动作绑定；物件词、否定句也可命中。
5. **文学语义未自动覆盖。** 有无物理动作开场、潜台词、岔话、命名人物承担代价、落像、第三人称限知和视角跳跃，均不能由目前的黑名单和存在性检查证明。
6. **现有阈值与圣经存在已知差距，未在本次改写。** 圣经第90行要求对白3—5行、每行约24字；脚本实际允许3—6行且每行≤34字。圣经第80行要求每场明喻≤2、每段≤1；脚本实际为粗略全场匹配≤6，且未核每段与比喻来源。此次没有放宽任何规则，也没有把这些旧差距伪称为已被机器严格覆盖。
7. **完整场次结构由机器合同另管。** 本次文学脚本验证20条圣经与第六稿基线规格，并校验当前出现的每场段数；正文是否恰好五幕二十场、ID唯一等仍由`verify-zheng-story.mjs`负责。文学3088项通过不代表全卷文学验收通过。

