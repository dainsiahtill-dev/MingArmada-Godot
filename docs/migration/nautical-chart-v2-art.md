# 古航图 v2 美术素材

使用内置 imagegen 生成两张独立素材。用户参考为
`C:/Users/dains/AppData/Local/Temp/codex-clipboard-c324d7d0-9cd4-4aff-8ad0-9e55e8dbde33.png`。
参考仅决定旧纸、靛青海墨、赭色陆地和传统云纹的美术方向。
素材不含地理、港名或船位，实际轮廓和交互仍由原生实时航图绘制。

| 素材 | 生成原文件 | 项目文件 |
| --- | --- | --- |
| 海纸与云纹框 | `C:/Users/dains/.codex/generated_images/01a12087-2701-7d12-9091-fd4eb5b1d3be/exec-a4cbd1f3-3eb6-4746-ad85-8fc22833ef50.png` | `assets/art/maps/ming-nautical-chart-v2.png` |
| 陆地纸纹 | `C:/Users/dains/.codex/generated_images/01a12087-2701-7d12-9091-fd4eb5b1d3be/exec-2b855d96-992a-4916-9e21-8bfd1676f651.png` | `assets/art/maps/ming-nautical-land-paper-v2.png` |

没有修改或删除生成原文件，保留 v1 素材供安全回退。
两图已复制进项目，经 Godot 导入，原生 Control 使用项目内资源。
海纸按图面尺寸绘制；陆地纸纹通过世界坐标 UV 仅填充真实陆地网格。
材质缺失时继续使用旧版海纸或原生纸纹，不影响投影和航点输入。

## 海纸完整提示词

Use case: stylized-concept. Asset type: production game UI background texture, Ming dynasty engraved nautical chart, rectangular landscape 4:3, high detail. Create a rich antique maritime chart material plate with NO land, NO geography, NO islands, NO ships, NO characters, NO writing, NO letters, NO numerals, NO labels, NO compass. Whole center is aged blue-green indigo sea on handmade fibrous parchment, muted slate-teal ink with visible warm paper grain, delicate very faint engraved Chinese wavelets across it; medium luminance so dark ink coastlines and light ocher islands drawn by game remain legible. Refined thin double-line antique gold engraved border close to all four edges; elaborate but restrained traditional Chinese curling cloud scroll ornaments only in corners and outermost 5% perimeter. Harmonious sea teal, old gold, ocher undertones. Handmade 17th-century navigation manuscript appearance; fine ink etching and genuine-looking old paper abrasion, no glossy metallic sheen. Main inner 85% has uniform quiet open water with no large illustrations so live map overlays are clear. NO modern graphics, NO heavy grunge, NO vignette, NO artificial drop shadows, NO fake cartographic symbols. This is an ART MATERIAL, not a whole invented map. Opaque full-bleed image.

## 陆地纸纹完整提示词

Use case: stylized-concept. Asset type: opaque repeatable parchment material texture used ONLY within runtime-drawn land silhouettes on a Ming dynasty nautical game map. Produce a square, seamless tileable texture, uniform golden ocher antique handmade paper with finely visible fibrous grain, tiny flecks and softly irregular warm ink-wash variations. Restrained antique yellow parchment, muted sand gold, faint sienna wash; medium-light luminance, plenty of calm even surface for black brush labels and engraved mountain relief. Original old navigation manuscript texture, high-resolution delicate natural paper detail. NO borders, NO dark edge vignette, NO holes, NO large stains, NO islands, NO geography, NO waves, NO mountains, NO symbols, NO writing, NO letters, NO labels, NO drawings. Entire texture extends uniformly edge-to-edge, matching adjacent repeat seams. Flat 2D material scan, no folds or 3D lighting. Suitable for readable tiny game minimap land, sophisticated subtle richness rather than heavy grunge.

两次均为新图生成，`transparent_background=false`，未使用 CLI/API fallback。
素材尺寸、PNG 签名与 SHA256 由 `tools/record-chart-captures.mjs` 的实际文件读取记录。
质量判断使用真正 Godot GPU 截图，概念素材不替代游戏运行证据。
