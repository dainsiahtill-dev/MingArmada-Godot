# R8a代理顶面修正候选（运行前）

沿用hero-fuchuan。H4/H6实证区分两条路径，H6又把黑点分成主甲板受hull proxy影响、抬高艉甲板受deck proxy影响。整体位移为诊断，不能进入正式模型。下一候选保持原R7c所有可见组件，只在Blender修正隐藏代理顶面，并维持侧/底连接。当前状态：尚未制作、未验证、未集成。

负责人基于用户持续授权选择：`Closed shadow shell`每个13点ring只将顶面三个顶点（5/6/7）局部Y内收36mm；其余10点不动；独立bulwark块的原sheer底边同时向下延伸36mm，保持与shell接触，炮口上缘/开口与侧面XZ不变。`shadow_deck`每ring仅上面两点内收4mm、底面两点不动。所有连接/三角拓扑维持闭合，重新计算代理法线。36/4mm先于候选运行确定，来自当前共享顶面极值34.455/3.071mm加约1.5/0.9mm余量；不等同证明侧/底全域内包，XZ footprint与接触仍需检查。

独立命名`hero_fuchuan_v3_r8a`、新Blend；旧R7c/R6/纹理/builder不覆盖。沿用原R6造型生成函数与R7c源Blend的两个灰木材质；先原mat选择生成UV，再换同一分区槽。导出后仅沿用已验证有界rudder UV规范化（参考R7c），最终可见几何/法线/UV/形态仍要求严格相等，不接受epsilon。不得以更改几何比较标准掩盖可见模型漂移。

实现细节ruling（导出前）：原B.mesh先按未改tuple建立原UV，再在join/代理法线重算前修改授权顶点；否则代理UV会随位置重生，违反仅POSITION/NORMAL变化合同。此为保真实现选择，不改变内收量或接受项。

接收项：三LOD除shadow_hull/shadow_deck的POSITION/NORMAL外全引用三角属性/形态/节点层级不变，全部材料/嵌入图片相同；两proxy拓扑/数量不变且闭合，其他三mast proxy完全不变；原资源SHA不变；所有可见geometry与桅/帆/舵/炮/crew合同保留。当前不改生产provider或默认入口。

再做同一既有实验、同主镜头/帆态/光照/AA4/GPU：对比R7c与R8a两方向与近景；主甲板和艉甲板黑点同时减少，真实帆影/船体影/炮口/栏杆不出现漏光、漂浮、轮廓断裂。随后连续相机/转向/收帆/损伤/LOD及全场正常入口验收、必要成本测量才考虑正式接线。帆面原生索影点划另行处理，不把此候选称全船或整场艺术完成。

## R8a导出失败与R8b独立包装前瞻

R8a已由真实Blender保存源Blend与三GLB，但LOD1舵UV的最大漂移5.96e-8超过原规范化2e-8上限，导出流程exit1；失败资产及原日志保留，不放宽上限、不称完整验证通过。只读映射确认两隐藏proxy各LOD均为单primitive，indices顺序、属性schema与全部proxy UV字节完全相同；POSITION/NORMAL计数与跨度相同，能建立确定的同索引作者数据映射。

下一R8b采用更小的数据边界：以原R7c每档GLB的BIN为基底，只从真实Blender R8a导出读取shadow_hull/shadow_deck的POSITION/NORMAL float32组件写入其对应原accessor。所有可见模型、原UV、morph、索引、其他proxy、材质与嵌入图像字节不动；此路线不接受或校正R8a舵UV，彻底不使用全量重导出的非目标数据。验证唯一目标节点/primitive、完整indices顺序相等、目标格式/数量/有限值/存储独占、其余proxy属性精确相等，拒绝alias/共享accessor或不支持布局。任何条件失败均不产生半成品输出。

JSON仅允许作者资产身份改为r8b、两目标POSITION min/max按新坐标更新；其余JSON结构值必须相同，BIN仅允许两proxy P/N组件改动。原Blend仍以R8a命名作为真实作者源，R8b manifest明确其是兼容包装增量，不冒称再次Blender完整导出。独立比较器仍要求可见模型精确相同、目标拓扑/其他属性不变且proxy闭合。R8b尚未生成/验证，正式默认仍R7c。

## 后续实际结果（2026-10-27）

上一段“尚未生成”是当时前瞻，已被后续证据超越：R8b三档与真实R8a作者Blend已制作，[CPU transfer](../../research/evidence/hero-fuchuan/rig-frequency-20261026/r8b-transfer-01.json)及[独立delta](../../research/evidence/hero-fuchuan/rig-frequency-20261026/r8b-delta-01.json)记录通过；作者源和三档输入/输出SHA当前复核一致。历史transfer回执没有保存独立进程退出码，不补造。

随后使用更严格的实际阴影与文件验收器，在受控HeroDemo按既有R7c基线、同光向/输入单独取得[R8b连续序列](../../research/evidence/hero-fuchuan/r9-cinnabar-20261027/motion-r8b-01/manifest.json)：257连续PNG、22张固定帆态/LOD/损伤/复位PNG，退出0、失败0；[三组配对审计](../../research/evidence/hero-fuchuan/r9-cinnabar-20261027/pair-audit-r2-20261027/audit.json)检查了状态、风、帆舵、代理、源哈希和原帧。固定相机手动LOD不能代表实际远距离，合成器计数不能证明每帧render-thread revision一一对应。持续操船、完整世界性能、细索点划和独立动态艺术审阅仍未完成，正式默认保持R7c。
