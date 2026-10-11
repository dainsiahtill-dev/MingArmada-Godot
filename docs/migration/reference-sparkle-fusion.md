# 原始海面细亮点与水纹理绑定核验

本轮按用户给出的线索追溯整个原始 Pak 库，而不是只依四个文件名猜用途。海面 helper 和 `ProjectedOcean` 绑定已冻结；真正融合到正式材质的 include/一次调用由主线程统一执行，然后做最终 GPU 画面验收。本轮没有导出新包或打开 GPU 窗口。

## 全库真实绑定

`build/tools/audit-reference-water-bindings.py` 只读扫描 **Pak0–Pak8，1253 个原 NIF**，从真实外部纹理名称与指定水面模型选出 **7 个相关资源**，用既有只读解析器读取至 EOF，**0 errors**。再沿 `NiTexturingProperty` 的真实对象指针解析材质槽，并在所有 Pak 中按精确 basename 寻找原图，记录完整路径、字节数与 SHA。证据：`assets/textures/pirates_reference/water-binding-provenance.json`。

| 真实资源 | 证实的纹理槽与全库路径 |
| --- | --- |
| `Pak1/sparkle_surface.nif` | **Base #7 → texture #8 `Pak0/water_spaarkle.dds`**；NIF SHA `1c203b6e7afcb76f9c284735b3839ffe998a74f7d9a6671f412aaff7f75b05b1`，11326 字节完整消费。 |
| `Pak0/fx_splash_body_in_water.nif` | **Base #12 → texture #13 `Pak0/fx_water_splash_02.dds`**；对应 Gloss #14 在 Pak5；其他 splash/drop 依赖分别精确解析到 Pak1/4/6/7。 |
| `Pak6/water.nif` | Base → `Pak6/water.dds`。 |
| `Pak3/reflectivewater.nif` | Base → `Pak5/water_shader.dds`；Detail → `Pak6/wavesdudv.tga`。 |
| `Pak2/waterbasin.nif` | Base → `Pak2/ocean deep.dds`。 |
| `Pak4/water_dark.nif` | Base → `Pak6/oceandeep2.dds`。 |
| `Pak7/old_water.nif` | `ocean deep.dds` 已精确解析；`waterdetail.dds/waterdetail2.dds/waterbump1.dds` 在本库没有精确文件匹配，保留未解析，不拿相似 `duel_*` 代替。 |

全库 NIF 内没有找到 `02_sparkle_b/foam0016/foam0024` 的原材质引用。因此它们在本作的亮点/浪沫角色依据实际通道、图像形状与游戏美术适配，不能写成已恢复的原作 shader 精确绑定。也没有凭此表批量塞入所有纹理，未新增无用途的 sampler。

原 shader 报告 `naval-study/SHADERS.md` 第 5/6 节分别证明 OceanWaterSparkle 的双层 Base RGBA 相乘、WaterSparkle 的 Base × 滚动 Detail × vertex RGBA。它们的 UV 动画不会修改几何位置。原 NIF 材质槽绑定与最终 shader/program 绑定是不同证据；原 `Top/Plane01` 矛盾仍保留，未补造运行结论。

## 四图实际内容

四张项目 PNG 已存在，实查均与来源 PNG 的 SHA 相同；Pillow 对原 DDS 解码后也逐像素一致。数据在 `assets/textures/pirates_reference/user-water-textures.provenance.json`。

| 图 | RGBA 范围 | 正确内容角色 |
| --- | --- | --- |
| `water_spaarkle.dds.png` | R 216–222，G 252–255，B 255，A 0–255；256² | RGB 近常量，**alpha 是稀疏斜向亮点**；平均 alpha 约 .096。海面微光蒙版。 |
| `foam0016.dds.png` | RGB 固定 203/227/214，A 0–255；64² | alpha 为不规则浪头与浪后泡沫，不能当法线或整幅白色 albedo。 |
| `foam0024.dds.png` | RGB 固定 203/227/214，A 0–238；64² | alpha 为互补浪头/尾沫与碎波蒙版；既有风浪层已经使用。 |
| `fx_water_splash_02.dds.png` | RGB 63–189/111–207/137–216，A 0–194；256² | 原 body-water splash 的泡沫/喷溅云 Base；RGB 不恒定，不拿来做普通 glint/normal。 |

原 DDS SHA 与 PNG SHA、alpha 统计及解码一致性都逐图记录。此轮采用原字节，不生成替代画面。

## 正式微光 helper

新增 `modules/scene_engine/ocean/reference_sparkle_fusion.gdshaderinc`：

```glsl
vec3 reference_original_micro_sparkle(
    vec2 world_xz, vec3 normal, float accepted_seconds,
    vec2 wind_direction, float wind_speed,
    float footprint, float view_distance, float light_alignment);
```

`ProjectedOcean` 绑定 `reference_original_sparkle_texture`，与原 `02_sparkle_b`、whitecaps 互补。helper 使用真实 alpha、两组不同倍率/旋转/相位的 UV，风向定义纹理坐标，风速推动 UV。重复接受时间完全重复结果，没有 shader `TIME` 或独立时钟。

低风、远景和无法解析的屏幕 footprint 消退。主 alpha 阈值高于未解析纹理平均覆盖率，避免远海变白；不同旋转与尺度避免共同方格周期。返回显示 RGB 增量受所有 0–1 权重限制，最高 `(.045,.061,.064)`；不影响几何、五波、物理或现有主配色。

主线程接线：

```glsl
#include "res://modules/scene_engine/ocean/reference_sparkle_fusion.gdshaderinc"
// Existing col/reflection_lobe variables in the formal optical expression:
col += reference_original_micro_sparkle(
    v_world.xz, n, u_time, surface_wind_direction, surface_wind_speed,
    footprint, length(u_eye.xz-v_world.xz), reflection_lobe);
```

可以把 `reference_original_sparkle_strength` 设为 0/1，在相同接受时间下独立开关对比新层；上限仍为 1。

## 本轮验证

- 新 helper 缺失时新增测试 RED，1 failure；创建并绑定后 GREEN。
- `test_reference_sparkle_fusion.gd`：**15 assertions，0 failures**，覆盖独立 shader include/签名解析、四图 SHA、实际 alpha 稀疏度、全库真实 Base 指针、未知绑定保留，以及正式 Ocean 绑定和接受时钟/五波不变。
- 全库审计：1253 NIF 搜索，7 相关 NIF 解析至 EOF，0 errors，两个线索纹理有实际材质指针证明。
- 四张 DDS → PNG 像素比对、原 PNG → 项目 SHA 比对，均为 4/4。

证据在 `docs/migration/evidence/reference-sparkle-fusion/green-original-layer.json`。以上不替代新 helper 接入后的实际 GPU 视觉检查；亮点尺寸、覆盖与动态观感由主线程的新截图/动画验收。
