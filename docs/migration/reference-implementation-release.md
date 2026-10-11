# 海战参考改进：Windows Release 与独立 PCK 验收

> 最新状态：用户要求直接移植学习 demo 中的算法，产品源码将继续调整。本轮新的 `sample_height` 包探针与隔离启动器已冻结，并完成语法检查；**尚未再次导出或执行新的 PCK 探针**。以下 `2026-10-11T12:12:43.605Z` 导出与 517 项验收属于此前发布包，不能代表后续算法移植。等待新 port source-ready 后，重新导出、运行包验证并替换本报告。未运行 GPU、full runner 或性能测试。

已准备下一轮包外启动器：`C:/Users/dains/Documents/Git/ming-armada/build/tools/run-reference-pack-probe.mjs`。默认 `rtk proxy node build/tools/run-reference-pack-probe.mjs` 使用编辑器 headless；主线程之后可执行 `rtk proxy node build/tools/run-reference-pack-probe.mjs --gpu` 使用实际发布 EXE。两者共用 `build/pack-probe-reference-implementation-empty-20261011` 空 cwd，用户数据分别隔离到 `build/pack-probe-reference-implementation-profile/headless/{roaming,local}` 与 `.../gpu/{roaming,local}`。GPU 图像与证明单独写入 `docs/migration/evidence/reference-implementation/release-gpu`，不会冒充本轮已执行结果。

2026-10-11，本轮源代码冻结后重新执行 Windows release 导出，随后在**不含项目文件的独立空目录**中，用官方 Godot 编辑器加载生成的 PCK，运行 PCK 外部的验收脚本。未启动 Windows EXE 或 GUI，未测 GPU 画面/性能，未提交或推送。

## 新导出结果

`rtk proxy node tools/export-windows.mjs` 实际退出码 0，导出完成时间 `2026-10-11T12:12:43.605Z`。导出日志重新检查无 `SCRIPT ERROR`、`ERROR` 或 `WARNING`。

| 文件 | 大小（bytes） | SHA256 |
|---|---:|---|
| [MingArmada.exe](C:/Users/dains/Documents/Git/ming-armada/build/windows/MingArmada.exe) | 109,168,640 | `3d19ee4a764e8bb153bfa7f811f98e0dfb0139c9e0c8bc6b76b93d3ed09185bf` |
| [MingArmada.pck](C:/Users/dains/Documents/Git/ming-armada/build/windows/MingArmada.pck) | 49,773,484 | `db81e180f682b11de26bea52b72b18a67e4d307a55f4a194a0b430792e4a9915` |

证据：[导出清单](C:/Users/dains/Documents/Git/ming-armada/build/windows-export.json)、[导出日志](C:/Users/dains/Documents/Git/ming-armada/build/export-release.log)。该导出工具的 stage 仍为 `exported-not-yet-runtime-accepted`，因为工具本身只证明导出和文件哈希；下面的独立验证另行补充 PCK 运行资源证据，没有把工具字段改成更宽泛结论。

## 独立 PCK 探针

从以下目录启动，启动前和结束后均确认目录完全为空，没有 `project.godot`：

`C:/Users/dains/Documents/Git/ming-armada/build/pack-probe-reference-implementation-empty-20261011`

使用独立 APPDATA/LOCALAPPDATA：

`C:/Users/dains/Documents/Git/ming-armada/build/pack-probe-reference-implementation-profile/{roaming,local}`

