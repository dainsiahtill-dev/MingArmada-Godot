# 岛岸与浅滩地形母版

资源ID：`nature-island-terrain` · 自然与材质条件 · P0

共享岛岸、沙滩、岩岸、岸路与水深碰撞需求，服务多个地域差异包。

## 视觉与结构

按可玩船尺度制作低远岸与近岸高差，砂/岩/草/土层过渡，岸路与码头接缝连续；实际地形大小由航速、镜头和导航测试确定，非历史测绘。

## 制作与复用

程序式地形/水深数据与场景原生资源；不是独立手工3D基模，83增量0。岩块实例引用nature-rock，不能把岛数乘算基模。

地形母版与水深皆为游戏制作概念；未对应原始17世纪海图测深或已验地形复原。

此目录是生产参考，不被Godot自动导入。需要运行时使用时另行经现有资产合同导出。

## 图片

- [data-texture-reference：weights_0-7da036eb.png](reference/weights_0-7da036eb.png) — 现有地形权重贴图；不是手工场景平面，也非真实历史水深。
- [scene-context：port-hub-v2-edf92ad5.png](reference/port-hub-v2-edf92ad5.png) — 现有港口整图；已目视有石堤、木货栈及日本城楼背景，只取局部材质、工作港密度参考，不整图指认为厦门。
- [technical-sketch：structure-v1.svg](sketch/structure-v1.svg) — 可编辑概念结构/空间关系草图；非实测比例、非历史实址、非精确复原，不替代写实原画、模型或史料。

## 关联

资源需求保留自旧版六幕43场。链接只指向当前6部22章的相近历史阶段，不证明该物件或人物仍在新主线演出；逐项制作范围须另行复审。

旧稿需求出处：zheng_a3_s2、zheng_a3_s3、zheng_a4_s6、zheng_a4_s7、zheng_a5_s4

UI：sailing-hud、port-hub、battle-hud、sea-chart

原始出处、图像哈希、依赖与旧基模映射见 [asset.json](asset.json)。
