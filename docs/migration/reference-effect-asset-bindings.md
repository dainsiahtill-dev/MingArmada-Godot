# 原作特效资源：完整绑定与 Godot 资源交接

本轮完成**完整资源导入**，为下一步 Godot 效果融合提供真实参数、纹理与材质证据。没有修改生产粒子、海面、世界、物理或入口代码；没有打开 GPU 窗口，也没有开展性能优化。完整参数保存不等于恢复原作粒子求解器，更不等于原作 DX9 画面已复现。

工作树：`C:/Users/dains/Documents/Git/ming-armada`。参考树 `C:/Games/Pirates-REA-Reference-20261011` 全程只读。CodeGraph 当前工程无索引，使用 RTK 源文件查询；未声称取得 CodeGraph 审查结果。

## 可直接接入的资源合同

| 文件 | 用途 |
| --- | --- |
| [definitions/systems.json](../../assets/data/reference_atmosphere/definitions/systems.json) | 原 `particle-contract.json` 全部 **276** 系统；原记录的每个字段保留，增加稳定 ID、容量、资源入口及实际纹理绑定 |
| [definitions/schema.json](../../assets/data/reference_atmosphere/definitions/schema.json) | public schema 说明、字段入口、坐标/单位边界与完整示例 |
| `assets/data/reference_atmosphere/definitions/assets/PakN/*.nif.json` / `*.kf.json` | **65** 份完整解析资产，包含几何、材质、控制器、关键帧及原始 block refs |
| [binding-index.json](../../assets/data/reference_atmosphere/binding-index.json) | 实际模型 → 属性 → 纹理块 → Pak 图片关系，包含 owners、scene paths、descriptor、未解决槽及未绑定候选 |
| [whole-fpk-inventory.json](../../assets/data/reference_atmosphere/whole-fpk-inventory.json) | 完整 `preview/images/fpk` 的 **3,840** 张 PNG，按 Pak 保留原路径、PNG SHA 与原文件 SHA |
| [coverage.json](../../assets/data/reference_atmosphere/coverage.json) | 资源覆盖与未恢复运行行为，机器可读 |
| [reference-atmosphere.json](../../assets/provenance/reference-atmosphere.json) | 输入、importer、像素检查器、全部输出定义与图片的哈希/像素证据 |
| [import-reference-atmosphere.mjs](../../tools/import-reference-atmosphere.mjs) | 可复现导入和只读重验工具 |

顶层合同固定为：

```json
{
  "schema_version": 1,
  "source_contract": "原合同除 systems 以外的全部字段",
  "source_assets": "完整解析资产索引",
  "effects": "16 个粒子根资产及各自 system_ids",
  "systems": "全部 276 个原记录，附以下新增字段"
}
```

这段是结构说明，真实文件中的字段是完整对象/数组。每项 system 的新增字段为：

```text
id = raw/fpk/PakN/source.nif#numericBlockId
particle_capacity = data.fields.num_vertices
source_asset = res://assets/data/reference_atmosphere/definitions/assets/PakN/source.nif.json
texture_paths[*].properties[*] = 原 declared_owner_id + 原 property
  + texture_bindings[base_texture / glow_texture / detail_texture / ...]
    .source_texture_block_id / source_texture_type / fields / descriptor
    .selection / files[*]
      .id / raw / raw_sha256 / resource / png_sha256
      .decoded_rgba_sha256 / width / height / channel_ranges
```

`property_chains` 原记录仍保持原样。`texture_paths` 对每条父路径分别补充真实绑定，不把不同继承路径合并。`descriptor` 保留 UV 平移、缩放、旋转、clamp/filter 等；完整资产保留相应 `NiTextureTransformController` 与其数据 refs。`NiAlphaProperty` 的 flags、阈值、源/目标混合因子及材质颜色原样保存。导入过程不预乘 alpha、不改白、不调亮、不修改寿命或插值。

