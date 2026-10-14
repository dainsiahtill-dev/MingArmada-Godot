# 海水透射：0.35 档与浅滩保留的正式接入

日期：2026-10-14。

## 用户目标与选择

用户选择了 tuning-3/low-linear-035.png：船底应隐约可见，深处逐渐融入海水。随后要求检查海滩，确认保留原浅滩通透和色调，向深水渐变到 0.35 档。旧 0.65 候选和全海域统一 0.35 均保留为对照。

最终共用 shader 默认参数：

- `water_scattering = 0.35`，单位 m⁻¹，属于有效消光的美术标定，不是实测海水参数。
- `water_linear_transmission = true`，仅水下透射这一步在线性颜色域合成；其余既有反射、天空与调色阶段未重写。
- `preserve_shallow_transmission = true`，按真实海底与离岸距离恢复近岸原有透射。
- 岸边羽化继续为宽度 0.6、原水色权重 0.55。五波、操船、升沉、3D 船员及双侧尾迹算法未改变。

## 方法与实施

远海透射采用：
`T = exp(-(vec3(0.19,0.075,0.035) + vec3(0.35))*optical_depth)`。
背景和水色先从已有显示编码解码到线性域，做 `background*T + water*(1-T)`，再编码回既有后续颜色流程。

靠岸保护权重为：
`P = (1-smoothstep(1.5,6.0,depth)) * (1-smoothstep(24.0,80.0,coast))`。

depth 是平均水位到实际海底的深度；coast 是既有岸场的离岸距离，均为世界米。真正贴岸且水深不超过 1.5m 时，保留原透射与原颜色合成；水深 1.5–6m、或离岸 24–80m 之间平滑过渡，深水/远海使用新方案。离岸浅礁不会仅因为底部浅就全部恢复旧绿底。权重不用屏幕船体深度，不会为每艘船生成一圈独立颜色区域。这里的距离阈值属于画面标定。

改动接缝：

- [共用海水 shader](../../modules/scene_engine/ocean/reference_game_water.gdshader)：新增三个明确参数与局部透射合成。
- [近岸辅助函数](../../modules/scene_engine/ocean/reference_shore_foam.gdshaderinc)：连续深度/离岸权重。
- [ProjectedOcean](../../modules/scene_engine/ocean/projected_ocean.gd)：显式设置默认参数，新的材质与画质重建复用同一方案。
- [已有海面实验](../../game/research/demos/ocean_surface_experiment.gd)：消光滑杆、线性合成开关、保留原浅滩开关；不新增首页示例。

## 实际证据

[统一对照页](evidence/ship-water-optics-2026-10-14/review.html) 引用原始 PNG，不做重绘；HTML 本身未另外进行浏览器交互验收。

- **用户原候选**：[0.35 图](evidence/ship-water-optics-2026-10-14/tuning-3/low-linear-035.png)。
- **正式船体**：[低位](evidence/ship-water-optics-2026-10-14/integrated-close-r3/low-production.png)、[高位](evidence/ship-water-optics-2026-10-14/integrated-close-r3/high-production.png)。6 个同态比较加 12 个真实升沉观察，GPU 回执无失败。正式输出与同分辨率 0.35 候选的平均 RGB 差分别约 0.000114/0.000054（8-bit单位）；局部最大差仍存在，不宣称逐像素完全相同。
- **海滩**：[原方案](evidence/ship-water-optics-2026-10-14/integrated-shore-r3/edge-baseline.png)、[统一 0.35](evidence/ship-water-optics-2026-10-14/integrated-shore-r3/edge-global035.png)、[最终保留浅滩](evidence/ship-water-optics-2026-10-14/integrated-shore-r3/edge-selected.png)。近景/全岛各三模式，同镜头、t=24、原羽化参数。
- 固定近沙 ROI 与原方案的平均 RGB 差为 0；外侧浅水的差异从统一 0.35 的约 24.93 降至 7.31，保留逐步转向深水的变化。该图像指标只描述色彩差异，不是物理透明度或自动美术评分。
- [普通自由试航验收](evidence/ship-water-optics-2026-10-14/default-game-r2/GPU_VERIFY.json) 检查直航、转弯、停船、暂停切换画质；三个光学参数、场绑定、零丢步、3D 船员与原五波分别检查。
- [综合 VERIFY](evidence/ship-water-optics-2026-10-14/VERIFY.json) 区分研究时的冻结 shader/owner 与当前正式源，校验每张图的 SHA。旧研究回执不再被表述为当前源码未变化。

## 合同测试与失败保留

新合同经历 RED 22 项/12 失败；显式 owner 默认接线 RED 24 项/1 失败；浅滩保护 RED 29 项/5 失败。最终 37 项零失败，覆盖实际材质参数、输入声明、非法值原子拒绝、质量切换、重置、时钟/五波不变及真实浅滩权重。相关 optics/ocean/shore 合同已回归，具体原始 stdout/stderr 在综合记录引用的文件中。

第一次正式特写与海滩脚本错误地把 `get_shader_parameter` 的 null 隐式默认值直接转为 float，导致 QA 协程中断。日志保留在 Temp/water-transmission-production-close-run.json 与 Temp/water-transmission-shore-run.json；它们不是通过证据。已让 owner 显式绑定新默认；对未修改的原羽化值，QA 在没有显式值时读取 shader 的真实声明默认，并加类型保护。后续 r2/r3 使用新目录复验。

## 范围与复现

正式默认已接入共用海面。尚未把本轮结果延伸为所有船型、全部天气、任意岸线或整场 FPS 达标。12 张升沉图是在一艘实际航行船上按 0.25s 采样，共 3s；不是完整航程录像。水中厚度仍采用既有 view-Z 近似，折射取样与透射光程的进一步统一属于后续课题。

实验室 → 近海与远海的水面层次，可调三个光学因子；关闭浅滩保护可复现统一 0.35，消光设为 0 且关闭线性合成可复现旧透射。候选参数不会改变物理波或船姿。

只读复核：

```powershell
rtk proxy node tools/verify-ship-water-optics-research.mjs
rtk proxy node tools/verify-godot.mjs --filter test_water_transmission --output Temp/water-transmission-review.json
```

GPU 复验须使用新的输出目录；驱动见 tools/diagnose-ship-water-optics.gd 的 --production-check、tools/verify-water-transmission-shore.gd，以及 tools/verify-interactive-wake-production-gpu.gd。

额外验收纠正：default-game 首次回执虽通过了当时的光学检查，事后发现停船标签下帆面仍为0.85，证明它不能用于停船验收。该运行保持原样并新增 INPUT_CONTAMINATION.json 标为不接受。QA 现关闭自身窗口的桌面输入和焦点，在实际运行时显式下达命令，并断言帆面为0、航速小于0.05m/s；最终采用 default-game-r2。它不是关闭正式游戏输入，而是隔离独立验收进程。
