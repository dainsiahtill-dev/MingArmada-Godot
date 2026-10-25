# 主角福船 · Blender 源文件

用户指定优先制作驾驶船，并要求艺术家的审美。当前造型是 `hero-fuchuan-v3-r6.blend`，三档GLB位于 `assets/models/hero_fuchuan_v3_r6/`，已切换正式入口并完成本轮原生操作复验。v3重塑外倾上扬艏、深船腹、实心四炮口舷墙、收束艉楼和梯形/扇形帆；r6再精修折角艉墙、真实侧凹窗、构造压边、后掠圆脚舵叶与4mm甲板细缝。v1/v2/r5源与GLB保留。接入通过不等于用户最终审美认可。

包含船壳板列、甲板与艉部操舵台、舱楼/窗格、栏杆、舱口、绞盘、锚具与盘绳，三组桅杆/竹帆桁/帆布/索具，舵轴/舵叶/舵柄，8组炮管/炮架与烟口。`crew_helm`标记上层操舵站位；人体手指精确握柄与随舵柄移动的IK尚未验收。

- 米制。Blender Z向上、-Y船首；GLB/Godot Y向上、+Z船首。
- 原有游戏物理合同：32m船长、9m船宽、2m吃水、每舷4炮。具体历史船线/布置为时期约束下的美术解释，未取得历史复原认证。
- `mast_0..2`是调帆/倒桅节点；`sail_0..2`带`furl`和`inflate`形态键，包含同步收放的布、帆桁和活动索。
- `rudder_pivot`同时带动舵叶、舵轴与长舵柄。`barrel_port_*`/`barrel_starboard_*`保留后坐轴，`socket_smoke_*`与物理炮口一致。
- 静止索具在调帆时保持船体连接，断桅时按明确桅杆归属倾倒。
- v3另带五个闭合投影资源：船壳/四炮口舷墙、艉甲板、三桅裸木。Blender视图显示为线框，渲染隐藏；Godot资源节点隐藏，仅同框架Mesh数据进入模板阴影。可见LOD0仍为101,299面，未削掉船体装饰细节。
- 帆布UV归一化供战损贴图使用。竹帆桁与索具不走帆布破洞材质。
- 网格由本仓库Blender脚本原创制作；v2的旧木、甲板、麻帆和铁件使用内置image_gen生成的四张1254×1254基础色图。原始PNG逐字节保留于 `assets/textures/hero_fuchuan_v2/`；提示词见 `texture-prompts-v2.json`。水下焦油木仍用程序纹理。没有把这些图称为扫描材质或完整PBR贴图组。
- 帆布基础色以12×18重复，战损UV仍为0–1。v2运行时首次加载为材质生成缺少的mip层，避免远景摩尔纹；不改原始生图PNG。

重新制作：

```powershell
rtk proxy 'C:\Tools\blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release\blender.exe' --background --python-exit-code 1 --python tools/blender/build_hero_fuchuan_v3.py -- --refine-stern --review-run=新运行名
```

本次实际使用Blender 5.4.0 Alpha fbe82a461016。打开`.blend`可编辑组件；源文件以全帆、零舵角保存。生成器会重新生成本包GLB、贴图、清单及源文件，手工修改后应另存版本，不能直接覆盖唯一手工作品。

游戏入口：Godot打开project.godot，主菜单的新生涯、自由试航与单舰炮战使用此福船；船舶图鉴可检查全貌、水下船壳、收帆与后坐；实验室“Blender主角福船”保留新旧外观对照。新生涯仍为既有1650剧情，本次未声称新的郑芝龙完整战役已制作。

v3造型与失败保留：`docs/production/hero-fuchuan-2026-10-26-art/`，当前以 `R6-DELIVERY.md` 为准；v1/v2历史记录：`docs/production/hero-fuchuan-2026-10-25/`；工程研究：`assets/research/papers/hero-fuchuan.md`。r6同负载正式自由试航约13.71FPS，仍未通过流畅验收。建模源文件、导出成功、独立实验和真实游玩为不同证据。
