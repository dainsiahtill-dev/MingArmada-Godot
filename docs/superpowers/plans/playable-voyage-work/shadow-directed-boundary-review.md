# 通用有向阴影边界修复：独立审查

日期：2026-10-14。审查者：voyage_visual。结论：本次限定范围内未发现阻断问题；603 条定向 CPU 断言独立通过。只新增本报告，没有修改实现，没有启动 GPU 进程。

## 范围与冻结版本

审查完整 helper、adapter、其原 Prepared 基类、新测试与相关既有测试；读取 CPU manifest、隔离实验和正式路径的既有 GPU 证据。CodeGraph 在本轮协作前已确认项目未索引，因此使用限定路径的文件审查，没有重试索引或扫描旧仓库。

| 文件 | 当前 SHA-256 | 核验 |
| --- | --- | --- |
| `game/presentation/world/target_shadow_boundary.gd` | `9f5474d9883a1cd9ca15912b39157dc906f2d8454fa5456bf1c11448890fc65f` | 与冻结候选、正式 GPU source receipt 一致 |
| `game/presentation/world/target_rigid_shadow_caster.gd` | `d3dd2092d514dc4ebc31b6c3a513a0f50f680f3ee6eeb92d082050b0e776e757` | 与冻结候选、正式 GPU source receipt 一致 |
| `game/presentation/world/prepared_rigid_shadow.gd` | `54d410dcef7fe7897f5f733ee5dc36cefc138bcbe7a6875c7dcea0d260fe44f8` | 与保留基线一致，未改 |
| `modules/scene_engine/fidelity_fx/source_shadow_math.gd` | `ccb6c4c79bdb72c220311191b2073e9d45e318e89e41dc51496dbf88d62fb137` | 与保留基线一致，未改 |
| `modules/scene_engine/fidelity_fx/source_shadow_rd.gd` | `0ba3b42c937d531203e1c8e277143d3c61e38c0991fdc4f631681e0e2cf99402` | 与保留基线一致，未改 |

基线、候选完整源文件和先前 RED/GREEN 记录位于 `docs/research/evidence/shadow-edges/target-directed-boundary-20261014/manifest.json`。当前文件哈希由本次审查重新计算。

## 合同逐项核对

| 检查项 | 结果与依据 |
| --- | --- |
| 无 caster ID 特判 | helper 不接收 caster ID。adapter 第 52 行仍使用原有 `target_rigid_shadow_caster` 元数据、可见性与 mesh 条件；第 65 行只将构造对象换成 Boundary。新测试使用两个任意 actor 名称，均经真实 renderer/PreparedShadowFrame 接缝成功发布。 |
| 同向重数与反向抵消 | helper 第 24–42 行以规范化索引对作键、以方向累加整数重数；从 cap 的有向边界减去既有 `_edges`。同向不再通过偶数奇数关系消失，反向抵消；按照绝对余额重复追加侧面。父类限制源索引小于 32768，16 位打包键不碰撞。 |
| 原 geometry 前缀 | 第 48–59 行复制原 positions/indices 后追加；既有侧面的 apex 继续引用原第 0 点。没有删去原边、重新排序原索引、改 cap winding 或修改方向。新测试与真实模型变光测试均验证原 positions/indices 完整前缀精确相等。 |
| 零原侧面且有 caps | 第 44–53 行仅在 `_edges.is_empty()` 时将新 apex 追加于原 cap 顶点之后；原第 0 点仍为原 cap 点。新 apex 使用原 direction 与固定源顶点，经过相同 float32 规则。双重和四重同向面测试覆盖此分支及 apex ray 平衡。 |
| 拓扑缓存 | 第 64–68 行以父类不可变 `original.indices` 身份变化触发重建。仅光向变化而面分类未变时，不重扫边/caps；只复制冻结的点引用并更新 apex。面分类变化与成功 configure 会刷新缓存。 |
| 发布不可变性与所有权 | 第 71–87 行保存原父类 volume 身份链。发布点、索引、字典均冻结；旧 publication 在后续光向变化后字节不变。`owns_volume` 同时检查当前修正输出和父类当前原输出，旧输出无法取得当前证书。零侧面私有 apex 占位在发布前被替换，没有暴露可变占位数组。 |
| 容量上限 | 第 45–47 行在追加前检查最终顶点数是否超过 65535。超限时返回完整原 geometry，并通过 `boundaryError` 向 adapter diagnostics 暴露；不截断、不删除 caster。11000 个重合三角面的测试覆盖此路径。 |
| 生命周期与原回退 | configure 成功清空 helper 缓存；configure 失败沿用父类的原子失败语义。adapter 原 dispose 与 mesh shadow 状态恢复逻辑保留。修改外部 source holder 后不能伪造 Prepared 身份，仍走完整原 Math 路径，既有测试验证。 |