实际执行命令（工作目录为上述空目录；环境使用上述隔离路径）：

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --main-pack C:/Users/dains/Documents/Git/ming-armada/build/windows/MingArmada.pck --script C:/Users/dains/Documents/Git/ming-armada/tools/migration/verify_pack.gd -- --pack=C:/Users/dains/Documents/Git/ming-armada/build/windows/MingArmada.pck --proof=C:/Users/dains/Documents/Git/ming-armada/docs/migration/evidence/reference-implementation/pack-verification.json
```

实际结果：**`PACK_RESOURCE_PROBE_PASS assertions=517 resources=26 models=21 failures=0`，退出码 0。** 独立复读日志无 `SCRIPT ERROR`、`ERROR` 或 `WARNING`。PCK 运行记录中的 packSha256 与导出文件新哈希相同。

| 验收内容 | 实际证据与范围 |
|---|---|
| 隔离性 | `res://project.binary` 存在，`res://project.godot` 不存在；空 cwd 没有松散工程；配置名与主场景由 PCK 读取 |
| 资源与模型 | JSON 直接读取、21 个 GLB native resource 实例化，ID collation 与一帧真实 NavalEncounter 执行；原有文档/测试/工具排除检查通过 |
| 动态损伤纹理 | 11 张 PNG 经 PCK ResourceLoader 真正加载；原 PNG 均未以松散文件存在，使用导出 remap/native texture。11 次 ShaderMaterial 绑定能力与 11 次实际 presenter 档位绑定，共 22 条绑定记录全部通过 |
| 损伤范围 | 实际动态加载 cache 为 11；船体检查 0/20/40/60/80/100，帆 subtype0 检查 0/20/40/60/80，零档恢复默认材质。`sail100` 检查可加载/可绑定，不声称默认 subtype0 会显示此档 |
| 新水效果纹理 | 4 张新 PNG 真正从 PCK 加载；实体水柱、伞壳、世界飞滴、弱雾、历史尾迹的实际 presenter 绑定共 5 条，全部通过 |
| 新场景资源 | detailed terrain shader、optics shader、optics helper、splash-volume shader 均作为 native resource 加载；逆投影 helper 实际执行数学往返检查 |
| 产品入口 | 发出实际默认菜单的 1650 按钮信号，进入 MingqiScene；权威状态就绪、厦门开局、五艘船、旗舰模型与甲板船员、真实相机均已挂载 |
| 岛屿与地形 | 产品入口实际建立 49 个近景地形块、2 个远景地形块、1040 个岛屿细节实例；当时可见 65 组批次 |
| 光学 | 真实入口为 balanced，屏幕空间反射 16 步，折射启用；相机有效，实际 ocean material 选择 optics shader；0 私有世界/0 离屏目标，原五波仍保留 |
| 时钟同步 | 由实际 MingqiRuntime 额外推进 1/60 秒，时间从约 0.0666667 到 0.0833333；所有近/远景 detailed terrain、海面、实际船损伤、尾迹、炮战特效和岛细节的时钟与权威一致 |
| 暂停与释放 | player pause 后请求推进 0.2 秒，实际 consumed=0，权威快照完全相同，各表现时钟仍一致；菜单与进入的场景随后释放 |

证据：[PCK 验收 JSON](C:/Users/dains/Documents/Git/ming-armada/docs/migration/evidence/reference-implementation/pack-verification.json)、[PCK 验收日志](C:/Users/dains/Documents/Git/ming-armada/docs/migration/evidence/reference-implementation/pack-verification.log)、[外部探针](C:/Users/dains/Documents/Git/ming-armada/tools/migration/verify_pack.gd)。

## 范围与复核哈希

本报告证明新 EXE/PCK 已生成、PCK 可独立提供所需运行资源，并完成真实菜单路由和 headless 权威/表现集成检查。它**不证明 Windows EXE 已启动、GPU shader 编译/画面已验收或性能达标**；这些由主线程单独记录。没有把 source PNG 哈希一致替代 PCK 动态加载，也没有把 headless 材质参数检查当作 GPU 像素。

- 外部探针 SHA256：`fd9d157158ec13dd59159101d6874f9c56a86d1070244f90e2204ab2416c40e7`
- 本轮 PCK 验收 JSON SHA256：`3170e643484870ccd20bea37ac46fc121bd59ef9e8fd46bead99de214dfe9f2d`

本子任务只修改 `tools/migration/verify_pack.gd` 并新增本报告；导出工具与探针按授权生成 build 和本轮证据。未改产品实现源码、原网页工程或参考目录，未删除用户文件或旧 build 目录，未运行全套 runner/GUI/性能测试。
