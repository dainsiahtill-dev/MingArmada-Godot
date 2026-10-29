# R14b 低货舱围框：作者候选记录

2026-10-27。根据 [R14b 预注册快照](r14b-preregistration.md)，在保留 R7c 原舱盖和格栅的前提下，制作两组 `1.85 × 2.25` 米的四边木围框，壁厚 `0.18` 米。顶部为舱口中心的原甲板高度加 `0.34` 米，底部各顶点按原甲板曲面加 `0.03` 米；围框为空心，未加遮板或额外装饰。

- 三份真实 Blender 作者文件位于 `assets/production/hero-fuchuan-blender/r14b-author-01-blends/`，各有实际进程、输入、输出与 SHA 回执。非目标部分在作者原始导出中均为 LOD0，因此原始 GLB 中间件已[单独归档](r14b-author-mirror-01.json)，不能作为完整低 LOD 成品。
- 实际候选 `assets/models/hero_fuchuan_v3_r14b/` 是在对应 R7c 三档上有界追加两组围框；[独立差异验证](r14b-independent-delta-01.json)三档通过：移除明确新增部分后原 JSON 精确一致，原 BIN 前缀逐字节一致，新顶点/索引/UV 取自真实 Blender 导出。模型没有替换正式默认。
- [负向测试](r14b-negative-tests-01.json)六项通过，覆盖原数据、节点、围框数据和障碍标记篡改，以及高围框 R14 冒充 R14b。
- [Godot 实际导入与站点检查](obstacles-01.json)为 213 项、0 失败。名称的小数点在 Godot 中变为下划线，`cargo_hold_` 前缀使现有 provider 正确标注障碍；三档均从 18 增到 20 个障碍，24 个船员站及每舷 4 个炮手站均保留，采样站点的人体包络不与新围框 AABB 相交。最近炮手足迹与围框水平间距约 1.139 米，属于静止站点包络测量。
- [静态三角面间距](static-clearance-01.json)中，围框与原舱盖最近约 0.020 米，与包含原格栅的整个合并 `deck_fittings` 最近约 0.090 米；这是非认证浮点三角面测量，不能代替动态碰撞检查。
- [同灯光 Blender 三视图](blender-review-01/BLENDER_REVIEW.json)由实际保存的 Blender 候选、Cycles 24 samples CPU 生成，独立进程退出 0、源文件未变；可用 `hero.png`、`stern.png` 和 `hull-detail.png` 与 R7c 同镜头对照。固定作者视角尚不能决定游戏主视距的可读性。
- 研究实验室与 formal-light 现可选择 `art_r14b`，正式默认仍为 R7c。实际三档及两处障碍加载在接线前 [RED 7/6](experiment-red.log)，接线后 [GREEN 23/0](experiment-r14b-green.log)；R12 80/0、R13 14/0。无 GPU 的 formal-light 测试在接受参数后按设计拒绝绘制。

高围框 R14 因静态美术审阅认为像敞口木箱而被拒绝，其模型、原始中间件、失败图及独立回执保留于 `r14-author-01`。两版均未验证帆和炮的动态扫掠、移动中的船员路径、LOD 连续切换、成本或操作系统实机体验；不得将本记录当成整船验收。
