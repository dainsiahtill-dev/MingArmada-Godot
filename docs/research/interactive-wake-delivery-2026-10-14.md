# 交互尾迹交付记录 · 2026-10-14

尾迹已完成独立 GPU 验证、正式场景验证与默认接入。正常试航无需候选开关即可使用新场；原尾迹仍作为未覆盖船只和失败路径的回退。此次结论限定于下面列出的尾迹源码与证据，不表示整个工作树全绿、整个游戏完成或达到某个整场帧率。

机器可读清单为 [DELIVERY_VERIFY.json](evidence/wake-flow/DELIVERY_VERIFY.json)。纳入最终联合正式运行后，交付审计实际校验了 **1161 张原 PNG，559,380,811 bytes（约533.47MiB）**，以及关联 GPU 回执、raw readback、严格进程 wrapper、CPU 回执和来源文件的 SHA256。逐文件哈希、文件大小、PNG 尺寸及核验断言保存在清单中。审计工具为 [verify-interactive-wake-delivery.mjs](../../tools/verify-interactive-wake-delivery.mjs)；默认只读，不启动 Godot 或 GPU。首版交付清单另存为 [DELIVERY_VERIFY.initial.json](evidence/wake-flow/delivery-2026-10-14/DELIVERY_VERIFY.initial.json)，没有覆盖原三组正式证据。

## 验收如何分层

这项工作采用可被反例推翻的工程假设：船体真实三维运动应成为局部水面的输入；双侧泡沫应留在世界空间、扩散并消散；转向不能把旧泡沫一起旋转；同时间观察不能再次注力；已发布纹理与世界 bounds 必须来自同一代；场不可用时原尾迹仍应正确显示。

这些假设分开接受检验。CPU 回归验证时间、队列、单位、资源所有权和回退合同；GPU readback 检查实际计算结果；原图与短连续采样检查表现；正式场景再验证默认入口、其他船只回退和画质重建。自动回执中的 `valid=true` 只证明该工具的检查通过，不能代替美术判断。此前单中线方案、主帆裁切和有限平面边缘都曾在数值或执行检查通过后被人工否定，失败材料仍保留。

本轮实际 PNG 已由 root 查看；用户在本轮会话中的反馈为“好很多”。这是有来源的人类视觉反馈，不是由自动指标推导的美术分数。本次交付审计未重新运行 GPU。

## 数值 GPU：9 个真实 readback 回执

[interactive-field-gpu-4/GPU_VERIFY.json](evidence/wake-flow/interactive-field-gpu-4/GPU_VERIFY.json) 为9个数值回执，Intel Arc 130T、Forward+，严格进程 wrapper 退出码0、完成标记唯一、`failures=0`。对应原始 RGBA32F 与 EXR 均存在；RGBA32F 哈希与回执逐项一致。[执行 wrapper](../../Temp/interactive-field-gpu-4-run.json)

| 数值检查 | 实际证据 |
| --- | --- |
| 脉冲与重复时间 | `01-impulse`、`02-duplicate` raw SHA256 完全相同；重复接受时间没有改变场 |
| 世界窗口移动 | `03-remap` 在不增加积分步的同一接受时间重映射，窗口移动0.375m |
| 波动传播 | `04-propagated` 到1.0s；本回执最大绝对高度0.002816405m |
| 时间回退 | `05-rewind-reset` 高度和泡沫总量归零 |
| 双侧泡沫与停止出生 | `06-dual-foam` 泡沫总量68.14537；停止来源1秒后 `07-stopped-decay` 为54.28422，减少20.3406% |
| 转向后旧泡沫 | `09-old-drift-after-turn` 保留旧泡沫向两侧漂移的数值检查；新方向来源放在远处 |
| 陆地遮罩 | `08-dry-mask` 使用真实 GPU 遮罩分支，`land_masked=true` |
| 发布所有权 | publication checks 包含等待消费者 ACK 时保持已发布 generation/bounds 的压力夹具 |

九个数值回执的 `dropped_steps` 均为0。此组只证明局部计算、readback 和发布合同；不单独证明船体外观、正式海面像素或整场性能。

## 实验室：十组动态矩阵与正式投影对照

[lab2 REVIEW_SUMMARY](evidence/wake-flow/interactive-lab-2/REVIEW_SUMMARY.json) 的十组回执均存在、`valid=true`、零失败，共943张原图。下表高度/泡沫值取各组**最后一次实际 readback**，不是对整段时间求得的峰值。秒数仅作显示舍入；原接受时间保留在 JSON。

| 组别 | 原图数 | 接受时长 | 末帧最大绝对高度 m | 末帧最大泡沫 |
| --- | ---: | ---: | ---: | ---: |
| source-cruise | 97 | 12s | 不适用 | 不适用 |
| cruise | 97 | 12s | 0.056143 | 0.787659 |
| side | 97 | 12s | 0.056143 | 0.787659 |
| turn-left | 114 | 16s | 0.048521 | 0.522665 |
| turn-right | 114 | 16s | 0.050699 | 0.633818 |
| stop | 146 | 24s | 0.043333 | 0.012296 |
| reentry | 83 | 8s | 0.053600 | 0.529726 |
| small（fisherman） | 97 | 12s | 0.038764 | 0.606158 |
| height 诊断 | 33 | 4s | 0.054995 | 0.801202 |
| foam 诊断 | 65 | 8s | 0.059521 | 0.529738 |

