# 主角福船最终定向复审

2026-10-26。只读检查当前代码、两张实际图及对应 manifest；未修改生产文件，未启动 GPU、游戏或重跑性能。

**结论：本次所看原生帧中，健康帆上的向上船底大斜影与破碎暗斑已消除。符号修正和默认代理接线相符，可继续交给用户作最终原生画面审看；本报告不代替用户认可或整场性能结论。**

- [原生 authored 图](native-shadow-isolation-corrected-sun-a/authored.png)：HUD 为风帆100%，帆幅连续，没有失败帧中大块船底轮廓和碎斑。其 manifest 的六种隔离模式 worldLight 均为 `(-.502184,-.698182,-.510249)`，实际传播向下。
- [独立 authored 反面图](shadow-gpu-corrected-sun-a/authored-reverse.png)：不再有自船底向上覆盖帆幅的破碎阴影。仍有相邻帆、桅与索具投到低处的成片暗区；这类与上方遮挡物对应的阴影应保留，不能将“帆上任何暗区”当成失败。

## 最终代码核对

- Weather target 使用 `[-source.x,-source.z,+source.y]`，正确把源传播方向转换为 Godot towardSun；原始 `sourceLightFields` 保留。WorldView 的 `looking_at(-direction)` 和 caster 的 `-sun.basis.z` 不再另改符号。
- HeroProvider 构造参数默认 `authored_shadows=true`；art 路径以隐藏 proxy Mesh 作为模板输入，完整可见角色、真实变换、native fallback 和原材质仍保留。实验显式传入 shadows 模式，所以 native/visible 对照不会因默认开关被迫使用代理。
- Hero 实验从同一份 `sourceLightFields.lightDirection` 得到 `ray=(x,z,-y)`：legacy 使用 `looking_at(-ray)`，corrected 使用 `looking_at(ray)`。它没有读取已修正的 target 再反转，比较因子独立且语义正确。
- `configure` 先 dispose；reset 重置 time/remainder；daylight/shadows 变化要求重置；pause 阻止 advance；dispose 先释放 compositor、恢复 rigid shadow 策略，再释放 ship/world。源码顺序未见生命周期破坏。
- 实验边界：初次 compositor 尚未 initialized 时，`refresh_shadow_projection` 先保留 native fallback；stencil 状态在下一次 refresh/advance 对齐。若初始 paused 且宿主不再次刷新，它不会自行二次对齐。这是源码边界，不据此推断当前捕获存在重复阴影。

## 剩余模型观感

当前正常游戏尺度下三帆主次、厚舷墙、炮口和收束尾楼都可读，v2 的矩形帆与独立盒形尾楼已实质改善。仍有三项精修空间：细索/帆骨阴影在缩小时呈点划线，木船舷在此镜头偏暗、纹理层次不够清楚，尾横墙和舵叶仍较平直；独立图的局部帆影边缘也偏硬。这些不再是此次“船底向上遮健康帆”的故障，保留给用户审美判断，不扩展海面或岛屿工作。
