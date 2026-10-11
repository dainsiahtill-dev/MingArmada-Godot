# Pirates 全图库：海面、水花与关联参考素材

日期：2026-10-11。来源：`C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk`。本轮按用户要求先学习原报告与资源绑定，再整理完整目录；没有修改原参考文件。新候选尚未大量导入游戏，首轮27张的绑定另见 [原清单](C:/Users/dains/Documents/Git/ming-armada/docs/migration/pirates-water-textures.md)。

## 实际收集范围

两位素材专家分工 Pak0–Pak3、Pak4–Pak8，扫描全部 **3,840 张 PNG**。先对名称和已知资源依赖候选逐张查看 RGB、alpha 和透明合成，再对其余所有图片做 RGB/alpha 缩略概览，放大核查新增疑似资源。共查看 **60 页**。概览确实补出了名字不含 `caustic`、只叫 `caustXX` 的焦散系列，故本轮不止按关键词筛图。

| 分类 | 数量 | 如何使用 |
|---|---:|---|
| 推荐候选 | 55 | 优先按材质槽、几何和事件职责评估；推荐不等于已经完成 Godot 画面验收。 |
| 备选候选 | 66 | 密度/形状/风格变化、天气或未确认编码；按具体效果选用。 |
| 关联参考 | 290 | 原加勒比地图岸线/高度/分类/法线场、海图拼片、百科图、角色等；帮助理解结构，不直接作为明郑海面通用贴图。 |
| 归档项 | 3 | 透明空白或恒色占位等，不直接显示。 |
| 排除项 | 72 | 名称误匹配的服饰、武器、建筑、UI阴影等，保留排除理由。 |

完整分类记录 **486 条**。推荐＋备选合计 **121 张**，其中 **96 张未包含于用户先前27项清单**；先前清单包含一张另外附加的用户焦散图，原图库统计不把该附件算入3,840张。相同字节按 SHA256 分组，但保留所有原路径和文件名。

- [全部486项 CSV：名称、尺寸、通道、分类、用途、源路径、SHA256](C:/Users/dains/Documents/Git/ming-armada/docs/migration/pirates-water-library.csv)
- [机器清单：486分类＋3,840完整源文件索引](C:/Users/dains/Documents/Git/ming-armada/provenance/pirates-water-library.json)
- [Pak0–Pak3 原审核记录](C:/Users/dains/Documents/Git/ming-armada/provenance/pirates-water-library-pak0-3.json)、[Pak4–Pak8 原审核记录](C:/Users/dains/Documents/Git/ming-armada/provenance/pirates-water-library-pak4-8.json)
- [本次独立文件/通道复核结果](C:/Users/dains/Documents/Git/ming-armada/docs/migration/evidence/pirates-water-library-verification.json)

## 优先补充的素材及正确用途

