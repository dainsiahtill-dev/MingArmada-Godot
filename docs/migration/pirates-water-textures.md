# Pirates 水面参考纹理来源与通道审计

本轮共 27 张 PNG：26 张用户提供的商业游戏参考预览，1 张用户本次附件。所有交付文件位于 `assets/textures/pirates_reference/`，逐字节复制，保留原文件名、空格与拼写。每张源文件与交付文件的 SHA256 相同；没有烘焙、调色、缩放或旋转。

用户明确指定本次复用这些文件。此授权记录不等于原版权许可已验证：商业参考图不标为原创或公开许可；用户附件也未确认作者、原创性与许可。这里只确认指定 PNG 的来源路径和复制结果，未验证它们与原 DDS/TGA 的转换过程。

## 推荐的当前组合

当前选择 12 张已在代码绑定，14 张作为备选，1 张空 alpha 归档。绑定清单已核对，首轮真实 Godot 截图验收见文末。保留原水面 normal/waves，所有参考图只承担对应细节层，不把 27 张全部叠加。这是最初 27 张的整理；全目录素材研究另行记录，不把首轮组合当作最终资源选型。

- 海面：`02_sparkle_b.dds.png` 取 alpha 高光，`duel_ocean deep.dds.png` 低强度深水色变，`water.dds.png` 低强度水面 RGB 细节，`duel_waterdetail.dds.png` 只在浅水取 RGB 焦散。当前海面接入限定 `style1 fragment_detail`。
- 岸浪：`foam0008.dds.png` 取 alpha 波头，`foam0009.dds.png` 取 alpha 拖尾；`water spash.tga.png` 取 alpha 飞沫圆点。
- 船舶：两张 `wake3` 按 ship id 稳定选择 variant；`fx_waterfroth_003.dds.png` 乘尾流遮罩添加薄细沫；`fx_water_splash_rings_01.dds.png` 做贴合波高的扩散环；`water spash.tga.png` 也用于短喷溅的稀疏水滴主遮罩，`fx_water_splash_02.dds.png` 仅作内部细节。喷溅使用外围透明的椭圆网格和径向渐隐。全部以 alpha 作为形状。
- 焦散备选：用户附件 `user_water_caustics.png` 与 `duel_waterdetail` 的 alpha 在顺时针旋转 90° 后完全相同，RGB 不同。当前选 `duel_waterdetail`，用户附件保留备选，不同时叠加两份同构网纹。源图仍保留原方向。
- 当前不绑定：其余泡沫帧、第二张 sparkle、mist、standing gloss、water_shader、waterbump 和用户焦散附件。`foam0030` 没有效 alpha，明确不渲染。`water_shader` 与 `waterbump` 不作为已确认法线替换原 normal。

## 接入结论

绝大多数闪光、泡沫、环纹、尾流和飞沫图案在 alpha。RGB 纯色的文件取亮度会变成实心矩形。`fx_standing_water_01_gloss`、`water_shader`、`duel_ocean deep`、`duel_waterbump1` 和 `water` 的 alpha 恒 255，应按 RGB 内容选择低强度用途。`foam0030` 的 alpha 恒 0，只归档不显示。

岸浪微纹理优先 `foam0008` 波头和 `foam0009` 拖尾；`foam0006/0007/0011` 是密度变化备选。`foam0023/0024` 较满，适合低强度后层。所有 foam 的 RGB 都恒为 `(203,227,214)`。这些图是横向浪缘及下垂网纹，不能当圆点飞沫。真正的圆点飞沫优先 `water spash.tga.png` 的 alpha；弱雾晕用 `water mist.tga.png`。

尾流主体可用 `wake3.dds.png` 的 alpha，条带细沫可用 `fx_waterfroth_003` 的 alpha。两者都有非零底值，需要在 shader 内加区域、横向和寿命衰减；froth 最低 alpha 是 34/255，可用阈值消底。`wake3.dds` 与 `wake3.tga` 的字节和像素并不相同，保留两份，不作去重。

`duel_waterbump1` 呈 RGB 近灰度浮雕，适合作为高度微纹理候选，再由相邻采样差分得到扰动；不可直接把灰度 RGB 当已确认单位法线。`water_shader` 呈青色浮雕，但原编码未知：按 RGB/127.5−1 解码仅 27.2% 像素长度在 1±0.05，不足以证明是可直接绑定的常规法线。继续使用原有水面法线，参考图用途属于候选。

