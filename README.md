# 海上明旗 · Godot

明郑背景的海商舰队冒险游戏，独立 Godot 迁移仓库。原网页版保留不变。原生菜单已连接两个生涯、海战练习和船舶图鉴；完整迁移与整机验收仍在进行。

使用 Godot 4.7 打开 [project.godot](project.godot)，按 **F5**。已验证版本为 4.7.2，Windows D3D12 / Forward+，Jolt Physics。

默认进入真实主菜单，可选择1650护粮生涯、1661生涯、新建或继续、海战单挑、舰队交战、航行练习、船舶图鉴及航海设置。继续读取原始存档而不旋转备份；无效1650存档进入恢复界面，可导出原文、读取已验证备份或导入v2 JSON。导入先建立实际原生场景，再提交磁盘事务。

海战与航行练习操作：

- W / S、上下方向键：升帆、收帆；A / D、左右方向键：左右转舵。
- Q / E：左、右舷开火；Space：朝最近敌船所在一侧开火。
- 1 / 2 / 3：实心弹、链弹、霰弹；R：自动调帆；[ / ]：调整帆角。
- Esc：暂停菜单；M / 点击小地图：展开海图。恢复、重启、投降及镜头切换均有可见按钮。
- 窗口失去焦点后保持暂停；回到窗口后需点击继续，避免意外恢复交战。

两个生涯保留各自的命令与快捷键，详见游戏内操作提示。1661完整海图可点图下达航向；1650点图填入目标后由按钮确认。航行练习展开图显示真实航位，不发经营或舰队命令。

独立航行实验位于`game/scenes/sailing_trial/sailing_trial.tscn`，可F6运行；其旧操作为W/S帆速、A/D转舵、Q/E帆角、Space暂停、1/2镜头、M海图、F12原生截图。水面实验位于`game/scenes/water_probe/water_probe.tscn`。两者继续保留，默认F5入口现在为主菜单。

明代古航图使用纸纹、金色云纹边框和墨绘岸线，并叠加真实浅滩、港口、船位及航向。1650场景为`game/scenes/mingqi/mingqi_scene.tscn`，1661为`game/scenes/legacy/legacy_scene.tscn`。古航图截图见[航图验收](docs/migration/native-nautical-chart-integration.md)，菜单与新增入口见[原生入口验收](docs/migration/native-entry-integration.md)。

使用Godot用户参数`--dev`可显示四小游戏练习及船舶LOD检查。决斗和宴会需点击开始；陆战和寻宝直接进入。原网页QA的十五个场景尚未全部迁移，QA入口会明确报告未就绪。船舶图鉴展示六类真实GLB、三档LOD、帆装及炮组动画；鼠标拖拽旋转、滚轮缩放。

运行独立检查（Node.js + RTK + 本机 Godot 可执行文件）：

```powershell
rtk proxy node tools/verify-godot.mjs --godot "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe"
```

所有测试使用原生 headless Godot。水面实际 GPU 证据必须额外运行图形模式：

```powershell
rtk proxy Godot_v4.7.2-stable_win64.exe --path . res://game/scenes/sailing_trial/sailing_trial.tscn -- --capture
rtk proxy Godot_v4.7.2-stable_win64.exe --path . res://game/scenes/sailing_trial/sailing_trial.tscn -- --capture --shore-loop
```

底层按 `modules/contracts`、`modules/physics_engine`、`modules/scene_engine` 分离，上层按领域、运行时、表现和 UI 分离。详见 [迁移进度](docs/migration/progress.md)、[实施计划](docs/superpowers/plans/2026-10-11-godot-migration.md) 和 [水面实际验收](docs/migration/water-probe-acceptance.md)。
