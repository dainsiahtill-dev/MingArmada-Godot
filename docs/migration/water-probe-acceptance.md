# Godot 海面首项验收

## 后续实际航行与明亮美术验收

以下为用户继续迁移并提供三张《席德梅尔的海盗》水面参考图后的新增验收；下方首轮记录保留其当时边界。

默认主场景已改为 `game/scenes/sailing_trial/sailing_trial.tscn`。实际福船物理、原 GLB、水手动画、明亮深水/青绿浅水/岸线白浪同时运行。`evidence/sailing-trial/route-0.png`、`route-1.png`、`route-2.png` 与 `tactical.png` 是真实 viewport 保存，JSON 含引擎/GPU/相机/相同物理状态；Root 逐张查看。24 张 `shore-loop-00..23.png` 为 6 秒固定镜头，`shore-waves.gif` 仅由这些原生帧编码。截图不代表完整海战已接通。

查出并修正三项实际视觉问题：Three 网格索引与 Godot 前面绕序不同导致岛面缺失；原五波波谷 −3.08m 低于 −2.4m 浅滩而露出灰色海底；低码头被高浪盖住。地形反转索引；新明亮样式在 0..8m 水深使用 smoothstep 衰减，船只、水手、水面和水花共享此规则，深水和原始样式保留五波；码头顶面抬高到 4.2m。地形采样和碰撞网格未降低或替换。

物理 CPU 精确采样实际高度场，GPU 从同一高度场生成的 512×512 RF 纹理取样，近岸存在纹理/网格插值近似；不能承诺逐像素或逐点完全一致。视口覆盖增加 10% 投影余量，避免波位移在屏幕边缘露空；相机静止时复用投影网格。

原波形对照仍有 77 项检查；另有浅水波形 1090 项、正确绕序 32 个三角形、输入路径 8 项及世界生命周期验收。原生输入测试使用生成的 Godot 键盘事件，未冒称人工逐键操作。

首轮实现文档中的原水面算法仍保留，新增 WaveUniforms 和 shared shader include 替代硬编码重复展开。原始源哈希描述指来源文件，不等于新增明亮样式与原网页画面完全相同。

## 首轮记录

2026-10-11。用户已认可海面方向并要求继续迁移。原生验证已运行，完整迁移仍在执行。

实际环境：Godot `4.7.2.stable.official.ed1daf0bf`，Windows D3D12、Forward+，Intel Arc 130T（16GB），1600×900。原生 Godot viewport 直接保存 PNG，未使用网页截图冒充 Godot。

执行记录：Root 运行 `tests/test_water_probe.gd`，76 assertions / 0 failures；48 个原 JS 黄金样本波高最大误差约 1e-14、gradient 0、normal 1.1932565e-7。Root 运行 `water_probe.tscn -- --capture`，三个镜头、0/24.7/80 秒共九张原生截图，退出 0，无 shader 编译或运行错误。Root 亲自查看船长/高位/地平线截图，水纹、雾和透明海面均实际存在，原福船可见。

首轮偏亮和白船保存在 `evidence/water-probe/initial-unaccepted`。修正原因：原 balanced projected fragment 直接输出 screen RGB，而 Forward+ 会编码输出；保留原公式，添加输出转换并使用 linear tonemap。原 GLB 色彩保存在 COLOR_0，实际 4.7.2 runtime GLTFDocument 生成的首个材质 `vertex_color_use_as_albedo=false`，Root 日志确证并启用，不重涂模型。修正截图和 GPU/相机/时间输入记录在 `evidence/water-probe/`。

范围限制：本次证明原生 Godot 能运行该海面算法、原纹理和原船模。截图未实现船舶操纵物理、水手、港口经营或海战。参考船只是波姿态视觉参照。Godot 的 linear 透明混合和 Three direct-screen 混合有区别，不承诺完整 frame 像素一致；原 high/legacy bloom 是另外的输出链。岸形只用原公式采样的三岛 fixture，简化颜色和细节未作为完整世界迁移。

帧间隔样本仅来自冻结的单船海面场景，不能当作完整游戏或多船海战性能结论。

后续：迁移独立船舶数学、操船输入、原生世界和资产，再接海战、水手、经营和存档。保持原网页只读。
