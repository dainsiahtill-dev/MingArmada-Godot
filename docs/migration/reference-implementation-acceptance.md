# 海战参考落地：整体验收

本轮将用户提供的 deep 与 island-water 学习报告和交互示例接入现有 Godot 游戏。水花、船浪、操纵、炮战、破损、3D 船员、水面光学和海岛材质已接入产品路径；没有将参考 WebGL 示例作为本作已完成的画面证据。原 Three.js 项目及参考目录只读。

## 交付范围与架构

| 领域 | 本作已实现 | 依据及报告 |
|---|---|---|
| 炮弹落水 | 三维水柱、伞状壳、波面水环、空间飞滴和弱雾；出生时间、岸线过滤、有限回收 | [水花/船浪](reference-implementation-water.md) |
| 船首/船侧/船尾浪 | 实际前进速度驱动，历史点生成尾迹，急转分段、停船消退；弯曲船首弧线 | 同上 |
| 操船 | 辅助模式起步、低速转向、回舵响应、迎风恢复；船型差异与真实力学预算保留 | [操船/炮战](reference-implementation-handling.md) |
| 炮战 | 分批齐射、装填底限、实心/链/葡萄弹，保留真实扫掠弹道；安全射界与中文舷侧状态 | 同上 |
| 破损/断桅/沉船 | 私有材质分档船壳损伤，原作 alpha 帆洞，整套桅杆/帆/横桁/索具/旗帜倒伏；有限沉船关键事件 | [破损/船员](reference-implementation-damage-crew.md) |
| 船员 | 实际三维骨骼水手与岗位动作；真实炮击后的 Jolt 刚体击飞、落水事件、非致命恢复、有限回收 | 同上 |
| 海水 | 明亮浅深水色、白浪分层、随风变化的微纹、岸浪与喷雾；原五波高度和法线合同保留 | [水面研究](pirates-rendering-study.md)、[光学](reference-implementation-ocean-optics.md) |
| 水面光学 | reverse-Z 深度重建、吸收/折射、Fresnel 和有上限的屏幕空间反射；相机释放/离树自动回退 | [光学](reference-implementation-ocean-optics.md) |
| 海岛 | 原地理/高度/碰撞，沙草岩按坡度和高度混合、湿沙、水下焦散、远处岛屿地形支持 | [海岛材质](reference-implementation-islands.md) |

`modules/physics_engine` 保持操纵与 Jolt 物理职责；`modules/naval_simulation` 负责弹道、命中、伤害与政策；`modules/scene_engine` 负责水面、地形和地理表现；`game/presentation` 负责权威状态驱动的船模、船员和有限事件效果。所有表现读取同一 accepted time，没有新增第二个积分、私有水面时钟或重复减员。

实际产品启动显式开启增强操纵/炮战与水面风格；冻结的旧配置及默认五参数 TerrainChunk 接口仍可回归。近景和远景地形复制海面只读波/岸线配置，静态值只在变化时写入；暂停与时间回退保持一致。

## 资源与证据

原作船壳贴图使用 RGB 颜色层和 alpha 混合权重，船壳不透明；帆 alpha < 160/255 裁洞。11 张损伤 PNG 共 76,804 字节，源/目标 SHA256 一致，见 [损伤来源清单](../../assets/provenance/pirates-damage-reference.json)。新水效果与既有纹理的来源、通道和绑定见 [水面来源报告](reference-implementation-provenance.md) 与 [清单](../../provenance/naval-reference-implementation.json)。海岛增强没有新增外部 PNG。

本作 authored 船壳/帆 UV 不同于原作，已按通道语义适配；没有声称原作 UV 或每个弹孔的撞击坐标相同。主帆当前 subtype0 满损使用080，100贴图保留并在包内验证可加载。

新学习台的镜像反射、Cat Island 和四波 Gerstner 是学习实现选择。本作保留现有地理、五波及海战水线，采用 Godot 当前不透明屏幕源的反射方案。屏幕之外及透明物体不进入该反射，均衡最多16步，高档24步，低档关闭反射；没有第二个 World 或离屏反射目标。

## 自动化与独立审核