`particle_capacity` 是本资源 DTO 对 `data.fields.num_vertices` 的便利用名，保存的是**静态 authored 数量**，没有证明它是原作运行时的动态最大容量。coverage 的 `capacity_boundary` 明确这一点；本作的生成器需要单独设定并披露容量策略。

原生浮点数精度、负时间、周期 flags、所有 KeyGroup、插值参数、切线、modifier order、发射器/重力对象变换链都保留。普通 `JSON.stringify` 会把 `-0` 改成 `0`；本工具采用稳定序列化，并输出 `-0.0`，完整原记录和 65 个资产的严格字段对照验证通过。

例如炮口烟层的真实 ID 为 `raw/fpk/Pak2/fx_cannon_fire_01.nif#9`。发射率读取 `emitters[*].emission_controllers[*].data.fields.float_keys.keys`；开关读取同一数据中的 `visibility_keys`；颜色读取 `NiPSysColorModifier.data_resolved.fields.data.keys`。粒子专家应该读取这些完整数据，不能把 compact demo 的白球、单个寿命或线性缩放当成原始合同。

## 实际数量

| 项目 | 实际导入/索引 |
| --- | ---: |
| atmosphere 根粒子效果 | 16 |
| atmosphere 完整系统 | 276 |
| 这些系统静态 authored num_vertices 之和 | 3,692，不是已验证的动态最大容量 |
| modifier 记录 | 1,832 |
| system controller 记录 | 728：176 reset-on-loop + 276 emitter + 276 update |
| atmosphere 完整解析资产 | 33（含 mesh/云/天空/动画上下文，不全是粒子系统） |
| 水花/船首船侧泡沫/沉船泡沫上下文 | 23 |
| 独立水面资产 | 3 |
| 岸线/焦散几何资产 | 6 |
| 完整解析资产合计 | 65 |
| actual texture slots | 340：327 有真实依赖，13 未解决 |
| atmosphere 研究的纹理依赖 | 53/53 已导入 |
| 导入图片合计 | 85：84 张完整 fpk PNG + 1 张内嵌云 NiPixelData |
| 透明像素非零的导入图 | 64 |
| 有部分透明像素的导入图 | 65 |
| 完整 fpk 图片索引 | 3,840 |
| filename-only 未绑定候选 | 180，不声称已绑定 |
| 当前 fpk 同名异 Pak 图片 | 0；算法保留多候选与不同 SHA，未依赖此结果合并路径 |

原 `compact-demo.json` 的 **10** 系统只用于教学，没有作为导入源。完整源为 `naval-study/atmosphere-fx/source-study/particle-contract.json`、33 个 `assets-json`、`textures.json`；水花/泡沫来自 `naval-study/deep/asset-details/complete-assets.json`；岸线来自 `naval-study/island-water/source-study/nif-structures.json`。

16 个完整粒子根效果：

| 根效果 | 系统 |
| --- | ---: |
| fx_cannon_fire_01 / 02 / 03 | 每个 11 |
| fx_cannon_hit_impact01 / 02 / 03 | 25 / 25 / 32 |
| fx_cannon_hit_blowout01 / 02 / 03 | 14 / 15 / 16 |
| fx_burning_smoke_low / medium / high_damage | 7 / 6 / 17 |
| fx_burning_smoke_sinking | 6 |
| fx_explosion_on_deck | 35 |
| fx_ship_destruction_explosion | 44 |
| smoketrail | 1 |

## 查实的贴图用途

下表根据原始 `NiTexturingProperty` 的真实 source ref 和模型 owner 编制，图片 Pak 与模型 Pak 通常不同，不能只扫描模型所在的 Pak，也不能凭文件名认定材质绑定。

