# 原始高度海岛接入正式世界

三张参考原始高度索引已完整导入，正式入口可通过 `HeightField.configure_ports(ports, include_shoal_shelf, {"reference_islands":true})` 启用。默认不传选项时继续执行原精确地形公式。没有改独立 Cat Island 示例，也没有修改港口 ID、世界中心、停靠坐标或补给浅滩规则。

## 来源与完整性

数据来自 `C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/source-study/data`。已阅读源报告、JSON 元数据和完整索引数组，并查看三张原索引图：Cat Island 呈狭长折线、山脊与曲折海岸；coastal2 为带凹湾和山地的大陆海岸片段；Virgin Islands 为分散群岛、峡道和浅滩。

| profile | 原完整尺寸 | 索引数 | 原 JSON SHA256 |
| --- | --- | ---: | --- |
| cat_island | 120 × 140 | 16800 | `d1b4f3b42347916ef7f85262e1ac16a65234c4981a374039b55ab0b417d30a1c` |
| coastal2 | 329 × 193 | 63497 | `ce35636beb51ec4865e8073bd0d0803c75c88e3633770517233c657a254d950d` |
| virgin_islands | 160 × 77 | 12320 | `5224fcf8947623796cf50f4ffffbb1a59a385af3df9a4c8604a2ad3fbc6fe06f` |

`tools/import-reference-islands.mjs` 对三份 JSON 与其原始 BMP 字节数/SHA 全部校验通过后才开始写入。各 `assets/data/reference_islands/<profile>/height.json` 保留原 JSON 字节；相邻 `provenance.json` 保存原始路径、BMP SHA、索引编码、未知单位与本项目转换说明。三份共 **92617** 个原始 uint8 索引，没有用显示颜色或灰度亮度替代调色板索引。

`ReferenceIslandProfile.load_source()` 再按固定 SHA 校验项目内原始 JSON，并检查完整尺寸、索引数、整数与范围，损坏或未知 profile 不静默回退。

复验：

```powershell
rtk proxy node tools/import-reference-islands.mjs --verify
```

## 地形转换与港口适配

原数据没有恢复世界高度倍率、单位或精确海平面。继续保留 `world_units/world_height_scale = null`；本项目显式选用索引 128 为海陆阈值。这些资源贡献游戏地形形状，不声明为厦门、金门的真实地理复原。

每个 profile 依据原正高度索引边界得到源中心和最大地形半径，保持原比例与内部形状，水平缩放至对应港口 radius 的 92% 并朝停靠方向旋转。正高度索引按源最大峰映射至港口 peak；负高度按源最低值映射至 -24 米深水。只有原矩形边缘 5 个索引像素作平滑闭合，避免 coastal2 大陆片段在项目世界里形成截断边缘。这是明确的游戏转换；没有用圆丘加噪声生成替代海岛。

正常三港顺序使用 Cat/coastal2/Virgin 三种不同轮廓；其他港口按数组顺序循环。可为港口显式设置 `referenceProfile`，合法值见上表，未知值原子拒绝。

沿每个固定停靠点到固定岛中心的方向，只局部适配一个窄港口：

- 入港水面、停靠点和初始船体附近保持 -8 米；中间 36 米宽航道为完整深度，两侧至 70 米宽平滑接回原地形。
- 向岛内 20–43 米逐渐接岸，43、47.5、55 米处形成约 2.1–2.4 米高的陆上码头平台，现有 55 米栈桥可以上陆。
- 55–95 米逐渐接回原地形；向外海远处同样消退。其余岸线、峰岭、岛间水道和海底保持原始索引形状。

几何、海图、地形碰撞、船舶水深判断、岸线 RF 均继续通过同一个 `sample_height(x,z)` 接口，不另外生成一张只用于美术的假海岸。原来的运输补给浅滩规则仍在同一 HeightField 最后合成，中心深度 -2.4 米。

## 代码接口

`modules/scene_engine/terrain/reference_island_profile.gd` 是纯高度 helper：没有渲染节点、时钟、波浪或业务港口目录。`configure(port, data, id)` 在完整验证和变换推导完成后才替换接受状态；`sample_height()` 是唯一地形采样；`diagnostics()` 返回数据来源和变换信息。

`HeightField.configure_ports()` 新增第三个可选 `options` 参数。只有 `{reference_islands:true}` 启用数据地形；原两参数调用的公式与数值保持一致。`reference_profiles()` 提供所用来源。非法 source、port、options、profile 名称均保留之前完整配置；reference 模式先检查数值类型，避免旧 `float()` 转换在 Dictionary 等非法输入上抛错。

正式 game routes 的 opt-in、植被/港口细节布局、GPU 画面和 Windows 包由主线程接线与验收。

## 当前验证

Godot `4.7.2.stable.official.ed1daf0bf`。严格 runner 检查进程退出、Godot errors 和唯一成功标记。

| 验证 | 结果 | 证据 |
| --- | --- | --- |
| 原始 profile 缺失 RED | 1 assertion / 1 failure | `evidence/reference-island-profiles/red-missing-profile.json` |
| 非数值港口转换 RED | 捕获真实 `Nonexistent float constructor` Script Error | `evidence/reference-island-profiles/red-invalid-port-type.json` |
| 新 profile、码头、源形状、非法更新与默认公式 | **4846 assertions / 0 failures** | `evidence/reference-island-profiles/green-profiles.json` |
| 两个真实旧/自由航海场景的实际 spawn 水深 | **10 assertions / 0 failures** | `evidence/reference-island-profiles/green-default-geography.json` |
| 独立 Cat 示例地形 | **591 assertions / 0 failures** | `evidence/reference-island-profiles/green-standalone-terrain.json` |
| 正式 terrain material/mesh 相关 | **114 assertions / 0 failures** | `evidence/reference-island-profiles/green-game-terrain.json` |

新 profile 测试独立反变换世界坐标，对许多非港口、非边界原内部索引点核对原始高度；检查每港海陆构成明显不同于旧圆丘；验证停靠船体范围、栈桥上陆、补给浅滩、默认 400 个世界点与旧公式逐值相同，以及整套配置的原子拒绝。

这轮验证证明原始数据、高度合同和接线行为，不能替代 GPU 地形/岸线的画面验收。没有性能调优、额外 GPU 窗口或 Git stage/push。