lab2 使用当时的有限 PlaneMesh。侧视原图暴露了384m平面远端；因此这组保留为动态矩阵，不能充当最终海面载体验收。reentry 是已标注的2m表现压力夹具，不称为真实飞船或腾空物理。stop 通过实际收帆命令减速，不把场景名称当作速度已经为零的证明。

最终载体对照为 [lab3 source](evidence/wake-flow/interactive-lab-3/source/GPU_VERIFY.json) 与 [lab3 field](evidence/wake-flow/interactive-lab-3/field/GPU_VERIFY.json)，各97帧，共194张原图。交付工具重新逐帧比较了完整 `native_ship`、记录的船体摘要、相机 transform/projection、tick 和接受时间：97对全部一致。这不是只读取已有 `paired=true` 标志。[原配对回执](evidence/wake-flow/interactive-lab-3/PAIR_VERIFY.json)

两组实际载体均为正式 projected Ocean、80分段、6561顶点、38400索引，距离上限3000m；这与正式默认80一致。field 组97帧均 ready/bound，发布接受时间匹配请求，`dropped_steps=0`。最终12s readback 的最大绝对高度0.056142878m、最大泡沫0.787659168，原 RGBA32F 为1,048,576 bytes。独立实验是开放深水，未启用陆地遮罩；正式场景的遮罩验证在下一节。[source wrapper](../../Temp/interactive-projected-source-3-run.json)、[field wrapper](../../Temp/interactive-projected-field-3-run.json)

## 正式场景：baseline、显式候选与无开关默认

[baseline](evidence/wake-flow/interactive-production-1/baseline/GPU_VERIFY.json)、[candidate](evidence/wake-flow/interactive-production-1/candidate/GPU_VERIFY.json)、[default](evidence/wake-flow/interactive-production-1/default/GPU_VERIFY.json) 各6张原图、零失败，共18张。三个严格 wrapper 均退出0、无诊断错误、完成标记唯一；默认运行参数没有 `--candidate` 或 `--baseline`，其回执为 `baseline=false`、`candidate_opt_in=false`。[baseline wrapper](../../Temp/interactive-production-baseline-1-run.json)、[candidate wrapper](../../Temp/interactive-production-candidate-1-run.json)、[default wrapper](../../Temp/interactive-production-default-1-run.json)

| 阶段 | 接受时间 | candidate/default 的积分步 |
| --- | ---: | ---: |
| 开始 | 0s | 0 |
| 直航 | 4s | 240 |
| 直航 | 12s | 720 |
| 转向 | 20s | 1200 |
| 收帆后 | 30s | 1800 |
| 暂停中切换画质 | 30s | 1800 |

candidate 与 default 的全部六帧都绑定有效场、覆盖 player、启用陆地遮罩且零丢步。player 原尾迹被覆盖门隐藏；4s之后，远处 fisher/merchant 的原尾迹仍可见。三组回执中的 `ship_states`、相机及接受时间逐阶段一致；不把不同运行的内部 `physics_sha256` 字符串宣称为同一值。

暂停切换画质前后，船体状态、相机和同次运行的物理摘要不变；field 的 tick/total_steps 都保持1800，reset计数不变。因此此次证据支持“画质重建保留已有场”，不是重新建立一个外观相似的空场。

### 最终普通启动联合 GPU

最终追加 [final/GPU_VERIFY.json](evidence/wake-flow/interactive-production-1/final/GPU_VERIFY.json) 与 [严格 wrapper](../../Temp/interactive-production-final-r1-run.json)：普通默认启动，没有 `--candidate` 或 `--baseline`，`candidate_opt_in=false`，6帧、退出码0、唯一成功标记、零失败。正式场景原图总量因此为24张，原 baseline/candidate/default 的18张继续保留。

交付工具再次逐帧核对 final 与 baseline、先前 default 的 `ship_states`、相机和接受时间，全部相同。六帧均为 field bound、覆盖player、`land_masked=true`、`dropped_steps=0`；最后两帧继续保留1800个积分步。六帧的 `shadow.errors`、caster adapter errors 均为空，GPU shadow error字符串为空。

root亲自查看了最终 [直航](evidence/wake-flow/interactive-production-1/final/03-cruise-12s.png)、[转向](evidence/wake-flow/interactive-production-1/final/04-turn-8s.png)、[收帆后](evidence/wake-flow/interactive-production-1/final/05-stop-10s.png) 原图，确认长黑线消失、双侧尾迹保留。这一段接受的是该组联合真实渲染结果；影子算法、来源恢复与更广场景的专项结论仍单独报告，不外推为整场性能或原版像素等价。