`duel_waterdetail` 与用户附件是焦散白网候选，仅在浅水范围使用 RGB 亮度；两者含 alpha 68..204，全幅非零，不能标为“无 alpha”或透明洞。两图 alpha 直方图相同，原方向逐像素一致：False；用户图变换后 alpha 完全匹配的方向：['rotate_270']；RGBA 完全匹配的方向：无。像素关系不用于推断作者、编辑历史或许可。

## 逐图通道和尺寸

数据来自 PNG 的 8-bit 存储值。RGB 亮度使用 Pillow Rec.601 权重；shader 若进行 sRGB 线性化，阈值必须在实际采样空间校准。以下均值和覆盖率是 alpha 的统计量。

| 文件 | 选择状态 | 原尺寸 | 掩码/内容通道 | alpha min..max / mean | alpha非零 | 用途候选及注意 |
|---|---|---:|---|---|---:|---|
| `02_sparkle_b.dds.png` | 主用，代码已绑定 | 256×256 | `alpha` | 0..255 / 42.509 | 63.41% | 水面稀疏高光；阈值筛选后的细滴飞沫。RGB恒(216,255,255)，散点图案仅在alpha；阈值和强度仅在shader中调整。 |
| `foam0016.dds.png` | 备选，当前未绑定 | 64×64 | `alpha` | 0..255 / 84.822 | 73.36% | 较密岸浪拖尾；第二层泡沫。RGB恒(203,227,214)，alpha为横向浪缘和下垂网纹，不是圆点飞沫。 |
| `foam0024.dds.png` | 备选，当前未绑定 | 64×64 | `alpha` | 0..238 / 101.460 | 93.21% | 密集岸浪泡沫后层。RGB恒(203,227,214)，alpha非零比例93.2%；避免单层高强度形成白带。 |
| `fx_standing_water_01_gloss.dds.png` | 备选，当前未绑定 | 256×256 | `rgb_luminance` | 255..255 / 255.000 | 100.00% | 局部低强度水面gloss变化。alpha恒255，RGB亮度0..109；可以shader内控制增益，原图不归一化。 |
| `fx_water_splash_02.dds.png` | 主用，代码已绑定 | 256×256 | `alpha` | 0..194 / 88.589 | 97.22% | 低强度水花烟状微纹理。RGB也有蓝白变化，alpha有起伏但97.2%非零；需要区域包络，避免满幅矩形。 |
| `fx_water_splash_rings_01.dds.png` | 主用，代码已绑定 | 128×128 | `alpha` | 0..255 / 16.619 | 27.25% | 局部水花环纹；短寿命涟漪。RGB恒(255,251,255)，环图案在alpha；局部clamp采样配合生命周期淡出。 |
| `wake3.dds.png` | 主用，代码已绑定 | 128×128 | `alpha` | 4..231 / 104.172 | 100.00% | 船舶尾流主体细节。alpha最低4且全幅非零，需尾流区域衰减；与tga版本不是相同文件。 |
| `wake3.tga.png` | 主用，代码已绑定 | 128×128 | `alpha` | 4..231 / 104.491 | 100.00% | 船舶尾流主体细节备选。alpha最低4且全幅非零，需尾流区域衰减；与dds版本不同，保留两份。 |
| `water_spaarkle.dds.png` | 备选，当前未绑定 | 256×256 | `alpha` | 0..255 / 24.486 | 48.50% | 较稀水面闪光；细粒飞沫。RGB近纯色，图案在alpha；拼写spaarkle保留。 |
| `foam0002.dds.png` | 备选，当前未绑定 | 64×64 | `alpha` | 0..68 / 7.359 | 16.31% | 岸浪早期或淡残留。alpha0..68仅5档、16.3%非零，密度很低；不适合作为主要白浪头。 |
| `foam0006.dds.png` | 备选，当前未绑定 | 64×64 | `alpha` | 0..255 / 44.708 | 37.84% | 岸浪波头微纹理。横向浪缘及网状拖尾；alpha38%非零，为较薄浪头。 |
| `foam0007.dds.png` | 备选，当前未绑定 | 64×64 | `alpha` | 0..238 / 47.908 | 42.04% | 岸浪波头微纹理备选。横向浪缘及网状拖尾；alpha42%非零。 |
| `foam0008.dds.png` | 主用，代码已绑定 | 64×64 | `alpha` | 0..238 / 51.369 | 45.04% | 岸浪波头微纹理优选。横向浪缘及网状拖尾；alpha45%非零，适合作为浪头。 |
| `foam0009.dds.png` | 主用，代码已绑定 | 64×64 | `alpha` | 0..255 / 54.719 | 49.07% | 岸浪拖尾微纹理优选。横向浪缘及网状拖尾；alpha49%非零，适合与0008异相叠加。 |
| `foam0011.dds.png` | 备选，当前未绑定 | 64×64 | `alpha` | 0..255 / 62.032 | 56.03% | 较宽岸浪泡沫带。横向浪缘及网状拖尾；alpha56%非零，为较宽泡沫层。 |
| `foam0023.dds.png` | 备选，当前未绑定 | 64×64 | `alpha` | 0..255 / 117.987 | 90.43% | 密泡沫后层。alpha90.4%非零，均值118，密度高；需较低增益或局部遮罩。 |
| `foam0029.dds.png` | 备选，当前未绑定 | 64×64 | `alpha` | 0..85 / 20.034 | 75.32% | 岸浪消退残留层。alpha0..85仅6档，低对比衰减层；不能用RGB取图案。 |
| `foam0030.dds.png` | 空白，仅归档 | 64×64 | `none_empty_alpha` | 0..0 / 0.000 | 0.00% | 来源归档。alpha恒0且RGB恒色，没有有效泡沫mask；原字节保留，不绑定显示。 |
| `fx_waterfroth_003.dds.png` | 主用，代码已绑定 | 256×64 | `alpha` | 34..255 / 120.830 | 100.00% | 尾流条带细沫；浪花条带微纹理。256x64条带；RGB恒(214,255,255)，alpha34..255全幅非零，需shader阈值去底及尾流区域淡出。 |
| `water mist.tga.png` | 备选，当前未绑定 | 128×128 | `alpha` | 0..63 / 4.760 | 41.39% | 船首弱雾晕；岸浪弱雾晕。RGB恒255，alpha0..63；原强度很弱，可shader控制增益，文件名空格保留。 |
| `water_shader.dds.png` | 备选，当前未绑定 | 256×256 | `rgb_luminance` | 255..255 / 255.000 | 100.00% | 水面RGB浮雕微纹理候选。alpha恒255。像素具有青色浮雕外观，但常规RGB单位法线解码仅27.2%长度在1±0.05；原shader合同未知，不按已确认normalmap使用。 |
| `duel_ocean deep.dds.png` | 主用，代码已绑定 | 256×256 | `rgb_color_or_luminance` | 255..255 / 255.000 | 100.00% | 低强度深水色变；低频海面颜色细节。RGB青绿色低对比纹理，alpha恒255；保留水面基础色，用小权重混合。 |
| `duel_waterbump1.dds.png` | 备选，当前未绑定 | 256×256 | `rgb_luminance_height_candidate` | 255..255 / 255.000 | 100.00% | 水面高度微纹理候选；以相邻采样差分生成扰动候选。RGB近灰度浮雕、alpha恒255；不是已确认RGB法线。直接XYZ解码长度均0.321，仅0.13%在1±0.05。作为高度使用也属于候选，原shader未验证。 |
| `duel_waterdetail.dds.png` | 主用，代码已绑定 | 256×256 | `rgb_luminance` | 68..204 / 88.569 | 100.00% | 仅浅水焦散白网细节。RGB青色白网；alpha68..204全幅非零，仅9档，不作为透明洞。与用户附件alpha逐像素关系另列。 |
| `water.dds.png` | 主用，代码已绑定 | 256×256 | `rgb_color_or_luminance` | 255..255 / 255.000 | 100.00% | 低强度水面颜色细节；低强度微波亮度调制。青蓝低对比RGB微纹理；alpha恒255；不可按透明mask或已确认法线使用。 |
| `water spash.tga.png` | 主用，代码已绑定 | 128×128 | `alpha` | 0..203 / 10.091 | 28.65% | 船首稀疏圆点飞沫；岸浪圆点飞沫。RGB恒255，alpha0..203；实看为离散圆滴/环斑，>64仅6.8%；spash及空格原样保留。 |
| `user_water_caustics.png` | 备选，当前未绑定 | 256×256 | `rgb_luminance` | 68..204 / 88.569 | 100.00% | 浅水焦散白网细节。用户附件，RGB白网清楚；含alpha68..204全幅非零，仅9档，不能宣称无alpha，也不作为透明洞。 |

