# 郑芝龙叙事图卷

当前版本为v7-readthrough-2026-10-23，即第七稿完成整体连读后的锁稿候选。两名独立读者完整审读五幕二十场，分别检查阅读牵引和人物声音；主编辑另核海上空间与因果。仅第二幕第三场两段澄清货物归属，正文26,951→26,986字符，其余十九场保留。291段、95条对白摘录、43旧映射与八图位不变。入口使用?edition=11#top；[整体阅读报告](../rewrites/v7-readthrough-2026-10-23/READTHROUGH-REPORT.md)、[微改独立复核](../rewrites/v7-readthrough-2026-10-23/PATCH-REVIEW.md)、[本轮网页验收](../../research/evidence/yiguan-readthrough-2026-10-23/REVIEW.md)。本轮没有新绘图；锁稿建议不等于出版或游戏成片认证。

本目录是独立的本地阅读网页。第七稿在五幕、二十场结构与史实边界不变的前提下，全篇重写文学正文：以《一官入海》第七稿改写圣经（`../rewrites/V7-REWRITE-BIBLE.md`）为体例，每场按“入场—器物—转折—代价—落像”重新执笔。此前逐场经文学与连续性双路评审及全卷连续性审校，此前的局部精修之后，本轮完成全卷独立连读与声音审读，并独立复核一场微改；审读结论建议暂锁主线，不代表普遍读者评价或出版认证。第六稿确立的贯穿主脑“为了不再成为别人的筹码，最终却替伙伴与妻儿定下价码”保持不变。段落数与第六稿一致，以保持八张过程图的段落锚点，并由修复后的文学校验器对照圣经及第六稿存档核验。配图采用5张第七稿补图轮新绘，其余28项仍为旧稿情境参考；不宣称全部新场逐动作画面已经重绘。实际采用引用以 `illustration-manifest.json` 为准。本目录不修改1650或1661生涯，不提供游戏战斗或任务结算。

本稿登记33项图像引用：5幕章首、20场主图、8幅过程参考。目前33项均展示，0项延期；其中5张新图由前轮补图审读采用，28项旧图继续标明情境参考。本轮保留其来源记录，核对八个过程段位并实际打开三场主图，不声明全部插图按新修正文重新完成美术验收。原来延期的三场主图和北上舟影已由新图承接；旧原图冻结保留作来源与完整性核验，不等于当前叙事采用。新图采用、旧图参考与页面浏览器验收分别记录，不能互相代替。

唯一内容源是上一级 `zheng-zhilong-story.json`。主稿为已确定行动的单线故事，`choices`可为空，不强制每场两个备选；字段完整不代表文学质量已验收。新稿以 `narrativeContract:{acts:5,scenesPerAct:4,canonicalPrefix:'yiguan'}` 明确结构，canonical场次为 `yiguan_a1_s1` 至 `yiguan_a5_s4`。根 `legacySceneAliases` 将旧43场的分享链接和续读书签一跳映射到新稿承接位置，旧场不会重复显示在新目录中。映射只表示结构承接，不能证明旧稿人物或道具仍在新主线出现。

电影图卷版采用固定浅灰纸页、深墨片头与章首。正文20px、约34汉字行宽、1.9倍行高；不随系统深色偏好把正文变成深绿。图片置于2.39:1画框，使用 `object-fit: contain` 保留全部构图，不裁人物头部。画面间留白承担转场，不叠加粒子、棕黄纸纹、暗角或图片滤镜。

阅读排版第六版将书名、非剧透引子和阅读入口放在封面之前的主要视线位置，桌面封面并排、窄屏文字优先。卷首五章索引采用有序书目与细分隔，显示幕名、年份、`readerHook`；章首序号与引子、每场 `readerTeaser`、幕末 `nextHook` 与明确下一幕链接承担阅读承接。三类公开引子须由作者填写，不能拿揭示结果的梗概替代。私用编辑字段 `act.suspense` 不进入阅读器标准化模型，也不作为读者文案展示。

人物弧光、伏笔回收和结局集中在卷后原生折叠区“人物与伏笔解析（含结局）”，初始关闭，目录入口也明确标注。全卷、幕、场梗概均提示包含情节或结果且默认收起；切换“剧本阅读”只展开对白，不主动打开梗概与结局解析。打印仍由既有流程暂时展开所有details，结束后恢复各区原状态。正文、对白与公开场次引子可搜索，卷后解析不混入场次搜索。

## 打开

直接双击 `index.html`。`story-data.js` 必须与页面同目录，并通过经典脚本设置 `window.ZHENG_STORY`；不使用 `fetch`，可从 `file://` 打开。构建工具将源 `../zheng-zhilong-story.json` 复制到本目录，整个目录可携带下载数据一起复制。

也可从仓库根使用本地HTTP服务：

