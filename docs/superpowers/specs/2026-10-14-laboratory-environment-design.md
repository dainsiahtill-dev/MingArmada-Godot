# 实验室环境课题补全

继续用户已确定的研究流程，补齐 ocean-surface、shore-surf、weather-shadow 三项独立实验。保留船体实验、正式海面、尾迹、操船与 3D 船员；这轮不替换生产效果。

## 合同

三个新的 Node3D 实验分别在 `game/research/demos/`，由 Laboratory 的独立 SubViewport 宿主推进。复用现有生产组件、真实纹理、原生接受时间；仅实验夹具、控制器和观察代码为新增内容。

每个 Demo：`configure(options: Dictionary)->Dictionary`，可挂树前配置，_ready 同步构建；`get_default_options()->Dictionary`；`control_spec()->Array`；`set_parameter(id: String,value: Variant)->Dictionary`；`advance(delta: float)` 固定32Hz且限制追赶；`reset_experiment(options: Dictionary={})->Dictionary`；`set_paused(bool)`；`set_camera_mode(String)`；`orbit_camera(float,float)`；`zoom_camera(float)`；`inspection_snapshot()->Dictionary`；`dispose()`。

控制描述 `{id,label,type,value,...}`：choice 有 `choices:[{value,label}]`；toggle 为 bool；range 有 `min,max,step`。set_parameter 原子校验，只改变声明因素，同时间刷新；需重构的变量明确返回 reset_required，不能暗改模拟时间或随机状态。默认 options 必含 paused 与 camera_mode，其他项按本课题命名。

inspection 最少包含 ready/disposed、topic、time/tick、parameters、实际相机16值矩阵与投影、viewport、资源计数、scope、telemetry。若有随机状态，记录实际 seed 与无损64位表示；无 RNG 明确说明。暂停、镜头、同时间开关不得推进时钟或改变原生天气/岸浪历史。

## 三项内容

海面：独立近海/低位/远景固定镜头；保留五波和生产材质；控制当前柔化光学/旧镜面响应对照、反射/折射、细节强度。用源码参数实现，不另写海水 shader。

岸浪：真实岛形/沙滩与生产岸浪组件，固定海岸相机；区分解析推进浪、源短浪和残沫三层，控制开关/透明度；提供周期推进观察与可复現快照。沿岸图形必须跟地形，不用空中圆环替代。

天气云影：生产天空云环、移动天气中心与纹理影组件的隔离场景；固定晴天/风暴/黄昏初态、时钟、云层/影开关；保留原计算更新次数与风场合同，原件未知项写明未知。

实验室增加按课题动态参数控件、单步32Hz、暂停同一时刻的开关对照与截图参数导出；现有船体控件/API 保持兼容。目录 still 5课题，4个可运行；阴影课题仍报告-only。报告实时更新为本轮结果，不自动改写旧manifest。

## 验收

每项先有失败测试；构建、确定性重置、暂停、同时间开关、参数非法输入、相机、释放验证；实际主菜单选课题，GPU连续时刻/对照原帧，切换返回无残留；五份论文与四个Demo包内可用。只运行受影响测试，不重复229脚本审计；上一轮8项异常原样记录，不伪称修好。

最终图像若发现表现问题，先把失败记录入本课题，再验证修复；新方案未通过就留在实验室，不能靠加白、隐藏物体或换标签宣称完成。