## CPU、入口与回退归档

[最终组件回执](../../Temp/interactive-wake-final-components.json) 为6/6通过：capture guard17/0、source fallback39/0、field38/0、ocean20/0、system62/0、interactive lab30/0。[catalog-2](../../Temp/interactive-wake-final-catalog-2.json) 为87/0；当前 `wake-flow` catalog 状态为 `integrated`，Demo仍是原有实验室课题。

交付时新跑的入口检查为 [laboratory UI26/0](../../Temp/interactive-wake-delivery-laboratory-ui.json) 与 [laboratory entry28/0](../../Temp/interactive-wake-delivery-laboratory-entry.json)。另新跑 system62/0，在运行前后校验相关源码哈希一致，将原始 stdout/stderr、进程参数和源 SHA 归档为 [system-contract.json](evidence/wake-flow/delivery-2026-10-14/system-contract.json)。这是一组明确限定的 headless 检查，不是全仓库测试结果。

回退 eligibility 的 [T2归档](evidence/wake-flow/2026-10-14-fallback-eligibility/manifest.json) 保留39/13 RED与39/0 GREEN、候选/基线源码和独立复核。它防止当前 dry/empty submission 后缓存旧 mesh 被重复调用或覆盖解除重新显示。[真实船体输入归档](evidence/wake-flow/2026-10-14-t2-water-interaction/manifest.json)、[世界遮罩归档](evidence/wake-flow/2026-10-14-world-wet-mask/manifest.json)、[field独立审查归档](evidence/wake-flow/2026-10-14-t2-field-review/manifest.json) 均已校验其引用文件存在及记录的 SHA256。

## 历史失败、源码冻结与限制

以下证据继续保留，不改写为通过：

- [早期 GPU2 baseline](evidence/wake-flow/20261014-gpu-2/baseline-cruise/GPU_VERIFY.json) 的 capture inventory 失败。
- [interactive field GPU1](evidence/wake-flow/interactive-field-gpu-1/GPU_VERIFY.json) 的重复接受时间失败。
- [旧中线近景](evidence/wake-flow/20261014-gpu-2/candidate-close/GPU_VERIFY.json) 虽执行有效，其视觉方向未采用。
- 有限平面边缘、完整船帆取景、duplicate queue 与 last-accepted输入回执修复的 RED/GREEN 记录在 [T3过程报告](../superpowers/plans/playable-voyage-work/t3-interactive-field-lab-report.md)。

每个 GPU manifest 的 `sources` 是**该次运行时**的冻结哈希。最终 production 工具已增加 shadow helper、adapter、Prepared 等来源和逐帧诊断，final回执记录21项源。最终工具的当次SHA256为 `9b633a3ab3b989819e8426bf89ea61056c5459f9bf7d0246f95a5a8f20689f54`；本交付不把旧三组工具SHA宣称为当前工具SHA。DELIVERY_VERIFY 另冻结11个尾迹运行时来源，已同时与先前default和最终final GPU回执对应SHA匹配，确认这次联合复验没有更换尾迹算法。

| 核心回执 | SHA256 |
| --- | --- |
| numerical GPU4 | `861da528ed8a390c09718ed8b8021d64744f91317b99f2ea029a653191818214` |
| lab3 PAIR_VERIFY | `e14d00040a57d61c669f81a8ea2b565be84bc8d608674fbf5b42f3205fceaf57` |
| production default | `f8fbd095f7f1b5a41b3a207557a834afedee251b69b100e20c45549e83c43fbb` |
| production final | `205f5369382467ee39422e1a9133616587bf54b8b41863a88e6350ebfd53835c` |
| final components | `44178e6f59306b62eb91cb63987201bb12f5241727f69eb227636a235fa76013` |

适用边界保持明确：最多3条满足安全覆盖条件的近船使用新场；本次正式截图实际覆盖player，远船保留原路线。局部场为96m/256，即0.375m场网格，但正式投影海面分辨率仍随视角和距离变化。正式场景提供的511采样世界湿区遮罩约为4.868493m×3.581213m单元，不能据此宣称窄礁石、细码头、精确岸线波反射或润湿过程已准确求解。该场是船→水的单向表现模型，没有替换浮力或实现完整流体求解。

没有本交付对应的正常游玩整场 frame-time/FPS测量；独立 Demo 的 CPU推进计时、固定时间GPU采样和第三方性能都不用于宣称整场60FPS。工作树其余改动、航程完成度及超出上述最终联合运行的 shadow 专项结论不在本报告范围。

复核现有证据可运行：

```powershell
rtk proxy node tools/verify-interactive-wake-delivery.mjs
```

此命令只读校验已有文件与回执，不覆盖历史失败，也不启动 GPU。首次创建交付 manifest 使用的 `--write` 仅接受尚不存在的目标文件；本次加入 final 的 `--refresh-final` 只允许替换与已归档首版逐字节一致的旧清单，保留首版文档、审计源码与清单。
