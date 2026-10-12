# 游戏海岛美术适配：平缓山丘、连片沙滩与林地

用户明确要求取参考实现的优点来改善游戏，而不是原样复刻所有示例参数。主线程真实截图的厦门显示了过高单峰、碎地块与稀疏林地；海面专家也查看了 `mingqi-island-shore.png` 和 `mingqi-shore-low.png`。本轮新增显式可选的地形美术转换，原始数据、SHA、默认 source adapter、默认旧公式及 standalone 示例都保留。

**最新分工：海岛/岸线/海面美术转交另一聊天继续。本轮仅完成定向回归与报告，源码冻结；主线程没有启用这些新 art 参数，没有新 GPU 验收或导出。以下是可交接的可选实现与 CPU 证据，不是当前游戏已经采用的画面。**

## 接口与推荐

```gdscript
HeightField.configure_ports(ports, true, {
    "reference_islands": true,
    "reference_profiles": {"xiamen":"coastal2", "kinmen":"cat_island", "forward-supply":"virgin_islands"},
    "reference_art": {
        "sea_index": 120.0,
        "height_gain": 0.28,
        "smoothing_radius": 2,
        "border_rounding": 0.15,
        "border_fade_pixels": 7.0,
    }
})
```

`ReferenceIslandProfile.configure(port, data, id, art_options={})` 同样可接受第 4 个参数。所有控制只作用于此游戏高度合同；正式场景/地图角色选项由主线程在 `reference_geography.gd` 接线。

| 控制 | 默认 | 合法范围与职责 |
| --- | ---: | --- |
| sea_index | 128 | 0–255 开区间，且必须在当前原数据 min/max 内。显式游戏海陆阈值。 |
| height_gain | 1 | >0 且 ≤1，只压低正高度；原 -24 米海底尺度保留。 |
| smoothing_radius | 0 | 整数 0–8；两轴三角权重小邻域平滑。 |
| border_rounding | 0 | 0–.45；闭合矩形的角部圆润转换。 |
| border_fade_pixels | 5 | >0 且 ≤32；边界闭合的渐变宽度。 |

默认不启用美术参数时继续使用 128/gain1/radius0/rounding0/fade5，保持现有 source adapter 精确输出；HeightField 不启用 reference 时仍运行原旧地形公式。

## 为什么这样适配

`shore-surf/source-audit/SOURCE_FIDELITY_AUDIT.md` 提供了 Cat Island 高度与原焦散几何的候选对齐：阈值 120 比演示调色板阈值 128 更接近资源零高程，但报告明确不是完全恢复的原引擎公式。本作采用 120 是美术/玩法选择，不能称为原作海平面复原；同样不把示例 `.35` 高度倍率当成原版参数。

较低阈值使源海岸和山脊之间的低地变为可用 backland、沙滩和浅滩；压低正高度避免原单峰直接被映射为 58 米尖针。半径 2 的三角权重滤波在原像素小邻域内平滑，保持源海湾和岭线关系，而不是换成圆丘噪声。

滤波一次生成缓存 `PackedFloat64Array`，原始 `PackedByteArray`、调用者 JSON 数组及文件都不改变。derived positive land 用于布局半径/朝向，原最大值仍用于高度分母，因此滤波不会重新归一化把尖峰拉回原高度。运行采样只读取缓存的四角并双线性插值。

矩形闭合采用可选 rounded-box signed distance，消除原大陆切片的硬角；核心形状和凹湾仍来自原数据。默认 rounding0 分支继续原 min-edge 公式，确保旧输出不变。这不是所有地形都改成一个椭圆。

## 码头与统一高度合同

美术参数不作用于固定局部港口 patch：停靠船体范围继续 -8 米，43–55 米栈桥末端继续 2.1–2.4 米陆平台；源海岸之外的原补给浅滩仍为 -2.4 米。地形、船舶水深、碰撞、海图与岸线 RF 继续共同使用 `sample_height()`，没有只美化画面而让物理停在旧岛形。

不正确类型、未知控制、非法值、不能形成海陆的 source 阈值均在替换接受状态前拒绝。解析与滤波结果只在全部通过后提交，不会一半参数更新、一半保留。

## 直接 CPU 证据

先运行独立 NumPy raw-index 参数探针，再用实际 Godot HeightField 在每岛 75² 世界点采样。后者包含真实 harbor/border 转换，坡度使用世界坐标 ±.5 米中心差分；森林候选为 h>1.2 且 gradient<.48，仅表示地形条件，不声称这些树已经出现在画面上。

| 实际世界探针 | 默认 source | 游戏适配 |
| --- | ---: | ---: |
| 厦门采样最高点 | 54.31 m | **13.41 m** |
| 厦门陆点 | 1179 | **1535** |
| 厦门林地候选 | 213 | **1235** |
| 厦门陆地 gradient P95 | 3.445 | **.689** |
| 金门采样最高点 / 陆点 | 31.76 m / 275 | **7.77 m / 602** |
| 金门林地候选 / gradient P95 | 75 / 3.903 | **345 / .551** |
| 补给群岛最高点 / 陆点 | 20.77 m / 499 | **4.45 m / 855** |
| 补给群岛林地候选 / gradient P95 | 227 / 4.174 | **409 / .652** |

原独立探针文件：`evidence/reference-island-profiles/art-adaptation-cpu-probe.json`。实际 Godot 结果在 `green-art-options.json` 的 `ISLAND_ART_LAND_PROBE` 行，可复算。

## 验证与边界

- 新参数最初被旧代码忽略，RED **5 assertions/3 failures**；实现后新美术测试 **226 assertions/0 failures**。
- 默认 profile/原 index 变换回归与 standalone 原 Cat 地形回归均通过，见 `green-default-profiles-after-art.json`、`green-standalone-after-art.json`。
- explicit default 144 个世界点与未传参数 profile 逐值相同；原调用者 indices 仍逐值相同。
- 原三份文件 SHA/92617 索引复验通过，未改任何原文件。

生产 source 已冻结。本轮三份定向测试共 **5663 assertions，0 failures**。后续是否采用本组选项、密林/港镇实际布局和 GPU 海岛画面由新的美术分工决定；本轮没有启用场景选项、GPU 启动、导出、性能调优或 Git stage/push。
