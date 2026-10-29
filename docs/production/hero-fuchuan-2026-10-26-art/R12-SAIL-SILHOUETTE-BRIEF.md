# R12 三帆轮廓节奏：制作前预注册

2026-10-27。用户要求优先改进主角船模，并以明代海战参考图作为美术方向。R10a 与 R10a2 的共同肩线调整在固定 Blender 视图里收益不足；R11、R11b 的帆布分幅在游戏主视距下也不够明显。当前问题是三个帆的轮廓及桁序过于相似。参考图只用于风格，不作为历史船型准确性的证据。

沿用 `hero-fuchuan` 既有课题和 R7c 模型合同，独立尝试一个造型候选：保留桅杆位置、高度、船体、炮位、8 条布幅、帆的材质和名义 UV；三面帆分别调整宽肩与顶缘倾斜，帆面、桁、缝、绑扎和形态键使用同一个表面函数。距离以米计，u、v 均为 0–1，固定风、相机和光照，不引入随机项：

```
B_i(v) = W_i * (1 + 0.10 sin(pi v) - k_i v²)
z = B_i(v) * (u - 0.70) - 0.045 W_i v²
y = base_i + H_i v + H_i c_i (1-u) v^2.2
x = 0.32 + (0.30 sin(pi v) + 0.025 sin²(pi ((8v) mod 1))) sin(pi u)

前 / 主 / 后：W = [7.4, 11.8, 6.8], k = [0.25, 0.40, 0.54],
c = [0.12, 0.17, 0.09], H = [10.3, 17.0, 9.0],
base = [4.6, 4.05, 5.35]。
```

基线宽度为 [7.7, 12.0, 6.8]，k 均为 0.40，c 均为 0.15。预期前帆上肩更饱满、主帆顶缘更舒展、后帆更收束；先比较真实 Blender 三视角，再决定是否继续 GPU 动态验证。早期二维截面粗筛不等于碰撞测试，不声明帆与帆、桅、桁、绳、甲板、火炮和船员已安全。

在作者源和三个 LOD 中分别重建并保留 `sail_0..2`、父桅、`canvas` 材质、`furl` / `inflate`、名义 UV 和伤损合同。包括 lashing 及形态键反解的原硬编码均须和新表面一致；如果构建需要 GLB 有界转移，保留 Blender 原始作者中间件及独立差异校验，不能称之为完整 Blender 导出。其余部件及原始候选不可覆盖。

先进行静态艺术门槛：与基线同镜头、同光照比较，前主后帆要在正常航行视距形成可辨且克制的不同轮廓，不允许显著折角、露出的桁端或错误缝线；没有明显改进即拒绝。若通过，再独立核对三 LOD、五种收帆度、正反风鼓、转帆扫掠、伤损、各类几何间距、正式场景的真实 GPU 连续画面及成本，最后才考虑正式游戏接入。桅杆由游戏联动旋转，固定索具不随之移动，不能事先假定扫掠安全。单张渲染不代表动画、性能或实际游玩。

本段是在 R12 制作前记录的假设和条件，尚无 R12 作者文件、构建、截图或验收结果。

## 事后补充：生图美术参考

使用内置 imagegen，根据用户提供的主界面参考和 R9b 正式场景截图生成[独立三维造型参考](r12-hero-art-direction.png)，SHA256 `911837c07d7d706ea3f29416f0f91338367105b631982da4059ec1962a895f6b`。提示词要求单艘三桅明式海船、旧朱砂亚麻帆、暖旧木、克制旧金属、清晰的甲板和三帆主次，以及舵、船员、索具和炮位；禁止龙首、额外船只、文字和过度镀金。

生成图只用于观察风化层次、帆桁阅读性和船体暖色，不是模型、不证明历史准确性，也不是 R12 预注册参数的来源。生成图的炮口数与现有游戏的每舷四门合同并不一致，不能照搬；索具、舵和收帆结构均需以真实 Blender 资源及游戏逻辑为准。

完整生图提示词：

> Create a single professionally art-directed 3D ship-model concept reference for the player-controlled Ming maritime war junk in the two supplied images. First image is the user's aesthetic and color reference, second is the current playable in-game model and component reference. Depict ONE complete, plausible, weathered wooden three-masted Chinese junk viewed in a clean high three-quarter side view against a quiet neutral dark desaturated teal studio background, large enough to see its entire silhouette and deck. Keep the actual existing arrangement: fore/main/aft masts, eight battens per sail, four broadside cannons per side, functional deck railings, tiller/rudder, working ropes, believable hull and human-scale crew, with a full main sail and distinct yet harmonious smaller fore and aft sails. Express asymmetrical angled upper sail edges and naturally aged dusty cinnabar hemp, warm worn dark wood, restrained aged brass details, clear tiered stern and bow; use the first reference's vintage Chinese maritime hand-painted atmosphere with credible modern real-time 3D materials. The sail silhouettes should be visibly related but not identical, with a graceful strong main sail and readable battens. Camera design should clarify how the ship is constructed and remains playable, without exaggeration or fantastical ornament. Thoughtful restrained artistic taste, realistic game material variation, no dragon figurehead, no lettering, no interface, no map, no frame, no extra ships or characters close to camera, no diagrams, no excessive gilding. This is a design reference, not a claim of historical reconstruction. Do not change the actual existing model.

## R12 实际制作与画面诊断

已保存独立 Blender 作者文件、三档有界 GLB 与作者中间导出；三档非目标数据和名义 UV / 顶点色保持的独立差异检查、36 项形态键数值检查及 5 项负向测试通过。真实 Blender 三视图和研究入口 80 项检查结果见 [R12 候选记录](r12-author-01/RESULTS.md)。这些检查并不代表转帆扫掠、碰撞或动画验收。

随后在隔离进程中使用 Godot 4.7.2、Intel Arc、Forward+ 绘制[正式场景基线和候选](../../research/evidence/hero-fuchuan/r9-cinnabar-20261027/world-r12-diagnostic-01/LIGHT_STUDY.json)，2 帧、0 失败、进程退出 0。主线和独立审阅均认为，首帆上肩、主帆顶缘和艉帆收束在对照时略有变化，但正常游戏视距仍需仔细盯住边缘，三帆依然规整而相似；预注册的明显艺术收益未达到。保留该候选作为失败对照，不将其切换为正式模型；不以静态图证明动态、LOD、碰撞、性能或人工游玩通过。点划状索具投影仍可见。
