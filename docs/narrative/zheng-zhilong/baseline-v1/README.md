# 郑芝龙叙事图卷

本目录是独立的本地阅读网页，呈现六幕剧本、分场插画、对白、分支设计和分层史注。它不修改1650或1661生涯，不提供游戏战斗或任务结算；分支在这里供阅读、比较。

## 打开

直接双击 `index.html`。`story-data.js` 必须与页面同目录，并通过经典脚本设置 `window.ZHENG_STORY`；不使用 `fetch`，可从 `file://` 打开。构建工具将源 `../zheng-zhilong-story.json` 复制到本目录，整个目录可携带下载数据一起复制。

也可从仓库根使用本地HTTP服务：

```powershell
rtk proxy python -m http.server 8765 --bind 127.0.0.1
```

打开 `http://127.0.0.1:8765/docs/narrative/zheng-zhilong/`。无需安装依赖、构建或联网加载字体。

## 文件合同

- `index.html`：页面骨架、目录对话框、大图对话框、阅读工具。
- `styles.css`：中文宋体系统字体栈、墨绿与纸色、响应式、深色偏好、打印与减少动效支持。
- `app.js`：容错数据标准化、渲染、搜索、目录、逐场导航、模式、续读与图片放大。
- `story-data.js`：从 `../zheng-zhilong-story.json` 生成的 `window.ZHENG_STORY` 数据，由内容构建方管理。
- `images/act-1.png` 至 `images/act-6.png`：每幕开篇插画。
- `images/<scene-id>.png`：每场插画。图片只接受 `images/` 下的相对路径；缺图显示明确提示，不生成替代占位插画。

根字段：`title, subtitle, logline, characters, acts`。`characters` 可为数组或以人物姓名为键的对象；可选 `foreshadowing / foreshadows / motifs` 与 `appendix` 也会容错展示。

每幕字段：`id, title, years, synopsis, cover, scenes`。每场字段：`id, title, year, location, summary, paragraphs[], dialogue[{speaker,text}], choices[{id,label,consequence}], history{level,note,sources[{title,url}]}, image`。`imagePrompt`保留在源数据中，网页不把生成提示词当正文展示。

正文、对白、人物、分支、史注参与搜索。输入多个空格分隔的词时，每个词都必须出现在同一场。显示匹配片段和跳转链接。数据使用DOM文字节点插入，不执行内容中的HTML；史料来源接受HTTP/HTTPS与受限项目研究Markdown路径。源数据中的 `../research/*.md` 自动转为阅读器相对的 `../../research/*.md`；路径中不接受任意协议、编码穿越或父目录穿越。

## 阅读交互

- “目录”打开六幕/各场锚点目录；“搜索”或 `/` 聚焦搜索框。
- 左右方向键、底部上一场/下一场逐场跳转。输入框与打开的对话框内不抢方向键。
- “故事阅读”收起对白和分支；“剧本阅读”展开。每个分支可单独查看后果。
- 阅读进度按进入的场次计算，不表示游戏通关。当前位置与阅读方式使用 `localStorage` 保存；存储禁用或损坏时仍可正常阅读。
- 卷首“继续阅读”跳到上次记录的场景，不强制自动跳转。
- 插画点击放大，`Esc` 关闭。目录和大图使用原生模态对话框，支持焦点约束与键盘操作。
- 打印前展开对白、分支与史注；打印结束恢复之前的展开状态。打印会隐藏阅读工具。

## 验收

静态合同自检：

```powershell
rtk proxy node docs/narrative/zheng-zhilong/verify-reader.mjs
```

此脚本检查JS语法、本地依赖、全六幕数据、每场正文/对白/分支/史注与图片路径、文件存在、ID唯一性。内容或图片还未落盘会如实失败。它不替代真实浏览器验收。

浏览器中打开 `index.html?selftest=1` 或对应HTTP地址；控制台 `window.__ZHENG_READER_TESTS__` 给出DOM/目录/搜索/溢出等检查结果，也可调用 `window.ZhengReader.runSelfCheck()`。

人工操作检查：

1. 1440px宽查看卷首与第一幕；确认封面、每幕开篇及每场插画实际加载，字号与留白适合长读。
2. 打开目录，分别跳到第一幕首场和第六幕末场；底部当前场、百分比、上下场按钮同步。
3. 搜索“郑芝龙”与一个对白词，点击结果；清空搜索恢复目录，`Esc`关闭并返回触发按钮。
4. 切换剧本/故事方式；逐个展开对白、分支后果和史料来源。分支不会宣称改变游戏状态。
5. 点击插画放大，按 `Tab`检查焦点、按 `Esc`返回；方向键翻场后标题获得焦点。
6. 阅读到中间场后刷新，点击卷首“继续阅读”；关闭本地存储再加载，页面仍能浏览。
7. 360px与768px检查目录、正文、底栏、图片，无水平溢出或遮住正文；开启系统深色与减少动效偏好复查。
8. 打印预览确认对白、分支与史注全部展开，工具栏不占页，文字为纸面深色。
9. 同时检查 `file://` 与本地HTTP入口，控制台没有未处理异常；史料外链只在用户点击后访问。

完整插画、浏览器截图、性能指标与人工操作结果需由实际执行方记录；静态合同通过不代表这些已经通过。
