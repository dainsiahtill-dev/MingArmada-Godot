# 新增海岛学习台与 Godot 合同比较

2026-10-11，只读学习新增 `naval-study/island-water`、原损伤纹理及当前 Godot 实现；本任务只新增本报告。未修改原参考、源码、水面参数或导入资源，未运行 UI/GPU 或测试。目标项目 CodeGraph 未建索引，按主线程提供的不可用结论用 RTK 读取；未重试建索引。

**结论：学习实现的接口与采样原则值得采用，默认水面算法和美术参数不能整套替换。** 用户要求保留原网页水面，本项目的五波、世界轴、accepted time 和注入波查询仍是集成合同。新增网页是自行编写的 WebGL2 学习示例，原游戏资源仅提供部分输入与研究证据。

已阅读 [新增 README](C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/README.md)、[AGENT_HANDOFF](C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/AGENT_HANDOFF.md)、[原地形 shader 解释](C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/ORIGINAL_SHADERS.md)、[资源证据](C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/source-study/SOURCE_REPORT.md)及 `demo/model.mjs`、`shaders.mjs`、`renderer.mjs` 的具体实现。另读原海面静态反射调用报告及深度学习台损伤材质选择代码。

## 已确认的学习点与当前对应

| 学习台事实 | 当前 Godot 对应与结论 |
|---|---|
| Cat Island 高度输入来自原 BMP 调色板索引；128 海陆阈值、0.35 高度倍率、160 覆盖范围为演示自选 | 当前注入 terrain Callable 不依赖这些原图。若研究原 H 图，读取整数索引，不能对彩色预览转亮度；不得把演示比例标成原作常量 |
| `terrainMesh` 生成三角网格；R32F LUT 直接保存实际绘制的 Float32 顶点 Y，`heightCode` 按同一对角线三角插值 | 当前 `terrain_chunk.gd` 用实际高度采样建网格；`shore_field.gd` 另生成固定分辨率 RF 高度图，由 shader 线性过滤。它是连续场近似，不是与每个近/远景三角面精确相等的 LUT |
| 岸线修正从原图双线性曲面改为真实绘制三角面；学习报告记录旧误差约 0.678 | 可借鉴“同顶点、同对角线、同分辨率”合同。若将来追求精确贴岸，应按当前 chunk/LOD 的实际顶点建立查询，不直接抄固定 161×161 和 160 分辨率 |
| 新水面为四分量 Gerstner，含 X/Z 位移、解析法线和 footprint 滤波 | 本项目保留五个正弦分量；GPU 只改变 Y，CPU 查询原世界 X/Z，因此无 Gerstner 反求需求。四波强度/尺度/滤波不能替换默认五波 |
| `waveAt` 的输入是未位移参数坐标，直接把已位移世界 X/Z 传入会产生误差 | 仅在另设 Gerstner 实验配置时需要迭代反求参数 X/Z，再取 Y。不能把这种水平位移误差强加到当前仅垂直位移的波模型 |
| 学习台岸深决定 foam，另有程序湿沙/焦散 | 当前岸线距离、深度、高度与原 alpha 泡沫分层，船尾迹独立。保留已有近岸衰减，不把浅沙洲直接当岸线，也不让船浪承担冲岸 Surf 生命周期 |
| 两个离屏目标、正常场景→镜像场景→主场景+水面，无水面反馈采样 | 当前水面使用自身着色与反光，没有此学习台的两个显式反射/折射 FBO。此处是可新增的渲染能力，不是“已接入原反射” |
| 海底延伸、程序天空/材质及 UI 自行编写 | 可借鉴避免有限贴片边界和资源释放的思路，但海底、海岛和可航区域仍以本作权威数据为准，不导入演示海底作为航行证据 |

当前 CPU `coastal_wave_field.gd` 与 GPU `coastal_wave_functions.gdshaderinc` 均在 0～8m 水深衰减原五波；CPU 直接查询高度 Callable，GPU 读取 shoreline RF 场。二者共享波与衰减规则，但离散采样方式不同，不能只凭公式就声明所有岸线位置完全一致。船体、炮弹海面命中、尾迹、落水人物应继续消费注入的连续权威波与同一 accepted time；表现层不另开墙钟。近船画面应保持足够分辨率，实测穿插与波高误差。

## 深度、反射与颜色：必须重新适配

学习台 `linearDepth` 固定 near=0.3、far=1200，使用 WebGL 标准深度。Godot 4.3+ 使用 reverse-Z；Forward+/Mobile 的 NDC 深度范围为 0～1，Compatibility 为 -1～1。应由当前投影逆矩阵重建 view position，齐次除法后取 `-view.z`，不能复制学习台的固定公式，也不能在 Godot 原始深度上重复做 WebGL 的 `2d-1`。[Godot 官方深度说明](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html)

