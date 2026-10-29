# 手绘海战 UI 透明资产

本页金云UI迭代已因用户审美反馈标记为 **rejected ornate iteration**，素材不删除；许福人物保留。当前克制候选见 [QUIET-ASSETS.md](QUIET-ASSETS.md)。

2026-10-27，内置 `image_gen.imagegen`，逐资产独立调用。不是 CLI/API fallback。原参考图先在 `view_image` 目检：`assets/ui/ming_maritime/menu-painting.png` 与 `docs/design/2026-10-26-ming-maritime/reference/menu-direction.png`。新资产延续深靛青漆木、旧金雕边、朱砂与青绿卷浪；正文与标题均由游戏实时绘制，图中无文字。

原始交付 PNG 在 `assets/ui/ming_maritime/painted/`。每张raw都是生成源的逐字节复制，RGBA 与原始 alpha 未改写；没有抠图、描边补画、颜色键或程序绘制替代。raw没有裁切、没有规范化缩放；`ASSETS.json` 中记录 `crop.applied=false`。生成原件仍留在 `C:/Users/dains/.codex/generated_images/01a17996-268f-72d2-b60d-a5d6678dba6f/`。后续授权的runtime裁切缩小副本与许福立绘见 [RUNTIME-ASSETS.md](RUNTIME-ASSETS.md)。

| 文件 | 原始像素 | 目检用途 | 外围 alpha=0 占比 |
| --- | --- | --- | --- |
| command-panel.png | 2172×724 | 操船/状态面板，云浪旧金边，深靛青安静正文面 | 17.73% |
| folio-panel.png | 1086×1448 | 航海日志竖面，细金双框，上角云纹，下缘卷浪 | 13.04% |
| header-cartouche.png | 2172×724 | 朱砂标题牌，旧金云头、两侧青绿波耳 | 40.98% |
| button-normal.png | 2172×724 | 靛青小按钮，细金框和小云角 | 44.39% |
| button-selected.png | 2172×724 | 同族选中/主要动作按钮，朱砂底、较亮旧金边 | 43.89% |
| compass-rose.png | 1254×1254 | 八向罗盘，旧金、深青、浅青针面，无方位字母 | 35.98% |
| button-normal-v2.png | 2172×724 | 未选用的更厚面备选，漆木纹理较明显 | 24.71% |
| portrait-xufu.png | 1086×1448 | 许福半身，朴素褐蓝布衣、闭合无字账册 | 41.25% |

六项主资产均逐张查看完整生成结果：外形完整、平视平面构图、无烘焙文字、无白纸中心、外部是真实透明。标题牌与按钮保留安静正文位置。选择按钮由一次独立的编辑调用生成，以 normal 原图为参考；同族和近似同轮廓成立，不能声称逐像素相同。

透明检测结果：每张 mode=RGBA，alpha 范围0–255；每张中心 alpha=253（约99.2%），不是严格255。近不透明的主体保持生成器原始输出，没有强制改成255。边缘偶有 alpha=1或2 的鲜色RGB像素，完整保留；正常alpha混合下贡献最多约0.8%。非零alpha包围盒因此不能等同于肉眼主体轮廓。完整统计和 SHA256 见 `ASSETS.json`。审计中七张均通过源文件字节相等检查。

## 接入边界

- 当前只完成位图生成与静态目检。游戏入口、GPU连续画面、正文对比度、窄窗、对话框、交互等由接入任务验证。
- 画布严格是3:1，但两张首选按钮的肉眼可见外形更接近5:1，并且上下存在生成的透明留白。不能把画布比例当作轮廓比例验收。
- 九宫格/三段横缩放可适配按钮宽度。当前原图较大；若希望约28px的源图边缘，可另存等比缩放副本，保持本轮原件与alpha源不动。不要把2172px宽原图直接套用28px边框后声称角饰已完整保护。
- 以下正文区是静态目检的保守起点，非正式布局合同：command约画布横向10%–90%、纵向23%–75%；folio横向12%–88%、纵向16%–83%；header横向18%–82%、纵向31%–67%；buttons横向13%–87%、纵向29%–66%。最终仍需实际字号、缩放与GPU截图检查。
- 不覆盖前轮 `menu-painting.png` 等素材；没有修改游戏脚本、场景或主题，也未提交。

## 复现信息

`ASSETS.json` 保存每张完整 prompt、生成原件绝对路径、文件SHA256、字节数、尺寸、alpha直方统计、alpha包围盒和裁切状态。选中按钮的实际工具参考图是本轮 normal 的生成源；其它调用未将前轮图作为编辑输入，参考图仅用于方向目检。

只读像素审计命令（仅更新本目录清单，不改PNG）：

```powershell
rtk proxy python docs/design/2026-10-27-painted-ui/audit_assets.py
```

保留备选与失败边界是本次记录的一部分；v2未替换首选按钮对。
