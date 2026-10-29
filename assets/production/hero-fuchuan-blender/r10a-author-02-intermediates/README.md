# R10a Blender 导出中间件

三张GLB是从真实R7c作者Blend重建 `+0.06` 候选帆后导出的原始结果。**不要直接作为游戏的LOD1或LOD2**：这两档只重新生成了帆，其他节点仍来自作者Blend的LOD0；它们仅用于证明目标帆payload来自真实Blender及复现独立比较。

逐文件SHA和来源见 `docs/production/hero-fuchuan-2026-10-26-art/r10a-author-02/r10a-author-mirror-01.json`；Blender逐LOD过程/日志/输入散列位于同一目录。与每档R7c对应资源严格组合后的候选位于 `assets/models/hero_fuchuan_v3_r10a/`，也仍是待GPU、形变和艺术验收的研究候选。

原始 `Temp/hero-fuchuan-r10a/r10a-author-02/` 不存在时，可用 `rtk proxy python -B tools/blender/mirror_hero_r10_author.py --restore-temp` 在目标完全不存在的前提下恢复原字节。脚本先检查三份SHA且拒绝覆盖；恢复后可重跑独立对照。Blender作者源为同目录上层 `hero-fuchuan-v3-r10a-author-02.blend`，它包含LOD0真实作者场景。
