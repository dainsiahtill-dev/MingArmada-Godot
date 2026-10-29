# R12 Blender 作者候选：保留记录

2026-10-27。按[预注册](../R12-SAIL-SILHOUETTE-BRIEF.md)制作了独立的三帆轮廓候选，船身、桅杆、炮、舵、船员挂点和正式 provider 不变。实际作者文件为 `assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r12-author-01.blend`；候选模型位于 `assets/models/hero_fuchuan_v3_r12/`，尚未进入正式默认游戏。

- 三次 Blender 进程的命令、退出码、唯一完成标记和输入输出 SHA 分别见 `blender-lod0..2-process.json`、`blender-lod0..2.json` 与对应日志。每次从 R7c 作者源重建三面帆，包括布、横桁、缝、补片和绑扎，同一个表面函数用于形态键反解。
- 原始 Blender 导出中每档的非帆部分来自作者源 LOD0，不是可直接交付的三档完整导出；三个未经修改的中间文件已按 SHA 归档于 `assets/production/hero-fuchuan-blender/r12-author-01-intermediates/`，见 [mirror receipt](r12-author-mirror-01.json)。
- [有界封装](r12-pack-01.json) 从对应 R7c 各档复制非帆数据，并只转移三帆 P/N 与两个形态键的 P/N。独立[差异核对](r12-independent-delta-01.json)三档通过：每档 72 个目标属性；其余 JSON/BIN、索引、UV、颜色精确相同；帆布实际 y/z 与预注册公式的最大误差小于 0.000002 米。稀疏形态键位置按受限规则转为追加的 dense 数据，并纳入完整 JSON/BIN 独立重建核对。
- [形态键语义检查](r12-morph-01.json) 对 3 LOD × 3 面帆 × 4 材质共 36 组逐顶点检查，`furl` 和 `inflate` 目标位移全部在 0.00002 米容差内；这不代表连续动画或碰撞安全。[负向测试](r12-negative-tests-01.json) 5/5，覆盖 R10a2 冒充、UV 篡改、帆几何篡改、非目标字节篡改和来源回执篡改。
- [Blender 三视图](blender-review-01/BLENDER_REVIEW.json) 使用实际保存的作者文件、Cycles 24 samples CPU，进程退出 0、源码 SHA 不变；提供 `hero.png`、`stern.png` 和 `hull-detail.png`。这是固定作者灯光下的静态评审，不是正式游戏动态画面。
- 研究实验室可选择 `art_r12`；[RED](experiment-red.log) 为 10 项中 6 项失败，[GREEN](experiment-r12-green.log) 为 80 项、0 失败，检查实际三档 GLB、三帆形态键和伤损材质；R11b 与 R11 回归各 74/0，R11b 测试同时检查 R9b。formal-light 工具接受 `art_r12`，无 GPU 时按设计拒绝。

固定 Blender 三视图只能支持静态艺术讨论，不构成游戏视距的艺术通过；帆与桅、桁、索具、甲板、炮和船员的间距，转帆/收帆、动态影子、性能、LOD 切换与完整实机体验均未在此验证。根据预注册，只有美术门槛和后续研究门槛通过后才能考虑正式接入。
