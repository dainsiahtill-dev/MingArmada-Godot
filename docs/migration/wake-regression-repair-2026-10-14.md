# Godot 尾迹退化修复与实际画面验收

本轮修复船两侧不透明白垫、旧尾迹几何、停船补发水花、静止升沉生成航迹、尾迹末端硬截面，以及正式低画质入口的海面深度裁切。参考最新 `weather-cloud-shadow-wake-native-continuation-20261013`，没有继续派发逆向任务，也没有使用被撤回的原版实玩报告校准效果。

## 根因与修改

1. **首／侧沫 RGBA 丢失。** 侧沫每族150个顶点中82个alpha=0；船首30个顶点中18个alpha=0。旧迁移回退到统一材质alpha=1，直接暴露网格轮廓。Compiler保留源RGBA与材质模式，froth消费者上传原顶点色及材质/controller alpha，保留粒子独立颜色路径。没有整体降低白沫透明度。
2. **旧尾迹仍是自制几何。** 按最新正常有限原缓冲恢复单段方向、头部外推、原A=B修补、inactive左右顶点复制和UV保留。固定62项source buffer，实际draw最多58顶点；原首次非有限域明确拒绝GPU。冻结原CPU夹具与Godot位置对照最大误差0，不代表任意x87输入逐位等价。
3. **停航冻结粒子计时。** 原目标引擎恢复时补算停航9.1秒出生，requested从14跳到155。现在只停止新出生，推进旧水滴寿命和controller；真实池到t10退场，恢复t10.1仍为14次请求，t10.3正常新生3滴。这是本作出生门，并非声称恢复475550原生命周期。
4. **6DOF表现污染航行历史。** 实际停稳后的5次假采样，水平变化0.00002～0.0115m，升沉0.432～0.466m跨过0.42707m距离门。scene30改用同一真实Dummy_Wake/model.transform的yaw和水平轨迹，低速假采样降到0。船身浮动、3D甲板人物、raw首／侧沫挂点及海战90历史输入保留。
5. **GPU末端硬边。** 原贴图粗mip侧缘alpha可达0.1333，最后源行alpha仍为0.0667。scene专用shader只羽化两侧6%边缘和最后三段，保留源纹理、RGB与主体原alpha。独立复审捕获inactive尾UV选错的P2；现按可见原alpha寻找实际末端，真实inactive原fixture红2失败→绿0。
6. **正式融合海水裁切宽尾迹。** 正常菜单进入自由试航、低画质、1069×600窗口中，Computer Use复现规则三角齿。原先均衡画质QA没有覆盖这一配置。实际路径是 `projected_ocean.gd` 的 `REFERENCE_GAME_SHADER`，即 `reference_game_water.gdshader`，在透明pass写深度；并非旧 `original_water_body` 的不写深度路径。宽尾迹和投影水网格的三角曲面不同，相交部分被裁掉。SceneStrip现在绕过透明海水的硬件深度，使用opaque-pass深度副本反投影作0.08m接触淡出，仍由船壳和陆地遮挡。原位置、宽度、UV、alpha缓冲不变；其他粒子和纹理影材质不变。这是Godot表面叠层适配。相关透明管线合同见[Godot 4.7 Spatial shaders](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html)。

## 前五项修复的配对记录（均衡画质）

`tools/verify-wake-production-gpu.gd` 使用实际自由试航场景、runtime、世界、船模型、Wakes与Forward+，固定操船命令和accepted time。修前冻结consumer限于QA进程，生产文件没有来回还原。7个配对时刻的船位、航速、航向和accepted time完全相同；输入适配差异是本轮修复的一部分。

| 观察 | 修前 | 修后 |
|---|---|---|
| 直航12秒 | [白垫问题](evidence/wake-regression-2026-10-14/before/gpu/03-straight-12s.png) | [原透明边缘恢复](evidence/wake-regression-2026-10-14/final/gpu/03-straight-12s.png) |
| 转向5秒 | [旧表现](evidence/wake-regression-2026-10-14/before/gpu/04-turn-5s.png) | [当前表现](evidence/wake-regression-2026-10-14/final/gpu/04-turn-5s.png) |
| 停船10秒 | [旧表现](evidence/wake-regression-2026-10-14/before/gpu/06-stopped-10s.png) | [附着白沫停止／旧水滴回收](evidence/wake-regression-2026-10-14/final/gpu/06-stopped-10s.png) |
| 再起航5秒 | [旧表现](evidence/wake-regression-2026-10-14/before/gpu/07-resume-5s.png) | [当前衔接与末端](evidence/wake-regression-2026-10-14/final/gpu/07-resume-5s.png) |