```powershell
rtk proxy python -m http.server 8765 --bind 127.0.0.1
```

打开 `http://127.0.0.1:8765/docs/narrative/zheng-zhilong/`。无需安装依赖、构建或联网加载字体。

## 文件合同

- `index.html`：页面骨架、目录对话框、大图对话框、阅读工具。
- `styles.css`：中文宋体系统字体栈、浅灰纸页与深墨章首、响应式、打印与减少动效支持。
- `app.js`：容错数据标准化、渲染、搜索、目录、逐场导航、模式、续读与图片放大。
- `story-data.js`：从 `../zheng-zhilong-story.json` 生成的 `window.ZHENG_STORY` 数据，由内容构建方管理。
- 五幕开篇与场次配图由JSON的 `cover/image` 字段驱动；可选过程图 `illustrations[]` 以 `afterParagraph` 指定正文位置。`illustrationStatus`按根、幕、场、过程图继承；`needs-redraw`时不创建延期图片或占位，主图与过程图可以分别采用。
- 旧稿57图的来源、原始prompt、哈希与当时审读说明冻结在上一级 `zheng-illustration-manifest.v4-2026-10-22.json`。当前清单对28项旧图保留 `originalId / originalVersion / originalReview` 并标明 `reused:true`；5张新采用图分别记录新来源、prompt、哈希与本轮目视依据。原审读不能冒充新版正文的视觉验收。旧1629湾口抗掠仍只是虚构战事，不因保留原图成为新稿史实。
- `images/act-1.png` 至 `images/act-6.png` 是旧版基线，未通过电影方向验收，不作为最终图源。不再在每幅图下重复“生成插画”，图下注场名、时间与地点；卷首和卷末说明图像来源性质，正文不显示素材制作进度。
- 图片只接受 `images/` 下的相对路径；缺图显示明确提示，不生成替代占位插画。

根字段：`title, subtitle, logline, characters, acts, plotThreads, ending`。`characters`可为数组或以人物姓名为键的对象；兼容旧 `foreshadowing / foreshadows / motifs`。人物、伏笔与结局均进入卷后。

每幕字段：`id, title, years, synopsis, prologue?, cover, scenes`。可选 `prologue` 是作者原创纪事小序，排在幕名后，标“小序”，不包装成史书引文。每场字段：`id, title, year, location, summary, paragraphs[], dialogue[{speaker,text}], choices[{id,label,consequence}], history{level,note,sources[{title,url}]}, image`。`imagePrompt`保留在源数据中，网页不把生成提示词当正文展示。

正文、对白、公开引子、分支与史注参与场次搜索；人物名可在正文中检索，卷后人物弧光与结局解析不混入搜索。输入多个空格分隔的词时，每个词都必须出现在同一场。显示匹配片段和跳转链接。数据使用DOM文字节点插入，不执行内容中的HTML；史料来源接受HTTP/HTTPS与受限项目研究Markdown路径。源数据中的 `../research/*.md` 自动转为阅读器相对的 `../../research/*.md`；路径中不接受任意协议、编码穿越或父目录穿越。

## 阅读交互

- “目录”打开五幕/二十场锚点目录；卷首另有五章有序书目；“搜索”或 `/` 聚焦搜索框。
- 左右方向键、底部上一场/下一场逐场跳转。输入框与打开的对话框内不抢方向键。
- 阅读方式与打印入口位于目录中的“阅读设置”。“故事阅读”收起对白；“剧本阅读”展开对白。全卷、本幕、本场梗概与分支始终按需折叠，避免长读时重复梗概。
- 阅读进度按进入的场次计算，不表示游戏通关。当前位置与阅读方式使用 `localStorage` 保存；存储禁用或损坏时仍可正常阅读。
- 卷首“继续阅读”跳到上次记录的场景，不强制自动跳转。
- 插画点击放大，`Esc` 关闭。目录和大图使用原生模态对话框，支持焦点约束与键盘操作。
- 打印前展开对白、分支与史注；打印结束恢复之前的展开状态。打印会隐藏阅读工具。

## 验收

当前正文构建与检查：

```powershell
rtk proxy node tools/build-zheng-story.mjs
rtk proxy node tools/render-zheng-screenplay.mjs
rtk proxy node tools/verify-zheng-story.mjs
rtk proxy node docs/narrative/zheng-zhilong/verify-reader.mjs
```

build同时写入`story-data.js`和可下载JSON镜像；render完整生成文学剧本Markdown及所有章场和过程配图引用。正文、插图、页面静态检查与真实浏览器结果分开记录；`--text-only`不读取或背书图像。编辑因果五字段是审稿辅助，不是文学自动评分。

当前图像清单同步用 `rtk proxy node tools/sync-yiguan-illustration-manifest.mjs`，既能重索引旧图，也会保留已采用的V7新图及其来源记录。旧版 `integrate-zheng-illustration-adoptions.mjs` 是v4采用管线，不得在新稿上运行，以免回写旧版字段与计数。

