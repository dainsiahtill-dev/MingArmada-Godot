# v3-r3 帆面锯齿明暗：只读根因审查

2026-10-26。范围：查看 `gpu-r3/full-sail.png`、`reverse-light.png`，追踪 `build_hero_fuchuan_v3.py` 的 `sail_surface/sail`、`ShipView`、`ShipDamage` 材质替换，以及当前 LOD0 GLB 的 canvas 基底/形变 POSITION、NORMAL。未修改模型或运行时，未启动游戏或重跑测试。GPU 单因素诊断由主线程执行。

**当前最可能：帆片波形的周期斜率突变，加上很稀的纵向采样与近切向光照，放大为周期明暗；其中“独立桅杆投影到起伏帆面”与“直接光的法线明暗终止带”尚需分离。源 GLB 负鼓帆法线外推没有表现出足以解释症状的数值错误。**

## 已确认的数据路径

- 源帆面：`x=.32+(.30*sin(pi*v)+.11*sin(pi*((8*v)%1)))*sin(pi*u)`；全帆鼓腹叠加每片帆骨之间的同向鼓包。
- `panel=sin(pi*fract(8*v))` 等价 `abs(sin(8*pi*v))`，在每个 `v=k/8` 连续但不可微。波形两侧斜率由 `-8*pi` 跳到 `+8*pi`，本质上在帆骨位置植入了规则折点。
- LOD0/1/2 分别 32/24/16 行，每帆 8 片，即每片只有 4/3/2 行。固定对角线三角化后的 quad 很容易表达成规律折片；`use_smooth=True` 只插值法线，不能让几何波形本身变成一阶连续。
- 帆骨与缝线复用这一曲面；补丁是偏移 `.026m` 的独立 canvas 网格，不能解释 r2 已有、覆盖全部帆面的周期条带。
- `ShipView` 全帆初态 `sailAngle=.42`，deployment=1，wind speed=14，因此 furl=0、inflate 约 `-14/18=-.7777778`。当前锯齿并非必须依赖收帆目标。
- shader 没有修改 VERTEX、NORMAL、NORMAL_MAP，也没有自定义 light；它使用原 UV/纹理/COLOR，再给原创帆布 `BACKLIGHT=base*.5`，其余交给标准空间光照。

## 源 GLB 数值检查

三张帆的 canvas primitive 均有 676 顶点、1224 三角形，包含 POSITION/NORMAL/TEXCOORD_0/COLOR_0；`furl`、`inflate` 均导出 POSITION 和 NORMAL target。

| canvas | 基底法线长度范围 | inflate 目标最大改向 | 负权重 -.7778 后法线与面积加权几何法线 P95 / 最大夹角 |
| --- | --- | --- | --- |
| sail_0 | 约 .99999993–1.00000012 | 3.373° | .792° / 2.074° |
| sail_1 | 约 .99999994–1.00000012 | 3.431° | .489° / 1.372° |
| sail_2 | 约 .99999993–1.00000012 | 3.350° | .910° / 2.394° |

计算使用 glTF 标准相对公式 `P=P0+w*dP`、`N=N0+w*dN`，再由同一索引的形变后三角形独立累加几何法线。权重 0、+.7778、1 也没有爆炸：全部帆 P95≤.95°、最大≤2.95°；负权重法线长度最低约 .99997。Blender 平滑法线与面积加权法线本来不必完全相同，这些小误差不能当成错误证明。

这排除了“源 GLB 法线已损坏或负 inflate 导致法线接近零”的强假设；**尚未检查 Godot 实际导入后的法线数组或 GPU 内部形变结果**，因此不能排除导入/打包层异常。

## 排序假设与最小判别

### 1. 波形/采样与近切向光照：优先

实验光源旋转 `(-40,-30,0)`，桅杆 yaw=-.42。按当前变换，指向灯光的向量在帆局部约为 `(-.0792,.6428,.7619)`：与平帆法向几乎垂直。用源主帆正常法线和负鼓帆目标计算，N·L 范围约 `-.0509…+.1849`，部分帆片从鼓包上半到下半会跨越零。8 个规则鼓包对应 8 组明暗变化，与图片的重复周期吻合。

