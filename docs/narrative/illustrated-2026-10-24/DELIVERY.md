# 郑芝龙全章插图交付

2026-10-24。用户要求使用ChatGPT生成相关插图、每章至少两幅，并合并进现有网页。已完成六部22章、每章正好两幅，共44幅独立新图，公开入口为[海上明旗：郑芝龙](http://8.138.113.205:18794/docs/narrative/zheng-zhilong/)。页面标识“史料重构 · 全章插图 · 2026年10月24日更新”。

版本`historical-reboot-illustrated-2026-10-24`，最终源SHA256：`8eedaf3ba504648f1630e4ffc1188bc388da820b199866d0e7328f68defba749`。基线精修版SHA256为`ff49298756869eb372fac8503a9a246eff213d7db592fc06bd2361b18d4ce53a`。22章343段正文、对白、史注、人物、关系与63个旧书签映射保持不变；只精确迁移一条“本版无新插图”的版本说明，并添加插图及发布元数据。

## 图片与网页

全部图片使用ChatGPT内置`image_gen`生成，选定原图复制到项目[images/illustrated-2026-10-24](../zheng-zhilong/images/illustrated-2026-10-24/)。44幅均为独立1536×1024 PNG，44个内容哈希不同，没有拆分拼贴或重复同图计数。原始生成文件保留在Codex生成目录，项目逐图receipt记下真实路径、尺寸、字节数和SHA。

每章两幅对应不同已写出的时刻，按1-based `afterParagraph`插入，保留图注和描述性alt；两图不重复放作章头图。自然写实的统一质感覆盖平户港场、家庭离别、大员水道、入伙与修船、受抚、公司交涉、海战救助、家族安排和1646父子分途。人物按创作面貌及年龄阶段延续，明制束发、日本生活与早期荷舰形态用于避免明显错置。

- [插图清单](../zheng-zhilong/illustration-manifest.json)：44项章节、段位、路径、图注、alt、尺寸和SHA。
- [带图小说正文](../zheng-zhilong/novel.md)、[带图完整史注剧本](../zheng-zhilong/screenplay.md)：按同一源在同一段后插图，Markdown相对路径指向阅读目录中的图片。
- [游戏场景稿](../zheng-zhilong/game-scenes.md)：保持制作文本；新图尚未作为Godot过场或任务接入引擎。
- [正式JSON镜像](../zheng-zhilong/zheng-zhilong-story.json)：与唯一正式源逐字节相同。

入口无需edition参数；旧edition=11入口及63个历史书签继续有效。前端三项资源使用20261024-illustrated缓存标识。

## 视觉检查与生成溯源

44个最终图均经过负责生成的代理逐幅查看，接受记录绑定实际id与文件SHA。最终范围：[QA-EARLY](QA-EARLY.json)17幅、[QA-LATE](QA-LATE.json)14幅、[QA-ROOT](QA-ROOT.json)9幅、[QA-SUPPLEMENT](QA-SUPPLEMENT.json)4幅；相应Markdown记录观察和限制。不是真人美术团队或现实读者试读。

已重做发现的明显问题，包括平户地貌误带入大员、无芝龙场景误入主角、芝虎与芝龙无法区分、漏船误画干船坞、火船抓索动作与伤处错人、父子图残留港景、差役服饰过贵，以及穿鞋场面多一只鞋。未选输出保留。救学徒图保留小块非血腥擦伤，与最初“完全包盖”的更严prompt存在已记录偏差；尝试盖布编辑被工具拒绝后没有反复绕路调用，root复看原图接受，详情见QA-LATE。

提示词记录：[艺术方向](ART-DIRECTION.md)、[前12章分镜](boards-1-3.json)、[后10章分镜](boards-4-6.json)、[首图实际调用](first-generation.json)、[ROOT实际提示词](ROOT-PROMPTS.json)、[LATE实际提示词](LATE-PROMPTS.json)、[后段补图提示词](SUPPLEMENT-PROMPTS.json)、[长约章补图提示词](SUPPLEMENT-A3S2-PROMPTS.json)。boards包含分镜目标；发生补充或重做时，以相应实际调用记录为准。没有切换API/CLI图像模型，没有将占位图称为成图。

[早期视觉来源](VISUAL-SOURCES-EARLY.md)与[后期视觉来源](VISUAL-SOURCES-LATE.md)记录官方馆藏、年代及适用范围。舰艇、衣着、室内和港口为审慎的文学概括，不宣称精确舰型、关隘、军服等级或人物真容。未根据有争议材料另画芝虎或田川氏死亡现场。

## 实际验证

| 范围 | 实际结果 |
|---|---|
| 图片解码 | 44 PNG均通过Node结构/CRC/解压栅格检查及Pillow verify后完整load；尺寸与manifest一致，内容SHA各不相同。[decode-verification.json](decode-verification.json)。 |
| 采用保护 | 当前源只能由已保存基线或同一候选进入；候选须通过正文守恒、44图片合同、当前哈希的解码结果及44项视觉检查。[adoption.json](adoption.json)。 |
| 回归 | 最终64/64，包括40项插图合同测试和真实CLI子进程回归；缺图、同图充数、错章/错段、损坏PNG、旧图目录、改正文/史注/别名、错误manifest均有负例。 |
| 源与导出 | 926/926；正文343段、44图及三个导出与源一致。[当前verification.json](../zheng-zhilong/verification.json)、[export-verification.json](export-verification.json)。 |
| 阅读器静态 | 937项、0失败。 |
| 现有资源库 | 13/13、21负例及391个既有图像文件通过；该数字是原有资源库范围，44新小说图另行检查。 |
| 公网 | 44图片+9页面/数据/导出，共53文件全部HTTP200且与本地逐字节相同。[public-verification.json](public-verification.json)。 |
| DOM与交互 | 22章343段逐段相同；44图的实际段位、src、alt、宽高属性与源一致；63别名、搜索、模式及JS触发的放大图检查通过。[dom-verification.json](dom-verification.json)。 |

[CLI完整记录](cli-verification.json)保留第一次真实验证入口失败和修复后的成功。根因是CLI动态导入验证器后，插图合同又导入CLI中的PNG函数，形成顶层await循环；已把解析原样抽到纯模块，保留旧导出接口，并用实际子进程回归防止只import测试漏查。没有为浏览工具的假红改写正确的网页选择器。

[接入调查](INTEGRATION-REVIEW.md)、[发布链复核](PIPELINE-REVIEW.md)、[旧证据快照](previous-evidence.json)、[覆盖记录](art-coverage.json)保留过程证据。前轮精修报告与候选不覆盖；未提交、推送、清理其他工作或修改服务配置。

## 验证边界

浏览工具的文档级后代选择器返回异常：`document.querySelectorAll('main img')`为0，而`top.querySelectorAll('img')`为44，逐章实际figure内也各有两个img；该自检不被当成有效浏览器失败或通过，采用独立的元素作用域逐图核验。工具同时不提供真实`image.decode`、`naturalWidth`及可靠布局几何；因此没有宣称浏览器栅格、手机排版、打印视觉、原生点击/hashchange或跨刷新阅读进度持久化已实测。实际图片内容由逐图查看、PNG/Pillow解码和公网哈希分别验证，不能互相替代。

全部图片是依据小说场面的当代生成插画；史实与私人重建仍以原章史注为准。更新命令见[阅读目录README](../zheng-zhilong/README.md)。
