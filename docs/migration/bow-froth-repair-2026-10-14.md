# 船首白沫修复记录 · 2026-10-14

本轮针对近景船首的厚白 U 形／盘状泡沫。GPU 分层确认，大块白垫来自附着船首网格；四套原粒子系统主要表现细碎喷溅。最终方案保留原贴图、UV、顶点 RGBA、三角索引和原粒子，修复船首网格的海面适配，并根据真实尖首水线与航速限定其长度、外扩和峰高。

本文件与新的 [DELIVERY_VERIFY.json](evidence/bow-froth-2026-10-14/DELIVERY_VERIFY.json) 记录本轮候选。旧尾迹交付记录保留历史状态，没有用新 hash 覆盖旧候选。

## 根因与实际对照

原 `fx_ship_bowfroth.nif` 的 `Box03` 是三维弧面：30 个顶点、40 个三角形，12 个 alpha=1 顶点在升起的弧面上，18 个 alpha=0 顶点组成边缘。按当前 fuchuan 的原单位映射，弧面峰高约 **1.138m**；旧适配却把全部顶点压到 **海面+.1m**。

原模板在本作的固定横向足迹为 **7.103×4.545m**，alpha=1 核心跨宽／长为 **4.304×2.708m**。它附在真实尖首附近，形成明显超出窄船首的白垫。恢复三维高度能纠正压平错误，但 [relief-only 船首层](evidence/bow-froth-2026-10-14/relief-only/bow/t30.png) 的实际 GPU 画面仍过宽，因此没有把恢复高度当作完整美术修复。

| 实际隔离 | 观察与证据 |
|---|---|
| 旧消费者，60Hz 全白沫层 | [dense/all/t30.png](evidence/bow-froth-2026-10-14/dense/all/t30.png) 仍有厚白盘。 |
| 旧消费者，60Hz 仅船首网格 | [dense/bow/t30.png](evidence/bow-froth-2026-10-14/dense/bow/t30.png) 仍有大块 U 形白垫；[原收据](evidence/bow-froth-2026-10-14/dense/bow/VERIFICATION.json) t30→t31 有2059个变化采样点，说明旧网格虽有流动但形状仍过宽。 |
| 旧消费者，60Hz 仅原粒子 | [dense/particles/t30.png](evidence/bow-froth-2026-10-14/dense/particles/t30.png) 是细碎动态喷溅，不能据此把白盘归因于四粒子。 |
| 最终消费者，60Hz 全层 | [after/all/t30.png](evidence/bow-froth-2026-10-14/after/all/t30.png) 去除宽厚船首白垫，保留局部喷溅。 |
| 最终消费者，60Hz 仅船首 | [after/bow/t30.png](evidence/bow-froth-2026-10-14/after/bow/t30.png)、[t31.png](evidence/bow-froth-2026-10-14/after/bow/t31.png) 为独立船首动态证据。 |

诊断使用同一真实模型、固定姿态和相机、平坦海面，按 60Hz 连续推进源调用，隔离已提交的 bow／side／particle 层。这是实际 GPU 材质与网格运行，不是正常游戏入口录制。冻结的 [baseline-source/source_froth.gd](evidence/bow-froth-2026-10-14/baseline-source/source_froth.gd) 与 UV 修正后的旧消费者一致：其中残留的 relief 计算未进入最终高度，最后仍使用原来的平面 water-fit。

## 最终实现

1. **海面重基准保留源弧形。** 船首高度来自源 `localVertices` 的 LocalZ，重基准到采样海面；没有 target profile 时，仍按原高度比例保留弧面。没有以每帧船体绝对高度替代源弧形。
2. **按真实尖首限定局部范围。** `hull_waterline_profile.gd` 在配置时缓存 hull-only 的 model-local Y=0 水线，排除帆、桅杆与索具。通过真实 `Dummy_Bowfroth` 挂点判定前端，在尖首向船身延伸的局部 run 裁出 sections，让原横向载体贴合实际水线，外扩采用已有的有界船外宽度。
3. **峰高与透明强度随航速变化。** `source_water_packet.gd` 提供 `targetBowRun`、`targetBowCrest`、`bowIntensity`。船首使用独立 `target_froth_role=bow`；强度作用于材质 `display_tint.a`，源 `ARRAY_COLOR` 保持原 RGBA。
4. **源内容与其他链保留。** 原 DDS／mips、UV 控制器与源 flags、三角索引和四套 native 粒子未改；Scene30／Battle90 历史、raw marker 与三维船姿保持原接口。没有盲套尚未闭合的原 class scale 表。

速度与尺寸是明确的本作 presentation 适配，不声称这些新增有界参数就是原游戏恢复值：

```text
q = smoothstep(0.35, 6 * 0.514444, speed)
targetBowRun = clamp(beam * .5, 1.25, 3.0)
targetBowCrest = lerp(.04, min(targetOuterWidth * .42, .35), q)
bowIntensity = enabled ? .65 * q : 0
```

fuchuan 的实际 Y=0 水线宽为 **4.972724m**；6kn 时局部 run **2.486362m**、船外宽 **.745909m**、峰高 **.313282m**、强度 **.65**。速度 .7m/s 时峰高约 **.045138m**、强度 **.029176**；停船强度为 0。源模板与尖首贴合而非围绕船中心统一缩小，避免把白沫移入船体内部后完全遮住。

主要代码入口：

