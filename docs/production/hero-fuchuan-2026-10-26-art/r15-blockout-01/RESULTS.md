# R15 整船轮廓：Blender 静态 blockout

2026-10-27。此为用户所要求的主角船整体形态探索，按[制作前快照](r15-preregistration.md)制作独立 Blender 文件 `assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r15-blockout-01.blend`；没有替换正式船模。候选同时探索抬起的首舷墙、船侧木加强带、开放式艉楼侧栏、重新比例的三帆及 R13 生图朱砂帆布，因此不能把结果归因于某一个因子。

- 真实作者进程见 [process](blender-author-process.json) 和 [author](author.json)，退出 0、源文件及预注册输入 SHA 保持不变。候选是完整可编辑 Blender 文件，新增 6 个实体构件，三面帆仍含原名、父桅、帆布/竹桁/缝/绑扎材质及 `furl`、`inflate`。
- 独立重新打开 R7c 与候选进行[数据核验](reopen-audit-01.json)：78 个原非帆对象的网格顶点、拓扑、UV、材质名称、父链和局部变换一致，包含 hull、deck、隐藏影代理、8 个炮口 socket、舵及 helm 节点；三帆 UV/拓扑与原一致，预注册帆面与形态键静态数值逐顶点误差小于 0.00001 米。新增结构最低高度为 y=1.34 米，原 hull 的 −0.5/0/+0.5 米剖面数据本身未更改；**并未验证**动态水沫、额外几何受损或阴影行为。
- R7c 与 R15 分别经真实 Blender Cycles CPU 在相同相机、灯光和输出尺寸各渲染三视图；[成对证据](paired-review-audit-01.json)核对两次进程、图像与源 SHA、相机参数一致。图位于 `baseline-review-01/` 和 `candidate-review-01/` 的 `hero.png`、`stern.png`、`hull-detail.png`。

初看朱砂帆与首尾高低形成明显主次，但新增首舷墙呈现硬直木板，端部和原船体的衔接不够自然；艉侧栏也仍有外加框架感。此描述是待独立审阅的静态观察，不是艺术通过结论。因当前同时改变帆色、帆形及船体构件，截图也不能单独量化任一项贡献。

新舷墙和艉侧栏的 Blender 自定义 obstacle 标记尚未证明导出后可被正式 provider 识别；新增结构没有更新目标阴影代理或损伤表现。收帆/转帆、帆与站索扫掠、炮管后坐、站点与路径、三 LOD、连续 GPU 画面、成本和操作系统实机游玩均未验证。R15 是独立静态作者 blockout，不能称为可集成游戏资源。
