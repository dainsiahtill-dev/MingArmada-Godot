# 可航行外海母场景

资源ID：`map-open-sea-mother` · 场景与地图 · P0

跨六幕共享的可操船海域、海天与遭遇空间；雾、无风、风暴、日夜、战后搜索是条件包。

## 视觉与结构

船尺度下连续海面，远岸按需显隐；海平线、天空、可见度、风浪和航行空间先保持一致；船和碰撞水深作为独立数据，不用剧情画面反推真实里程。

## 制作与复用

场景/地图装配，不是独立3D基模，83预算增量0。共享海面/天空/天气场景＋船只/目标数据；地域战场是下列差异包，不能乘成24张独立地图。

地名与年代边界沿当前剧本；可游玩尺度、海岸布局、战术航线和建筑配置均为制作概念，未作原始测绘或逐舰战报复原。

此目录是生产参考，不被Godot自动导入。需要运行时使用时另行经现有资产合同导出。

## 图片

- [scene-context：sailing-background-76a6fe13.png](reference/sailing-background-76a6fe13.png) — 现有航行背景整图，提供海天构图；不是动态海面或可玩地形。
- [story-context：zheng_a3_s1-a9bc1b0f.png](reference/zheng_a3_s1-a9bc1b0f.png) — 雾航情境；为整幅剧情情境图，不能当本物件独立原画或结构验收。
- [story-context：zheng_a3_s10-9c790155.png](reference/zheng_a3_s10-9c790155.png) — 无风夜划情境；为整幅剧情情境图，不能当本物件独立原画或结构验收。
- [technical-sketch：structure-v1.svg](sketch/structure-v1.svg) — 可编辑概念结构/空间关系草图；非实测比例、非历史实址、非精确复原，不替代写实原画、模型或史料。

## 关联

资源需求保留自旧版六幕43场。链接只指向当前6部22章的相近历史阶段，不证明该物件或人物仍在新主线演出；逐项制作范围须另行复审。

旧稿需求出处：zheng_a1_s3、zheng_a1_s6、zheng_a2_s8、zheng_a2_s6、zheng_a2_s7、zheng_a2_s4、zheng_a2_s5、zheng_a3_s1、zheng_a3_s9、zheng_a3_s2、zheng_a3_s6、zheng_a3_s10、zheng_a3_s8、zheng_a3_s3、zheng_a4_s6、zheng_a4_s3、zheng_a4_s7、zheng_a5_s6、zheng_a5_s3、zheng_a5_s4、zheng_a5_s7、zheng_a5_s5、zheng_a6_s4、zheng_a6_s5

UI：sailing-hud、weather-wind、sea-encounter、battle-hud、fleet、battle-damage

原始出处、图像哈希、依赖与旧基模映射见 [asset.json](asset.json)。
