# 原生主菜单与入口整合

目标仓库：`C:/Users/dains/Documents/Git/ming-armada`。来源冻结于`9ad6a44daecd4ec36a8172d83ff27493feffe5dd`；原网页及来源工作树保持只读。默认`application/run/main_scene`为`res://game/scenes/main/main_scene.tscn`。

## 实际功能与分层

`game/runtime/game_router.gd`管理入口、请求世代、存档准备与显式导入事务；`game/scenes/main`管理真实节点生命周期；菜单、恢复及设置位于`game/ui`。两个生涯和海战练习继续复用`NavalWorldView`。物理位于`modules/physics_engine`，地形、海面及流式世界位于`modules/scene_engine`；UI不成为损伤、财富或浮力权威。

菜单连接1650与1661新建/继续、单船炮战、舰队交战、三船试航、六船图鉴和四小游戏练习。船图鉴公开；小游戏练习及LOD开发控件由可信`--dev`/`--qa`入口控制。QA十五场景尚未完整迁移，按钮返回明确未就绪状态。

继续使用原始JSON，不重写存档、不旋转备份。1650无效槽进入恢复页，原始损坏文本可单独导出；备份经规则和原生投影验证后才允许继续。显式导入先建立实际地形、船队与界面，确认原生启动成功，再提交磁盘事务并切换显示。失败保留旧槽和恢复界面。候选场景在准备期隐藏、停钟、停声音，不改变当前窗口标题、MSAA或全局物理频率；成功后才激活。

海战练习使用来源`Encounter`：seed1661、风向(-0.8,-0.6)、风速14m/s，单挑一敌船、舰队两敌船、试航三艘原船。Q/E舷炮、Space近敌方向炮击、三弹种、实际装填、转舵和帆速共用权威状态。投降使用真实battleId/tick预览与确认，重启产生新身份；练习没有生涯财富或存档权限。窗口失焦保持暂停，玩家点击继续才恢复。原生HUD使用流式布局与滚动，在320×480逻辑视口内仍保持可操作范围。

地形整合中发现1661与练习误用了1650护粮航道浅滩。`HeightField.configure_ports(ports, include_shoal_shelf=true)`默认继续保留1650；1661与海战练习显式传`false`，匹配来源`world-layout.ts`六岛/山脊公式。五个实际开局船位均为来源深度-24m。海浪算法、水面配色及船只浮力没有为此改写。

四小游戏使用既有领域模型，固定来源输入；决斗/宴会需明确开始，陆战/寻宝直接进入，结算不发放生涯奖励。船图鉴加载六船型×三档实际GLB；帆morph、炮管后坐、舵机、旋转和六个视角读取真实模型。模型读取失败保留已确认模型，重试针对上次失败选择。

## 聚焦验证与审查

| 真实Godot测试 | 断言 | 失败 |
| --- | ---: | ---: |
| CareerStartup | 53 | 0 |
| LegacyStartup | 11 | 0 |
| LegacyGeography | 10 | 0 |
| GameRouter，含真实设置/物理Esc | 48 | 0 |
| NavalPractice | 58 | 0 |
| NavalPracticeScene，含320×480/失焦/真实按键 | 16 | 0 |
| PracticeEntries | 88 | 0 |
| ShipBook，含十八GLB及失败恢复 | 158 | 0 |

三名实现者交叉复审启动、路由、小游戏、船图鉴和海战整合，范围内P1/P2已关闭。地形误注入、小游戏开始门槛/快捷键、船图鉴失败重试、失焦恢复及窄屏控件均有真实失败后修正的回归证据。完整验证结果及原生GPU证据见本目录`evidence`与下述记录。

## 完整检查与GPU画面

最终完整执行`rtk proxy node tools/verify-godot.mjs`：48套全部通过，0失败，退出0；验证器16项自检。逐项原始stdout/stderr、命令、时长及唯一完成标记保存在`evidence/verification-full-48.json`。`tools/record-entry-captures.mjs`额外扫描了全部Godot输出，0条Godot警告；RTK未安装全局hook的提示不计为引擎诊断。

GPU命令：

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --path C:/Users/dains/Documents/Git/ming-armada --rendering-method forward_plus --rendering-driver d3d12 --script tools/capture-native-entries.gd
```

最终输出`NATIVE_ENTRY_CAPTURE_COMPLETE captures=20 failures=0`，退出0，无Godot诊断。使用项目真正的默认PackedScene，独立测试存档及设置路径，不碰玩家槽。菜单点击采用原生鼠标输入；选择船型/小游戏由真实原生选择控件或其既有命令完成。返回流程部分使用实际场景返回信号，不能宣称所有返回按钮都在GPU轮次被鼠标点击。三种海战入口推进60个实际权威tick，截图不用于统计帧率。

| 画面组 | 文件前缀 | 张数 | Root逐张视觉观察 |
| --- | --- | ---: | --- |
| 默认菜单、设置 | menu-wide / menu-settings | 2 | 港口画、标题和输入可见；聚焦按钮深色文字；设置模态完整。 |
| 损坏槽恢复、导入后菜单 | recovery-invalid / recovered-1650-menu | 2 | 原文保护说明、导入及返回控件可见；真实恢复场景保持暂停菜单。 |
| 两代新生涯 | mingqi-native / career-native | 2 | 真实船体和甲板水手可见，水面明亮；1661小图按古航图风格显示；1650旗舰面板打开时按既定规则隐藏小图。 |
| 单挑、320窄屏、舰队、试航展开图 | duel-native / duel-narrow / fleet-native / sail-native | 4 | 深水不再出现误注入的大块浅水；实际帆装、实弹和船位可见；窄屏按钮滚动可达；展开图有金色边框、真实六港岸线与船位。 |
| 六船图鉴 | shipbook-* | 6 | 六类船体、帆型和甲板配置均真实显示；船体未被检查平面截掉；选择说明与模型对应。 |
| 四小游戏 | practice-* | 4 | 决斗/宴会等待开始，陆战/寻宝格局与实际模型一致；操作与结果区可见，无旧界面叠加。 |

Root在最终复拍后亲自打开全部20张PNG；尺寸与GPU/引擎元数据、每图及每份JSON的SHA256由`evidence/entries/integrity.json`记录。19张为1600×900，一张为真实320×480逻辑视口。游戏菜单画是已有美术资产；其余截图均由真实Godot viewport直接保存，没有替换成效果图。

美术仍有明确提升空间：岸上较大空地和棕榈比例需要整理；图鉴检查平面为简单展示背景，亮帆高光较强；四小游戏仍是现有规则面板，未制作完整角色演出。古航图表达的是当前玩法地形，不能把局部六岛布局当作精确东亚历史地图。完整参考质量继续作为后续美术验收要求。

## 明确边界

分阶段加载显示的是实际工作阶段，没有测量资源字节比例。平台文件选择器、剪贴板交付、每个备用路径的GPU行为仍需实机交互验收。船图鉴已实现立即旋转/缩放，来源OrbitControls的阻尼与平移尚未迁移。入口静态截图不能证明完整护航回港、俘获救治、真实炮弹驱动水手击飞、声音听感或帧率。旧PCK不覆盖本轮新增资源，Windows EXE及目标设备性能仍待验证。59项迁移验收清单保持开放，不能用入口整合检查点宣称全量迁移完成。
