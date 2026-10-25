# 模型前期资源库 v1

[图文台账](../../../docs/production/model-preproduction-2026-10-24/index.html) / [完整清单](../../../docs/production/model-preproduction-2026-10-24/manifest.json) / [考据与制作说明](../../../docs/production/model-preproduction-2026-10-24/README.md)

按ships、characters、garments、weapons、buildings、environment、props分目录。每个模型或草图任务有稳定ID。

- `model-brief.json`：制作范围、旧需求来源、覆盖的绘图任务；部分共享配置明确不计基础模型。
- `art-brief.json`：本张图覆盖的模型、视图与范围。
- `prompt.txt`：实际首稿提示；修订另存`prompt-v2.txt`。
- `shape-notes.md`：年代、地区、史料支持与创作推定。
- `review.json`：逐图所见、错误与待核项；`preferredImagePath`指向当前优先修订。
- `multiview-v1.png`：首稿；不覆盖，修订另存v2。
- `generation.json`：首稿来源、尺寸、哈希、路线与批准状态；修订另存`generation-v2.json`。
- `generation-error.json`：未取得图片的真实原因；文件存在不表示已出图。

所有历史与建模批准均保持false。这些图是有史料约束的创作候选，不能直接当同一比例精确工程图。Blender应在造型、方向一致性、尺寸与动作空间审定后进行。不得把LOD、图像张数、材质、年龄和模型制作项混为同一计数。

旧170项目录与83项预算保留。这里没有改写正式剧情、Godot运行资产，也没有将原版提取模型视为商业授权完成。
