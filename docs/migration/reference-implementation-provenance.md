# 海战参考增量来源核验

> 后续发布状态：新增标量高度路径的外部 PCK 探针和隔离启动器已完成语法检查，但因用户要求继续移植学习 demo 算法，新的 release 导出与来源检查点暂缓。下面的素材与绑定审计保留其原核验时间；本轮没有把旧包、旧源码哈希改写为新算法已落地的证明。

本次只新增本报告与 provenance/naval-reference-implementation.json；未更改参考目录、源 DDS/PNG、既有纹理、先前清单或实现代码。核验时间：2026-10-11T11:45:11.578722+00:00。

重新计算了源 DDS、源 PNG、目标 PNG 的 SHA256，并逐对比较 PNG 原始字节。**5/5 对一致，0 差异**。既有 pirates-water-textures.json 所列 **27 张目标纹理全部符合其记录哈希**；该清单哈希仍为 9fd8a079882365d090c3173ad12ec46cf3008ea1263676dd6a17c674304cd6a3。

| 来源 | 本轮变化 | 尺寸 | 恒定 RGB（8 bit） | alpha 范围（8 bit） |
|---|---|---|---|---|
| Pak6 / fx_water_splash_004.dds.png | 本轮新增 PNG 依赖 | 128×256 | [255, 251, 255] | [0, 127] |
| Pak1 / fx_streakin_001.dds.png | 本轮新增 PNG 依赖 | 128×128 | [255, 251, 255] | [0, 219] |
| Pak5 / fx_mist_01.dds.png | 本轮新增 PNG 依赖 | 128×128 | [255, 251, 255] | [0, 206] |
| Pak4 / wake3unique.dds.png | 本轮新增 PNG 依赖 | 128×128 | [214, 255, 255] | [0, 187] |
| Pak0 / foam0024.dds.png | 既有 PNG，新白浪绑定 | 64×64 | [203, 227, 214] | [0, 238] |

五张图片的 RGB 均为常量，实际变化存于 alpha。当前实现读取 .a 作覆盖率，输出使用本作设定的泡沫颜色；没有把 RGB 白底直接当作不透明方块。导入配置均生成 mipmaps、修复 alpha 边缘、不预乘 alpha；这是 Godot 的派生导入，原 PNG 字节仍完整保留，不声明运行纹理与原 DX9 GPU 采样逐字节等价。

## 实际绑定

- fx_water_splash_004：water_splashes.gd 为 WaterColumn、UmbrellaShell 绑定 foam_texture；splash_volume.gdshader 取 alpha，经阈值响应与顶点 alpha 渐隐。
- fx_streakin_001：同 presenter 为世界空间 WorldDroplets 的交叉条带绑定；与实体水柱共用体积 shader，alpha 决定稀疏飞滴覆盖。
- fx_mist_01：WeakMist 椭圆 billboard 的主纹理和细节纹理均使用该图；pirates_foam.gdshader 读取 alpha，有限早期相位可见。旧 WaterSpray 兼容节点默认隐藏，沉船 surface_only 模式关闭雾。
- wake3unique：wake_trails.gd.configure 当前选择该图，沿观测船尾历史点形成带状网格；alpha 控制尾迹，既有 fx_waterfroth_003 的 alpha 只调制细节。保留的 WAKE_DDS/WAKE_TGA 常量不是当前默认绑定。
- foam0024：projected_ocean.gd 绑定 reference_whitecaps_texture，surface_layers.gdshaderinc 两次取 alpha 作风向滚动白浪覆盖，original_water.gdshader 混合海面颜色。它是 fragment 层，未驱动顶点高度或浮力。

完整绝对路径、文件哈希、具体代码行及导入哈希均在增量 JSON 中。四张新依赖此前已出现在参考库存清单，但不属于先前交付的 27 张 PNG；本轮把它们加入项目并绑定。foam0024 属于先前 27 张，原清单的 alternative_not_bound_in_current_code 是先前快照。本报告以当前实际绑定补充该变化，不覆盖历史记录。

## 证据边界

本次核验覆盖磁盘文件、通道、导入参数与实际代码绑定，15 项绑定字串检查全部通过。GPU 画面与性能由主线程单独验收，本报告不把静态绑定验证说成已验证画面。

深入报告的海面反射创建/绘制/恢复链是有证据的静态发现；原游戏 GPU 帧、最终材质选择与 Top/Plane01 查找差异仍未恢复。新增水柱、伞壳、飞滴与船浪采用本作的米秒尺度、几何和生命周期，仅以报告的分层结构与资源依赖为参考。不声明完整 DX9 重现、完整碰撞原语、六自由度浮力、任意网格切割或原 40 槽落水救援系统已迁移。

素材仍注明商业游戏参考来源；本记录不将其标作原创或公开再分发授权素材。本核验没有运行或修改原游戏。
