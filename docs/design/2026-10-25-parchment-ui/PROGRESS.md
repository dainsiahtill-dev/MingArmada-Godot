# 当前任务：Godot整套纸本UI

## 最终状态：2026-10-25 已完成

实际 Godot UI、7 张生成原图、11 个控件图标和4张根目录实际运行预览已交付。以 [DELIVERY.md](DELIVERY.md) 和 [final-delivery-manifest.json](evidence/final-delivery-manifest.json) 为最终记录：menu-r4、mingqi-r2、legacy-r2、naval-r3、catalog-r2、practice-r1、auxiliary-r1 共83图、905检查、0失败，源文件/素材/截图哈希当前一致。相关行为回归通过；最终主题56/菜单62、文件窗口10、首航缩放24、实验室布局与真实滚轮输入10均通过。独立审查两项P2、picker验证点及最后实验室1280裁切问题均已关闭。

原用户存档/设置只读核对未变；未提交/推送；不是连续海况/FPS或Windows导出包验收。以下保留的是实施中途历史快照，其中“仍在执行/待完成”和旧断言数字不代表当前状态。

## 实施中途快照（保留）

用户已明确要求全套实施，不是仅生成背景。项目C:/Users/dains/Documents/Git/ming-armada，所有shell用rtk；CodeGraph本会话确认无索引，不重试。禁止提交/推送/清理既有工作。git里大量model-preproduction等并行/先存变更不属本任务，不能回滚。

当前实际已完成：
- ChatGPT生成主菜单图与初版、账册底、海图备选底、纸面板、普通按钮、朱砂按钮，均保存根目录。assets.json记录真实尺寸/哈希；主背景1672×941，面板1254×1254，按钮2172×724。提示词保存在本目录asset-prompts.json和根ming-armada-ui-background-generation.json。
- shared/parchment_theme.gd已落地，覆盖native控件和嵌入Window；root main_menu实际应用新背景/样式并收紧首屏让设置退出可见。
- 管理组6文件与玩法组6文件已完成；辅助scene组8文件也已完成，见各implementation文档。所有产品文件当前冻结。
- headless管理6组591断言、玩法12组2271断言、辅助10组1095断言；root最终theme44/mainMenu62通过。计数是各组运行记录，不声称互不重叠或全项目286测试已跑。
- 已完成editor headless导入；仅一次原helper祖先目录写错导致无测试运行，已修为../../../并留正确隔离profile。

视觉回归：runtime agent /root/parchment_runtime_probe 负责capture-parchment-ui.gd及7组单实例正常GPU，证据本目录evidence。menu r1/r2留下失败：纸面透明padding让留白看似失效，button大cap太粗，FileDialog灰底与标题透明。root通过region裁32px(panel)/24px(button)、cap8/2、AcceptDialog/FileDialog纸面，以及按Godot默认Window expand_top32/content_top28等修好，并补先红后绿测试。menu r3现11图121断言0失败，已逐图检查；Mingqi r1为14图174断言0失败。其他组正在顺序捕获，不得提前宣称完成。

当前agents：
- /root/parchment_runtime_probe：正常GPU依次menu/mingqi/legacy/naval/catalog/practice/auxiliary，保护原槽+profile默认槽，必须检查run-result源码稳定。可以请已结束实现agent只读看图，不能再改冻结代码。
- /root/parchment_final_review：全新独立代码/规格审查，只写FINAL-REVIEW.md。若有实质问题root处理并通知runtime重新冻结/复测。
- /root/parchment_ui_inventory、/root/parchment_gameplay_inventory：分组实现已完成，可能被runtime请求独立图片复核。

剩余：等所有GPU组结果并实际看代表画面、关闭审查必修；记录最终源/素材/截图哈希，更新PLAN和DELIVERY/运行说明；必要时把最终主菜单/设置/战斗截图复制到根目录供用户直接看。不要替换/改动小说44插图网页。全局PRODUCT/DESIGN已更新为用户最新Godot纸本方向，旧网页设计历史仍保留。

Godot路径：C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe。root helper run-check.mjs设置子进程APPDATA/LOCALAPPDATA=repo/Temp/parchment-ui-profiles/root-checks，默认timeout180秒；runtime用独立profile和真实原槽hash保护。native API disabled不妨碍Godot CLI自己的get_viewport().get_texture().get_image()截图；不得将其称为外部真实鼠标或动态海况验收。
