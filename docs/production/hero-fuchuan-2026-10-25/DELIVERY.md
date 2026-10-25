# 主角福船制作与接入记录

当前结论（2026-10-26检查点）：功能船模已接入，生图复古材质v2已完成独立GPU与正式入口验证，但用户明确否定现有船体、艉楼、帆形和构件比例的美术质量。本提交是保存全部现状的检查点，不是主角船美术验收。后续优先重塑船模，再统一海、岛和整体氛围。

最新增量：四张1254×1254内置image_gen贴图已接入 `hero_fuchuan_v2`，可编辑源为 `hero-fuchuan-v2.blend`。首次GPU暴露mip缺失造成摩尔纹，已保留失败帧并补真实mip层；新候选40条纹理断言通过，257连续GPU帧及暂停/重置通过。正式自由试航实操100%→42%→0%收帆、船速降至零，见native-play/07至09。新版最终转舵、炮击、靠泊与存档闭环尚未完成。

回归：初始全量294项为270通过/24失败或超时；33项定向复验全部通过，包含原24项失败。材质v2正式接入后4项主角船测试、图鉴、实验宿主、原船游戏合同、4项普通入口均通过。默认音效/音乐已关闭，用户设置与音频测试通过。这些分批结果不冒充同一冻结版本的一次全量运行。

## 实际交付

- 编辑源：assets/production/hero-fuchuan-blender/hero-fuchuan.blend，757934字节，Blender 5.4.0 Alpha fbe82a461016实际生成。
- 制作程序：tools/blender/build_hero_fuchuan.py。网格和4张贴图均原创生成，无提取模型输入。
- 运行时：assets/models/hero_fuchuan/fuchuan-lod0.glb、lod1、lod2；实际导出三角面38002 / 19310 / 10978，按GLB索引统计；76节点、43网格、12材质。节点数不当成76件独立资产。
- 包含船壳、甲板、艉楼、栏杆、舱口、绞盘、锚、盘绳、三桅、帆布、帆桁、索具、旗、舵叶/舵轴/长舵柄、8组炮管/炮架与烟口。
- 保持32m船长、9m船宽、2m吃水、每舷4炮。1650旗舰、试航、炮战及船舶图鉴使用新船；实验室提供原参考船对照。本次未实现新的郑芝龙完整战役。

## 已验证

|证据|实际结论|
|---|---|
|Temp/hero-fuchuan/effect-units-green.json|模型126、组件20、水面9条断言，合计155/0；三LOD、真实水线、甲板与上层舵位、帆形变、实例隔离、8炮口、后坐/烟口、倒桅、效果单位和喷水。|
|Temp/hero-fuchuan/book-green.json|图鉴GLB切换、收帆滑块、相机与后坐回归通过。|
|Temp/hero-fuchuan/reference-waterline-green.json及reference-froth-green.json|旧参考船固定夹具保持原输入并重新通过；新船水面另测。|
|Temp/hero-fuchuan/lab-wake-green.json|新模型与旧效果单位衔接正确，交互水面不可用时仍有尾迹。|
|Temp/hero-fuchuan/lab-host-green.json及catalog-green.json|实验室宿主/登记通过。|
|gpu-final-v5/manifest.json|Forward+ / Intel Arc 130T；257张连续GPU原帧，固定1/32秒，0至8秒；暂停快照不变，同输入重置初态相等；另有反面光照和80/60/30帆健康截图。|
|hero-rig-continuous-v5.mp4|原帧编码的1280x900、32fps、257帧、8.03125秒诊断视频。原帧在Temp/hero-fuchuan/continuous-v5，SHA在manifest；不是操船录像。|
|native-play/01至04截图|普通主菜单进入试航、真实航向变化、左舷40减到39弹药并出现炮烟。使用Windows Computer Use；此轮早于最终帆布、舵站及水面适配修正。|

## 修复记录

1. Blender factory-empty无World导致首次预览失败；补显式World后重跑完成。首次形态键值为1导致默认收帆，明确置零；错误预览保留。
2. 活动索并入帆桁共同形变，消除收帆后悬空线；静止支索单独绑定倒桅。
3. 独立审查发现布面平铺UV不满足夹边损伤贴图。先补RED，再归一化UV；竹帆桁/绳索不套布料破洞材质。仅原创canvas启用薄布背光。
4. 新模型米制marker与旧效果单位分开。effectSourceToWorld保留原福船换算0.021353528480495498，明确family3；没有把原创模型伪称原参考船。
5. 旧约5m水线与特定俯仰夹具显式注入原provider保留回归；新增新船约6.94m水线和真实平水接触测试，没有改喷水算法迎合旧几何。
6. Blender新增crew_helm挂点，舵手落在实际上层甲板。精确手部握柄与全舵角随动IK未验收。
7. GLB三角面改按导出后索引计数；重置检查改为同输入初态快照比较，避免把time=0叫确定性证明。

## 保留限制

- v2真实收放帆已完成；近景舵手、返港/交割、继续游戏未完成。安全弹窗现已不存在。曾因高权限游戏与普通权限桌面工具不匹配而无法输入，改以普通权限启动后已恢复实际操作。
- 本次隔离试玩进程已结束，以便重新加载最终版本。APPDATA为Temp/hero-fuchuan-player-profile，未用用户存档。
- 初始全量及后续定向复验分别保留；未完成严格配对整场帧时间测量，未验导出包，不宣称60FPS或性能提升。
- 船线和硬件布置是时期约束下的游戏美术解释，非考古复原认证；旧水面/战损资源的来源与授权状态未改变。
- 用户要求提交当前全部代码和资源作为检查点；没有推送、重置或删除用户工作。原参考模型保留；图鉴已有用户UI改动保留。

## 复现

Blender源目录README提供完整生成命令。Godot打开project.godot，主菜单选试航/新生涯；图鉴可看水下船壳、收帆和后坐；实验室选Blender主角福船。新增测试用RTK包装tools/verify-godot.mjs的--filter hero_fuchuan。GPU脚本为tools/verify-hero-fuchuan-gpu.gd，--output与--continuous必须使用新目录，保留历史失败。
