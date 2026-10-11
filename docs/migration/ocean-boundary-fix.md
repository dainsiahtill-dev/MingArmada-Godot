# 深海三角色块：根因与原生截图验收

2026-10-11。检查范围为固定岸浪镜头中的深海色块；不重新设计海面、不改变原五波位移或船舶物理。

## 根因证据

修复前亲自查看 `shore-wave-71.png`，左上出现一条从屏幕顶部约 `(346, 0)` 到左缘约 `(0, 383)` 的直线色块边界。它是流式海床窗口的外缘，经过半透明深海透色后的结果。

`world_view.gd::_update_window()` 以 `floor(focus.x / 250)` 更新半径 2 的地形窗口。捕获流程先 `_present()`，仍以旗舰位置更新地形，再将相机固定到 `(-480, 270, 185)`、朝向 `(-480, 0, -60)`。因此固定相机不等于固定海床窗口。

| 帧 | 旗舰 X | 地形中心 X | 海床窗口左缘 X |
|---|---:|---:|---:|
| 00 | -265.0186 | -2 | -1125 |
| 24 | -260.1758 | -2 | -1125 |
| 48 | -254.9775 | -2 | -1125 |
| 71 | -249.8475 | -1 | -875 |

独立 headless CPU 相机投影将海床 `Y=-24` 边界映射为：

| 边界 | 顶部交点 X | 左缘交点 Y |
|---|---:|---:|
| X=-1125 | 58.9610 | 39.9935 |
| X=-875 | **346.1854** | **383.4390** |

后一组严格吻合修复前 71 帧的大三角。诊断脚本为忽略的 `build/verification/ocean_boundary_diagnostic.gd`，正常 headless 运行退出 0。CodeGraph 未索引此项目，源码链路使用 RTK 只读检查确认。

## 最小修复

Root 仅调整 `original_water.gdshader` 中 style 1 的透明度：

```glsl
// Before
output_alpha = clamp(0.95 - bottom_visibility * 0.17
    + fresnel * 0.07 + shore_foam * 0.22, 0.0, 1.0);
// After
output_alpha = clamp(1.0 - bottom_visibility * 0.22
    + fresnel * 0.07 + shore_foam * 0.22, 0.0, 1.0);
```

深海 `bottom_visibility=0` 时透明度为 1，海床或天空背景不会透入；最浅海 `bottom_visibility=1` 时基础透明度仍为 .78。style 0、原五波顶点位移及物理采样不变。该处水材质本已 `unshaded, shadows_disabled`，无需关闭场景阴影。深海位置的岸浪区域为零，岸浪函数也无需改动。

## 实际视觉验收

Root 使用相同相机与模拟时间重新捕获 72 帧。审阅者亲自打开新的 00、24、48、71 四张原生截图：**此前左上直线三角边界已消失**，71 帧在地形窗口跨界后仍为连续深海颜色；00/24/48 未出现同类边界。岸边薄浪线和青绿色浅水仍可见。

| 当前截图 | 模拟时间 | Native tick |
|---|---:|---:|
| [00](evidence/mingqi/shore-wave-00.png) | 5.0833 s | 305 |
| [24](evidence/mingqi/shore-wave-24.png) | 7.0833 s | 425 |
| [48](evidence/mingqi/shore-wave-48.png) | 9.0833 s | 545 |
| [71](evidence/mingqi/shore-wave-71.png) | 11.0000 s | 660 |

截图元数据记录 Godot `4.7.2-stable (official)`，GPU 为 `Intel(R) Arc(TM) 130T GPU (16GB)`，镜头位置均为 `[-480,270,185]`。当前 71 帧 PNG SHA-256：`b266f925bc761e848be1f64d84152245ae07b50d6c6ad414cc2dcd8a22b70bc4`。

此次重拍同时包含水面纹理通过 ResourceLoader 加载的发布兼容改动，不能将所有纹理细节差异归因于透明度这一行。修复前 PNG 已被同名重拍覆盖，前态证据为之前亲看截图及精确 CPU 投影记录；本文不提供虚构的像素级差异指标。这是该镜头、四个时间点的真实视觉通过结论，未额外启动 GPU、运行全量测试或验证性能。
