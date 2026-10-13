# Godot 天气、云、阴影与尾迹整合交付 — 2026-10-13

本轮已按已接受的逆向交接，完成源规则、引擎模块与正式游戏入口整合。实际仓库为 C:/Users/dains/Documents/Git/ming-armada。保留现有海水、自然海岛、鼠标操船、跟船镜头与 3D 甲板人物；本轮没有新增游戏菜单入口或独立体验场景。

## 已接入正式游戏

| 能力 | 落地行为 | 引擎与游戏接线 |
| --- | --- | --- |
| 天气权威 | 原 int32/fixedTrig/RNG 更新；三个天气中心；暂停、重启、近期回放 | modules/environment_engine/weather_state.gd；Encounter 与 SailingRuntime 接收游戏时间 |
| 天空与天气云 | 独立天空云环及三个世界云 actor；45 个原网格、完整 DDS mip、持久控制器、源 TRS；减少动态冻结显示 | atmosphere/cloud_render_compiler；WorldView 透传完整环境包 |
| 云影、雾与光照 | 5 个资源烘焙影平面、低透明度地雾、原始光照方向和颜色；太阳与现有海面同步 | 源资源继承保留；云影投到海面、雾调度与能量是显式 Godot 适配 |
| 船尾迹 | 海航 30 点与海战 90 项／7 段／3 层分别实现；原历史与 UV、透明度更新；表面贴合与有限保护 | existing Wakes seam；正式 scene_30 / battle_90 路由 |
| 船首、船侧白沫 | 原 authored 网格、9 族侧沫资源、4 个原粒子池；六种游戏船均取真实源挂点 | ShipModelProvider 缓存 Dummy_Wake / Dummy_bowfroth；真实模型根与 importer 单位分开处理 |
| 船舶阴影 | 真正 RD 两面 stencil 增／减和屏幕遮暗；实际 hull/mast 几何、缓存、回退与资源清理 | SourceShadowRenderer／Compositor；实际 GPU 成功前保留原阴影；当前六船族不擅套 fluyt 纹理影 |

正式新生涯、自由试航、单舰炮战、舰队遭遇与原试航共享相同引擎消费接口。控制镜头时可刷新白沫朝向，暂停不消耗尾迹历史、随机数或粒子出生。天气风场独立于操船输入，原操船风与休闲辅助保持原有权限和行为。

## 本轮修复的实质问题

- 天气每步扫描／复制完整历史造成长期增长：改为轻 journal、稀疏 checkpoint 与默认 120 秒滚动保留；窗口内精确回放，窗口外原子拒绝并可诊断，time0 重置仍支持。独立 30,000 步验证末段 10,000 步增量约 35 KB，原约 28.74 MB/段的持续增长已消除。
- 同一 source call 的暂停转镜头被去重逻辑拦住：拆出仅展示刷新，RNG／出生／历史／UV 均不推进。
- 阴影 snapshot 附件未对账、最后 caster 的 GPU buffers 未回收、画质切换的外部 framebuffer 自动失效后重复 free：全部有 RED→GREEN 与独立复核；按设备资源类型验证 RID。
- 画质／全局／单 caster 阴影开关互相覆盖：改为三者合取，保留原调用包及真实 source actor 绑定。
- 离线 ShipView 读未入树的 global transform：没有世界姿态时不伪造出生历史；显式提供的捕获姿态仍可记录。
- 参考地形旧 raw-index 插值与实际三角网格相差约 0.24m：新增目标端三角高度权威，保留原公式 API，顶点／索引／UV 与原 oracle 网格数组逐项一致。6,902 查询与保留的逆映射采样函数一致；独立实际 Float32 顶点构造的 2,224 内点最大残差 0.156mm，不能扩大声称任意空间点几何零误差。缓存最多 12 项。
- 完整回归暴露的旧 fixture：恢复明确的公共离港前置条件和已有 HUD 高度合同；历史 Egress 地形记录单独冻结，并补当前三角地形合法转向／预测同伴／制动／取消及旧位置拒绝案例。生产操船权限没有因此放宽，历史 journey 收据未改。