| 原始消费资产/属性 | 查实依赖 | 可用于 Godot 的方向 |
| --- | --- | --- |
| `waterbasin.nif` property 7 / base | `Pak2/ocean deep.dds.png` | 深海底色的参考资源 |
| `reflectivewater.nif` property 6 / base | `Pak5/water_shader.dds.png` | 原水面基底 |
| 同一 property / detail | `Pak6/wavesdudv.tga.png`，原字段写 `WavesDUDV.tga` | 原材质扰动/滚动 detail；33 倍 UV tiling 原样留在 descriptor |
| `water.nif` property 11 / base | `Pak6/water.dds.png` | 另一个原海面路径 |
| Cat/Coastal2/Virgin 岸线 `Surf` properties | `Pak2/surf_bart3.dds.png` | 岸线条带的真实基底；三个岸线资产共 24 个绑定槽 |
| `cannon_ball_splash.nif` Cylinder01/02，properties 6/132 | `Pak6/fx_water_splash_004.dds.png` | 真实三维水柱网格纹理 |
| 同一资产五个水平水环，property 96 | `Pak0/fx_water_splash_rings_01.dds.png` | 水面扩散环 |
| 同一资产 SuperSpray，properties 25/148 | `Pak1/fx_streakin_001.dds.png`、`Pak5/fx_mist_01.dds.png` | 水滴及喷雾层，仍需解释各自 raw emitter/controller |
| 旧 `cannonball splash.nif` property 18 | `Pak7/water spash.tga.png` | 旧 sprite 水花版本；不能替代不同扩展名的未解决槽 |
| `fx_ship_bowfroth.nif` properties 12/35/84 | `Pak4/fx_waterfroth_002/001.dds.png`、`Pak3/fx_waterfroth_003.dds.png` | 船首泡沫粒子与 Box03 几何层 |
| `fx_ship_sidefroth_sloop.nif` property 8 | `Pak3/fx_waterfroth_003.dds.png` | 船侧泡沫；其他船型也按各自源资产提供 |
| `fx_ship_sinking_froth.nif` | `Pak4/fx_waterfroth_001/002`、`Pak3/fx_waterfroth_005`、`Pak6/fx_waterfroth_006`、`Pak0/fx_water_splash_rings_01` | 沉船大片泡沫、几何与水环；不是一个平面大白块 |
| `fx_cannon_fire_01.nif` properties 14/38/97 | `Pak5/fx_cannon_smoke_01`、`Pak2/fx_cannon_smoke_02`、`Pak6/fx_cannon_smoke_03` | 不同炮口烟层，完整 root 有 11 系统 |
| `fx_explosion_on_deck.nif` properties 12/37/60 | `Pak4/fx_explosionplasma_002a`、`Pak2/fx_explosionplasma_002b`、`Pak3/fx_explosionplasma_002c` | 不同爆炸图层，另外保留 glow、dust、sparks、splinter 层 |
| `fx_burning_smoke_high_damage.nif` properties 49/83 | underlit smoke 00/01 的 base 与各自 glow | 烟与发光来自不同纹理槽，不能忽略 glow 或据此统一加白 |
| `smallcloud.nif`、`largecloud.nif` property 10 | `Pak2/cloud_bw.dds.png` | 几何云，不能假设为 276 个 particle system 中的一个 |
| `smoke explosion.nif` source block 25 | `Pak5/cloud.nif` 的 pixel block 0 / mip 0 | 64×64 内嵌 RGBA；保留真实依赖，未换成 cloud_bw |

所有 PNG 本地路径均以 `res://assets/textures/reference_atmosphere/fpk/` 开头并保持 Pak 子目录；内嵌云单独放在 `embedded/Pak5/cloud.nif/embedded-0.png`。为让旧场景容器完整对应，32 个新增依赖中包含 **7** 张旧 `cannonball splash 02.nif` 整船容器的船帆/桅杆/旗/炮纹理；索引明确其 owner 与上下文，未把它们称为水纹理。

`02_sparkle_b.dds`、`water_spaarkle.dds`、`wake3.dds/tga`、`foam0002...` 等用户给出的线索已在**完整** fpk 索引中定位。当前选择的真实模型属性没有绑定这些文件，因此放在 `unbound_candidates` 而非伪造一个 source block。已看见的 shader 只证实 `NTM_Base/NTM_Detail` 的数学语义，不能凭 shader 名字证明某张 DDS 在原作运行时绑定。随后融合效果可以自主选用候选，但必须作为本作的明确选择记录。

