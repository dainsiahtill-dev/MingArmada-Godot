# 插图候选与发布链独立审查

2026-10-24。只读审查 `prepare-candidate.mjs`、`adopt.mjs`、`export.mjs`、`verify-http.mjs`、`decode-images.py`、`record-generation.mjs`，本报告为本阶段唯一写入。未执行prepare/adopt/export/decode/HTTP发布链，未改正式源或manifest，未为缺失图片制造成功结果。

## 初查发现与复核关闭

1. **解码证据未绑定当前图片内容。** `adopt.mjs:13`仅要求 `decode.passed` 与 `decode.sourceSha256`相符。若保持JSON的图片路径、尺寸、图注不变，更换PNG并更新manifest的图片SHA，候选源SHA仍相同；旧Pillow报告也会被接受。新的PNG仍会经过Node结构校验，但无法据此声明它已有当前Pillow完整解码证据。采纳前应要求44个唯一decode项与当前manifest的 `id/image/sha256/width/height`逐项相等、全部passed且无遗漏/额外项。
2. **目检门槛只有文件存在。** `adopt.mjs:14`检查QA-EARLY/QA-LATE文件存在；部分或空白审阅文件同样满足。审查时QA-EARLY已存在，但只列2张，首图审阅另在first-generation，后续尚在生成。采纳前需要完整44个ID及实际图SHA绑定的审阅记录；Markdown可保留人读说明，建议另有结构化完成门槛。至少明确逐项全表核对，不能把存在文件当作完成目检。

两项先报主线程，由主线程修正。本代理再次读取代码，确认 `adopt.mjs:14`检查44个唯一decode ID且逐项匹配image/SHA/width/height与passed；15-17行要求三份QA Markdown及合计44个唯一QA JSON ID，各项绑定当前manifest SHA、accepted及非空observations。两项代码缺口已关闭。尚未运行实际44图采纳门槛，不能等同整卷验收通过。

复核时 `adopt.mjs`SHA：`aac3d8cab9c50154ea693eb88727ccd7608f0cf31b570e8df4af6565219fab41`，`node --check`退出0。生成/编辑并行进行，初查代码摘录与随后摘要采样未作原子快照；此SHA只标识修正后复核版本。

## 已确认的正确边界

- `prepare-candidate:7-8`固定本轮基线原始SHA，读取本轮baseline，不重新组装旧故事；12-27行仅添加/更新艺术字段、版本和report路径。22章全文及原文学元数据保持原对象内容。
- prepare要求44个唯一job ID；遍历当前22章，每章恰两项slot=1/2且段位递增。所有44项被这22章消费，因此未知scene不能靠额外job混入。每项须合法1基段位、非空caption/alt/prompt，读取实际PNG和receipt后再核对id、provider、SHA及全卷内容哈希唯一。
- prepare在完整循环结束后才写候选、候选manifest、coverage；缺receipt或缺文件会在写候选之前抛错。它不写正式源。
- `adopt:8-12`仅允许正式源仍为固定基线或同一候选，并调用独立 `validateIllustrations`。新validator输入名称、Buffer读取函数和返回字段与root调用完全兼容。该验证器比较全部非艺术内容与固定精修基线，保留22个章ID和63个别名映射，并检查44图/图源/manifest/实际尺寸。
- 根manifest的sourceSHA来自最终候选字节；manifest自身不写入story，不构成摘要循环。每项字段完整匹配本轮约定：id、sceneId、image、afterParagraph、caption、alt、width、height、sha256、generator。
- `export:8-11`约束新version和本轮editorial目录；CAUSE-CHAIN写本轮，三个下载稿写reader，未发现指向full-polish证据文件的写入。新renderer输出小说/完整剧本段后图，正确使用reader内部 `images/...`路径。
- `decode-images.py`逐项Pillow verify，再重新打开load；核对PNG、尺寸及SHA。报告写本轮目录。它本身不保证44个条目唯一，最终validator已检查唯一性；需要修复的是adopt对报告内容的绑定。
- `verify-http:8-14`先做本地全链校验，再比对9个页面/数据/导出文件及44张图的公网响应字节；报告明确HTTP验证不替代浏览器或视觉历史判断。所有记录写本轮目录。
- `record-generation:7-14`限制ID、生成图片目录和PNG扩展名；已有同名选图内容不同时拒绝替换，避免无声覆盖。每图receipt有原始生成路径、选图路径、文件SHA、尺寸、provider。

## 分镜与当前正式源全量核对

实测本轮 `baseline.json`与正式源字节一致，SHA均为 `ff49298756869eb372fac8503a9a246eff213d7db592fc06bd2361b18d4ce53a`。两份boards合计44个唯一ID，覆盖当前22章且每章2幅，无未知scene；ID格式与scene/slot一致；caption/alt/prompt均非空；所有位置为整数、1基、未越界，且每章第二图晚于第一图。

