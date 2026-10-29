# 明朝海事 UI 图像资产

2026-10-26；游戏名仍为「海上明旗」。这批素材使用内置 `image_gen` 真生成，随后用 Pillow LANCZOS 规范尺寸，并为透明海图插画补足透明画布安全边，未用程序绘图替代。精确 prompts、原始生成文件路径、原始 SHA256、处理步骤、最终 SHA256 及参考图身份见 [ASSETS.json](ASSETS.json)。工具未报告具体模型版本，不作推断。

| 资产 | 最终尺寸 | 用途 | SHA256 |
| --- | --- | --- | --- |
| [menu-painting.png](../../../assets/ui/ming_maritime/menu-painting.png) | 1664×936 RGB | 首页原画，左约 38% 留低细节雾纸 | `161a2dfb0f0e0f4c7b7add721e1ede8b46981f9da4d80e94a912cc548e81bd1f` |
| [panel-paper.png](../../../assets/ui/ming_maritime/panel-paper.png) | 1024×1024 RGB | 宣纸正文面板，约 44–52 px 九宫格角保护 | `a03437eb04302d7212409b55a10e7d88f4d9c6fa4ea2d84fe44b6ba480a704cb` |
| [chart-paper.png](../../../assets/ui/ming_maritime/chart-paper.png) | 1664×936 RGB | 海图无地理底纸，真实地理交由 Godot 绘制 | `1819b2358bd12ceaab47d6e5abd066c4412ca43a6b94beafd030364139520aca` |
| [primary-button.png](../../../assets/ui/ming_maritime/primary-button.png) | 1024×256 RGB | 朱砂主按钮，奶油白文字由 Godot 渲染 | `ccad8fd00d9817793448a8522e5285d383c0047544ac936eaf05be6fd62c7a4b` |
| [secondary-button.png](../../../assets/ui/ming_maritime/secondary-button.png) | 1024×256 RGB | 暖象牙纸次按钮，细靛金边线 | `f42ef48243772a7ff5186ecda7605444a777be721f9ae5096f0c7850ae434e1f` |
| [atlas-vignette.png](../../../assets/ui/ming_maritime/atlas-vignette.png) | 1024×683 RGBA | 世界海图边栏透明福船／海龙／卷浪插画 | `07292557d91332d4b0b542a26428c56bc1067ee0258fed516c6271227995f8cc` |

## 来源边界

[菜单参考图](reference/menu-direction.png)与[海图参考图](reference/chart-direction.png)由用户提供，仅作本地风格基准；未另行确认第三方作者或许可，不能将其当作史料或宣称来源许可已完成。生成素材是 AI 插画／纹理。参考图自身的原始路径、尺寸、SHA256 已入 manifest。

## 目检与处理记录

- 菜单：蓝金甲明将、朱红披风、红帆福船、青绿山、奶油浪纹。左侧雾纸留白；无文字、牌匾、龙脸或水印。原始 1672×941 微缩到精确 1664×936（16:9）。
- 面板：浅象牙宣纸与细双线，中心大面积干净，角纹较小；角纹约深入 4–5%，实际九宫格需保护。原始 1254² 缩到 1024²，全图 RGB 不含透明 padding。
- 海纸：灰青墨刻横浪与极淡角云；无海岸、大陆、岛屿、地名、地图符号。原始 1672×941 微缩到 1664×936。
- 按钮：均匀朱砂漆／印泥纹理、细金线与角纹，无字。工具原始 2172×724（3:1），尺寸归一到要求的 1024×256（4:1），角纹有轻微横向拉伸。
- 次按钮：参考本批 panel-paper 生成，比面板稍深的暖象牙纸、靠外细靛金线、小卷云角，中心安静无字。原始 2172×724（3:1）仅缩放到 1024×256（4:1）；未像素裁切，边线外约左右 4–5 px、上下 2–3 px 可由 Godot region_rect 裁去。完整 prompt 和生成源 hash 见 manifest。
- 海图插画：三桅红帆福船、小型青金海龙、奶油卷浪；两轮均使用 imagegen 的 transparent_background=true。首轮 viewer 显示隐藏 RGB 造成色晕误判；实际 alpha 取样与暖纸底合成确认无该背景。选第二轮清晰版本，原生 1536×1024 RGBA 保比例缩至 819×546，居中放入 1024×683 透明画布，外侧约 10% 安全边 alpha 最大值为 0。未抠图、未阈值修改 alpha、未程序绘制主体。奶油浪核心为高 alpha 实体色，原生 alpha 通常约 253/255，不宣称每个像素均为 255。完整初始／修正 prompt、两轮源 hash、alpha 校验与限制见 manifest。

每张已查看生成图，并以 Pillow 重开验证最终尺寸、RGB、文件大小和 SHA256。此处仅证明资产生成与目检；真实入口、文字可读性、交互与 GPU 运行验收属于接入任务。