中间分层截图保存在`isolate/gpu/08..10`，确认扇形来自SceneStrip，而非已修首侧沫或水滴。最后参数选择修复仅改变短inactive前缀；7个正式场景时刻全active／全不可见时参数与最终代码一致，独立复审确认。

这组记录拍摄于第6项深度适配之前，用于核对前五项根因修复，不能替代下列最终低画质验收。

## 正式低画质入口追加验收

`tools/verify-wake-production-occlusion-gpu.gd` 使用自然 `_process`／`_physics_process`、正常船速、实际viewport鼠标投影、原窗口比例和低画质，捕捉4／12／24／40／60秒。随后冻结同一帧，依次显示最终材质、旧硬件深度处理、恢复最终材质，三份船位与accepted time完全一致。8份记录无错误，以下同帧对照直接显示被海水裁掉的尾迹恢复：

| 同一帧 | 截图 |
|---|---|
| 原硬件深度处理 | [海面截掉尾迹](evidence/wake-regression-2026-10-14/final-low/gpu/02-hardware-depth-original.png) |
| 修复后 | [尾迹完整、船身遮挡保留](evidence/wake-regression-2026-10-14/final-low/gpu/01-fixed.png) |
| 恢复修复材质 | [复核结果](evidence/wake-regression-2026-10-14/final-low/gpu/03-fixed-restored.png) |

原低画质现场及分层诊断保存在 `low-layers-diagnosis`，均衡画质和固定步长的未重现样本只作为排查记录，不作为现场缺陷已解决的依据。

最终再次用Computer Use从正常菜单进入自由试航，保持玩家保存的低画质并点击海面转向；约168°／6.2节现场未再出现规整三角齿，船壳遮挡保留：[修复后的实际窗口](evidence/wake-regression-2026-10-14/final/native-play/mouse-turn-fixed.jpg)。早期实际窗口问题截图也保留：[修复前的齿边](evidence/wake-regression-2026-10-14/final/native-play/mouse-turn.jpg)。两张实玩图不是同一时间、姿态的像素对照；严格同帧对照使用上述GPU冻结记录。

## 验证与边界

- 26项受影响headless回归通过；真实原缓冲、真实资源RGBA、生产packet→History、生命周期、原粒子默认路径及水面采样覆盖。没有宣称全项目所有功能已重新验收。
- 正式7张GPU截图均无source错误或非有限顶点；GPU日志无错误。
- `tools/verify-source-wake-feather-gpu.gd` 通过实际SourceSurface材质读回：修前3失败；修后中心alpha0.494、两侧0.00784，末端趋透明，有符号UV及缓存参数更新通过。该诊断使用常量纹理隔离边界响应。
- 独立审查的唯一P2已修复并新增真实fixture回归。
- `tools/verify-source-wake-occlusion-gpu.gd`：红阶段证明透明写深度的海水挡住白沫；绿阶段3项通过，海面白沫显示、前景opaque船壳遮挡、后景opaque不误遮挡。实际Forward+ GPU读回，非源码字符串断言。
- 深度适配完成后严格复跑10项直接受影响headless测试，全通过；边缘羽化GPU检查也再次通过。独立审查确认正常船壳和地形为opaque，缓存及反投影公式正确。Compatibility只审查公式，没有实际GPU验证。
- [综合回执](evidence/wake-regression-2026-10-14/DELIVERY_VERIFY.json)保存配对输入与各回归记录。没有提交、推送或覆盖用户原有修改。

本轮验收范围是已复现尾迹问题及当前Godot画面。原DX9光照／混合像素等价、完整475550生命周期与持续航行FPS仍不在本轮证明范围；停船时30环历史按原合同保留，其残留尾迹并非年龄寿命系统。截图已实际检查，但后续美术质量仍需按游戏画面逐项迭代。
