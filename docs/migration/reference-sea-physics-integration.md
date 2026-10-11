# 正式海面整合：物理与水面合同

本轮将已经验证的 Godot 海岛、水面表达接入正式航海与海战场景。物理部分保留现有五波、船体水线、操船参数及存档形状；四组 Gerstner 波的精确参考场景继续独立保留。

## 权威与传递路径

- `modules/contracts/wave_descriptor.gd` 提供原五波的普通数据描述；没有从物理模块导入渲染模块。
- `game/runtime/{mingqi,legacy,naval_practice,visual_qa}_runtime.gd` 向 Encounter 注入 `CoastalWaveField` 与原五波描述。Encounter 的 tick 决定物理时间，`SailingSimulation.render_snapshot()` 提供同一时间区间的插值时刻。
- `ShipDynamics` 的四个船体探针从 Encounter 的同一水面采样；船舶展示直接使用物理位置，没有另加船体 Y 偏移。
- `NavalWorldView` 把 runtime 的 `sample_water_height(x,z,time)` 注入尾迹、炮弹落水与船员 Jolt 击飞；展示中的海面消费传入的 snapshot 时间。

正式海面高度继续采用 `Σ A·sin(kx·x+kz·z+ω·t)`。浅海采用 `smoothstep(0,8,-terrainHeight)` 衰减。岸线 RF 纹理的采样映射由海面整合实现处理；本报告不声称离散纹理插值与连续地形函数在任意点完全相等。

## 修复

先复现了两项合同缺口：共享描述允许零方向，而 GPU 拒绝；CPU 波场不能接受 GPU 所用的同一自定义描述。

`WaveField.configure(descriptors)` 现在校验并复制普通数据，在双精度标量中归一化方向、计算波数。`CoastalWaveField.configure(height_sampler, descriptors)` 以原子方式接收地形与波场；无效输入保留原配置。显式空数组代表平静海面。未调用配置以及传入原描述均保留原五波的精确累加顺序，避免从波长重建波数引入舍入变化。

本轮不调整默认振幅、频率、方向、时间、浮力、水线，也不实现性能优化。

## 直接验证

`tests/test_sea_physics_integration.gd` 在 Godot 4.7.2 / Jolt Physics 中实际运行：

| 验证内容 | 证据 |
| --- | --- |
| 红灯复现 | 初始 4,369 项检查中 2 项失败，分别为零方向验证及 CPU 配置缺口；其余实际运行时检查通过 |
| 修复后新合同检查 | 4,457 项检查，0 失败，退出码 0 |
| 默认浮力 | 实际航行练习的福船、商船、渔船运行 240 个 tick；每船四角探针等于 runtime 相同时刻的水面采样 |
| 船舶水线 | 上述三艘健康船的中心甲板始终在当前波面之上；没有额外渲染 Y 偏移。该检查不替代所有海况、甲板边缘及受损沉船验收 |
| 时间 | 暂停、无效负时间与非有限时间保持状态；渲染插值显式按插值时间采样，没有隐含墙钟 |
| 船尾泡沫 | 实际历史尾迹生成 ArrayMesh；所有顶点等于相同水面加 0.10m 的效果面偏移；暂停不重建，逆时清除旧历史 |
| Jolt 入水 | 实际 RigidBody3D `_integrate_forces` 采样前后接受时刻，形成 water 接触；暂停后无后续水面采样或墙钟漂移 |

补充回归均退出 0，无错误：

| 测试 | 断言数 |
| --- | ---: |
| `test_coastal_waves` | 1,090 |
| `test_wave_height_fast_path` | 17,845 |
| `test_wave_uniforms` | 8 |
| `test_ship_physics` | 16,557 |
| `test_naval_invariants` | 72 |
| `test_reference_demo_ocean` | 3,249 |
| `test_layer_boundaries` | 16 |

新测试与上述回归合计 **43,294 项检查，0 失败**。原船舶数学 24 条轨迹、215 个记录帧对照最大误差 `0.00000000001455`。全项目 runner 与最终原生 GPU 截图由主 Agent 在场景整合结束后执行；这些局部检查不宣称全项目或最终画面已经验收。

运行新检查：

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_sea_physics_integration.gd
```