三份 shader 索引为 `OceanWaterEMBM_ps11.nsf`、`OceanWaterSparkle_ps11.nsf`、`WaterSparkle.nsf`。`tReflectionTexture` 的 `empty.dds` 是**声明默认值**；索引保留 Pak3 候选，却没有把它标为实际反射纹理。原生运行时反射 render target 与该默认图不能混淆。

`dg_caustic.dds` 原研究明确为 filename candidate，六个岸线/焦散 NIF 中无其纹理引用。本轮保留 `binding_verified=false`，没有升级为已证实的焦散绑定。

## 已知缺项与实现边界

13 个未解决槽全部来自旧 water-effect 上下文，完整 atmosphere 53 依赖没有缺项：

- `Pak3/cannonball splash 03.nif` property 24 要求 `water spash.dds`；完整 fpk 没有这个精确文件，不能自动换成 `water spash.tga`。
- `Pak7/cannonball splash 02.nif` 是含整船对象的旧容器：`4SHOW_ship_pinnace_alpha_for_color.tga`、`4SHOW_ship_incidental.tga`、`flag_jolly_001.dds`、`flag_pennant_spanish.dds`、`ship_ropes_dark.dds`（2 个槽）、`4SHOW_ship_shrouds.tga`、`4SHOW_ship_pinnace_alpha_for_transparency.tga`、`ship_spanish_treasure_galleon_001.dds`、`ship_masts_002.dds`、`ship_spanish_treasure_galleon_001_alpha_objects.dds`、`ship_treasure_galleon_FORSHOW.dds` 合计 12 个槽未找到精确文件。

保留未知不会阻止使用已有现代 `cannon_ball_splash*`、现有三维水柱、水环和实际泡沫纹理。源码合同保存未知的采样分布、角度约定、color age 映射、spawn 容量处理、周期执行与 shader 质量 override 等；只有有原生证据的 GrowFade 数学另有 source 记录。本轮不替这些未知发明“原作公式”。Godot 可以以现有 accepted clock、shared water 与明确的本作规则实现好看的融合效果，后续再逐层做实际画面验收。

## 重现与验收

依赖 Node.js、Python/Pillow（本机 Pillow 12.2.0）、RTK；所有 shell 命令经 RTK。导入器在写任何输出前完成输入、原文件 SHA 与所有图片像素验证；参考树不会写入。支持 `--reference-root` 和 `--output-root`，拒绝向参考树或其子目录输出。

```powershell
rtk proxy node tools/import-reference-atmosphere.mjs
rtk proxy node tools/import-reference-atmosphere.mjs --verify-only
rtk proxy node tests/test_reference_atmosphere_import.mjs
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tests/test_reference_atmosphere_resources.gd
```

验证结果：

- 第一次 Node 合同测试按预期失败：没有完整导入器。
- 严格原字段对照曾发现 JSON 负零丢失，已修正稳定序列化，未减弱断言。
- Node 全量字段/完整资产/绑定/保留 Pak 变体/禁止扩展名替换/路径边界/输出 SHA 检查：**8,123 checks，0 failures**。
- Godot 4.7.2 headless 真实 JSON 与 Image 解码：**1,988 checks，0 failures**；85 张解码后的 RGBA SHA 与原 DDS/TGA/内嵌像素一致。
- `--verify-only` 重新导入到内存，全部 **156** 输出 SHA 与磁盘一致，未修改文件。

独立记录见 [local-verification.json](evidence/reference-atmosphere-resources/local-verification.json)。没有写入主任务的共享 verification.json。该证据证明资源可用、数据完整与转换可靠；效果画面、实际射击时间线、云雾组合、材质 blend 应由 root 在正式 Godot 场景亲自截图验收。
