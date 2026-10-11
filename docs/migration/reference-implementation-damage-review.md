# Task 3 破损与船员独立审核

日期：2026-10-11。只读审核实现，仅新增本报告；未修改实现、stage、commit、push，未运行 GUI 或 `tools/verify-godot.mjs`。产品世界接线由主线程正在完成，未将未完成接线列为 Task 3 缺陷。

审核依据：`docs/superpowers/plans/2026-10-11-naval-reference-implementation.md` 的 Global Constraints / Review Focus / Task 3，以及 `docs/migration/reference-implementation-damage-crew.md`。CodeGraph 在派发前已查询：目标未索引，本审核按派发约束使用 RTK 读取源码与资产。

## 结论

本次未确认需要修复的 P1 / P2。实现与已批准 Task 3 的状态、时钟、预算和权威边界相符；局部 headless 复核通过。此结论不代替主线程 GPU 及完整产品交互验收。

## 审核证据

- `game/presentation/ships/ship_view.gd:53-106`：从快照 visual pose 更新根节点，损伤 helper 仅变换子模型和桅杆；使用 `ship.time`，旧调用回退到 consumed。倒退时间清 recoil / event 去重，helper 清时间线；没有第二次 hull / sail / crew 结算。
- `game/presentation/ships/ship_damage.gd:49-96`：首次或回退后载入全损状态直接 seek 终态，跨键只发一次 scheduled time；健康恢复重置断桅 / 下沉。帆损按 6 量化再转 subtype 0 档位，壳损按 20 取档。
- `game/presentation/ships/ship_damage.gd:24-47,78-89`：每个 GLB 实例、每个 LOD、每个 hull / sail 节点独立创建 ShaderMaterial；没有写 AssetLibrary 缓存 mesh / material。三 LOD 同步 material stage / fall / sink，结束隐藏；LOD 切换不能复活沉船。
- `game/presentation/ships/ship_damage.gdshader:13-37`：基于 UV 的稳定孔洞、discard 与焦痕；COLOR 乘原 albedo，保留原 roughness。只读解析实际 18 个船型 / LOD GLB：所有受覆盖 hull / sail primitive 均有 POSITION / TEXCOORD_0 / COLOR_0 / NORMAL，hull roughness=0.82，sail roughness=1、doubleSided=true；没有被覆盖但遗漏的 albedo texture / metallic 配置。福船主帆实际 UV 为二维 0..1 网格，帆洞坐标有真实数据依据。
- `game/presentation/crew/crew_view.gd:117-157,264-320`：accepted time 控制动画采样与接管；动画 player pause 后皮肤转到物理池，骨骼 override 只由物理 transforms 驱动；恢复清 override 并回岗位。回退释放旧 rig / skin；当帧损失预算不会跨后续快照累加。
- `game/presentation/crew/crew_view.gd:148-153,322-331` / `modules/physics_engine/impacts/impact_pool.gd:30-46`：真实 hull / deck 三角形注册到 active model global transform，沉船子模型下沉与倾斜后不会保留根位置的空中甲板。
- `modules/physics_engine/impacts/impact_pool.gd:52-57,119-169,171-179,207-234`：target / event / slot 去重有 256 条上限；全球 12 rig cap；重复 phase 不老化，倒退释放并清去重；18 骨入水只发一次入口事件；到期 / wet 到期 / dispose 释放 rig 和全局计数。standing 24 / 8 / 2、单船 24、全球分配 120 与 1800 米外回收路径保留。

## 本次直接复跑

运行器：`C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`，直接 `--headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/...`，命令均通过 `rtk proxy`。

| 测试 | assertions | failures | exit |
|---|---:|---:|---:|
| `tests/test_reference_ship_damage.gd` | 188 | 0 | 0 |
| `tests/test_reference_crew_lifecycle.gd` | 13 | 0 | 0 |
| `tests/test_crew_impacts.gd` | 578 | 0 | 0 |

真实 native 复跑输出：躯干 before=(0,5.87,0)，after=(1.333492,6.571035,0.000099)；pause frozen 与 after 完全相同。甲板 minimum_y=0.05010643601418，max_anchor_error=0.0376947298646；入水 wet=0.45，minimum_y=-0.12532214820385。

## 剩余验收边界

- 本审核没有 GPU 渲染证据；帆洞轮廓、裁剪阴影、背面光照、healthy 与 damaged 色彩、六船型三 LOD 的真实画面仍需主线程截图检查。源码 / GLB 数据检查只能排除缺 UV / 缺 COLOR / 共享材质污染等具体风险，不能证明观感。
- 完整产品的 paused / restored / rewind / scene exit、连续 hit / sinking / LOD 切换与性能范围由主线程统一验收。局部 tests 验证的是组件及真实 Jolt 路径，不将未执行的产品验收声明通过。
- shader 的 cull_disabled 双面法线处理另核对 Godot 官方 renderer source，未把缺少自写 FRONT_FACING 翻转当作缺陷：引擎渲染 shader 有 DO_SIDE_CHECK 背面法线处理。参考：[Godot Forward+ scene shader](https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl)。当前运行器实际 GPU 结果仍待截图确认。

## 第二次独立复审：原作破损贴图与完整 rig 倒伏