## 采样和验收限制

交付保留原尺寸。64×64 泡沫只用于微纹理，避免单张大尺度拉伸；128×128 局部尾流/飞沫需要区域包络；256×64 froth 保持 4:1 内容比例。27 张 `.import` 已设置 `mipmaps/generate=true`，保持 `compress/mode=0`、alpha remap=3、premult_alpha=false、size_limit=0 和默认 fix_alpha_border=true；由主任务统一重新导入以供远景抗闪烁采样。源 PNG 原字节不变，Godot 衍生纹理有 mips 和默认 alpha 边缘处理，不宣称 ctex 与源 PNG 逐位一致。纹理边缘无缝性尚未验证。不要生成放大版、alpha烘焙版或调色版替代这些交付源图。

诊断 contact sheet 的三列依次是忽略透明度的原 RGB、alpha 灰度、RGB 亮度；仅诊断图使用最近邻放大显示小纹理。诊断文件位于 `build/water-reference/`，不作为游戏资产绑定。完整逐通道 256 档直方图在 `channel-audit.json`，正式清单提供 RGBA min/max、均值、标准差、零值/满值计数、阈值覆盖率及 alpha 各值像素数量。所有 contact-sheet 页均经 view_image 人工检查。

通道审计阶段仅检查文件；主任务后续完成了下述真实 Godot 采样。原游戏的材质运行路径仍需依据原研究的静态证据与限制区分。CodeGraph 在目标目录没有索引，本任务采用 RTK 源码与文件检查。

