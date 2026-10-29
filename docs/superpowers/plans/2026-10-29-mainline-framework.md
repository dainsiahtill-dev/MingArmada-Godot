# 全主线框架 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for root implementation and verification. Independent content and pure-progress files are delegated; root alone runs engines.

**Goal:** 先贯通郑芝龙—郑成功全程和各玩法的薄层，再深化局部系统。

**Architecture:** 主线内容声明动机、学习曲线、地区和目标；进度器仅拥有阶段与唯一结算，世界会话继续拥有钱、人、船、货。真实执行适配器向进度器提交经其核验的事实，UI没有判胜／跳章命令。旧1650及1661存档分别保留。

**Tech Stack:** Godot4.7、GDScript、JSON；RTK严格headless runner、真实GPU及静态介绍网页。

**Spec:** `docs/design/2026-10-29-naval-world/38-mainline-first-framework.md`。

## Global Constraints

- 用户要求先整体框架后细节；火势分区实战接线后移。剧情为玩法理解与逐渐难度服务，可调整章节。
- 父子为不同人物；交棒不能复制船货／补血／清债；跳年不高速消耗多年工资。
- 琉球、满剌噶及区域交互有实际任务与承诺；地方统治者和年代以专项来源为准，原创会面明确标注。
- 所有引擎串行；现有dirty工作保持，不提交／推送／删除／重置。当前`codex/godot-migration`为持续工作区，复用其未提交游戏资产，不创建脱离工作成果的干净副本。
- 核合同、内容预览、实际玩法、真实GPU和完整通关分别下结论，不能互相替代。

## Review Focus

1. 仅改标题／换主角姓名而玩法不通：逐阶段记录真实执行适配器和实际结果，缺失必须列为待接线。
2. 最后阶段漏目标：T10同时需要谈降、撤离、实际接收；缺一不得完成。
3. 读档／重放重复发奖与交棒：唯一回执、完整游标校验，旧回调按run/stage拒绝。
4. 失败回退把旧船与新奖励混合：保损恢复不重置世界；检查点只恢复整份世界＋进度。
5. 年代与地区错置：父篇／子篇身份顺序、王府／港口权限和已实现区域分别标记。

## Task 1：可执行全章内容

Files: 新`assets/data/story_campaign/zheng_family_v1.json`、`game/domain/story_campaign/catalog.gd`、`tests/test_story_campaign_catalog.gd`。

- [x] Guarded缺Catalog有效RED；24章／30阶段数据与严格加载器完成。
- [x] `load_content/validate/stages/stage/chapter`返回分离副本；父子、台湾归属与地区ID已校验。
- [x] 遗漏、身份／模式／类型／难度、重复ID、副本污染与CH09抵达／CH12接收者反例覆盖。
- [x] 最终内容238项GREEN，汇入final-regression-01；未标已可玩。

## Task 2：真实世界之外的进度合同

Files: 新`game/domain/story_campaign/progress.gd`、`tests/test_story_campaign_progress.gd`。

- [x] 缺模块有效RED后实现configure/begin/observe/settle/continue/retry/serialize/restore。
- [x] 状态仅进度，事实按run/stage/attempt/目标归属，重复事实幂等；旧尝试回调审查缺陷已修。
- [x] 30阶段、每转移存取、失败重试、CH12／T10与篡改拒绝；新增300失败归档后可继续，2072项GREEN。
- [x] 合同范围明确，无实际世界资产交棒或玩法通关证明。

## Task 3：同一课题实验与真实执行接线

Files: `assets/research/papers/story-campaign-flow.md`、原实验室目录，以及后续独立Demo／新主线runtime、scene与存档合同。

- [x] 同一story-campaign-flow论文先记录假设／单位／接受标准；合成Demo与framework-gpu-02完成，不能代替下面真实接线。
- [ ] 将操船、交易、护送、炮战、接舷、陆战、王庭条件和恢复逐类接入统一stage host；先薄层覆盖全部，不深挖某一局部。
- [ ] 所有stage没有任意“成功”产品命令；调试fixture与真实adapter不共用可见入口。
- [ ] 实验与真实入口GPU覆盖首章、海外关系、交棒、台湾全部阶段、失败与存取；缺失stage继续列未接。
- [ ] 全部真实从头到尾跑通后才标“主线粗闭环”；此前不宣称全游戏完成。

## Task 4：文档、网页、审查

- [x] 独立审查Task1/2，重大问题RED→GREEN，失败与最终证据已保留，见40号交付。
- [x] 研究论文、38/39/40号文档与介绍网页已同步；区分内容／进度合同与实际玩法。
- [x] 构建、--check、网页23测试与本机／LAN23条服务检查通过，revision210e22df6c89；未测外网，frp仍由用户维护。

## 执行账

本计划新建时任务均未运行。先前一轮是三区实验的真实进展；本轮用户已要求方向调整，不再推进其生产接线。两名只读代理确认新24章尚未进入Godot，现有Legacy模块可作为执行零件。选择先建立独立内容／进度合同以避免放宽旧存档；代价是此阶段仍未构成实际通关，Task3不能被省略。

Task1/2及Task4本批完成；Task3仅完成合成实验／实际实验室入口，真实世界适配继续。最终5相关文件2573检查0失败；framework-gpu-02为379PNG／366样本／5445tick，直接源码和原用户目录未变，主线程查看原图。源结果与当前hash核对见framework-delivery.json。全游戏目标未完成，主线实际粗闭环也未完成；下批按40号30阶段清单铺真实执行薄层，不回到火灾细化。