|章ID|总段数|两幅插入段后|
|---|---:|---|
|zzl_a1_s1|16|2 / 13|
|zzl_a1_s2|16|6 / 15|
|zzl_a1_s3|15|5 / 11|
|zzl_a1_s4|17|10 / 16|
|zzl_a2_s1|16|3 / 10|
|zzl_a2_s2|19|3 / 17|
|zzl_a2_s3|16|6 / 10|
|zzl_a2_s4|17|4 / 11|
|zzl_a3_s1|13|4 / 10|
|zzl_a3_s2|13|6 / 12|
|zzl_a3_s3|13|7 / 11|
|zzl_a3_s4|19|2 / 18|
|zzl_a4_s1|14|2 / 13|
|zzl_a4_s2|14|10 / 14|
|zzl_a4_s3|18|5 / 17|
|zzl_a4_s4|20|9 / 16|
|zzl_a5_s1|12|2 / 11|
|zzl_a5_s2|13|2 / 10|
|zzl_a5_s3|13|2 / 11|
|zzl_a6_s1|14|6 / 12|
|zzl_a6_s2|19|1 / 16|
|zzl_a6_s3|16|11 / 16|

这是位置/完整性检查，不表示已逐幅证明图中行动与全文相符。

## 首图实际提示词与已有图片

`first-generation.json`确有首图实际prompt，与boards中后来记录的首图prompt不同；应将前者作为首图真实生成记录。该文件的sourcePath/destination/provider与 `receipts/zzl_a1_s1_01.json`完全一致；receipt SHA与选图实际字节匹配。

一次只读资源快照时已有以下7幅：`zzl_a1_s1_01`、`zzl_a1_s1_02`、`zzl_a1_s2_01`、`zzl_a3_s3_02`、`zzl_a4_s1_01`、`zzl_a4_s1_02`、`zzl_a4_s2_01`。逐张Pillow verify/load通过，均1536×1024，receipt尺寸/SHA相符，7个实际内容哈希唯一。生成正在继续，此数量仅为该次检查快照，不能外推44图完成。

## 运行顺序与改进项

本轮export没有生成 `story-data.js`和JSON镜像；完成adopt后仍必须运行既有 `tools/build-zheng-story.mjs`，然后新export与verifyReboot。若漏build，最终verifier会失败，但export命令本身不会提醒。

初查 `record-generation`仅检查PNG签名就复制，损坏PNG可能先占目标再抛错。主线程已修正，复核14-18行确认先完整inspectImage、要求PNG，然后才复制；receipt尺寸取解析结果。该项已关闭。复核版本SHA：`d85c1bc1517cfa1785cda9833f2159daf2c5421855bd531dd6658063bb33919c`，语法检查退出0。

HTTP核验过程中仅检查源JSON未变化，未锁定所有本地reader文件快照。最终核验应在代码/资源冻结后执行；若边验边改app/styles/manifest，报告可能混入不同时间的本地状态。此项不影响当前未发布阶段。

五个MJS执行 `node --check`均退出0；Python脚本AST解析通过。未运行尚不具备44图输入的发布链，也未写decode成功报告。此前插图合同35项与相关回归合计58项通过，详情见INTEGRATION-REVIEW；这些测试不替代本轮发布与真实画面验收。

## 七幅独立目检

以下每幅均用 `view_image`单独打开整图，结合对应正式段落及分镜检查。只记录实际看到的内容，不作服饰、船型、建筑或人像的专家鉴定；没有仅凭文件名评图。

|ID|实际观察|判断与限制|
|---|---|---|
|zzl_a1_s1_01|年轻一官在左船舷蹬腿拉绳，湿货包悬在开阔船岸缝，日本收货人右岸指货，踏板已撤。|主要动作和开放水隙清楚；无现代起重设备/文字水印。绳索受力与港形仅属图像概括。|
|zzl_a1_s1_02|李旦右侧抬掌打断，中央一官望他，外国来客左侧说话；脸与头巾延续首图。|与译话过快被叫停的段落相符。窗外小城楼未经地方建筑史校对，不据此声称1623平户建筑复原。|
|zzl_a1_s2_01|孕中的田川氏把卷被递进一官怀里，一官双手接住；柜上钱袋、腾出的室内空间可见。|动作与第6段一致，人物关系清楚；住宅和衣服属于创作概括。|
|zzl_a3_s3_02|院中赏袍与伞、居中的空椅清楚，郑芝龙看向右侧，右侧官员听随从附耳低语，荷方来客等候。|空位与被打断的授赏场面可读；官员仍坐着但前倾，可理解为起身前一刻，未见必须重做的动作冲突。|
|zzl_a4_s1_01|船主在案前拢起湿布和船底碎屑，水印明显；郑芝龙右侧沉吟，身后候答者与港中桅杆可见。|与许可不能即刻放行的段落相符，青年至壮年脸型延续。服饰纹样与旗幔不作制度史证明。|
|zzl_a4_s1_02|荷舰甲板上左侧来客催书记落笔，右侧船长持信指帆；水手俯身缝补大块帆布。|书写/异议/补帆三要素均可读，无明显18世纪军服或现代设备。个体身份为文学重建。|
|zzl_a4_s2_01|船工把受伤学徒向艇中递下，学徒手中凿子及两名接应者清楚，背景炮击烟和高尾帆船。|救援动作与正文相符，但学徒上臂有一小块裸露红色伤口，超出该prompt的“no exposed wound”要求；已报主线程，若按提示词严格验收应改为布团/包扎遮住。该图不属于血腥画面。|

前六幅未发现需立刻重做的明显场景/现代物件问题；这不是严格历史认证。第七幅的裸露伤口为具体偏差，是否按非血腥且正文有伤的边界保留，须由主线程记录决定；本代理未替其修改接受记录，也未重绘图片。
