# 海上明旗 · 玩法长卷

持续介绍游戏玩法、美术素材和真实进展的独立前端网页。无npm依赖、外部图片或网络字体，可直接打开完整构建，也可通过HTTP浏览。

## 打开与更新

在项目根目录运行：

```powershell
rtk proxy node web/gameplay-journal/scripts/build.mjs
rtk proxy node web/gameplay-journal/scripts/build.mjs --check
```

然后用浏览器打开 `web/gameplay-journal/dist/index.html`。不应打开 `src/index.html`：源文件还没有复制图片与内容数据。

局域网服务（前台运行）：

```powershell
rtk proxy node web/gameplay-journal/scripts/serve.mjs --host 0.0.0.0 --port 4173
```

本机打开 `http://127.0.0.1:4173/`，当前局域网地址为 `http://192.168.10.6:4173/`。IP随网络/DHCP可能变化。结束前台服务按Ctrl+C。服务仅提供 `dist/`，禁止目录浏览；只接受GET/HEAD，新构建刷新即生效。

Windows隐藏后台启动（检查端口归属，不结束其它进程）：

```powershell
rtk proxy powershell -NoProfile -File web/gameplay-journal/scripts/start-lan.ps1
```

当前已建立专用入站规则 `MingArmada-Gameplay-Web-4173-LAN`：Node程序、TCP4173、来源LocalSubnet。规则不开放游戏目录。该规则只用于本地子网；frpc运行在同机时使用回环地址，无需为反向隧道扩大入站范围。

用户选择自行配置frp。反代上游填写 `127.0.0.1:4173`，网页使用相对资源路径，可通过根路径的自定义域名访问；HTTP/HTTPS入口与证书由反代端配置。服务已用自定义Host及X-Forwarded-Proto请求核对，真实外网连通性须待用户frp配置后验证。不要把Site草稿的预期URL当作已部署外网地址。

## 每次游戏进展都同步

这已成为根 `AGENTS.md` 的工作约定。每次新增玩法、美术、叙事、正式集成、验收证据或修正实现边界：

1. 编辑 `content/gameplay.json`：更新对应功能的状态、玩法说明与限制，在 `updates` 开头加入具体航志，更新 `updatedAt`。同日多次进展可以有多条记录；不要用构建时间冒充内容更新时间。
2. 有新图片就编辑 `content/media.json`：引用仓库内的真实原件，填图片尺寸、出处与来源类型。`art`=生成原画，`render`=模型静帧，`game`=正式游戏界面，`experiment`=独立实验。不要覆盖或伪造历史证据。
3. 构建并执行 `--check`。构建复制白名单资源，校验引用、尺寸、来源及状态。`dist/manifest.json` 保存来源散列；来源或产物变动后检查会提示未同步。
4. 变更交互、布局或图片构图时，在桌面与手机浏览器复验；记录实测与未测范围。
5. 游戏进展汇报中同时说明网页更新结果。正式可玩状态需要实际入口证据，实验通过不自动升级。

内容字段的 `source` 是维护用仓库出处，不是网页对外跳转链接。新功能在 `features` 中加入，同步其 `related` 关联。新媒体默认进入图集，可用 `galleryTitle` 指定短标题、`galleryOrder` 指定先后，或用 `gallery:false` 排除；不需要修改前端脚本。首屏及固定福船、海图图片路径仍在HTML中，改名时构建会验证这些引用。

首页开篇剧情维护在 `storyOverview`：`heroLead` 为首屏短介绍，`title/lead/paragraphs` 为原画之后的三段完整梗概，`note/status/source` 记录主线规划与出处。构建直接写入HTML，因此不开启JavaScript也能读到剧情。正文放在玩法目录之前，后文 `chapters` 保留详细阶段；不要只改后文时间线而遗漏开篇。

## 文件职责

- `src/`：页面结构、样式、交互；文字是可选择的真实HTML。
- `content/gameplay.json`：玩法、船型、章节、航志。
- `content/media.json`：素材与截图白名单，保留原件及来源。
- `scripts/build.mjs`：确定性构建与过期检查；不删除文件。
- `tests/build.test.mjs`：错误引用、路径、状态与过期产物检查。
- `dist/`：可独立打开/托管的完整站点。

验证命令：

```powershell
rtk proxy node --test web/gameplay-journal/tests/build.test.mjs
rtk proxy node --test web/gameplay-journal/tests/server.test.mjs
rtk proxy node --check web/gameplay-journal/src/app.js
rtk proxy node web/gameplay-journal/scripts/check-service.mjs --lan 192.168.10.6
```

每次开发收尾由执行者按以上流程同步并重新构建。运行中的局域网服务会读取新产物，刷新即可看到更新；外网经用户维护的frp转发同一服务。电脑重启后可用后台启动命令恢复。