## 首轮 Godot 实景验证

`tools/capture-reference-water.gd` 启动真实 LegacyScene，在隔离存档下使用出港、持续前进、转弯、暂停及舷侧开炮命令；GPU 为 Intel Arc 130T，Godot 4.7.2 / D3D12 Forward+。捕获 10 张 1600×900 原始画面，每张对应 JSON 记录实际状态、镜头、事件、GPU 与图片 SHA256。主线程通过 view_image 逐张检查全部十图。

- [靠岸静止](C:/Users/dains/Documents/Git/ming-armada/docs/migration/evidence/reference-water/coast-docked.png)：没有尾流色块。
- [前进](C:/Users/dains/Documents/Git/ming-armada/docs/migration/evidence/reference-water/sailing-straight.png)、[转弯](C:/Users/dains/Documents/Git/ming-armada/docs/migration/evidence/reference-water/sailing-turn.png)：船后有随航迹变化的渐隐泡沫；仍是首轮细节，后续依据原 wake.ini 和新增资源调整。
- 岸浪 a/b/c 按接受时间推进；[wave-c](C:/Users/dains/Documents/Git/ming-armada/docs/migration/evidence/reference-water/coast-wave-c.png) 与 [暂停](C:/Users/dains/Documents/Git/ming-armada/docs/migration/evidence/reference-water/coast-paused.png) PNG 哈希完全相同，naval/adventure 状态完全相同。runtime 的 pauseReasons/paused 等响应字段按暂停命令改变。
- [真实炮弹落水出生](C:/Users/dains/Documents/Git/ming-armada/docs/migration/evidence/reference-water/real-cannon-splash.png)、[+0.183s](C:/Users/dains/Documents/Git/ming-armada/docs/migration/evidence/reference-water/real-cannon-splash-peak.png)、[+0.5s](C:/Users/dains/Documents/Git/ming-armada/docs/migration/evidence/reference-water/real-cannon-splash-fading.png)：实际连续炮弹产生水滴与扩散环，先前的实心矩形已消除。当前仍缺原研究说明的真正三维水柱；本轮不把面片喷溅称为完整原作水花复刻。

抓图脚本 exit 0，`captures=10 failures=0`。随后全套 headless 验证 58 项测试全部通过，含水效 127 assertions、岸浪喷溅 13 assertions；完整原输出见 [verification.json](C:/Users/dains/Documents/Git/ming-armada/docs/migration/evidence/verification.json)。独立复核确认原 water normal/vertex、CPU/GPU 波函数、船体动力内容保持。截图使用固定接受步长，**不是 FPS/帧耗时性能测试**，不证明完整迁移、全场景美术或大舰队性能验收。

## 字节来源与 SHA256

完整绝对源路径在 `provenance/pirates-water-textures.json`。游戏预览基路径为 `C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk/`，下表标明 Pak；附件记录原 Temp 路径。

