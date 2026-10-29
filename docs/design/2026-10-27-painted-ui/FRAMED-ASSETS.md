# Quiet framed：细旧金边与柔和投影

2026-10-27，用户新增“适当克制的金边”和“每个窗口都应该有投影”反馈。独立两次内置imagegen编辑，以当前quiet command/folio为明确edit targets，调用前已view，透明背景true。保留青绿布纸方向、folio单角淡云与安静正文区域，只加细旧金单线和外部暗软影；未回到雕花金框。两张raw/runtime均已逐张view。

- raw：`assets/ui/ming_maritime/painted/quiet/framed/command-panel.png`、`folio-panel.png`
- runtime：同目录 `runtime/` 下同名文件，command768×384，folio512×677。
- 完整prompt、edit target与生成源、源/新图SHA、alpha与派生信息在 `FRAMED-ASSETS.json`。

raw与生成源逐字节一致，原始alpha未改。生成式编辑会重新解释局部纤维，不能称正文像素与输入原图完全一致。旧quiet及ornate所有图仍保留。没有追加第三张shadow-frame：本轮一体skin实际存在低alpha渐变暗影，root接入时按原生expand_margin保护外部绘制空间；其九宫格最终效果仍须GPU核验。

## 透明阴影证据

图中深色外缘不是白底或棋盘背景。以view确定右中“细金线以外”的暗缘位置后，读取真实RGBA：

- command，原图1774×887，y=443，x=1747、1750、1753、1756、1759、1762、1765、1768、1771，alpha依次172、132、106、68、30、16、9、5、3，RGB为低亮中性暗色。
- folio，原图1086×1448，y=724，x=1047、1050、1053、1056、1059、1062、1065、1068、1071、1074，alpha依次216、118、76、49、31、18、9、3、1、0，RGB为低亮暗色。

这证明对应外缘有逐渐淡出的真实半透明像素。将该外缘解释为“投影”同时依赖完整图像目检；单靠alpha不能自动区分投影、抗锯齿或纸纤维。完整witness RGBA存于JSON，不把任意透明边缘一概算作投影。

四周4%透明安全边是prompt目标，但生成器未完整满足：command原画布边缘最大alpha13，folio最大alpha1；command右侧尾部触画布alpha3。不能宣称四周已有4%完全透明边，画布外被截断的极低alpha尾也无法由现有PNG恢复。原始结果如实保留，未用程序补画或抠图制造验收。root已采用约8px的StyleBoxTexture.expand_margin，将窗口绘制外扩而不挤正文；这不等同于恢复画布外未生成的阴影。

## 派生策略

本轮绝不用alpha≥16裁切。仅取alpha>0精确包围盒，外扩8原像素；只允许丢弃alpha严格为0的外围，程序断言所有非零alpha像素数保留，然后等比LANCZOS缩小。

- command非零alpha包围盒覆盖整画布，所以未裁，1774×887→768×384。
- folio裁切框为[0,13,1086,1448]，只去掉顶部完全透明区，1086×1435→512×677。
- runtime中心alpha仍253，command中心RGBA为[18,55,63,253]，folio[24,56,65,253]。

复现：

```powershell
rtk proxy python docs/design/2026-10-27-painted-ui/derive_framed.py
```

最后执行exit0，raw字节一致、所有非零alpha保留断言通过。此脚本不改输入raw或旧素材。

## 验收边界

旧77/2、113/6、120/0的headless记录全部保留，不能复用为新framed素材验收。字体、contrast、扩展绘制矩形到正文的映射、焦点与九宫格投影由新的framed验收和GPU检查。小inset仍可保留无云/无投影的quiet内底，按钮仍quiet。没有改产品代码、提交或运行GPU。
