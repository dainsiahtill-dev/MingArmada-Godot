# 区域航海与势力底图

资源ID：`map-world-nautical-chart` · 场景与地图 · P0

澳门、福建、大员、平户、吕宋方向的跨区域导航底层；不得据界面示意补出已证历史行程。

## 视觉与结构

纸面/数字矢量海图，海岸轮廓、地名层、目的港、航路、限制区和当前位置分层；16:10与窄屏可裁，地图装饰与操作标记分开，图形位置先服务导航可读性。

## 制作与复用

场景/地图装配，不是独立3D基模，83预算增量0。二维底图与UI图层；旧art-maps的航行底图之一，不另算手工3D。当前矢量在render-world.js内联，无独立SVG文件。

地名与年代边界沿当前剧本；可游玩尺度、海岸布局、战术航线和建筑配置均为制作概念，未作原始测绘或逐舰战报复原。

此目录是生产参考，不被Godot自动导入。需要运行时使用时另行经现有资产合同导出。

## 图片

- [map-reference：ming-nautical-chart-v2-16f5d1dc.png](reference/ming-nautical-chart-v2-16f5d1dc.png) — 现有海图PNG，仅美术底层参照，非实测/原始历史海图。
- [material-reference：ming-nautical-land-paper-v2-fb8a2f1d.png](reference/ming-nautical-land-paper-v2-fb8a2f1d.png) — 现有陆地纸纹PNG；不是可导航海岸几何。
- [technical-sketch：structure-v1.svg](sketch/structure-v1.svg) — 可编辑概念结构/空间关系草图；非实测比例、非历史实址、非精确复原，不替代写实原画、模型或史料。

## 关联

资源需求保留自旧版六幕43场。链接只指向当前6部22章的相近历史阶段，不证明该物件或人物仍在新主线演出；逐项制作范围须另行复审。

旧稿需求出处：zheng_a1_s5、zheng_a1_s6、zheng_a2_s1、zheng_a2_s6、zheng_a3_s1、zheng_a3_s9、zheng_a3_s10、zheng_a5_s2

UI：sea-chart、route-plan、destination-detail、factions

原始出处、图像哈希、依赖与旧基模映射见 [asset.json](asset.json)。
