# R9 旧朱砂帆布：模型艺术对照（预注册）

2026-10-27。用户要求主角福船有艺术家的审美，并提供了红帆、青海与暖旧木的明代海战插画参考。当前正式R7c在航行视距的三帆呈近似均一的米灰色、深色船舷缺少明度层次；R8b只更改隐藏阴影代理，不能称为可见造型或配色的改进。此项沿用 `hero-fuchuan` 既有课题，先单独比较一种帆布材质方向，不把配色试验等同船体造型完成。

## 假设和方案

H9：在保持船体、帆/横桁形态、索具、甲板和光照不变的前提下，风化旧朱砂布面能使三帆在实际航行视距更易识别，与主界面所示的青海、暖木和旧红形成统一视觉语言，同时保留自然纤维、背光、收帆和破帆的可信感。纯色统一染色会丢失材料层次；整体加亮环境会改写整个场景；故选择可编辑的真实布料底色纹理，仅替换原 `canvas` 材质的底色图像，先不动船壳和隐藏影子代理。颜色是基于用户参考作出的艺术设计，不宣称历史上每艘福船都使用红帆。

基线为正式 `art_r7c`；候选命名 `r9`，以同一R7c为底，不能与未接受的R8b代理修正混成一个因子。保留旧白帆、原Blender及三档GLB。实际生图贴图为原尺寸1254×1254 PNG，sRGB颜色纹理，未声称物理测量或无缝；需要用实际UV视图核查重复边缘、近景摩尔纹及压缩/缩放效果。初始平均RGB约(170,65,42)，是否过饱和以实际游戏画面决定，不靠这组数值判美术通过。

## 生图来源

内置imagegen，编辑目标为原有 `assets/textures/hero_fuchuan_v2/antique-hemp-sail.png`（SHA256 `f0e431fa9db2032a14d0086ac6a7e03af180629adffaf8121eeb0e038bdd9964`）；色彩参考为用户提供的 `docs/design/2026-10-26-ming-maritime/reference/menu-direction.png`（`d2f3e87d9eee94c0449605cebff3a69a4f37b89604607b578ede1335787a921f`）。生成原图未编辑，复制为 `assets/textures/hero_fuchuan_r9/cinnabar-hemp-sail.png`（`b4bf04b8f2cd5f5558bf63a2c533e95864d7d1b5c16368db5841540dd6695ce8`）。

提示词：

> Use case: style-transfer. Asset: square base-color texture for UV-mapped 3D sailcloth on a Ming-era sailing ship. Image 1 is the editable sailcloth texture; image 2 is a color and period-art reference only. Transform image 1's cream hemp into restrained, sun-faded cinnabar / warm brick-red hemp, matching the old red sails in image 2, with gentle ochre undertones and fine, authentic woven fiber. Preserve image 1's flat, straight-on, evenly lit fabric texture, fine grain, and uniformity across the square so it can tile across the existing sail UVs. It should read as weathered dyed cloth, not bright modern red paint: quiet variation and subtle wear, no large stains, no stripes, no dark seams, no sail battens, no ropes, no folds, no lighting gradients, no image of a ship, no ornament, no text, no border, no watermark. Full-bleed texture only; avoid texture features that visibly repeat.

## 基线冻结与接受标准

R7c作者Blend SHA256 `ac057d349395a5e0547ec20e382188c34ed2c6481778b5142a99c4d920045fb3`；LOD0/1/2分别为 `b87af112855cb6883faf97ec02a5eeb5fd61a5d504f204d3b3a573e73735d02d`、`db9f01b8968f66f2a1c27c689e9a9e0cdd7f03ea27d86a9b6f2bb911872e461a`、`16aa79cb89074879354d82402540f478e9ad5279085d2c53d7f92d579aa2291d`。预先记录的单位为米、秒、百分比、像素和SHA256；无随机输入。

1. 实际Blender另存独立可编辑源，并保留 `canvas` 材质名及其原UV、三个 `sail_*` / `furl` / `inflate`、竹桁、舵/舵柄、八炮、crew挂点和三档LOD。原作者文件、图片和GLB哈希不能变化。
2. 三档候选严格验证：允许变化限定为帆布颜色纹理及必需的图像资源引用；所有被引用的可见几何、节点层级、三角、UV、法线、形态键、其它材质/纹理、影子代理保持精确相同。因Blender全量导出存在已记录的舵UV漂移，必要时以原GLB为底构造受限纹理包装；明确它不是一次完整Blender重新导出，并独立比较，不改变容差来隐藏漂移。
3. 同正式主相机/光照/AA/尺寸/时间/帆态的R7c和R9原帧配对，检查整船、反光、细节、至少三档破帆及连续收帆/转舵；需实际查看纹理缝线、暗部、远景对比和标识效果。颜色过艳、像塑料或帆过暗、接缝/闪烁明显、破帆变白或细索黑点恶化均不接受。影子点划单独研究，不用关闭投影换取漂亮截图。
4. 候选在独立研究中的几何/材质合同、真实GPU动画及艺术审阅通过后，才考虑正式生产接线；正式入口再验证选择、帆、舵、炮、画质切换、暂停/恢复、保存和默认静音，以及全场成本。独立demo的帧率不代表完整游戏FPS。

预注册时状态：已生成原始纹理与冻结基线；当时候选Blend、GLB、对照渲染和正式接入尚未完成。