第七稿装配脚本为 `rtk proxy node docs/narrative/rewrites/assemble-yiguan-v7.mjs`。它会回写主内容源，覆盖尚未同步到装配输入的人工审校；**不得在已审校稿上随意重跑**。确需重新装配，先保留本轮主稿与差异，将审校结果同步到装配输入，再核对装配结果。常规页面更新使用上述build与render。

文学规则校验用 `rtk proxy node tools/verify-zheng-literary.mjs`，段数漏检负控回归用 `rtk proxy node --test tools/verify-zheng-literary.test.mjs`。校验器现能完整解析圣经横排段数表、统一场次ID，并对照第六稿存档保护段数；种收、知情等词根检查仍有语义边界，详见 `../rewrites/v7-review-2026-10-23/literary-validator-audit.md`。文学校验与机器合同分开记录，通过不等于文学验收通过。

脚本按明确合同检查JS语法、本地依赖、新五幕二十场（兼容已发布旧六幕结构）、43条旧锚点映射、逐场正文/对白/分支/史注、图片路径、文件存在与ID唯一性。不允许用新数据任意声明一个较小计数规避缺场。内容或图片缺失会如实失败；静态检查不替代真实浏览器验收。剧本、数据脚本、HTML、reader JS或CSS改变后，旧浏览器证据应标为过期。

补图轮在`v7-reviewed-illustrated-2026-10-23`上执行的[九项记录](../../research/evidence/yiguan-v7-2026-10-23/QA-NINE-CHECKS.md)是旧版证据，当时六项完整通过、三项部分完成。edition 8的[三场减法记录](../../research/evidence/yiguan-subtractive-2026-10-23/REVIEW.md)也只背书当时的输入。edition 9的二十场逐字核对、全部43个旧链接、幕间跳转与窄屏证据见[前轮全卷修订浏览器记录](../../research/evidence/yiguan-full-polish-2026-10-23/REVIEW.md)，不能将旧结果移记为新版全量通过。内置浏览器的file协议、原生打印纸面及打印后恢复、系统深色和减少动效偏好的未测边界仍保留。

浏览器中打开 `index.html?selftest=1` 或对应HTTP地址；控制台 `window.__ZHENG_READER_TESTS__` 给出DOM/目录/搜索/溢出等检查结果，也可调用 `window.ZhengReader.runSelfCheck()`。

人工操作检查：

1. 1440px宽查看卷首与第一幕；确认封面、每幕开篇及每场插画实际加载，字号与留白适合长读。
2. 打开目录，分别跳到第一幕首场和第五幕末场；底部当前场、百分比、上下场按钮同步。另逐条验证43个旧锚点与旧续读书签能跳到新稿对应场。
3. 搜索“郑芝龙”与一个对白词，点击结果；清空搜索恢复目录，`Esc`关闭并返回触发按钮。
4. 切换剧本/故事方式；逐个展开对白、分支后果和史料来源。分支不会宣称改变游戏状态。
5. 点击插画放大，按 `Tab`检查焦点、按 `Esc`返回；方向键翻场后标题获得焦点。
6. 阅读到中间场后刷新，点击卷首“继续阅读”；关闭本地存储再加载，页面仍能浏览。
7. 360px与768px检查目录、正文、底栏、图片，无水平溢出或遮住正文；开启系统深色后正文仍为浅灰纸页。减少动效偏好保持静态阅读。
8. 打印预览确认对白、分支与史注全部展开，工具栏不占页，文字为纸面深色。
9. 同时检查 `file://` 与本地HTTP入口，控制台没有未处理异常；史料外链只在用户点击后访问。

图像来源、原稿目视依据、生成提示词、旧稿复用边界和哈希保存在 `illustration-manifest.json`。外部史料链接可独立访问，项目内研究链接依赖原`docs`目录层级，单独复制reader文件夹不会一并复制研究原文。`zheng-battle-illustrations-2026-10-22`与`zheng-story-revision3-2026-10-22`均只代表对应旧稿和当时页面的历史证据，不能背书此后改写的正文、新采用图片或当前页面行为。edition 10第二遍精修记录保留在`docs/research/evidence/yiguan-second-pass-2026-10-23/`；当前整体连读微改的证据以`docs/research/evidence/yiguan-readthrough-2026-10-23/`为准；旧证据按各自输入哈希保留，未测项目不得沿用旧报告宣称通过。

过程图字段为 `illustrations[{id,image,caption,afterParagraph,width,height,imagePrompt,illustrationStatus}]`。段落位置从1开始，同段多图按数组顺序；图注参与搜索，提示词不进入正文。旧版图片原件保留，采用与否只由当前源和清单决定。
