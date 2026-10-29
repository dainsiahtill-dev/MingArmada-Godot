# R13 生图帆布候选：作者资源和 CPU 验证

以 `hero-fuchuan-v3-r9b.blend` 和对应 R9b 三档 GLB 为唯一基线，生成独立 `hero-fuchuan-v3-r13.blend` 和 `hero_fuchuan_v3_r13/fuchuan-lod0..2.glb`。Blend 从 R9b canvas 材质替换并打包 [R13 生图原件](../../../assets/textures/hero_fuchuan_r13/weathered-cinnabar-hemp.png)；GLB 通过保留对应 R9b 的完整原 BIN、在尾部追加 PNG 并重定向唯一 canvas 图像视图构建，不是 Blender 全量导出。构建前后基线文件哈希不变，候选与作者文件的 SHA 记录在 [manifest](../../../assets/models/hero_fuchuan_v3_r13/manifest.json)。

- [独立差异检查](../../research/evidence/hero-fuchuan/r13-cloth-20261027/r13-independent-delta.json)确认 3 档原始 BIN 全部一致，JSON 仅有声明的图像、视图与 buffer 长度变化；[7 项真实输入篡改/回归样例](../../research/evidence/hero-fuchuan/r13-cloth-20261027/r13-adversarial-retry.log)通过。
- [真实 Blender 重开检查](../../research/evidence/hero-fuchuan/r13-cloth-20261027/r13-blender-independent.json)：81 对象、47 mesh、13 材质，父子/变换、位置与拓扑、UV、形态键及材质结点/连线所列结构子集无差异，目标图像 packed SHA 与原件一致；它不是全部 Blender 状态的逐属性证明。
- [Godot 实际运行时加载](../../research/evidence/hero-fuchuan/r13-cloth-20261027/runtime-02.log)：130 项、0 失败。通过真实 AssetLibrary、HeroProvider 和 ShipDamage，检查三档 LOD、三帆精确解码图像像素、实际 mipmap、furl/inflate、100/80/60/30 帆状态的原贴图与伤损贴图绑定。
- 研究实验室候选接线 [14/0](../../research/evidence/hero-fuchuan/r13-cloth-20261027/test_hero_fuchuan_r13_experiment-green.log)，R12 [80/0](../../research/evidence/hero-fuchuan/r13-cloth-20261027/test_hero_fuchuan_r12_experiment-green.log)、R11b [74/0](../../research/evidence/hero-fuchuan/r13-cloth-20261027/test_hero_fuchuan_r11b_experiment-green.log)、R9b [59/0](../../research/evidence/hero-fuchuan/r13-cloth-20261027/test-r9b-experiment-green.log)。正式 provider 默认仍是 R7c。光照对照入口接受 R13 参数，headless 时按预期拒绝无 GPU 环境。

保留两个中间失败：首轮独立测试包装错误地只匹配 LF，而 Windows 输出使用 CRLF；7 个测试本身通过，但其外层进程回执因标记数为 0 被拒，换行规范化后用新回执重跑。`runtime-01` 测试读取共享纹理后原地清除 mipmap，导致后续 6 项 mipmap 检查失败；改为检查副本，`runtime-02` 为 130/0。均保留原日志，没有把失败回执当通过。

上述是 CPU/无头资源和绑定证据；没有证明正式场景视觉改善、连续运动、性能或实际游玩。R13 图像比 R9b 偏深的视觉风险仍需在同一正式镜头审查。
