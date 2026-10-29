# 玩法长卷网页 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在项目内交付带真实图片、可探索玩法和持续更新机制的古风游戏介绍网页。

**Architecture:** 独立静态HTML/CSS/JS读取构建注入的数据，不依赖开发框架。内容与媒体登记分离，Node构建/检查保证白名单资产、来源和输出一致。

**Tech Stack:** HTML5、CSS、浏览器JavaScript、Node内置模块。

**Spec:** `docs/superpowers/specs/2026-10-29-gameplay-showcase-design.md`

## Global Constraints

- 所有命令使用RTK，不提交、推送、重置、删除；保留现有游戏工作。
- 只动独立站、文档及根AGENTS新增同步约定；不改游戏算法。
- 明确已可玩/实验中/规划中，图片明确来源，不冒充实机与历史性能。
- 直接打开构建HTML也可用；不依赖外部字体、CDN或图片。

## Review Focus

- 手机菜单与弹层必须可键盘关闭、恢复焦点，页面不被遮挡。
- 搜索无结果与快速切换状态不能留下旧详情。
- 规划船型不能复用福船渲染冒充已制作资产。
- 新内容/图片/出处不一致时构建失败而非静默漏图。
- 不将实验、静帧或自动采样升级为整体游戏验收。

## Task 1: 内容与资源

**Files:** `web/gameplay-journal/content/gameplay.json`, `content/media.json`

- [x] 根据当前文档录入12条玩法、25船型、父子章节与真实更新；25船型为用户后续追加。
- [x] 目检并登记既有生成原画、福船渲染、正式火攻图、货物与船员实验图。
- [x] 核对状态与来源，无不存在的引用。

## Task 2: 前端与构建

**Files:** `web/gameplay-journal/src/index.html`, `src/styles.css`, `src/app.js`, `scripts/build.mjs`

- [x] 实现原画首屏、玩法探索、船型图鉴、主线、图集与航志。
- [x] 实现筛选/搜索/空态、图集弹层、移动导航、键盘与减少动态（源码完成，浏览器实测未完成）。
- [x] 校验输入、生成支持独立打开的dist并复制白名单资源（file://实际浏览器运行未测）。
- [x] 运行构建；检查无效关联/缺失来源会失败、改动输入后check会拒绝旧输出。

## Task 3: 持续同步与验收

**Files:** 根`AGENTS.md`、`web/gameplay-journal/README.md`、站点验收记录。

- [x] 写入每次项目进展同步内容/航志/图片并构建检查的约定。
- [ ] 在真实浏览器检查桌面、平板、手机；操作全部关键交互，保存截图。
- [x] 独立审查并修复维护缺陷；20项构建/真实HTTP服务检查与部署后20项HTTP探测通过。浏览器连接不可用，视觉与焦点证据缺失，详见DELIVERY。

用户后续选择局域网服务+自行维护frp。已提供0.0.0.0:4173与LocalSubnet专用规则；外网域名待用户配置后验证。不继续发布先前未部署的Sites草稿。
