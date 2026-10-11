# 首个目标：Godot原生海面验证

用户明确先验证Godot能否实现网页海面；完整迁移计划保持，当前只实施本验证。需要实际Godot GPU渲染及截图，CPU波形数值一致只是必要条件。

参考是当前网页默认ProjectedWaterSurface/ProjectedWaterShader，不是另外可切换的Three.Water模式。保留五波世界坐标、waternormals.jpg三层滚动、Fresnel、250次幂高光、墨绿水色、碎屑、峰顶泡沫、100–1500m雾及透明度。原shader没有真正的planar镜像反射/岸线泡沫，不在对照图中虚称这些已有。

Three.Color把hex先转linear，原fragment又pow2.2；Godot移植显式保留该输入颜色和原公式以作首轮一致性比较，之后的色彩调校单独记录，不暗改波或船高。

分层：`modules/physics_engine/ocean/wave_field.gd`纯CPU采样；`modules/scene_engine/ocean/projected_ocean.gd`及shader负责投影网格和渲染，接收Camera3D、Texture2D、simulation_time，不拥有墙钟、游戏规则或物理船。`game/scenes/water_probe/`负责验证场景装配与截图。测试和来源fixture独立。

Root从原JS导出黄金波样本及地形数据，复制原纹理和福船GLB且记录hash。海面owner先RED后GREEN，只写海面模块/test；Root原生场景加载真实船模作尺度/水线视觉参照，静态参照不冒充船舶浮力已迁移。以多时间/多镜头原生截图检查波形、颜色、透明、地平线、岸边和船周水面。保留错误及修正证据。

验证通过后输出明确结论和限制，再开始完整物理/规则迁移。此阶段不宣布Godot游戏完成。