- [source_froth.gd](../../modules/scene_engine/water/source_froth.gd)：LocalZ relief、船首局部 footprint、海面重基准及 role 提交。
- [target_froth_fit.gd](../../modules/scene_engine/water/target_froth_fit.gd)：真实水线采样、局部 bow sections 与横向距离适配。
- [source_water_packet.gd](../../game/presentation/world/source_water_packet.gd)：速度、外宽、局部 run、crest 与 intensity。
- [hull_waterline_profile.gd](../../game/presentation/ships/hull_waterline_profile.gd)、[ship_view.gd](../../game/presentation/ships/ship_view.gd)：配置期 hull-only 缓存及真实 model transforms。
- [source_surface.gd](../../modules/scene_engine/water/source_surface.gd)：独立 role 材质强度和遮挡合同。
- [test_source_bow_contact.gd](../../tests/test_source_bow_contact.gd)、[test_source_bow_relief.gd](../../tests/test_source_bow_relief.gd)：真实消费者检查。

## 验证与证据范围

| 收据 | 实际结果 | 覆盖 |
|---|---:|---|
| [bow-relief-red.json](evidence/bow-froth-2026-10-14/checks/bow-relief-red.json) | 588 检查，26 失败 | 改前压平使升起顶点无法保留源相对高度。 |
| [bow-contact-red.json](evidence/bow-froth-2026-10-14/checks/bow-contact-red.json) | 91 检查，38 失败 | 恢复 relief 后仍未限定尖首范围、峰高、速度与独立 bow 材质。 |
| [bow-contact-final.json](evidence/bow-froth-2026-10-14/checks/bow-contact-final.json) | 2 项通过：contact **291**、relief **588** | 六类实际船 contact loop；fuchuan 高／低速／停船；无 profile relief 及海面偏移。 |
| [bow-froth-regressions.json](evidence/bow-froth-2026-10-14/checks/bow-froth-regressions.json) | 6/6，8646 检查 | 源 froth、UV 动画、停发／残留／恢复、footprint、粒子与顶点 RGBA。 |
| [bow-profile-regressions.json](evidence/bow-froth-2026-10-14/checks/bow-profile-regressions.json) | 1/1，1400 检查 | 真实 hull-only 水线、缓存、六船、LOD 与速度参数。 |
| [bow-packet-regressions.json](evidence/bow-froth-2026-10-14/checks/bow-packet-regressions.json) | 1/1，83 检查 | planar Scene30、raw Battle／froth marker、完整船姿。 |
| [bow-wake-regressions.json](evidence/bow-froth-2026-10-14/checks/bow-wake-regressions.json) | 5/5，409 检查 | 原历史／几何 fixtures、renderer、terminal descriptor 和时钟。 |

最终以上 **15 个测试，11417 个检查，0 失败**。RED 记录和重复独审不加入这一通过总数。仅复制指定的九份原始收据，未把 Temp 中其他历史候选归入本交付。

独立复核的 [bow-bounded-final-review-20261014.json](evidence/bow-froth-2026-10-14/checks/bow-bounded-final-review-20261014.json) 为较早的 **91 检查** contact 版本，加 relief 588；[froth-after-bow-final-review-20261014.json](evidence/bow-froth-2026-10-14/checks/froth-after-bow-final-review-20261014.json) 复跑 6 项 froth 回归。它们早于最终六船 loop，不能将六船覆盖归到独审。

[after/bow/VERIFICATION.json](evidence/bow-froth-2026-10-14/after/bow/VERIFICATION.json) 中，t30→t31 的独立船首层有 **193 个变化采样点**，阈值为 RGB 绝对差和 >.03，网格每隔 2 像素采样；可证明该角度下船首自身仍在变化。全层的 **2547** 点同时包含粒子／侧沫变化，只作组合观察，不作为独立船首运动证明。亮足迹计数也来自诊断阈值抽样，不能当作物理面积或整体美术评分。

[occlusion-gpu/current/VERIFICATION.json](evidence/bow-froth-2026-10-14/occlusion-gpu/current/VERIFICATION.json) 使用实际 `SourceSurface` 的 role=bow，Forward+ **3/3 遮挡检查通过**：透明海面不抹去泡沫、实体船壳仍遮住泡沫、位于泡沫后方的不透明几何不错误抹去它。

GPU 回放工具为 [verify-source-bow-froth-gpu.gd](../../tools/verify-source-bow-froth-gpu.gd)，遮挡工具为 [verify-source-wake-occlusion-gpu.gd](../../tools/verify-source-wake-occlusion-gpu.gd) 的 `--role=bow`。本轮没有重跑 sourceModelContract，不能据本表宣称船模型的全部合同再次验收。

## 正常入口与边界

已通过实际主菜单进入自由试航，保存[侧近景 close-01.jpg](evidence/bow-froth-2026-10-14/native/close-01.jpg)和[高位近景 high-close-01.jpg](evidence/bow-froth-2026-10-14/native/high-close-01.jpg)，画面包含实际游戏 HUD、海面、三维船员和尾迹。这两张是有限的正常入口视角；没有声称完全匹配用户截图的正面船首视角，也没有据此宣称全部角度或连续转向帧已验收。

[对照 review 页面](evidence/froth-closeup-2026-10-14/review.html) 已追加本轮 before/after 与新报告链接，并明确页面下方旧候选只验侧沫、当时船首问题仍在。浏览器自动打开 file 协议被安全策略拒绝；没有绕过，也没有将静态文件检查冒称浏览器渲染验收。新交付 hash 只在两张正常入口截图和 HTML 稳定后计算，旧 DELIVERY 不重写。

原 `475550` 的完整 birth／实例生命周期、原 ship class 索引与隐藏 scale ABI、完整 DX9 光照及逐像素等价仍未闭合。本轮确认并修复的是本作船首附着白垫与水线适配问题，不声称所有船型、镜头和美术效果已达最终品质。
