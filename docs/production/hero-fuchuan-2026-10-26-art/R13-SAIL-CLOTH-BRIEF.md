# R13 旧朱砂帆布素材候选：制作前预注册

2026-10-27。R9b 改善了船帆与海面的辨识度，但主镜头下仍显平整；R11、R11b 的顶点色局部变化不足以形成可辨的材质层次。用户要求复古贴图并用生图模型制作，拟制作单独的旧朱砂麻布底色图，以 R9b 为基线，保持原帆形、UV、材质、形态键、索具、伤损处理、船体、光照、相机和 mipmap 合同，仅比较原图像像素。

设计方向：正视、无透视和光影烘焙的暖旧朱砂织物，以细致天然纤维和低对比、宽尺度的日晒色差为主，控制颜料褪色，不画文字、纹章、桁条、阴影、破洞或硬边接缝。色差应在正常游戏距离形成柔和的材质变化，近看仍可信，不产生明显条纹、棋盘、色斑或重复图案。布图不声明可无缝平铺，也不修改原 UV。

先保存生图原件、完整提示词和哈希；独立 Blender 作者文件与三个 LOD 的有界纹理包装必须精确保持其他数据，并验证实际 Godot 加载与损伤纹理。以同一正式场景和 R9b 对照评审，若主视距无可辨收益、过脏/发花、细纹闪烁、破帆或颜色失真，则拒绝；静态图不能代替收帆动态、LOD、性能、实际游玩或生产接入。先冻结此方案，尚未生成 R13 素材或测试。

## 生图原件

随后以内置 imagegen 编辑原 R9b 帆布，并以 R12 造型参考的帆布色阶作风格参考，输出 [weathered-cinnabar-hemp.png](../../../assets/textures/hero_fuchuan_r13/weathered-cinnabar-hemp.png)，SHA256 `0a25b0a8833eb81e8b03708f113e6e10238fec03c3adeb4b72143333917c8c3b`；原始输出 `C:/Users/dains/.codex/generated_images/01a172ba-3d47-7490-88ee-52dc41a9c20a/exec-c67c1bd1-037b-4d5f-9af4-66df552fd28d.png` 未改动。

完整提示词：

> Generate one square flat physically plausible albedo texture for a game-ready Ming junk hemp sail. The FIRST supplied image is the existing R9b texture and is the edit target: retain its warm sun-faded cinnabar / faded red-orange hue, fine woven hemp fiber, matte woven roughness, and overall exposure. The SECOND supplied image is only an art direction reference for the subtle aged color richness of the red sails, not a picture to reproduce. Introduce controlled broad-scale, very soft weathered pigment variations and delicate sun-fading across the cloth in addition to the fine fibers, enough to read softly when minified to a ship sail in game; make the medium-scale variations subtle, irregular, natural and artistically restrained, not blotchy, striped, grid-like or uniform noise. It must be an evenly lit orthographic 2D fabric surface, full-bleed square, no perspective, no lighting gradient, no highlights or ambient occlusion, no imagery, text, insignia, embroidery, battens, ropes, painted hard seams, holes, borders, wrinkles, cast shadows or specular shine. Do not add a ship. The result is a material texture only and should preserve believable vintage hemp, rich but not saturated. No transparency.

首次目测图像较 R9b 偏深偏红，是否过暗、宽尺度变化是否足够以及贴图映射后是否改善均需独立实测，不能从生图原件直接推定。

## 已完成的候选与静态对照

独立 Blender 作者文件、三档有界 GLB 已完成：以 R9b 为基线仅追加并重定向帆布 PNG；[CPU 记录](R13-CPU-RESULTS.md)包含差异检查、六项篡改负向检查及实际 Godot 资源、mipmap、形态键与伤损绑定的 130 项检查。构建和测试中两次包装/测试自身问题及修正回执均保留，不能把测试中的旧失败称作模型缺陷。

以隔离进程拍摄[同场景 R9b](../../research/evidence/hero-fuchuan/r9-cinnabar-20261027/world-r9b-r13-pair-01/LIGHT_STUDY.json)与[R13](../../research/evidence/hero-fuchuan/r9-cinnabar-20261027/world-r13-pair-01/LIGHT_STUDY.json)，两组各 2 帧、0 失败、进程退出 0；独立核对实际相机、风、光、环境、画质和抗锯齿一致，共同源码 13 项一致，R7c 帆区基线像素一致。候选帆区平均绝对差为 4.09/255，但目视主要表现为更深、更红，未形成预注册要求的宽尺度褪色层次；主线和独立美术复核均认为没有足够收益。故保留候选与对照，不推广为正式默认。此结果仅限单一日光静态游戏视角，不代表其他光照、连续动画、性能或人工游玩。
