# 插图工作状态

用户要求现有22章每章至少两幅ChatGPT新图。目标44幅独立生成并接入原阅读页。正文精修版SHA ff49298756869eb372fac8503a9a246eff213d7db592fc06bd2361b18d4ce53a已保存baseline.json，不回用更早故事和图。

首幅zzl_a1_s1_01已生成、检视并复制到reader/images/illustrated-2026-10-24；first-generation.json存真实prompt，receipts存原始工具路径与PNG哈希。首幅同时作为后续风格/人物参考。

分镜完成44项。最终生成分工：illustration_early_boards生成17幅（首图除外，截止a3s1），QA-EARLY；illustration_late_boards生成a4s1到a5s2共12幅并补a3s2两幅，共14幅，QA-LATE；illustration_reader_path在完成代码后生成a5s3与a6s1共4幅，QA-SUPPLEMENT；root负责首图及a3s3/a3s4/a6s2/a6s3共9幅，QA-ROOT。所有新图用内置image_gen，每图独立调用，不使用API fallback、不切拼贴充数。root独占正式源及新轮发布文件。每份QA JSON逐项绑定接受图的id与hash，不以报告存在代替44图完成。

技术约定：新version historical-reboot-illustrated-2026-10-24，narrativeContract不变；top/act/scene status ready，无章头图或部封面，两张仅以illustrations段后插入。manifest schemaVersion2，记录最终sourceSHA与44帧id/sceneId/image/afterParagraph/caption/alt/width/height/sha256/generator。source图片尺寸由PNG实读填入。

已完成并公开发布插图版，最后分工为early17、late14、supplement4、root9。44图全部1536×1024，44唯一内容哈希、44份视觉检查绑定实际字节。最终正式源SHA8eedaf3ba504648f1630e4ffc1188bc388da820b199866d0e7328f68defba749。正文343段不变，只更新明确的当前插图状态说明。

已完成prepare→全量Pillow解码→adopt→build→新export→剧本导出→资源目录同步。64回归、926源/图片/导出检查、937阅读器静态检查通过；53个公网文件（44图+9页面/数据/导出）全部200且与本地一致。DOM逐章核对44图路径、alt、尺寸、段位与343段原文，63别名及放大图等直接运行时检查通过。已打开用户不带参数的阅读地址。详情与工具限制见DELIVERY.md、dom-verification.json。

最终验证曾发现真实CLI循环导入，已把PNG解析抽到纯底层模块并加入实际子进程回归；首轮失败与修后通过均保存在cli-verification.json。勿运行full-polish旧export清空manifest。
