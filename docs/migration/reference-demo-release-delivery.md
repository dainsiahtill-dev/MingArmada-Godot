# 海岛与海面：Windows 原生交付

2026-10-11。本阶段按当前顺序交付海岛与海面预览；粒子与航海玩法仍由后续阶段处理。

当前 Windows Release 已从最终冻结代码重新导出，并用实际 `MingArmada.exe` 启动、保存原生 GPU 画面。最新导出时间为 `2026-10-11T13:05:54.323Z`，包含入口截图协程的取消/释放保护。

## 打开方式

当前机器双击 [Launch-IslandWater.cmd](C:/Users/dains/Documents/Git/ming-armada/build/windows/Launch-IslandWater.cmd)，会校验当前 EXE/PCK 哈希，经正常主菜单路由直接进入海岛与海面。运行使用项目现有 RTK；不启动 Godot 编辑器或浏览器。

也可以双击 [MingArmada.exe](C:/Users/dains/Documents/Git/ming-armada/build/windows/MingArmada.exe)，在主菜单选择“海岛与海面”。这两个入口使用同一个导出包。EXE 与旁边的 `MingArmada.pck` 需要一起保留。

预览操作：拖动旋转、滚轮缩放；右栏切换晴天/夕阳/风浪，调节波浪强度、潮位和泡沫宽度，分别开关波浪、反射、岸线泡沫和浅海焦散。空格暂停，Esc 返回主菜单；“保存画面 PNG”使用已有原生视口保存接口。

当前仅留给用户一扇本阶段原生预览窗口，PID `14176`，验收时标题“海上明旗 · 海岛与海面”、`Responding=true`。未关闭其它 Godot 编辑器。

## 当前包与运行证据

| 文件 | 大小 | SHA256 |
| --- | ---: | --- |
| MingArmada.exe | 109,168,640 B | `3d19ee4a764e8bb153bfa7f811f98e0dfb0139c9e0c8bc6b76b93d3ed09185bf` |
| MingArmada.pck | 49,885,764 B | `15a213bd0453b9f77632d52b3b5d6b35336aa34568a37c0066d5bf1e8bba0940` |

导出退出码为 0，日志无 `SCRIPT ERROR`/`ERROR`。[导出记录](C:/Users/dains/Documents/Git/ming-armada/build/windows-export.json) 包含上述文件以及启动脚本、14 份海岛海面源码/数据的散列。启动脚本的 `-VerifyOnly` 当前验证通过。

验收明确分成两个运行路径：

- **实际 Windows EXE**：通过已校验的启动脚本传入正常用户参数 `-- --water-study --water-study-capture=<absolute PNG>`。主入口触发真实菜单按钮，等待 staged/router 场景就绪后调用已有 `save_frame`。日志 `ISLAND_WATER_STARTUP_CAPTURE failures=0`，保存 1242×758 原生 GPU 视口 PNG。交付校验 **32 项、0 失败**，包括当前包/源码散列、进程路径、响应与标题、当前导出之后的新 PNG、日志、菜单路由和非递归平面反射合同。
- **编辑器执行当前 Release PCK**：从空工作目录，以编辑器 GPU 可执行程序明确加载当前 PCK，运行外部探针。**54 项、0 失败**，验证包内原始高度 JSON、模型/Shader、真实菜单进入/返回、潮位与反射/夕阳控件及无存档写入；4 组状态各保存视口和界面，共 8 张 PNG。工作目录始终为空，日志无引擎或脚本错误。这条路径单独报告，没有冒充 Release EXE。

本次真实 Release 画面已亲自查看；PCK 的晴天、反射关闭、高潮位和夕阳界面也已亲自检查。Cat Island 形状、浅水颜色、动态岸线白浪、焦散与潮位导致的岸线变化正常，未见缺材质、白色方块或递归反射反馈。

![实际 Windows Release EXE 海岛海面](C:/Users/dains/Documents/Git/ming-armada/build/reference-demo-release/native-release/clear.png)

完整本阶段证据：

- [交付校验](C:/Users/dains/Documents/Git/ming-armada/build/reference-demo-release/native-release/launch-verification.json)
- [实际 EXE 截图元数据](C:/Users/dains/Documents/Git/ming-armada/build/reference-demo-release/native-release/clear.png.json)
- [实际 EXE 输出](C:/Users/dains/Documents/Git/ming-armada/build/reference-demo-release/native-release/clear.png.stdout.log) 与 [错误日志](C:/Users/dains/Documents/Git/ming-armada/build/reference-demo-release/native-release/clear.png.stderr.log)
- [PCK 探针运行记录](C:/Users/dains/Documents/Git/ming-armada/build/reference-demo-release/pack-gpu/release-launch.json) 与 [54 项探针细节](C:/Users/dains/Documents/Git/ming-armada/build/reference-demo-release/pack-gpu/release-verification.json)

## 复现交付验证

从 Godot 项目目录执行：

```powershell
rtk proxy node tools/export-windows.mjs
rtk proxy powershell -NoProfile -File build/windows/Launch-IslandWater.ps1 -VerifyOnly
rtk proxy node build/tools/run-reference-demo-release.mjs
rtk proxy powershell -NoProfile -File build/windows/Launch-IslandWater.ps1 -CapturePath C:/Users/dains/Documents/Git/ming-armada/build/reference-demo-release/native-release/clear.png -PassThru
```

等待实际 EXE 的 PNG 与 `.json` 保存后，使用启动脚本返回的当次 PID：

```powershell
rtk proxy node build/tools/finalize-reference-demo-delivery.mjs 14176
```

上述 PID 是本次记录，重跑时替换为新的 PID。实际 Release 会继续运行，供用户观察动态海面。

## 已修正的交付路径

本机官方 Release 模板禁止 `--main-pack` 路径覆盖，并忽略外部 `--script` 启动覆盖。最初尝试的真实失败记录仍保留在 `build/reference-demo-release/evidence/`；当前用户入口使用正常用户参数与包内主菜单路由。前一版取消保护修复之前的实际 EXE 截图单独保留在 `build/reference-demo-release/native-release-before-capture-guard/`，不作为当前包通过证据。

本报告验证的是本阶段原生预览与打包路径。没有开展 FPS 验收，也未宣称原游戏与 Godot 像素完全一致。原算法与 Shader 的详细移植说明见同目录的海岛/海面技术报告。