**还不能排除独立桅杆影。** 帆 MeshInstance 的 cast_shadow=OFF 仅关闭帆作为投影者；独立 `mast_timber_*` 仍能向帆投影。由于光的法向分量只有 .079，帆与桅之间约 .3–.7m 的法向距离会将桅影沿帆面方向放大到数米；每片 `.11m` 起伏足以让影子边界摆动约 1m。`reverse-light` 的宽带形状与这一机制相符，这是几何与照明关系的推断，未获 GPU 证实。

**最先做的分离：** 只将实验 DirectionalLight3D.shadow_enabled=false，保留直接照明。若宽带消失，接着只关闭 `mast_timber_*` 投影以定位投影者；若宽带仍在，优先查 N·L/法线路径。这是诊断，不是建议最终关闭阴影。关闭帆的 caster 不能替代这一步。

**最小判别：** 保持姿态、光照、shader、纹理、原 `.30*sin(pi*v)` 全帆鼓腹及 inflate 不变，只在临时诊断候选中将 `.11*panel` 置零。若宽锯齿消失，根因落在帆片曲率/采样；不是 shadow caster 开关。后续应重新设计受力曲面与一阶连续性，并在原光照下证明结果，不能靠关光照交付。

另一只读诊断思路是在同一捕获中输出带符号 N·L 或法线颜色：若图案跟随法线场而非阴影衰减，即可分离直接漫反射终止带与投影。注意使用同一坐标系转换光向量，防止诊断 shader 自己制造假信号。

### 2. Godot 导入/形变法线与 glTF 数值不一致：次优先

源码 GLB 正常不保证导入 mesh 和渲染后法线仍正常。AssetLibrary 使用 `GLTFDocument.append_from_file/generate_scene`，随后打包 PackedScene；没有自定义替换法线。需要在这个边界比较基底、target NORMAL 和 `blend_shape_mode`，不能把相对 delta 与绝对 target 混为一谈。

**最小判别：** 同一姿态只比较 inflate=0 和当前 -.7778；读取导入后的 base/shape 数组，按其声明模式算出实际 P/N，与 GLB 的 P0+w*dP、N0+w*dN 对照。若零权重正常而负权重异常、导入数组或实际法线编码出现大角度差，才追导入/形变通路。现有源数值证据让这个假设排在波形之后。

### 3. 双面 shader 与背光放大：需要分离，不能盲目翻法线

`cull_disabled` 与 `BACKLIGHT` 可能使近切向法线变化更醒目。当前 Godot 官方 Forward+ 源码会在启用 DO_SIDE_CHECK 时按 `gl_FrontFacing` 翻转背面插值法线，因此“再手动乘 -1”可能造成二次翻转；需结合实际引擎版本和材质生成条件确认。见 [Forward+ fragment 法线处理](https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl)；该链接是当前上游源码，并非对本机二进制的版本验证。

**最小判别：** 维持同一几何和形变，只将 canvas 的 damage ShaderMaterial 替回原 StandardMaterial3D，保持双面与相同 albedo/roughness。若两者均有同周期锯齿，问题在共同法线/几何或引擎照明；若只有 damage shader 出现，再单独检查 BACKLIGHT 与正反面处理。禁止同时换几何和材料后宣称找到了根因。

## 不支持继续投入的方向

已知帆的 cast_shadow off/double 没有消除症状，继续重复同一帆 caster 开关不能区分上述假设；阴影 bias 也不应作为先行修补。需首先区分“帆是否投影”与“帆是否接收独立桅杆影”。UV/颜色通道存在，r2 在 r3 增加 SailAge 前已出现相同宽锯齿；不能将新旧颜色或纹理缺失作为首要解释。SailAge 使用离散 panel/sector 值并做顶点插值，可能产生额外三角色差，但不解释原始 r2 症状。

本审查没有宣称根因已获 GPU 证实。最高收益下一步是先用全灯 shadow_enabled 单变量分离投影，再针对性做第 1 项波形幅度或直接法线/N·L 可视化，利用主线程正在执行的受控 GPU 诊断闭环收敛。
