# 《一官入海》剧本图卷实施计划

## 2026-10-22：剧情优先，覆盖下列初始定额

用户先后要求先打磨剧情、增加海上遇盗/反制/从盗/合伙翻脸章节、借鉴西部与海盗叙事、展开葡荷西日及区域航海者接触。现稿扩为六幕42场；取消每幕5场、每场2选择和现阶段必须36幅图的限制。

- [x] 审读第二稿，确认权力形成缺场、主角过度正确、重复搜救与末年性格突变。
- [x] 重写完整单线剧情，增加12场海上故事，明确受压自保到结伙从盗的创作动机。
- [x] 完成西部/海盗结构参考与跨文化史实边界，不照搬原作桥段或以国籍划善恶。
- [x] 合并唯一JSON，完整生成文学剧本和网页数据/下载镜像，保留前稿。
- [x] 全文连续性审读，修正动作绳索、杜七复盟条件、画作往返、旧地点与已取消前史残留。
- [x] 分开正文、插图、页面验证；隐藏待重画旧图，不以文件齐备声称画面适配。
- [x] 当前42场真实浏览器验证结果归档，桌面与窄屏截图及范围记录见`docs/research/evidence/zheng-story-revision3-2026-10-22/`；页面保留于8793本地阅读入口。
- [ ] 剧情审读收口后，按最终场面生成和验收章首/分场插图；当前暂缓，不以旧图抵交。

## 初始实施记录（下列定额保留供追溯）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付六幕三十场、三十六张对应插画的完整中文剧本网页。

**Architecture:** 单一JSON权威内容生成story-data.js供静态阅读器使用；剧本Markdown用于编剧交接。生成图像与来源提示独立保存，页面不依赖服务端或外部CDN。

**Tech Stack:** 原生HTML/CSS/JavaScript、Node.js构建及验证、内置imagegen；浏览器实际验收。

**Spec:** docs/superpowers/specs/2026-10-21-zheng-illustrated-screenplay-design.md

## Global Constraints

- 六幕、每幕五场、三十六幅独立生成插图；不得用占位图或复用图冒充。
- 原有1650、1661代码与存档不变；分支阅读不是运行中的海战任务。
- 史实、晚出传奇、小说创作明确分层；不把后出整理当十七世纪原件。
- 文件操作和命令使用RTK；不提交、不推送、不删除用户改动。
- file://可读，无CDN或网络字体依赖。

## Review Focus

- 1630、1633、1645、1646事件先后及人物年龄称谓。
- 信物和家书存在具体传递/误读/复核链，不能凭巧合解决所有冲突。
- 搜索或翻场不会导致所有折叠内容不可达；键盘和窄屏均可用。
- localStorage异常或损坏续读值不会阻止正文渲染。
- 插图与具体场景一致、对应文件唯一、断网仍可显示。

## Task 1: 完成研究与完整文学稿

**Files:** docs/research/zheng-drama-baitu-method-2026-10-21.md; docs/narrative/zheng-zhilong-campaign-script-2026-10-21.md; docs/narrative/zheng-zhilong-story.json

**Interfaces:** 输出{title,subtitle,logline,characters,acts:[{id,title,years,synopsis,cover,scenes:[{id,title,year,location,summary,paragraphs,dialogue,choices,history,image,imagePrompt}]}]}。

- [ ] 核对《白兔记》版本和可借鉴的戏剧因果，保存直接来源。
- [ ] 写完整六幕三十场和角色弧、伏笔回收；输出JSON与台本。
- [ ] 独立审读历史先后、人物动机及转折，修正重要问题。

## Task 2: 逐图生成并保存

**Files:** docs/narrative/zheng-zhilong/images/*.png; illustration-manifest.json

**Interfaces:** scene.image与act.cover为相对路径；manifest包含prompt、生成来源、文件哈希和尺寸。

- [ ] 六幅章首图与三十幅场景图分别调用imagegen。
- [ ] 目视校验、保存全部生成图片，检查年代、角色与场景。
- [ ] 逐图建立manifest，校验36路径唯一且所有引用存在。

## Task 3: 静态图卷与内容构建

**Files:** docs/narrative/zheng-zhilong/index.html, styles.css, app.js, story-data.js, README.md; tools/build-zheng-story.mjs; tools/verify-zheng-story.mjs

**Interfaces:** window.ZHENG_STORY为唯一正文；DOM使用真实章节与场景ID。

- [ ] 实现目录、搜索、续读、模式、翻场、灯箱与打印。
- [ ] 构建story-data.js；校验结构、时间线、链接语法及全部图像。
- [ ] 创建可完整携带的网页目录与使用说明。

## Task 4: 浏览器验收与交付

**Files:** docs/narrative/zheng-zhilong/verification.json; docs/research/evidence/zheng-illustrated-screenplay-2026-10-21/

- [ ] 桌面实际打开，操作目录/搜索/模式/灯箱/翻场/续读。
- [ ] 360px及桌面检查排版、图像与长文可达性；检查控制台。
- [ ] 最终独立评审并修复重要问题；再次运行内容与资源校验。
- [ ] 打开最终网页，交付链接、范围、图片数量与尚未测得的限制。
# 2026-10-22 战斗插图整合增补

在已完成的42场正文上新增明确标记为虚构的湾口抗掠故事；全卷6幕43场。逐场审读旧图，重画失配画面；四场重点战斗补8幅独立过程图。采用清单为唯一图片依据，使用内置ImageGen、保留原文件、逐图目视、核对尺寸与SHA256。渲染器支持段间多图、搜索图注与原生灯箱，验证器包含过程图数量、位置与全局唯一ID。完成后执行严格静态验证，再以真实浏览器核对桌面、手机、导航和灯箱，并保存当前版本证据。

