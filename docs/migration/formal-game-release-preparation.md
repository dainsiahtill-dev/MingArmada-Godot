# 正式游戏 Windows 交付准备

当前阶段为**准备完成、尚未导出或验收最新 Windows 包**。等待主线程确认海岛细节、岸边白沫等源码冻结，完成新 GPU/整仓验证后，才执行本轮导出。

## 普通 release 入口

`game/scenes/main/main_scene.gd` 支持以下正常用户参数：

```text
MingArmada.exe -- --start-game=mingqi
MingArmada.exe -- --start-game=sail --game-capture=C:/absolute/path/sail.png
```

合法模式为 `mingqi/career/sail/duel/fleet`。入口查找现有菜单按钮并发出实际 `pressed` signal；菜单生成 generation/nonce，原 Router 验证并分阶段加载。没有开发者权限、外部场景脚本或 pack override。重复/未知模式、冲突的 `--water-study`、非绝对或非 PNG capture 路径均不启动另一入口。原 `--water-study` 及其截图/P2 token 防护保持原行为。

正式截图等待真正激活的 scene request stamp；每个 await 前后检查 generation、nonce、operation 与 current scene 身份。切换、返回、取消都让任务失效。最终在 `RenderingServer.frame_post_draw` 后读取实际主 viewport，导出 PNG 和 metadata：真实 snapshot、启动回执、请求标识、camera、镜像诊断、源海岛 profile、GPU/引擎信息和 PNG SHA。没有换场景、暂停/修改玩法状态或生成假的展示图。

## 导出清单

`tools/export-windows.mjs --prepare-only` 只生成 `build/windows-export-prepared.json`。当前准备覆盖 **488** 个 `game/modules/assets` 文件及项目、导出配置，包含 UID 与纹理 import 配置；源码还可能在最终冻结前变化，此数字不是发布包完成证明。

真正导出前后分别计算全清单 SHA；若任何游戏、模块、资源内容/文件集合变化，该次包不接受。原 14 项参考示例清单仍保留供既有链兼容。EXE/PCK 与所有交付启动脚本独立记录 SHA。便携目录中放置一份同内容 receipt，使复制出的 EXE/PCK 可以脱离源码项目启动。

准备输出：`Launch-Menu.cmd`、`Launch-Mingqi.cmd`、`Launch-Game.ps1`；原 `Launch-IslandWater` 保留。

`tools/launch-mingqi.ps1` 验证当前包 SHA 与新的正式入口 receipt，拒绝把旧水面展示包当作最新正式包。默认游玩使用独立持久的 release-player-profile；截图验收使用独立 fresh profile，也可显式指定 ProfileDirectory。仅改变子进程的 APPDATA/LOCALAPPDATA，之后恢复 PowerShell 环境；现有用户存档不覆盖。

## 待实际执行的原生包验收

`build/tools/run-formal-game-release.mjs` 将当前 EXE/PCK/启动器/receipt 复制到新目录，不带 `game/modules/assets/project.godot`。实际 EXE 从空 cwd 启动，依次使用普通菜单入口 `sail`、`mingqi`，分别读取原生 GPU PNG；每个模式使用单独的隔离 profile。

验收核对实际进程路径/响应、正式场景路径、Router 标识、启动与 snapshot、五波、共享非递归镜像、源海岛、PNG 新鲜度/SHA、引擎日志与全源码冻结。只停止已核对路径的 owned native process；最终可保留 Mingqi 单窗口。既有 editor+PCK 验收不会冒充 EXE 运行证据。

此脚本尚未运行；未产生新的 actual EXE GPU 完成声明。

## 已执行验证

- 新入口 RED：缺入口时 1 failure；重复空模式参数曾错误通过，新增 RED 精确检出，后已修复。
- `test_release_game_entry.gd`：**45 assertions，0 failures**。真实菜单按钮/Router 权限覆盖五模式；检查无效参数、路径、取消和 warmup 期间场景身份替换。
- 既有 `test_reference_demo_scene.gd`：**35 assertions，0 failures**。原 water-study staged menu 路由、独立四波 scene 与 screenshot cancellation 防护保持。
- Node export/原生验收脚本语法检查通过；prepare-only 实际生成清单。
- 正式启动器对现有旧 receipt 实际拒绝，进程未启动；这不是最新包成功验证。

证据在 `docs/migration/evidence/release-game-entry/`。正式游戏成功捕获、实际新 EXE/PCK 和完整发布验收仍待最终源码冻结后执行。没有进行性能调优、额外 GPU 启动或 Git stage/push。
