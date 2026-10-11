# 精确海面高度快路：正确性收尾

2026-10-11，Godot 4.7.2 stable official `ed1daf0bf`。用户现已要求优先完成画面和玩法效果；本项保留已完成、数值不变的改动，停止进一步性能分析、优化和帧率测试。

## 完成的改动

- `modules/physics_engine/ocean/wave_field.gd` 新增 `sample_height(x, z, accepted_time)`。逐项保留原五组波浪的双精度相位、正弦值和累加顺序；仅省去调用者不使用的余弦导数、向量和结果字典。
- `modules/physics_engine/ocean/coastal_wave_field.gd` 新增同名接口。只查询中心地形高度，保留八米深度边界、三次衰减、陆地零高度及无效/非有限地形的原始波浪退路。完整 `sample()` 的四个地形梯度查询、梯度和法线计算保持原样。
- `sailing_runtime.gd`、`legacy_runtime.gd`、`mingqi_runtime.gd`、`naval_practice_runtime.gd`、`visual_qa_runtime.gd` 的 `sample_water_height()` 调用新接口。原 accepted time、Legacy 默认时间及未配置时的 `NAN`/零值退路保持原样。

本项不改变五组波系数、波高、CPU/GPU 水位合同、画质、地形、尾迹几何、暂停时钟、反射或折射设置。现有需要梯度/法线的物理消费者继续使用完整 `sample()`。

## 验证

新测试 `tests/test_wave_height_fast_path.gd` 先验证缺失接口和旧 runtime 路由：RED 为 17 项断言、7 项失败。实现后 GREEN 为 **17,845 项断言、0 失败**，包括：

- 48 项冻结海面样本，以及新旧高度严格 `==`；冻结外部数值容差为 `1e-12`。
- 164 组坐标、九个地形深度、六个 accepted time。坐标保存在标量数组中，保留 GDScript `float` 的双精度；覆盖十亿量级含小数坐标、微小坐标、随机海域点和较大时间。
- 离岸、浅水、陆地、`NAN`/正负 `INF` 地形；空及已释放对象的 Callable 退路。
- Terrain spy：浅水完整采样保持 **5 次**查询，高度接口为 **1 次**查询；返回高度严格相等。
- 高度调用前后完整 `height/gradient/normal` 字典相等；五个 runtime 的 spy 证明只调用标量接口，并原样传递 accepted time。

已有 focused 回归均退出 0，总计 **18,078 项断言、0 失败**：

| 测试 | 断言 |
| --- | ---: |
| `test_coastal_waves.gd` | 1,090 |
| `test_wave_uniforms.gd` | 8 |
| `test_reference_surface_optics.gd` | 122 |
| `test_sailing_runtime.gd` | 13 |
| `test_mingqi_runtime.gd` | 12 |
| `test_visual_qa_runtime.gd` | 133 |
| `test_legacy_runtime.gd` | 123 |
| `test_ship_physics.gd` | 16,557 |
| `test_naval_world_view.gd` | 20 |

船舶原始参照回归最大误差仍为 `0.00000000001455`。本项新旧海面标量比较没有误差。

## 证据边界

此前主验收的真实 fleet wrapper 记录为 309 帧/20.047 秒、973,470 次 water 调用总计 4.912 秒，另有同数 filter 调用总计 2.432 秒；这是启动本项工作的原有诊断证据，不能作为修改后的帧率证明。

在停止性能工作的指示到达前，一次短 headless CPU 微测已结束，保留在 `Temp/reference_wave_height_microprobe.gd`。每组 20,000 次、三个 trial，使用固定地形 Callable，新旧校验和均严格相等。离岸旧接口为 2.047–2.181 µs/次，新接口为 1.219–1.343 µs/次；浅水为 3.325–3.845 与 1.298–1.533 µs/次；陆地为 2.506–2.543 与 1.234–1.300 µs/次。它没有真实地形、GPU、上传、船队呈现或帧率含义，不再继续测试。

本项未运行 GPU、完整测试 runner、游戏 benchmark，也不声称整体性能已经改善。后续由主验收流程检查功能与真实画面效果。