| 文件 | 来源 | SHA256 |
|---|---|---|
| `02_sparkle_b.dds.png` | Pak0 | `c22a0922885b21eb048d7a69bebbe3121d354630ff5a133ac2c7e97500362811` |
| `foam0016.dds.png` | Pak0 | `4e5cdddf6b16cabb3955b5ac3a539123abbb78017cb8d74beab43958e5c51a96` |
| `foam0024.dds.png` | Pak0 | `1ac058271974fb0dadac22feb12f3104c7d4be75b444012ce08d88eacedad34a` |
| `fx_standing_water_01_gloss.dds.png` | Pak0 | `744e20d6a405a2a7dfa9b72b55f9e126d80d85563ceca58160901046583c56d5` |
| `fx_water_splash_02.dds.png` | Pak0 | `eb2f400a40f0a9cc1ce46f12b86bca45ff0ecfe21aee9ba0245349f6c8d3617e` |
| `fx_water_splash_rings_01.dds.png` | Pak0 | `e49d14b518122a8499be6df059a2e60d7a55195efebb57263a4147b8f88fa675` |
| `wake3.dds.png` | Pak0 | `81662e09f67ea959729426381ce6aaf8d7d3f718b17d6abfeb6b9fdd5019e6ea` |
| `wake3.tga.png` | Pak0 | `da7a60e0141c4e24707d6af69c09351032b0b3dfc1864a22b84d425c20f030da` |
| `water_spaarkle.dds.png` | Pak0 | `7ffdd77800ec4e7a0badd54bc220b919de272045bfb5e4bf763c3431fb933952` |
| `foam0002.dds.png` | Pak3 | `3e43122607248f7b7e1af7b1326422e318ea2d2abd7bf29550af75cb58789dd9` |
| `foam0006.dds.png` | Pak3 | `6a4f97298295fd55c04a94d1b362629a386cd06cd5e3bccf4a49ba773ef5dc2c` |
| `foam0007.dds.png` | Pak3 | `1301cc1c965acccdcc8c80c4e4d769088b65908e7cd987c8bd1294a39be5c81e` |
| `foam0008.dds.png` | Pak3 | `ce455937e195fb6d0ad4d52a5d35ae89bb39a1ceb3c50dc0f581c7d2b89293ad` |
| `foam0009.dds.png` | Pak3 | `632cc4b0e026f91acf9c29ddd71fcfae517dbf663e897532c88f6683c415905e` |
| `foam0011.dds.png` | Pak3 | `c08de9b157d0bdb7d85fc37e0fdef0aa913e4d7eed07d7334ca11e9dbeabe456` |
| `foam0023.dds.png` | Pak3 | `cf426de7afc45cf181465cbabe8287fbb0f81ed57c3e04796c62691a0d9a1b73` |
| `foam0029.dds.png` | Pak3 | `e7d41b61d1de28748462200f339a42b7367af68755c5a1b50e78773114b869aa` |
| `foam0030.dds.png` | Pak3 | `2c9bdaa0dd8ca30bd2d17f54ffde79df434241200979325752f0bf7d00caec96` |
| `fx_waterfroth_003.dds.png` | Pak3 | `a9cfae87b3b4a1c25d4dfa7c37fbb197ebbf14d8e50f5d4bb579ada3a3c37a7e` |
| `water mist.tga.png` | Pak5 | `6e7117f87cb16e6111f5bbc7824cf570adf9cc7d8a6368b26a45740be9225198` |
| `water_shader.dds.png` | Pak5 | `dd40fffd22e33f942793d4a959475bf5dc0443786c643db9a5b267b9b5b293dd` |
| `duel_ocean deep.dds.png` | Pak6 | `562194e4ed5f9fb69300d40a105e9aad7da100c503d78513f49b1c11e604b7a7` |
| `duel_waterbump1.dds.png` | Pak6 | `e847ce9dc32122c042affbd6e7694db53ac011e669eb35282e15df4f3e36a14f` |
| `duel_waterdetail.dds.png` | Pak6 | `05a0f1576bfe44327c2c1ece9f69b32b350928ee7019819e4582414a32c6ee64` |
| `water.dds.png` | Pak6 | `ab4ce406eefb8b15128355e6c66c6ecc62ccc757da5937954f6b66c2f88b5fe3` |
| `water spash.tga.png` | Pak7 | `4dca5f9fb03655b6317404570ccd8649cd27c1af619a3bea4252d1df8480bf38` |
| `user_water_caustics.png` | 用户附件 Temp/codex-clipboard-83c0b05f-9a86-4a66-a828-2f94d77d5223.png | `83c670624064a6817e3e7e94079b98d512fff5abf19b82a389fe50aca46c3e5e` |