日期：2026-10-11。目标始终为带 hyphen 的 `C:/Users/dains/Documents/Git/ming-armada`；无 hyphen 网页项目与原作参考目录只读。本节对应新增 PNG 主路径与索具拆分后的实现，优先于上文较早快照的 shader / 行号描述。只更新本报告，未修改实现、测试或源资产；未运行 full runner / GUI / 性能测试。

**结论：未确认 P1 / P2。** 已批准的贴图接入、状态驱动完整 rig 倒伏、暂停 / 回退 / LOD 合同在本次源码与针对性 headless 检查中成立；GPU 与实际 PCK 运行仍需主线程最终验收。

### 语义与资源

- `assets/provenance/pirates-damage-reference.json` 的 11 条源和目标路径均实际存在；独立重新计算两端 SHA-256，逐条等于 manifest.sha256。总 PNG 字节为 76,804。独立用 Pillow 检查每张尺寸、RGBA 通道范围、alpha<160 像素数，全部等于清单，没有以目标单端校验代替源/目标校验。
- 只读核对原作 `PSShipHull_11.psh` 与 `SailShader.NSF`：壳损是 RGB 颜色层、alpha 为层权重；帆 HolesTex alpha test 为 GREATEREQUAL 0xa0，UV0 clamp。本作 `ship_damage.gdshader:22-29,48-51` 保留这些通道职责，帆裁剪 `<160/255`，壳不写 ALPHA / 不 discard。将壳 damageRGB 乘本作 authoredColor、棕色仅局部染帆边，是报告明确记录的本作色盘适配，未声称复刻原作全部颜色层。
- `ship_damage.gd:29-37,97-111` 在 configure 有界加载 11 个资源；hull 0..5 档对应 intact / 020..100，主帆 subtype0 的 0..4 档对应 intact / 020..080，sail100 保存但不错误绑定到 q96。选中档位缺图才回退有机裂口。stage 未变不重复绑定，纹理可以不可变共享，每个船/LOD的 ShaderMaterial 保持独立。
- 全部 11 个 `.png.import` 独立检查为 lossless mode0、mipmap=true、premult=false、fix_alpha_border=false；测试直接检查实际 Texture2D mipmaps。source_color 仅按 RGB 色彩纹理处理，不改变 alpha 阈值职责。
- `export_presets.cfg` 为 all_resources，排除目录不包含 `assets/textures/pirates_damage_reference`；动态字符串资源路径没有被当前 preset 排除。此为配置证据，未将其写作已经执行 PCK 加载验证。

### 完整 rig、隔离与回退

- `ship_damage.gd:165-249` 只读提取每个实例的 fittings_trim 数组，对同位顶点焊接后按真实三角形连接组件拆分；rope 颜色与高度/邻近桅杆判断分离高索具与甲板 trim。新建 fixed/moving ArrayMesh，再赋给实例节点，不改 AssetLibrary 共享 mesh 或原材质。
- 独立解析六船型三 LOD GLB：现有 fittings_trim 全部为 model-space identity transform，数组属性为 POSITION/NORMAL/TEXCOORD_0/COLOR_0；因此本次 `_emit_vertex` 保留这些实际属性，rig 直接挂 model 的坐标合同成立。fisherman LOD2 原本无 fittings_trim，helper 正常跳过；不是漏拆高索具。
- `ship_damage.gd:112-126` 对桅杆、拆分索具、masthead flag 分别从 rest 重组相同的 model-space fall 矩阵，枢轴为真实 deck mast origin；帆/横桁/桅木作为原 mast 子树保持 local attachment。没有在上一帧变换上继续累乘；连续正常推进/重复 phase 或回退后的 healthy tick 不累计旧 fall。reduced motion 仅冻结旗帜 sway，保留断桅状态。
- `ship_damage.gd:72-94,127-137` 保留首次 terminal seek、回退重建、健康状态恢复、scheduled key 只发一次与三 LOD 同步。贴图 stage 与 tear 参数由当帧权威健康重算，旧 stage 不会因时间回退继续绑定到新状态。

### 本次针对性测试

与第一次复核相同的 Godot 4.7.2 exe，逐项直接 `rtk proxy <Godot> --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/...`，没有运行统一 runner。

| 测试 | assertions | failures | exit |
|---|---:|---:|---:|
| `tests/test_reference_damage_textures.gd` | 1900 | 0 | 0 |
| `tests/test_reference_ship_damage.gd` | 235 | 0 | 0 |
| `tests/test_reference_dismast_assembly.gd` | 243 | 0 | 0 |

合计 2,378 条断言通过。texture 用例涵盖每船型/LOD/档位的实际资源绑定、健康另一实例隔离、缺图回退与 mipmaps；assembly 用例读取实际 rendered mesh 顶点，检查 18 个模型的倒伏最高高度 < 健康值 60%、flag deck pivot、子树 attachment 不变、暂停无累积以及回退恢复高度。ship_damage 复核单次 key、真实 scheduled birth、根姿态、terminal restore、LOD 与资源释放。

### 本次保留的验收边界

headless 不证明新 PNG 帆洞/壳裂痕、min/mag/mip 距离变化、完整 rig 下落过程及背面光照的真实画面；尚未独立运行 actual PCK、连续完整产品战斗、GUI 或性能测试。上述局部通过不替代主线程负责的这些验收。