## 验证与证据

最终覆盖当前 **209 个 GDScript 测试脚本**。首次完整执行 205 项：197 通过、8 失败；随后修复失败原因，逐项严格复验，并覆盖新增 4 项与受影响地形／场景测试。最终覆盖无缺项、最新回执无失败。**这是完整首轮加定向复验的合并覆盖，不是另一次 209 项一次运行全部绿色。**

- [覆盖与逐项回执](evidence/weather-cloud-shadow-wake-integration-2026-10-13/COVERAGE_VERIFY.json)
- [保留的首次完整执行](evidence/weather-cloud-shadow-wake-integration-2026-10-13/full-suite.json)
- [最终源专项 16/16](evidence/weather-cloud-shadow-wake-integration-2026-10-13/source-final-suite.json)
- 独立天气／尾迹、阴影、正式接线、地形／导航审查均已关闭已复现 P2，记录位于 .superpowers/sdd/weather-cloud-shadow-wake-20261013/*review-final.md。

真实 GPU：Godot 4.7.2 / Vulkan 1.4.325 / Intel Arc 130T / Forward+。正式 Scene 的 8 组截图覆盖航行、暂停转镜头、低／高画质、炮战与炮烟；日志无 ERROR。海航 3 船 scene_30、海战 2 船 battle_90 均有原资源及粒子输出；实际源 stencil 初始化并运行，低画质清空 GPU 网格缓存，再升画质重建。原研究的 D3D 像素一致性不由此推出。

- [正式 GPU 验收](evidence/weather-cloud-shadow-wake-integration-2026-10-13/gpu/VERIFICATION.json)
- [开阔海面航行](evidence/weather-cloud-shadow-wake-integration-2026-10-13/gpu/sailing-moving.png)：4 个 accepted 秒实际位移 11.094m，状态记录在 paused-orbit JSON；没有用靠岸卡住时的 HUD 航速代替位移。
- [暂停转镜头](evidence/weather-cloud-shadow-wake-integration-2026-10-13/gpu/sailing-paused-orbit.png)
- [炮战与炮烟](evidence/weather-cloud-shadow-wake-integration-2026-10-13/gpu/battle-cannon-smoke.png)
- [Computer Use 真实菜单／试玩](evidence/weather-cloud-shadow-wake-integration-2026-10-13/native-play/VERIFICATION.json)：鼠标、滚轮和实际开炮按钮验收；弹药40→39、左舷装填0→4.9s。Q 的自动按键尝试未证实，未冒称成功；后续鼠标转向截图靠近海岸，明确不作为开阔水面受控时延证据。

## 明确边界与当前状态

原完整尾迹 head／normalize／self-cross ABI、原 475550 效果门控／缩放、全部原 caster 分类／方向生产者／skinning、完整原场景 fog 调度及 DX9 全场景像素一致性仍没有证据闭合。本轮把可用原数据和代码接入产品，缺口用明确命名的目标适配，未把未知写成原版等价。海面接触 fit、单位、32次/秒天气调度、120秒回放窗口、刚性 hull/mast caster 策略与独立 stencil 附件也属于目标适配。

本轮没有完成十几船／上百门炮的整场压力 FPS 验收；CPU 专项、真实 GPU 路径、连续正式场景生命周期和实际按钮反馈均已验证。参考 legacy / visual-QA 场景专项用原60s超时分别53.44s/53.83s通过，测试余量有限，未提高时限隐藏超时。

实施过程基线 1a596d02；用户／外部 checkpoint 将 HEAD 更新为 c5fef91，工作均保留。Agent 没有 stage／commit／push，原游戏、参考包、个人存档未修改。当前交付为实际 Godot 仓库的源码和复验记录。
