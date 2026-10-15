# 云体被海面截断：weather-shadow 修复（2026-10-14）

## 问题与假设
用户截图中深色天气云被海面边界水平截断。云应保留独立世界位置、随天气中心移动及投影。初始怀疑位置/缩放不一致；GPU单因素实验证实合成顺序是本次根因。
当前天气云为stormcloud_sound与两个cloud00 MeshInstance3D，非skybox。天空云环是另一路历史机制，本轮不将世界云替换到背景。

## 基线与实验
同一实际自由试航、同一t=1s、同一相机/材质/资产，分别：原样、隐藏海面、只把风暴云优先级设为1、只抬节点80m（不适用于shader billboard，已标记诊断限制）。
[diagnosis-1/DIAGNOSIS.json](evidence/cloud-ocean-composition-2026-10-14/diagnosis-1/DIAGNOSIS.json) 保存原帧和实际状态。
低机位原云可见；俯视机位原云完全被海面覆盖；仅改变绘制顺序就恢复完整云形。不能以抬高云位置修饰这个遮挡错误。

## 根因与方案
海面写ALPHA=1仍处于透明管线，并写深度；天空/天气云使用软透明、不写深度。当前海面优先级为1、云为0，海面在云后绘制，覆盖已合成的云像素。
Godot官方说明：[Spatial shader ALPHA](https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/spatial_shader.html)、[透明排序限制](https://docs.godotengine.org/en/latest/tutorials/3d/3d_rendering_limitations.html#transparency-sorting)。
首轮诊断将云设1，同优先级在这两个机位恢复，但实际海面亦为1；新增跨生产owner合同抓住此缺口，最终采用2确保严格在海面之后。
候选：仅天空云体和世界天气云采用海面之后的透明绘制优先级，保留深度测试，实际山体/船舶/海面仍按深度遮挡；原云内部距离排序、源材质alpha、几何、RNG、位置和移动规则保持。烘焙云影与地雾不跟随云体更改优先级。

## 接受标准
1. 原失效机位同一时刻，云在天空/海面背景上保持完整；低机位不回归。
2. 加入不透明前景遮挡夹具，云不能盖住更近的不透明物体；反射相机仍显示同一云体。
3. 暂停转镜头不推进天气中心/RNG；接受时间推进时世界云位置确实变化，不随相机锁定成skybox。
4. 质量重建及当前weather-shadow独立实验继续使用生产修复；回归工具保留原优先级反例；校准地面实验不伪造透明海面效果。
5. 保存GPU原帧与机器验收、CPU源状态/天气/实验室回归。范围不含新天气造型、雨或全场FPS。

## 当前状态
已完成生产修复及GPU/CPU回归。修改集中于Atmosphere云材质的合成顺序；实际深度测试保留。


## 实测结果
[GPU回执](evidence/cloud-ocean-composition-2026-10-14/production-1/COMPOSITION_VERIFY.json) valid=true，19张主相机/反射原帧。三个固定机位，基线与当前云作用像素分别7423/7436、4839/7369、34/7109；不透明前景遮挡区差异像素均为0；镜像受该云影响2675像素。正常接受时间1到3秒时世界云中心变化，相机固定。暂停与画质重建保留权威状态。

CPU共11份相关测试文件通过；新合成合同7/0。完整验证与源/图片SHA256在VERIFY.json。GPU视图含洋红色测试盒的帧为遮挡夹具，不能冒充正常游戏外观。未修改云影算法、海面光学或前一轮船体浮动修复。

## 复现
使用Godot真实GPU运行tools/verify-cloud-ocean-composition.gd，传--output=res://新证据目录。通过tools/run-research-proof.mjs保存原日志；校验COMPOSITION_VERIFY.json、PNG、sources及失败数组。CPU使用rtk proxy node tools/verify-godot.mjs --filter cloud_ocean。旧来源与首次失败均保留。
