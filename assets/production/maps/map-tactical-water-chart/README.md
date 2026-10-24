# 海战与接舷态势底图

资源ID：`map-tactical-water-chart` · 场景与地图 · P0

战术封口、护货、回援、火攻和双船接舷的共享图层语法；每场载入差异配置。

## 视觉与结构

俯视海面/海岸简形、船影、射界、潮风、危险浅区、接应承诺和撤出线分层；接舷图保留双船、过板、甲板、舱门，文字和标记矢量化。

## 制作与复用

场景/地图装配，不是独立3D基模，83预算增量0。二维战术层＋船模俯视投影；对应art-maps的战术底层。不得把每场战术截图当一个3D地图；当前接舷SVG在render-ships.js内联。

地名与年代边界沿当前剧本；可游玩尺度、海岸布局、战术航线和建筑配置均为制作概念，未作原始测绘或逐舰战报复原。

此目录是生产参考，不被Godot自动导入。需要运行时使用时另行经现有资产合同导出。

## 图片

- [ui-screenshot：battle-orders-d692ff34.jpg](reference/battle-orders-d692ff34.jpg) — 已有评审截图，供信息层级参考，不能冒充独立矢量原稿。
- [story-context：zheng_a5_s4-523047d4.png](reference/zheng_a5_s4-523047d4.png) — 料罗湾战斗空间情境；为整幅剧情情境图，不能当本物件独立原画或结构验收。
- [technical-sketch：structure-v1.svg](sketch/structure-v1.svg) — 可编辑概念结构/空间关系草图；非实测比例、非历史实址、非精确复原，不替代写实原画、模型或史料。

## 关联

资源需求保留自旧版六幕43场。链接只指向当前6部22章的相近历史阶段，不证明该物件或人物仍在新主线演出；逐项制作范围须另行复审。

旧稿需求出处：zheng_a2_s7、zheng_a3_s3、zheng_a4_s3、zheng_a4_s7、zheng_a5_s4

UI：battle-orders、boarding、fleet、battle-hud、tutorial

原始出处、图像哈希、依赖与旧基模映射见 [asset.json](asset.json)。
