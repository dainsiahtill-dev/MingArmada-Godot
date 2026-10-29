# Runtime 派生皮肤与许福立绘

2026-10-27。六张主UI皮肤派生到 `assets/ui/ming_maritime/painted/runtime/`，本轮raw PNG逐字节保留。派生仅执行矩形裁切与等比LANCZOS缩小：先用alpha≥16定位可见包围盒，向外扩8个原始像素，受原始画布限制；原图画布已贴边的地方无法凭空补透明边。阈值只用于定位裁切框，没有对保留区alpha做阈值化、抠图、重涂、颜色键或强制不透明。

| 文件 | 输出像素 | 原图裁切框 x0,y0,x1,y1 | 推荐源图九宫格caps 左,上,右,下 | 适用目标 |
| --- | --- | --- | --- | --- |
| command-panel.png | 768×233 | 0,24,2172,682 | 90,40,90,62 | 370×150 操船HUD |
| folio-panel.png | 512×684 | 13,2,1073,1419 | 72,76,72,110 | 450×640 航海日志 |
| header-cartouche.png | 768×206 | 1,49,2171,632 | 130,36,130,36 | 至少260×72；优先保持比例 |
| button-normal.png | 512×101 | 7,126,2165,553 | 52,14,52,14 | 至少104×28，宽按钮 |
| button-selected.png | 512×102 | 5,122,2170,554 | 52,14,52,14 | 至少104×28，宽按钮 |
| compass-rose.png | 256×256 | 0,0,1254,1254 | 不做九宫格 | 保持正方形 |

caps是静态目检起点，不是GPU验收结果。command下沿卷浪较高，需要留出正文底部空间；建议370×150的正文边距从左28、上30、右28、下42开始。folio目标比例接近原图，角饰变形有限，但侧边中段也有纹饰，任意大幅纵向伸缩会拉伸这些纹饰。

100×36的小按钮使用额外的 `button-normal-small.png`（128×25）和 `button-selected-small.png`（128×26），二者从相同raw裁切框重新等比LANCZOS缩小，推荐源caps为左14、上5、右14、下5。512源的安全左右caps合计104px，无法原尺寸保角塞入100px控件；small副本让两端装饰在目标控件内合理保留。按钮正文应继续使用游戏Label，图中没有文本。二者保持各自等比尺寸，不能声称其轮廓逐像素一致。

`ASSETS.json` 给出阈值、阈值包围盒、最终exact crop、缩放比例、raw/派生SHA256、被裁外围的低alpha非零像素数以及每张caps。被裁掉的是阈值可见轮廓以外8px之后的极低alpha杂点，不影响raw原件；没有手工改alpha。派生后逐张完整查看，金色细角与外形保留。

复现：

```powershell
rtk proxy python docs/design/2026-10-27-painted-ui/derive_runtime.py
rtk proxy python docs/design/2026-10-27-painted-ui/audit_assets.py
```

## 许福

单独内置imagegen调用开启透明背景，生成并保留原件：

`assets/ui/ming_maritime/painted/portrait-xufu.png`

形象为半身老福建水手，褐色与旧蓝布衣、头巾束发、风霜脸、温和坚毅神情，双手持无字闭合旧账册；完整头手、自然墨刷下缘、无相框、无文字、无官甲。图像已静态目检，符合当前old-ledger人物角色方向。未生成陈阿海、林账房。

源码核对范围：`OpeningStory._scene_text()`第107–114行、人物投影第156行、许福关系第174–176行；`SecondVoyageAftermath.project()`第255–256行。源码只证实许福是承家号老水手、关注欠薪与船员伤亡；褐蓝衣着、头巾、具体年龄和脸部是本次用户方向下的美术解释，不能称源码记载的历史服制。陈阿海为领航员，林账房是留守金门的账房，不与林管事混同。second-return的speaker是交差账单/船上账册，不能强配许福为该场景证实在场的发言人。

完整prompt、生成原件路径、alpha/SHA与源合同证据在 `ASSETS.json`。本次CodeGraph明确返回本项目无索引，使用RTK精准源码读取；没有捏造CodeGraph查询结果。游戏代码与剧情合同未修改。实际old-ledger布局、对话按钮与GPU连续画面交由root集成核验。