反射对象、裁剪平面、目标实际宽高比、UV 翻转、开关/resize/场景退出释放都须独立验收。平面反射不得采样自己正在写入的目标，也不得将本水面再次绘入反射；不同 viewport 的深度读取能力要按引擎合同处理。当前环境采用 ACES、线性地形颜色，原水面另保留迁移时的屏幕色转换合同；不能把学习台显示空间颜色直接加入 HDR/PBR 再重复 gamma。

原研究已有 512×512 反射目标创建、绘制、恢复静态链；这支持继续研究反射，并未证明原游戏实际帧中的最终材质、镜像矩阵和透明排序。`ReflectiveWater` 的 `Top` 与运行代码查询 `Plane01` 差异仍未知。新学习台反射宽度最高 768 是新程序选择，与原 512 目标不是同一证据。

## 原损伤预览：优先学习分布，不盲套 UV

亲自查看三张原 PNG，并在内存中分离 alpha 查看；未向原目录写衍生图：

- `Pak7/ship_sail_damage040.dds.png`：RGB 恒定 `(74,64,57)`，alpha 0～255。alpha 显示稀疏、不规则的局部孔洞，边缘有碎裂。直接看 RGB 单色预览无法辨认损坏形状。
- `Pak1/ship_sail_damage080.dds.png`：同样恒定 RGB，alpha 显示数量更多、形状拉长且相连的撕裂与边缘破损；不是每个网格单元一个同样圆孔。
- `Pak7/ship_hull_damage040.dds.png`：256×64，RGBA 有变化；alpha 中损坏集中为局部冲击簇和放射裂痕，不是覆盖全船的等密度细线。

当前 `ship_damage.gd` 已保持船体 20 量化、船帆 6 量化和有限关键帧时序；`ship_damage.gdshader` 采用程序 UV 网格孔与裂痕，属于本作设计。美术改进可保持量化、私有材质与权威伤害不变，转为确定性的少量不规则撕裂/冲击簇，避免全帆规则筛孔和全船统一变黑。原材质四槽包含底纹、标记、damage、scorch；两张预览不足以证明原组合效果，且原船 UV 与本作 GLB 不同，直接换纹理并不保证位置正确。破损分布改动必须重新验收六船型、各 LOD、近景与中远景。

## 本次没有声称的验证

来源 README 记录 Node 8 项、浏览器 27 项、GPU 波/岸线读回误差；这些是对学习台的既有证据，本任务未重跑，不能当作当前 Godot 测试或原游戏 GPU 帧验收。完整碰撞原语、六自由度浮力、任意网格断裂、40 槽救援玩法仍不因该 demo 自动成立。

本任务建议的顺序是：保持当前水面合同，先用原 alpha 分布改善受损视觉；保留现有近岸模型并测实际三角面与岸图误差；将来有独立反射性能预算时，再以可关闭配置验证镜像/折射。GPU 对比与项目全套验收由主线程负责。

## 本次阅读文件 SHA256

| 相对参考根目录的文件 | SHA256 |
|---|---|
| `naval-study/island-water/README.md` | `ff62eaa01e7d4a203607710d6c42a3b2704c6f5b4c78f47a47b8111074b27f6e` |
| `naval-study/island-water/AGENT_HANDOFF.md` | `2bc57242534a0da4b1f78b9590adf1925b099f002112d301eea54477be951ae9` |
| `naval-study/island-water/demo/model.mjs` | `39dda7dfbef6184f79975e73aa13a07899e5ebe8818cce4cdfa3f78893238d57` |
| `naval-study/island-water/demo/shaders.mjs` | `652df55dae5f76b8d50dba72413b42462ee06d6a475caa0a715f471775608d12` |
| `naval-study/island-water/demo/renderer.mjs` | `82f2afde7bd0699dff66a5a532bbf33f4cb941e3d25090a084097b81565f2c7f` |
| `naval-study/island-water/ORIGINAL_SHADERS.md` | `6291813687cd54ebd76bdd534b596a62b62c94551075f1f09096d6dc314f41ba` |
| `preview/images/fpk/Pak7/ship_sail_damage040.dds.png` | `add849bf932329d4ed6c98a014385d6c72a2b6a628996bcfb0114466b76a25ec` |
| `preview/images/fpk/Pak1/ship_sail_damage080.dds.png` | `3f54cd63f152f4a92c6cea4f90844eabe487923f94ad36c42bf14c7ff0a2568d` |
| `preview/images/fpk/Pak7/ship_hull_damage040.dds.png` | `a4470098a6dc51643904a7e654c5911b599dca8168f31bfb81ca3766d0e14394` |
