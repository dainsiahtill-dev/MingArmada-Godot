# 海天与风雾昼夜条件集

资源ID：`nature-ocean-sky-profile` · 自然与材质条件 · P0

海面、天空、云雾、风雨与能见度的视觉目标；与production-assets中fx-ocean-weather同一需求，不重复新增效果数量。

## 视觉与结构

连续海平面与远海天线，青灰/蓝绿水色、晨昏/夜色，横浪/无风/雾/风暴轮廓可辨；水花尾迹由对应效果条目提供，参考图只锁视觉方向。

## 制作与复用

海面shader、天空/天气配置与效果资源，独立基模0；映射既有fx-ocean-weather，不把shader、粒子或贴图算模型。

游戏海天条件概念；剧本风暴、无风、雾航多数为虚构具体航次，未声称对应历史气象观测。

此目录是生产参考，不被Godot自动导入。需要运行时使用时另行经现有资产合同导出。

## 图片

- [scene-context：sailing-background-76a6fe13.png](reference/sailing-background-76a6fe13.png) — 静态航行背景；不代表这些天气已全部原生验收。
- [material-reference：waternormals-add9912b.jpg](reference/waternormals-add9912b.jpg) — 现有水面法线素材，不能当新海面方案验收。
- [technical-sketch：structure-v1.svg](sketch/structure-v1.svg) — 可编辑概念结构/空间关系草图；非实测比例、非历史实址、非精确复原，不替代写实原画、模型或史料。

## 关联

资源需求保留自旧版六幕43场。链接只指向当前6部22章的相近历史阶段，不证明该物件或人物仍在新主线演出；逐项制作范围须另行复审。

旧稿需求出处：zheng_a1_s2、zheng_a1_s3、zheng_a3_s1、zheng_a3_s10、zheng_a5_s7

UI：sailing-hud、weather-wind、battle-hud、laboratory

原始出处、图像哈希、依赖与旧基模映射见 [asset.json](asset.json)。
