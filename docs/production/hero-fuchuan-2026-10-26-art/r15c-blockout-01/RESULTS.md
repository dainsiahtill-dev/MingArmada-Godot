# R15c：单一位移场重塑旧栏杆，保留为失败样本

结论：不建议推广。原网格足够支持可复核的、无新增结构的位移实验，但 Blender 静态对照中，船首栏顶部出现突兀尖折，艉栏局部凸起；可见变化主要是细栏，不构成 300–400 像素船身尺度下清晰、可信的整体轮廓改善。按预注册的自然接合及正常视距可读性门槛，作为美术失败记录。图像为固定 Blender 灯光与机位，不是实际游戏距离截图；需要独立审美复核。

## 来源与顺序

- 唯一基线为 R9b 作者文件，SHA-256 `2961f7f28d31cfc71a16638fbd634b4245912adb1fcf79bc55bfc5d00722d2e8`，保持 R9b 帆色。先测量旧栏，再写入预注册，再制作候选。冻结的 [预注册](r15c-preregistration.md) SHA-256 `ea341050127c112af3b23fca7e89daa0162b1f31fd9d44491cd5e2b237911d46`，与作者进程记录的输入哈希一致。
- 新的可编辑 [Blender 作者文件](../../../../assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r15c-blockout-01.blend) SHA-256 `9cfd86e951640c401abec7339e96662d6e1353eba765db3424d4ac613db3c2f4`。没有覆盖旧版，没有导出或接入游戏。
- 同机位、相同脚本和 CPU Cycles 24 样本对照：基线 [主视角](baseline-review-01/hero.png)、[艉向](baseline-review-01/stern.png)、[舷侧](baseline-review-01/hull-detail.png)；候选 [主视角](candidate-review-01/hero.png)、[艉向](candidate-review-01/stern.png)、[舷侧](candidate-review-01/hull-detail.png)。[配对审核](paired-review-audit-01.json)核对机位、图像及来源哈希与真实进程，结果通过。

## 可核对的几何证据

原 `bulwark_rails` 是一个对象，但并非焊接网格：4008 顶点、3000 面、168 个拓扑分离分量。先测的 26 对顶栏/柱分别属于不同分量，且原始三角面距离均为零并已有横穿；不能称为连续焊接。实测及进程见 [原网格分量](../r15c-baseline-rails-01/RAIL-COMPONENTS.json)、[原栏柱关系](../r15c-baseline-rails-01/JOIN-BASELINE.json)、[进程](../r15c-baseline-rails-01/process.json)。

实现仅移动原栏顶点，不加结构或修改原网格拓扑。作者报告有 904 个顶点移动，最大位移约 0.8411 米；字段理想值与保存的浮点数据最大误差约 0.000000238 米。独立 [重开审计](reopen-audit-01.json) 比对 80 个非栏杆原对象的矩阵、网格、UV 和形态键，以及帆画布打包图和材质连线；栏杆顶点之外的边、面、UV 和材质一致，未发现新增退化或翻面三角形。[作者记录](author.json)、[作者进程](blender-author-process.json)、[重开进程](reopen-audit-01-process.json)保留源和工具哈希。

对预选 26 对栏/柱做真实三角面复测，最大最小距离增加为 0 米，无一对超过预注册 0.01 米新增间隙阈值。但这仅证明每对仍有至少一个表面接触点，不证明无缝或无穿插。部分三角面横穿计数增加，例如艉右 1468 柱 30→44、艉左 3332 柱 30→46，必须结合外观审查；未进行全船的接缝和交叉覆盖。候选实测为 168 个分量；详情见 [候选网格分量](candidate-rail-components-01/RAIL-COMPONENTS.json)、[栏柱对照](JOIN-COMPARISON.json)。

位移公式及边界单元测试最终 5/5 通过。初次端点测试把浮点表达式要求为严格等于零，测得约 `4.4e-36` 的舍入残余；改为 14 位小数容差后重测通过。理想连续映射的单调性不等同于离散三角面的连接与美术质量。

本实验未运行 GPU，未做 LOD、炮后坐、帆/舵扫掠、甲板站位、完整碰撞、阴影代理、游戏性能或实机体验验证；不证明生产合同通过。