| 素材 | 有什么区别 | 拟用在本作哪里 |
|---|---|---|
| [Pak4/wake3unique](C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk/Pak4/wake3unique.dds.png) | `wake.ini` 指定的原尾迹纹理；alpha0..187，约34.2%非零，两条不规则白迹。 | 历史航迹带的纹理候选，比原两张wake3的全幅非零底值更适合干净的透明轮廓。仍需宽度/寿命与实际船型配合。 |
| [Pak6/fx_water_splash_004](C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk/Pak6/fx_water_splash_004.dds.png) | 原炮弹落水NIF的柱体材质；128×256，RGB恒白，alpha0..127。 | 真正三维水柱/壳体上的流纹，配合UV与透明度时间线；不能把它铺成高亮竖直方片。 |
| [Pak1/fx_streakin_001](C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk/Pak1/fx_streakin_001.dds.png) | 原落水粒子明确依赖；alpha中有纵向水滴喷流。 | 初始和延迟喷滴、短水滴拖线。 |
| [Pak5/fx_mist_01](C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk/Pak5/fx_mist_01.dds.png) | 原落水雾组明确依赖；圆形淡雾和稀疏水滴。 | 水花展开后的弱雾层，按真实落水事件计时。 |
| [Pak5/fx_water_drop_01](C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk/Pak5/fx_water_drop_01.dds.png) | 单颗圆形滴，32×32，有真实透明轮廓。 | 少量世界空间水滴；与纵向喷流区别使用。 |
| [Pak1/fx_water_drops_02](C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk/Pak1/fx_water_drops_02.dds.png) | 稀疏独立水滴图案。 | 飞沫粒子/局部UV候选，避免整张图反复产生相同滴阵列。 |
| [Pak3/fx_water_splash_03_circular](C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk/Pak3/fx_water_splash_03_circular.dds.png) | 圆形云状泡沫，RGB和alpha均有内容。 | 水柱底部短时破水/扩散底层，与细水环分开。 |
| [Pak4/ripple](C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk/Pak4/ripple.dds.png) | 窄、不完整的水环，alpha仅约2.3%非零。 | 贴海面的细扩散环候选。 |
| [Pak4/fx_waterfroth_001](C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk/Pak4/fx_waterfroth_001.dds.png)、[002](C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk/Pak4/fx_waterfroth_002.dds.png) | 原船首/沉船泡沫资源依赖。 | 船首左右破水、碎泡，配合局部挂点和迎水速度。 |
| [Pak3/fx_waterfroth_005](C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk/Pak3/fx_waterfroth_005.dds.png) | 128×512纵向泡沫，沉船泡沫资源依赖。 | 沉船/强破水流纹候选；按原长宽比使用。 |
| [Pak0/surfsmall](C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk/Pak0/surfsmall.dds.png)、[Pak2/surf_bart3](C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk/Pak2/surf_bart3.dds.png) | 朝一侧衰减的真实浪缘与拖尾形状。 | 岸浪波头/拖尾候选；沿海岸走向贴合，不能随机平铺成同向白带。 |
| 32张`caustXX` | 64×64，RGB恒青，网格在alpha，最低alpha17或34而非零。 | 归一化alpha后调制浅水/海底亮度；不同于`duel_waterdetail`的RGB焦散。数字序列是否动画尚未证实。 |

![新增重点图的原RGB和alpha通道](C:/Users/dains/Documents/Git/ming-armada/docs/migration/evidence/water-library-shortlist.png)

该图册是诊断展示，源PNG未缩放或重绘。缩略图仅为阅读方便；不作为游戏贴图替换。

## 通道、动画和数据纹理的边界

`foam0000`、`foam0001`、`foam0030` 和 `surf_fill` 的alpha为空。`wakeblue` 和部分gloss图完全不透明，不能拿来直接贴透明尾迹。水色图、灰度浮雕、DUDV、法线、反光和透明遮罩分别核对原材质槽；不能按文件名统一当normal。

编号泡沫/焦散只证明存在一组图片，不证明原作连续播放它们。需要找到NiFlip/纹理变换控制器或shader/CPU选帧路径，才能还原动画顺序和时长。类似`WakeSpreadFunc`、`WakeAlphaFunc`、`WaterSparkleRotation`的细长RGB图可能是曲线/查找数据；先核对编码，不能当普通海水纹理或任意改采样方式。

`coastal*_b/n/ch/cc/t` 及地区岸线图与原地图绑定，`coast_*`含海图边界拼片。其存在能帮助我们设计岸线距离/深度/湿润数据层，但不证明可直接移作厦门、大员等海域的纹理。

## 复核与复现

主线程重新计算全部3,840源PNG的字节数/SHA256，并对486条分类重新读取尺寸、alpha范围/覆盖率、RGB是否恒色；检查唯一路径、源目录边界和CSV完整性，实际exit0、无失败。主线程还亲自查看了上述八张优先素材的RGB/alpha图册。其余分类判断来自两位专家的60页人工审查，不冒称主线程逐张看过原分辨率3,840张。

```powershell
rtk proxy node tools/research/assemble-pirates-water-library.mjs
rtk proxy python tools/research/verify-pirates-water-library.py
rtk proxy python tools/research/preview-pirates-water-shortlist.py
```

合并脚本读取两份保留的审核清单；它验证当前目录与本轮3840/486范围一致。目录增加或修改时需要重新人工审核，不能通过脚本自动将新增名称认定为海水素材。

全部PNG已概览，普通岛屿地图字段与百科图没有逐一拆解原分辨率语义。无特征或特殊编码仍可能需要绑定证据。原游戏没有运行或抓取draw call；PNG、静态模型依赖及报告数学结果不能代替原作GPU画面。本作后续实施顺序见 [学习与改进清单](C:/Users/dains/Documents/Git/ming-armada/docs/migration/pirates-learning-plan.md)。
