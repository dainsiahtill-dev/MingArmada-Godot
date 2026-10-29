# Quiet：克制的航海册材质

2026-10-27，依据用户否定“太花里胡哨”后新一轮方向生成。原金云素材完整保留，原清单逐项标记 `rejected ornate iteration`；许福人物保留为美术焦点，未生成其它人物。四张新图均用内置imagegen单独调用、透明背景true，无CLI/API fallback。完整prompts、生成原件、SHA256、alpha与裁切信息在 `QUIET-ASSETS.json`。

新raw：
- `assets/ui/ming_maritime/painted/quiet/command-panel.png`
- `assets/ui/ming_maritime/painted/quiet/folio-panel.png`
- `assets/ui/ming_maritime/painted/quiet/button-normal.png`
- `assets/ui/ming_maritime/painted/quiet/button-selected.png`

四张raw均与各自生成源逐字节相同；没有画布程序绘图、抠图、调色、重绘边缘或强制修改alpha。四张已用本地 `view_image` 完整查看：command只在左缘一短段低对比缝线，无闭合描边；folio仅左边旧书脊和单一左上淡青墨云，无描金或重复云角；按钮均为无描边旧墨纸条。无金框、雕花、对称奢华饰件、发光、厚阴影、文字或标题牌匾。folio云纹按最新方向作为安静文化呼应，prompt要求面积<2%；未分割该区域进行精确面积测量，因此不声称量化证明。

原始画布像素：command1774×887、folio1086×1448、normal/selected2089×753。按钮实际可见轮廓长宽比约5.7:1，超过prompt约4:1；安静纸条边缘适合九宫格适配100×36，不掩盖这一生成偏差。command raw画布2:1，裁掉外围留白后可见材质更接近2.4:1。

## Runtime副本

`quiet/runtime/`下同名文件，仅alpha≥16包围盒外扩8原像素裁切，再等比LANCZOS缩小。阈值用于找矩形框，没有改保留区alpha；raw完全保留。

| 文件 | 尺寸 | 源caps 左、上、右、下 | runtime中心RGBA |
| --- | --- | --- | --- |
| command-panel.png | 768×322 | 8、8、8、8 | 15、47、54、253 |
| folio-panel.png | 512×676 | 32、16、8、8 | 22、51、60、253 |
| button-normal.png | 128×23 | 8、3、8、3 | 18、50、55、253 |
| button-selected.png | 128×23 | 8、3、8、3 | 118、55、41、253 |

八张raw/runtime均逐张目检。alpha范围均0–255，中心253/255，不假定为严格不透明。按钮sourcecaps最大8px，可在100×36内留下足够中央区域。具体字体、标题层级、色彩、焦点及实际窗口表现仍需原生控件与GPU验证；本页不把静态位图目检当作游戏验收。

复现仅派生与审计：

```powershell
rtk proxy python docs/design/2026-10-27-painted-ui/derive_quiet.py
```

该脚本生成副本、记录raw字节等同性并标旧素材rejected；不改游戏代码。原生成文件继续保留在Codex generated_images。正式Theme与标题由root接入，header不再生图。

## 已暂停的旧skin测试

之前新增的 `tests/test_maritime_art_theme.gd` 针对旧金云runtime资源，首轮headless日志为 `evidence/skin-headless.json` 与 `evidence/skin-headless.log`，真实marker为 `MARITIME_ART_THEME_TEST assertions=77 failures=2`。所有旧texture中心对比和focus资源检测通过；两项失败是默认16px“确定”按钮原生最小高38px超过测试36px。该现象并未证明sourcecaps造成推大；HUD另用14px。用户改方向后已暂停旧测试，未将失败改写为通过，也未修改产品来满足测试。测试尚需在新quiet接入冻结后按真实字体和控件适配；旧日志不构成新方案通过。
