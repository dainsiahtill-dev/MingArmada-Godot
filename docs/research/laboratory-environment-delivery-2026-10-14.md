# 环境实验室与水岸融合交付

本轮把海面、岸浪、天气云影三篇论文接成独立Godot实验，沿用首页“实验室”。连同已有船体水沫共四个可运行课题；阴影边索引仍是论文。当前交付包含统一因子控件、暂停单步、同条件重置、真实截图与状态导出。

## 用户本轮视觉要求

沙滩与水面的硬线来自二值干地裁切和全覆盖水色；旧shore transition只调整颜色。新共用水面材质在接岸处将完成的海水颜色与同像素、未折射的不透明场景做线性合成，岛和水的ALPHA仍为1，避免改变现有透明排序。真实地形、五波、推进浪算法、船尾和3D船员没有更换。

随后按用户连续修正扩大融合范围：默认 `shore_edge_feather_m=0.6`，`shore_edge_water_weight=0.55`。目标是图中垂直岸线方向、岸浪推进后消散的带，而不是海浪上下起伏或整海透明度。宽度参数是用于映射这条水平过渡带的垂直地形高差；平坡会有更宽水平范围，不能宣称各处恰好同米数。覆盖率的两端保持0与1，过渡中间水色更透；外侧coverage1的浪头保持原效果。

可以在实验室“沿岸推进浪与残沫的融合”选择“俯视水岸交界”，将宽度设0查看原硬边；同宽度下将“贴岸水色覆盖”设1查看降低覆盖前的效果。当前0.55不是整海固定alpha。

## 新实验与宿主

- 海面：近／中／低位远景，柔化／旧镜面响应、真实平面镜像、折射和细节强度，同一32Hz接受时间对照。
- 岸浪：真实厦门257×257三角地形与原生产海水，解析推进浪、源短浪、残沫/接触花边分别控制。三个因素保留真实生产耦合，不伪称物理独立。
- 天气：原天气中心、天空云环和纹理云影；观察面标注为5m诊断网格，原模型尺度和源状态保持。预设重建会重新对准该初态天气中心，保留用户相对orbit/zoom。
- 宿主：参数按课题隔离；暂停后单步1/32秒；普通重置保留镜头；暂停resize同刻刷新投影；等待截图时切换参数会取消旧截图。

## 实测与证据

证据根目录：`docs/research/evidence/laboratory-environment-2026-10-14/`。初次失败、候选和最终记录并存，没有覆盖旧实验室交付。

- `final/regressions.json`：9个实验室脚本、509断言，全部通过。
- `final/coverage-tests.json`：真实shader纯函数、局部覆盖和实际Ocean合同254断言通过。以上10个独立脚本共763断言，严格检查退出码、唯一完成标记及Godot错误。
- `final/GPU_VERIFY.json` 与 `final/gpu-run.json`：实际普通主菜单进入／退出，44组原场景PNG和UI图，完整快照、参数、镜头、viewport、接受时间、资源与源码散列。存档与设置字节保持。
- `feather-wide-study/GPU_VERIFY.json`：0/0.5/2/8秒、edge/close/9m低位，24张同刻0对0.6图；32组交替帧间隔，40帧预热。原样保留低位失败。
- `feather-wide-study/PIXEL_ANALYSIS.json`：探索性RGB跳变指标约为原边界的22%–25%。ROI由baseline固定带内峰值选择，**不是预注册冻结ROI确认实验**。四个时间点的下半帧完全相同，不能扩展为所有海域证明。
- `final/WEIGHT_PIXEL_ANALYSIS.json`：同宽度0.6，weight1对0.55仅在该镜头接岸带改变65,739像素；最大RGB通道差5/255，下半帧完全相同。
- `production/GPU_VERIFY.json` 与 `production/run-verified.json`：通过既有普通海岛实景入口，真实共用世界中的码头、岩石、植被及船舶组件保留；4张近／远同刻A/B，返回主菜单。不是完整自由试航性能验收。
- `final/PACK_VERIFY.json` 与 `final/pack-run.json`：从空工作目录只加载导出PCK，实际菜单进入四个实验、单步、释放，并读取五篇内置论文；29项检查通过，唯一完成标记与严格错误扫描通过。

`DELIVERY_VERIFY.json`最终120项交付校验通过，当前GPU源码、原PNG/状态、包内论文散列均吻合；`review.html`提供同镜头滑杆与时序查看。

平台为Godot4.7.2、Vulkan Forward+、Intel Arc130T。32组交替wall-frame p95：原硬边17.219ms，当前候选17.640ms，约+2.4%，在预设+10%局部门槛内。包含桌面调度/VSync，既不是GPU计时，也不证明正式航行达到60FPS。电源策略与其他程序负载未隔离。

## 保留的问题与边界

1. 极低机位仍能看到原投影网格的大面片及近处裁切；0宽度基线也存在。本轮仅解决普通近景水岸融合，**低位整体观感未通过**。
2. 共用世界远景中已有的浅滩大色块、岛形细节及船上方细线仍可在原帧看到；未以羽化宣称全部场景美术修复。
3. 斜视辅助垂直厚度使用view-Z差乘视线Y的近似；真实地形接触带限制影响范围。任意坡度、独立沙洲、全部透明喷雾/人物遮挡与其他GPU后端未穷尽。
4. 天气近景是中心0首2秒固定观察窗口，不是完整天气系统的最终美术；网格只用于观察原云影。
5. 上轮全仓229脚本审计的8项异常未重跑或宣称解决；本轮采用受影响检查。仅vegetation那一项当时有未改HEAD对照，不能把8项全部标成已证实旧问题。
6. 首次production运行有一次解析错误、一次exit0但没有完成标记，均不算成功；最终通过以`run-verified.json`和4张实际原帧为准。GPU夹具的头几次失败和宿主旧缓存镜头故障也保留。

## 复现与回退

```powershell
rtk proxy node tools/verify-godot.mjs --filter laboratory --output Temp/research/lab-new-run.json
rtk proxy node tools/verify-godot.mjs --filter shore_edge_coverage --output Temp/research/edge-new-run.json
rtk proxy node tools/run-research-proof.mjs Temp/research/gpu-new-run.json '["--path",".","--script","res://tools/verify-laboratory-environment-gpu.gd","--","--output=res://Temp/research/gpu-new-run"]'
```

重复采集换新目录。`run-research-proof.mjs`保留全部stdout/stderr并要求对应GPU／pack唯一完成标记。`analyze-shore-feather.py`需要Pillow与NumPy，仅分析原PNG，不修图。

回退局部水岸候选只需将共用shader `shore_edge_feather_m` 设0；weight设1可仅回退本次更透明曲线。无需重建地形、改尾迹或改存档。后续继续按七段论文、单因素对照、原帧与范围说明工作。
