# 船首与船侧水沫重做

2026-10-14。本轮按用户要求重新设计近船水沫，保留当前尾部效果。新方案已接入正常游戏的水效果入口，没有新增玩家示例或菜单。

## 表现方式

船首分向两侧形成短、低的破水浪。船侧使用实际船壳外的窄流沫，纹理按航行距离向船尾流动；前段较强，中后段减弱。飞溅改为厘米尺度的小水滴，继承约75%船速，随后独立向侧后方运动、上抛、下落并回收。

浪脊峰高约0.153–0.160米；水滴面片全尺寸0.07–0.20米。当前福船6节的控制场景通常有5–6滴同时存活，池容量48。新水沫有自己的材质与状态，不再使用原先约3.2米宽的大白沫billboard。

## 上下浮动与接水

配置时从真实船壳三角形缓存13个高度截面，保留原Y0截面。每帧结合海面高度与船体完整姿态，分别选择左右接水轮廓；浪脊按自身高度处的船壳外张量构建。升沉、俯仰和横摇都会改变接触线。没有有效接水轮廓的部分渐隐并停止出生，避免抬起的船首挂着悬空白沫。

已出生的小水滴使用世界坐标，父节点和船体浮动不会把它们拖着升降。停船关闭新出生，既有水滴继续落水回收，附着流沫平滑减弱。暂停与同时间重绘不推进年龄或流动。

## 尾部保留证据

真实ShipView与WaterPacket的航行及海战输入，通过新水沫路径与原水沫对照路径逐步比较：尾迹历史、draw arguments、实际提交vertices/UV/RGBA/indices与可见性一致。重复call、owner转移、epoch切换也比较。原30点、90点历史及尾迹材质路径保留。

[文件校验记录](../../Temp/hull-contact-tail-preserved.json)确认五个历史、几何、海战、尾迹shader及共享Surface文件的SHA256没有变化。外层renderer另外补了跨类型session ID的重建守卫，防止Godot比较整数与字符串时报错。

## 验收记录

- [连续前后对比](evidence/hull-contact-redesign-2026-10-14/review.html)：同船型、航速、相机及输入序列，包含低位船首、低位侧面、高位和起伏过程。
- [低位船首旧版](evidence/hull-contact-redesign-2026-10-14/before/low-front/all/t064.png)、[新版](evidence/hull-contact-redesign-2026-10-14/after/low-front/all/t064.png)。
- [起伏帧](evidence/hull-contact-redesign-2026-10-14/after/low-front-heave/all/t080.png)。
- [独立水沫形状](evidence/hull-contact-redesign-2026-10-14/after/low-front/foam-isolated/t064.png)：隐藏船体供诊断，不能当作实际游戏画面。
- [新材质深度检查](evidence/hull-contact-redesign-2026-10-14/depth/current/VERIFICATION.json)：透明写深度海面不裁碎水沫，前方不透明船壳仍遮挡；foam/spray六项通过。去掉相应深度模式的RED有四项失败。
- 新模块399项，真实生产集成4555项；尾迹五项及水面packet回归通过。真实多高度截面13571项、原Y0轮廓1400项通过，另有独立审查。收据在本目录的evidence/checks中。

近景GPU控制画面使用真实模型、3D甲板人物和生产水效果路线，海面是固定的透明写深度诊断海面；起伏序列输入±0.45米升沉、0.10弧度俯仰、0.14弧度横摇。正常游戏另外通过主菜单进入自由试航检查，其截图保存为live-*.jpg。控制画面不等于原版游戏像素恢复，也不等于全场景FPS验收。

## 实现与实际边界

主要实现：`modules/scene_engine/water/hull_contact_froth.gd`及独立foam/spray shader；入口选择位于`source_wake_renderer.gd`，真实速度来自`source_water_packet.gd`。`hull_waterline_profile.gd`负责配置时的多高度缓存。

当前接触线使用缓存高度环插值，并在范围边缘保守裁剪；任意连续高度相对原三角形的误差尚未全量量化。定向fixture每船每接受帧观察到725–731次水面查询，完全淡出后为0；这些不是任意场景的性能上界。本轮没有修改船体操控、海面或3D甲板人物。
