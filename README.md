# 海上明旗 · Godot

明郑背景的海商舰队冒险游戏，独立 Godot 迁移仓库。原网页版保留不变。当前已能运行单船航行；完整战斗、经营与历史任务迁移仍在进行。

使用 Godot 4.7 打开 [project.godot](project.godot)，按 **F5**。已验证版本为 4.7.2，Windows D3D12 / Forward+，Jolt Physics。

- W / S：升帆、收帆。
- A / D：左右转舵；默认开启均衡操船辅助。
- Q / E：调整帆角。
- Space：暂停、恢复，船只/海面/水手共用暂停后的模拟时间。
- 1 / 2：船长镜头、高位海图镜头。
- M / 点击右上小地图：展开试航海图；M / Esc / 关闭按钮返回，保留先前暂停状态。
- F12：保存实际 viewport PNG 与状态 JSON 到 `docs/migration/evidence/sailing-trial/`。

海面实验场景另位于 `game/scenes/water_probe/water_probe.tscn`，可单独按 F6 运行。默认航行场景已接入原船模、水手和原物理，不是静态截图。

明代古航图已接入默认试航与两套生涯场景。1650场景为`game/scenes/mingqi/mingqi_scene.tscn`，1661为`game/scenes/legacy/legacy_scene.tscn`，均可单独F6运行；完整主菜单路由仍在迁移。小图读取真实地形与船位；默认试航海图仅显示航位，两个生涯继续使用各自原有导航命令。原生截图和边界说明见[古航图验收](docs/migration/native-nautical-chart-integration.md)。

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
