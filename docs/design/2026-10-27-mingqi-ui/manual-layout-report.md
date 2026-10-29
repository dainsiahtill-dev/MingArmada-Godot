# 明旗航程操船手册布局

- HUD 的 `sailing_manual` 是本地按钮，默认显示“操船手册”；展开后显示“收起手册”及原有 `keys` 四行说明。按钮不发送航程命令，手册状态保存在界面实例中，跨面板切换和快照结构重建保留，不写入存档。
- 1600×900、`mingqi-reference.json` 初始快照的无窗口 Godot 夹具：改动前 HUD 430×360；改动后收起 430×314、展开 430×401。尺寸随真实航况、文字、窗口及主题变化，不把夹具尺寸当作真实游戏运行或 GPU 截图结果。
- 独立 profile 先运行新测试，确认旧界面因按钮缺失、说明默认可见而失败；改动后 `test_mingqi_manual.gd` 通过，覆盖开关、完整说明、释放布局空间、面板切换、快照及 generation 重建、无命令发送。
- 独立 profile 回归：`test_mingqi_ui.gd` 195 项、`test_mingqi_file_dialog.gd` 10 项、`test_mingqi_scene.gd` 18 项均 0 失败；`test_mingqi_rules.gd` source golden PASS。仅验证无窗口控件和夹具，真实 GPU 画面及输入由统一验收另行验证。
