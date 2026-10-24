# Game UI Prototype Implementation Plan

> **For agentic workers:** 使用现有明确合同并行实现独立renderer，root负责共享壳、集成与真实浏览器验收。用户已选完整可点击原型；当前仓库工作保留，不提交、不建新分支、不修改Godot。

**Goal:** 根据43场故事交付30系统、72页可点击游戏UI与全部页面预览。

**Architecture:** systems.json为系统/页面/流程清单；构建工具生成经典data.js；三个独立renderer按页面ID注册，共享ui-core及内存演示状态。原型目录包含index、样式、预览和逐页截图。

**Tech Stack:** 原生HTML/CSS/JavaScript、本地Python HTTP、内置ImageGen、CUA浏览器。

---

- [x] 逐场映射系统和页面，核对现有Godot与艺术资产边界。
- [x] 固定PRODUCT/DESIGN及renderer合同；新船图保留提示词、原件与采用记录。
- [x] 并行制作舰船战斗、港贸日志与root航行菜单页面，各文件独占。
- [x] 构建数据、统一样式、页目录、系统表、流程与预览入口；实现内存交易/修船/船员/弹药/家书等反馈。
- [x] 执行页面覆盖、剧情ID、资源与链接校验；真实浏览器操作关键流程。
- [x] 保存全部页面截图、索引、README与限制，展示已验收原型。
