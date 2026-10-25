# r6 独立技术复核

日期：2026-10-26。范围：r5 与 r6-b 实际 GLB，三档 LOD；provider、角色消费者及释放路径只读审查。以 `r6-glb-contract-audit.json` 内逐文件 SHA-256 锁定此次证据。未运行 Godot/GPU，未改生产代码，未认证 FPS 或用户美术认可。主线程已说明本轮 CodeGraph 无索引，本审查使用 RTK 精确读取。

**结论：未发现阻断航行、炮击、帆控、甲板支撑或阴影坐标合同的 r6 回归。存在两项美术 brief 偏差，需保留为限制；不能把工程合同通过写成造型全部通过。**

## 实际资源比对

独立 Python 解析 GLB JSON/BIN，按 accessor 组件读取有效元素，处理 byteStride 和 sparse morph，排除存储偏移/填充后比较有效字节、解码数值、元数据。Sparse 的索引和替换值也各自比较 SHA-256。另比较完整父链与本地 TRS，不仅比较节点名称。审查脚本：`C:/Users/dains/AppData/Local/Temp/r6_independent_audit.py`。

- 每档 43 个指定合同节点。LOD0/1 各 228 个 accessor，LOD2 为 204 个；全部字节、数值、元数据一致。
- `hull`、`deck`、`sail_0..2` 的全部 attribute/index accessor 不变；三帆 `furl` / `inflate` morph accessor、目标名称、初始权重及父桅坐标不变。因此本轮没有重写船体尺寸、主甲板或帆形合同。
- `shadow_hull`、`shadow_deck`、`shadow_mast_timber_0..2` 的全部有效数据及父链不变。五组代理与可见对象逐组拥有相同父节点及本地坐标，未出现代理/全模坐标漂移。
- 八个 `socket_smoke_*` 本地坐标及整条 cannon/root 父链完全相同；八个 `barrel_*` 几何和坐标也相同。此结论直接来自两版资源，不是源代码推断。
- `rudder_pivot`、三桅 marker、`crew_helm`、`helm_grip` 坐标不变。`rudder_stock`、`tiller_beam`、`tiller_grip`、三根 `mast_timber_*`、三份 `rigging_*`、两处水效 marker 的指定合同数据不变。
- 三档实际变化集合一致：已有 mesh 只改变 `bulwark_rails`、`deck_fittings`、`rudder_blade`、`sterncastle`；新增 `stern_transom` 和 `rudder_hardware`，移除三份旧 `Rudder gudgeon`。没有把高细节精修合入五份低面数阴影资源。

## 角色与生命周期

`art_r6` 独立解析到新目录；审查时 provider 默认仍为 `art`。新增后横墙具有 `deck_obstacle`；新增舵铁件由 `rudder_pivot` 携带。帆、炮管、桅杆的识别仍经过原有名称和元数据，舵控制仍为原有 `±0.42 rad`。provider 隐藏 `shadow_*` 节点，只在同父且同本地 transform 时绑定代理 Mesh。

阴影消费者仍从可见完整部件取得 `global_transform`、可见性与 native-shadow 回退，只替换几何输入。破桅仍移动父桅，其可见 timber 与代理同框架。新部件没有单独注册额外每帧服务。`ShipView.dispose()` 释放模型及角色绑定；实验 `dispose()` 断开一次性 post-draw 回调、释放影子 renderer/adapter，再释放船与 world。未见 r6 特有生命周期泄漏路径；这属于源代码审查，不能替代运行中重置/释放验证。

## 应保留的限制

1. **两扇新增尾窗仍在完整实墙前。** `refined_stern()` 构造的 `stern_transom` 没有窗洞；`deck_fittings` 的暗色窗面位于其外侧。三档 GLB 独立三角形射线复现：从 `(-0.78,3.59,-17)` 到 `(-0.78,3.59,-14)`，先在 t=0.4508333/0.4591665 命中 fittings，再在 t=0.4643284/0.5107925 命中完整 transom；另一窗 x=0.88 同样成立。侧窗生成器已实际分开墙面，上述限制特指两扇后窗。若后窗应作为真实凹窗交付，需开洞与退进背板；若作为盲窗，交付文字需明确。当前测试只射检侧窗，未覆盖后窗。
2. **舵叶投影面积略超 brief 的收缩目标。** 从实际闭合舵叶三角形计算局部 YZ 投影面积：r5 为 6.3744999 m²，r6 LOD0/1/2 为 5.9891685 / 5.9889544 / 5.9894501 m²，约减少 6.04–6.05%，略超“尽量 ±5%”。测法为闭合、前后两皮无投影自叠的舵叶全部三角形无符号投影面积之半。此为视觉工作面偏差，游戏操舵权威未随 mesh 面积改变。

肩部、收脚、楔形截面和并入同轴的铁件在导出几何中存在；源代码与资源结构符合本轮局部精修方向。完整舵扫掠碰撞、灰模光面与原帧视觉是否令人信服仍由主线程 GPU/连续动作验收负责。本独立报告不冒用主线程 202/227 断言或 GPU 结果作为自己运行的证据。
