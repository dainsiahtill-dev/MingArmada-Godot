# 东洋南海地理底层

这是现代广域物理海岸数据，供明代风格的只读游戏海图使用，不是十七世纪测绘图。经度/纬度与原游戏局部 `x/z` 米坐标分开；此目录不包含跨洋航行规则。

`east_asia_land.json` 裁切范围为东经 92–148°、南纬 12°–北纬 45°。来源为 Natural Earth 50m land，保拓扑简化容差 0.025°，舍入到六位小数，省略面积小于 0.002 平方度的岛屿及内陆水面孔。328 个陆地多边形、4590 个顶点；Godot 实际三角化为 3934 个三角形，失败多边形 0。文件约 104KB，原始全球 GeoJSON 用可重现 gzip 保留，约 532KB。

[Natural Earth land 官方说明](https://www.naturalearthdata.com/downloads/50m-physical-vectors/50m-land/)提供物理陆地与主要岛屿。[官方许可](https://www.naturalearthdata.com/about/terms-of-use/)说明其栅格及矢量地图数据属于 public domain，允许修改和商业使用。地图不使用现代国界；“大明、朝鲜、琉球”等为游戏历史叙事标签，不表示测绘行政界线。

`atlas_places.json` 的 8 个城市／区域定位来自 [Natural Earth 10m populated places](https://www.naturalearthdata.com/downloads/10m-cultural-vectors/10m-populated-places/) 的实际 GeoJSON Point geometry；原始 feature 子集保存在 `selected_natural_earth_places.json`。Macau 的属性经纬度与 Point geometry 存在差别，本项目明确选 Point geometry，不混合两套字段。端口名中的“大员”“爪哇”分别使用台南、雅加达区域定位，不冒称古代沙洲、城市或泊位精确复原。

平户点另取 [长崎县《測定地点一覧表》](https://www.pref.nagasaki.jp/uploads/2022/03/1646357182.pdf)，PDF 第25页／纸面第21页的 `620-1 平戸港`：世界测地系北纬33°22′17.0″、东经129°33′18.0″。这是现代港区测站，不等同郑芝龙时代的靠泊点。核对原 PDF SHA256：`04ef4b4d86b02183bcffd8b5433f2faada22866a7220b167f7549a05dea4bb30`；不转载整份 PDF 图像。

原始 URL、文件散列、构建参数与局限见 `provenance.json`。下载源为 Natural Earth 作者维护的 [natural-earth-vector](https://github.com/nvkelso/natural-earth-vector)；构建前校验完整源 SHA256，源更新会拒绝静默重建。

重建仅是开发工具，不是游戏依赖：

```powershell
rtk proxy python -m pip install --target Temp/research/cartography-py shapely==2.1.2
rtk proxy python assets/data/cartography/build_atlas.py --shapely-path Temp/research/cartography-py
```

游戏运行只读本地 JSON，不联网、不运行 Python，也不读取原始全球 gzip。山形、船式、罗盘与海浪是装饰；物理海岸来自矢量，地名由原生字体绘制，AI 纸纹不提供地图地理或中文标签。