- 完整 `tools/verify-godot.mjs`：**73 / 73 测试文件通过，0失败**。完成标记、退出码、超时和脚本/资源错误均由 runner 校验；不是只看退出码。记录：[verification.json](evidence/verification.json)，本轮开始时间 2026-10-11T12:08:21.950Z。
- 新光学122、海岛材质155、真实World同步32、损伤贴图1900、整rig断桅243、船损235、船员生命周期13、既有Jolt船员578条聚焦断言均0失败；完整 runner 包含这些用例。
- 独立审核：[破损审核](reference-implementation-damage-review.md)、[光学/海岛审核](reference-surface-optics-review.md)、[前轮整体审核](reference-implementation-final-review.md)。相机 detach/null viewport 的P2经有效RED复现、实现修复和独立 detach/re-attach 复验关闭；当前未解决 P1/P2 为0。

## 主线程真实 GPU 画面验收

Godot 4.7.2 / D3D12 Forward+ / Intel Arc 130T 16GB。主线程运行四个原生截图脚本：产品航行15张、实际菜单QA20张、真实炮击近景14张、相同权威状态光学开关11张，共 **60张**。常规1600×900；另有窄窗口UI样本。

主线程亲自查看全部10张有标签的联系表，并单独查看关键全尺寸原始PNG：海岸、转弯、低角度水花、破损帆、水手击飞、断桅中段/末段、沉船、反射/折射开关。联系表是查看用的派生文件，原始截图像素没有修饰。索引包含每张PNG及相邻JSON的SHA256、尺寸和GPU：[visual-index.json](evidence/reference-implementation/visual-index.json)。主线程观察记录：[manual-visual-verification.json](evidence/reference-implementation/manual-visual-verification.json)。

| 样本 | 实际观察 |
|---|---|
| 岸线多个时刻/暂停 | 亮蓝绿海水、白色岸浪与湿岸过渡；码头和远港位于地形上；权威状态暂停保持 |
| 前进/转弯/停泊 | 弯曲船首与连续船尾迹，没有白色矩形贴片背景；停泊无尾迹 |
| 实际炮弹落水 | 高/低/俯视镜头可辨水柱和水环，按每个事件寿命消退 |
| 船员实际中弹 | 三维甲板水手、实际Jolt位移与落水，非致命恢复及回收诊断吻合 |
| 破损与断桅 | 原始不规则孔洞；桅杆、帆、横桁、索具、旗帜同向倒伏，健康船未被共享材质污染 |
| 沉船 | 真实船壳归零触发下沉、泡沫与烟雾；末帧模型沉至海下，无再次播放 |
| 光学开关 | 三组固定相机对照的权威快照完全相同；码头/船体倒影和浅水折射有实际像素差异，采样视角未出现大块屏幕反馈 |
| UI与船型 | 六种船、窄窗口QA滚动、实际舷侧状态；低/高水面档均成功渲染 |

同状态像素差异仅是辅助证据，不代替人工观察：[pixel-comparison.json](evidence/reference-implementation-optics/pixel-comparison.json)。这些固定 tick 截图不用于FPS结论，也不能覆盖所有硬件和所有镜头。

## 发布资源验收

Windows EXE/PCK 已重新导出。独立空cwd、隔离用户数据、外部 `--main-pack` 探针实测 **517断言、26资源记录、21模型，0失败**，导出与探针日志无 ERROR/SCRIPT ERROR。11损伤PNG与4新水效果PNG通过包内 native/remap 读取，松散PNG不存在；实际菜单进入1650场景，验证水面、详细近远地形、船员及 accepted time。见 [Release报告](reference-implementation-release.md)、[PCK证明](evidence/reference-implementation/pack-verification.json)。

| 产物 | 字节数 | SHA256 |
|---|---:|---|
| `build/windows/MingArmada.exe` | 109168640 | `3d19ee4a764e8bb153bfa7f811f98e0dfb0139c9e0c8bc6b76b93d3ed09185bf` |
| `build/windows/MingArmada.pck` | 49773484 | `db81e180f682b11de26bea52b72b18a67e4d307a55f4a194a0b430792e4a9915` |

## 当前边界

本轮完成已批准的参考海战与水面/海岛改进，未把整部1650—1683历史战役、完整远航经济或所有原作系统称为完成。断桅和沉船是状态驱动的有限表现；没有任意实时网格断裂、完整原DX9渲染复原或40槽拾救机制。波浪依旧是本作五波，不能把学习台CPU/GPU对照数字转写成Godot本轮误差。实际性能与发布EXE画面记录在后续章节，完整记录与当前硬件范围共同约束结论。