## 2026-10-27 R9首帧评价及R9b对照预注册

R9实际Blend及三档严格纹理包装已制作，Blender三视图和正式场景冻结首帧随后取得。`world-01` 实际主视角红帆辨识明显，但在当前自然光下偏暗、偏整体色块；主帆中央代表点由R7c约RGB(153,138,121)变为R9约(95,33,32)。这些是两张原帧的局部样本而非全帆平均，也不代表全光照/运动验收。保留R9，不将该首帧称为最终艺术通过。

首轮外层PowerShell隔离启动命令因引号错误未能设置单独用户目录，但内部Godot实际进程完成2帧/0失败、exit0，使用内存存档和独立settings路径；其3项实际原存档前后SHA一致，另将12个原存档/备份/暂存的当前SHA与此前最近GPU回执核对一致。该run仅可用作有明确来源的实际视觉观察，不称隔离环境；后续采用正确隔离配置并新目录复验。

针对偏暗重新由内置imagegen编辑同一织纹，生成更褪色的暖陶红R9b素材 `assets/textures/hero_fuchuan_r9/sunfaded-cinnabar-hemp-sail.png`，原PNG不作像素修改，SHA256 `f89da712948d0b3f3f72506f1375fbe27c8fabee6d816c5ea055ced67b491970`，尺寸1254×1254，平均RGB约(197,112,76)。参考用户同一图片，具体提示见 `provenance-sunfaded.json`。这是新的单一底色纹理候选，并非对世界光照、材质色乘数或投影的调整；各项几何/动画/损伤/三LOD严格标准与前述相同。R9b与R7c同正式条件取得新原帧后，逐项比较红色层次、主体可读性、布料质感和阴影噪声，若仍偏暗、偏艳或变粉则不接受。生产默认仍为R7c。

## R9b已取得的证据（尚未完成验收）

- 实际Blender另存 `hero-fuchuan-v3-r9b.blend`。重开新旧作者文件，按记录的对象/网格/材质结构、UV、形态与节点链接比较0失败；嵌入的PNG SHA匹配生图。三档R7c原BIN完整保留、仅追加目标PNG并重定向canvas图片；[独立delta](../../research/evidence/hero-fuchuan/r9-cinnabar-20261027/r9b-cpu-delta-green-v2.json)全部通过，七个破坏/共享反例被拒绝。GLB是受限包装，不称Blender全量重导出。
- [隔离正式场景](../../research/evidence/hero-fuchuan/r9-cinnabar-20261027/world-r9b-isolated-01/LIGHT_STUDY.json)与[真实进程回执](../../research/evidence/hero-fuchuan/r9-cinnabar-20261027/world-r9b-isolated-01.log.process.json)：Godot 4.7.2、Forward+、Arc 130T、1600×900、均衡画质/MSAA4；同一冻结主相机、灯光和初始状态，基线R7c及候选R9b各1张，3船和35名可见船员未变，2帧/0失败、exit0。实际载入R9b LOD0；音效/音乐均false。原玩家12项存档和备份前后SHA相同。此次由独立APPDATA进程运行，场景authority冻结，不是连续航行或FPS证据。
- 主帆同一代表点：R7c约RGB(153,138,121)，R9b约(124,55,45)；R9约(95,33,32)。这些局部样本只用于定位当前首帧颜色，不能外推背光或实际屏幕色彩。独立艺术审阅认为R9b比R9更温暖、易辨，也更贴近参考，但三帆仍偏平、等距且点划阴影明显；因此保留为继续迭代候选，并未接受为正式成品。[R10帆形](R10-SAIL-FORM-BRIEF.md)及[R11分幅](R11-SAIL-WEATHERING-BRIEF.md)分别继续独立对照。
- [R9b真实模型加载](../../research/evidence/hero-fuchuan/r9-cinnabar-20261027/r9b-experiment-green.log)：59断言/0失败，检查三LOD/三帆、mipmap、furl/inflate和R7c默认；原R9、原provider及帆操纵回归也保留。动作、破帆、真实转向、LOD切换GPU和实机操作仍需后续证据。

随后同一改进后的独立GPU工具分别运行R7c、R9b及R8b，每组保存257张连续原帧、22张固定姿态原帧，退出0/失败0；检查真实阴影compositor及作者代理、帆舵姿态、五档展开（含完全收帆）、三LOD选择、健康80/60/30及暂停/复位。记录的连续序列中展开范围0.2400–1.0000、舵值约−1–1；它由固定步的研究台驱动，五档部署则是单独的受控快照，非真实玩家航行。经独立[配对审计](../../research/evidence/hero-fuchuan/r9-cinnabar-20261027/pair-audit-r2-20261027/audit.json)核验三组状态/风/姿态及837张原PNG散列；记录的光向精度、渲染线程revision、实际远距离LOD及光色/强度仍有审计边界。已人工看R9b正/反光、全收/半展、重度破帆、近布面及每16帧一张的17帧索引；局部点划与平整感仍在，不能由此宣称全部257帧均已人工审核。供检查的[无声音32fps预览](../../research/evidence/hero-fuchuan/r9-cinnabar-20261027/motion-r9b-01-preview.mp4)由257原PNG编码，非原生游戏录像、非性能数据。原玩家12项状态在上述隔离运行后仍与先前一致。系统级连续操船及全场性能仍未测。