adapter 改动集中于 Boundary 构造与 `boundaryBuilds`、`addedSides`、`boundaryError` 诊断汇总。没有增加 caster ID 过滤、shader 分支或 renderer 数学改写。

## 独立 CPU 复跑

使用仓库严格 runner 和 Godot `4.7.2.stable.official.ed1daf0bf`，两个定向用例均 exit 0、无解析/脚本异常、明确完成标记：

| 命令 | 结果 | 本次原始证据 |
| --- | --- | --- |
| `rtk proxy node tools/verify-godot.mjs --filter test_target_shadow_boundary --output Temp/research/visual-shadow-boundary-review-green.json` | 57 assertions，0 failures | `Temp/research/visual-shadow-boundary-review-green.json` |
| `rtk proxy node tools/verify-godot.mjs --filter test_rigid_shadow_preparation --output Temp/research/visual-shadow-preparation-review-green.json` | 546 assertions，0 failures | `Temp/research/visual-shadow-preparation-review-green.json` |

新测试包含同向 2/3/4 重面、反向抵消、闭合例、同向共享边、零原侧面、真实 fuchuan 组件、任意 actor ID、容量回退、变光缓存、旧 publication 不变与认证失效。原通用 Prepared 对 Math 的完整等价断言仍保留；真实 target 仅在明确追加修复侧面时改为精确前缀合同，并保留 mutable holder 回退的完整 Math 等价断言。

manifest 另记录实现者的 RED 51/14、GREEN 57/0 与十个 shadow 测试文件全部通过。这些是先前证据；本次独立复跑只覆盖上表两项，没有把先前十文件结果算作本次运行。

## 已有 GPU 证据审查

已用图像工具亲看以下原图：

- `docs/research/evidence/shadow-edges/directed-boundary-baseline-20261014-r1/all-retained.png`
- `docs/research/evidence/shadow-edges/directed-boundary-production-20261014-r1/all-retained.png`

基线存在从船上方向画面顶部延伸的细长斜线；正式候选原图中该远距离线条消失，船与近处场景仍保留。两组记录的 camera 与 accepted time 24 s 相同。

严格区分两种证据：先前 `directed-boundary-candidate-20261014-r1` 是针对一个已定位 caster 的隔离注入实验，只用于验证原因；`directed-boundary-production-20261014-r1` 记录当前通用 helper/adapter 的正式路径，source receipt 与上表 SHA 一致。正式路径 `valid=true`、`failures=[]`、`activeCasters=44`、`volumeCount=44`、`addedSides=4`，adapter/GPU errors 均为空。它没有通过移除目标 caster 来消除线条。

本次重新计算 PNG 文件 SHA：正式与隔离候选 `all-retained.png` 均为 `438459a7208e43e3ab31920c81cca29d9610af3623caa5a17a05f80769be7e57`；三组 `stencil-off.png` 均为 `e235149181450ea3627c8282abe98697d51a0ee55b6ed247d72a0d4f7b4c179a`。因此，保留的 `prior-isolated-gpu-compare.json` 中相同图像对的 ROI 结果也适用于这张正式截图：远 ROI 深色差异像素 158→0，近 ROI 29→22；阈值是三个 RGB 通道均比 stencil-off 深超过 10/255。这里没有重新运行 GPU，也没有将近 ROI 22 像素归零当作目标。

`rigging-hidden` 记录的实际隐藏节点数为 0，因此本次不把该图片当作“移除索具”的有效因子实验。

## 保留边界

- 这是在现有 target caster policy 内的通用有向边界补全；不等于恢复原游戏所有 caster 分类、skinning、receiver 调度，GPU 自身仍明确标记 `nativePixelEquivalent=false`。
- 超 65535 顶点的修复保留原输出并报诊断；安全回退已验证，该范围的缺面修复没有完成。
- GPU 结论限定于保留的同相机、同时间场景。未独立覆盖所有船型、太阳角度、远近裁剪和运行时变形，也未运行性能采样。缓存计数是工作量合同证据，不能替代本机性能结论。

本次未发现需要返工的实现问题。冻结候选可继续由主线程进行正常航行与其他场景验证；不得将这份审查扩称为全场景像素等价证明。
