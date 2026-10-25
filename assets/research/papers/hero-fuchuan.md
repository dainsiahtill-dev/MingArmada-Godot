# Blender 主角福船与运行时组件适配

- 课题 ID：hero-fuchuan
- 日期：2026-10-25；类型：前瞻工程研究；状态：研究中。
- 摘要：原创 Blender 分体船模通过现有 ShipView 动作、甲板和水线合同接入；当前结果按下文记录，未完成项不视为通过。
- Demo：res://game/research/demos/hero_fuchuan_experiment.gd
- 原件：assets/production/hero-fuchuan-blender/hero-fuchuan.blend；生成程序 tools/blender/build_hero_fuchuan.py。
- 运行时资产：assets/models/hero_fuchuan/；manifest.json 保存原始模型散列。

## 问题与假设

用户要求优先制作亲自驾驶的船，包括舵、帆和组件。现有 fuchuan 映射到原参考 barque 外观。H1：原创福船可保持32米船长、9米船宽、2米吃水和每舷4炮的权威配置，同时由原控制状态驱动可观察的舵柄、舵叶、帆面和炮管。

坐标为米、Y向上、+Z船首，Blender源为Z向上、-Y船首。模型和正常物理碰撞合同独立，新增视觉不修改质量、炮弹或伤害。三桅福船轮廓参考既有v2概念和研究，具体线型与长舵柄布置是游戏美术解释，不宣称复原史实舰。

## 方案比较

1. 原参考manifest直接换GLB：易混淆原件等价和新美术的来源；不采用。
2. 新建全部船舶运动/显示系统：增加状态与回退风险；不采用。
3. 独立原创provider复用ShipView：原件保留，先实验验证、再改默认选择；采用。

## 算法与实现

Blender按预先声明断面生成外壳板列，独立甲板、艉楼、栏杆、舵轴、舵柄、三组桅帆、索具与八组炮座。GLB保留furl/inflate形态键；布与帆桁共同折叠。三个几何LOD使用相同角色名与挂点。原运行时接受时间驱动形态、转舵和后坐，不另建动画时钟。

hero_ship_provider建立原创来源、甲板/障碍/投影/水线元数据；其它船型仍由原provider加载。源GLB通过既有AssetLibrary生成独立节点，未新增全局节点缓存。具体形制参考见docs/production/model-preproduction-2026-10-24/research-ships-weapons.md。

## 实验设计

2026-10-26材质增量预注册：用户要求生图贴图。候选四类albedo为旧木、甲板、麻帆、锻铁；沿用本实验固定输入与相机。原v1程序贴图/GLB/源文件保留，候选独立命名。接受项为无烘焙光照/文字、真实船面木纹方向合理、无明显拼接、帆损UV和组件合同不变；同镜头日光、背光、半帆和近景GPU审阅后再接入正式入口。此时尚未生成和验证新贴图，不把旧GPU结果视为新材质证明。

固定seed1650、1/32秒、初始位置原点、无船体摇晃、同一镜头/光照。实验用sin(0.8t)驱动舵/帆，控制输入明确标为诊断，不冒充物理操纵。对照原参考船与候选，保持相同快照。

预定接受项：三LOD均加载；主船壳长31.9–32.3m、宽8.8–9.3m、穿越y0；非空水线；真实甲板支撑；三桅两形态键；8炮口与原权威位置误差小于0.001m；多实例不串形态；暂停不动、重置确定；真实GPU近/中/远镜头与动态收放帆；正式主菜单进入后操船/开炮；同负载整场帧间隔单独报告。

## 结果与证据

原参考船合同基线见Temp/blender-maritime-kit/baseline-ship.json。provider、烟口/倒桅、默认入口、布料背光、损伤UV、上层舵位和水面单位均有失败回执及修后通过；当前Temp/hero-fuchuan/effect-units-green.json为3项155断言/0失败。

docs/production/hero-fuchuan-2026-10-25/gpu-final-v5/manifest.json保存257张连续GPU原帧（1/32秒，0至8秒）、暂停快照相等、同输入重置初态相等，以及反面光照与3档中途帆损。视频hero-rig-continuous-v5.mp4实测1280x900、32fps、257帧；它是固定诊断序列，不称原生操船录像。

native-play保存真实主菜单进入、航行、鼠标转向和左舷炮击（40至39弹药）截图；早于最后的帆布/舵位/水面单位修正。Windows安全提示阻止后续原生输入，完整候选验收未完成。细节及保留失败见同目录DELIVERY.md。

## 局限与失败

材质v2首次GPU候选位于texture-v2/gpu-candidate：近景帆布摩尔纹和远处木面噪点，不接受此画面。运行时GLB生成的ImageTexture缺少真实mip层，has_mipmaps检查复现12次失败。仅在原创v2材质首次加载时生成缺失mip，不改原始生图像素或旧船算法，后续同资源复用。texture-v2/gpu-mips-v2同镜头复验消除明显噪点，保留近处材质差异；40条纹理合同通过。机制依据[Godot Image文档](https://docs.godotengine.org/en/stable/classes/class_image.html#class-image-method-generate-mipmaps)，结论依据本机失败/通过回执与原始GPU图。

不宣称新战役、救援玩法或港口资产已完成。独立GPU连续序列已记录；完整最终原生游玩、帧成本和导出包未验收。全量回归运行中且已有超时，不能称全绿。概念图三炮口与游戏四炮不同，按既有每舷四炮制作。原创模型不改变旧资源授权状态。

## 集成与复现

先执行RTK包装的Blender脚本，再运行test_hero_fuchuan，进入实验室对照动态组件；候选达到接受项后切换ShipView默认provider，执行模型/船员/水面/炮火与普通入口回归。原provider和原GLB保留作为回退。所有结果以新目录保存，不覆盖历史失败。

外部实现来源：[Blender glTF文档](https://docs.blender.org/manual/en/5.0/addons/import_export/scene_gltf2.html)、[Godot 3D导入](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)。二者只解释格式能力，不构成模型或游戏实测。
