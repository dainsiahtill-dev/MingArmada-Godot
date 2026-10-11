# 1661 生涯与四类遇敌：原生规则交付

来源固定为只读网页工作树 `C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada`，HEAD `9ad6a44daecd4ec36a8172d83ff27493feffe5dd`。实际规则来自 `packages/adventure-core/src/{session,catalog,surrender}.ts` 和 `packages/adventure-encounters/src/{common,duel,land-battle,treasure,banquet}.ts`。CodeGraph 返回未索引；本任务使用 RTK 精确查询，没有建立索引或写入原网页。

## 已实现的规则

`game/domain/legacy/adventure_session.gd` 为纯 `RefCounted` 权威。原生游戏执行不依赖 Node、浏览器、`Input`、`Time` 或场景树。

- 六港、六主线、五种可续接支线、六货物、六船型、三个持续环境船身份、五登岸地点，均从原目录导出为常量数据。
- 动态库存分层计价、港税与关系价差、任务预留货物、修理资源、招募、购船/售船、旗舰切换、跨船人员/货物转移、船体/火炮/帆装/操船装备三级升级。
- 三军官费用、薪银、装填/航速/粮耗倍率；300 模拟秒一天，断粮/欠薪/士气/年龄/旧伤/天气/市场和弹药补货，港内、暂停、退休及待确认投降不消耗航海时间。
- 六章原目标与奖励、真正船只位置判断、期限失败/重新接取、救援抵近和护送、探索委托当次访问，三岛线索、宝藏失败/冷却/重试与一次奖励，守舰战后陆战失败/冷却/胜利，退休评分与原叙事结局。
- 原接舷距离、相对速度、船体/船员削弱、舰队上限及操船人员门槛；失败伤势与冷却；俘获/掠夺/放行的分别结算；稳定 ID、事件去重、战果/战利品/关系结算、海战败北救回厦门。
- 投降按最近存活未结算敌舰报价、明确损失摘要、过期 token 拒绝、幸存船保持损伤、沉没船删除、委托失败、返回厦门及待确认收据。原摘要字段顺序、排序和 JavaScript 数字文本由原生确定性函数处理。
- 数字摘要按 ECMAScript 最短 binary64 表示：低于 `1e-6` 或达到 `1e21` 使用指数格式，其他值使用小数格式。直接解码 IEEE 754 位与精确整数舍入区间，覆盖次正规数和最大有限值。v1 JSON 数字读取同样采用精确区间校正，避免 Godot 小数解析偏移一位导致合法收据被拒绝；保存数字使用相同最短表示。
- v1 `{version:1,state,meta}` 完整恢复、来源原校验及四项旧存档加法兼容：缺少军官、弹药库存、投降次数及环境船 routeLeg；旧第三章说明迁移。已有损坏字段拒绝，失败恢复保持原实例完整状态。

## 原生 API

```gdscript
const Adventure = preload("res://game/domain/legacy/adventure_session.gd")
var voyage = Adventure.new({"seed":1661,"name":"沈沧海"})
var state = voyage.snapshot()                  # 深拷贝，只读消费
var result = voyage.command({"type":"dock","portId":"xiamen"})
var json = voyage.serialize()                 # 原 v1 envelope
var restored = Adventure.from_json(json)      # 无效时 null
var accepted = voyage.restore(json)           # 原子替换；失败 false + last_error
```

保留 source camelCase：`snapshot`, `command`, `preview`, `advance`, `serialize`, `save`, `setPaused`, `commitFrom`, `syncNaval`, `syncDockedFleet`, `navalSetup`, `ambientNavalSetup`, `ambientWaypoints`, `quoteSurrender`。提供对应 `set_paused`, `commit_from`, `sync_naval`, `sync_docked_fleet`, `naval_setup`, `ambient_naval_setup`, `ambient_waypoints`, `quote_surrender`。

GDScript 不支持同名静态/实例 `restore` 重载：实例 `restore(json, storage=null)` 原子替换，静态 `from_json(json, storage=null)` 返回新实例；静态 `load_storage(adapter)` 对应原 `AdventureSession.load`。构造或恢复错误记录 `last_error`，不以 GDScript 异常作为产品流程。`advance` 对非法时间返回 false；`syncDockedFleet` 锚定失败返回 false。`save` 可消费带 `read`/`write` 方法的注入存储适配器；文件 I/O 和版本路由由独立持久层负责。

Godot 平台不能在普通 `String` 中保存 NUL 或孤立 UTF16 代理项：`String.chr` 会替换为 U+FFFD，孤立代理项字面量会编译失败。`utf16_text.gd` 因此提供有界内部字符串编码：NUL、孤立代理项和保留标记 U+E000 编码为私用标记加四位码元及分隔符，原始标记也转义，避免与来源的字面标记字符串碰撞。其他 Unicode 保持原样，成对代理项保存为对应的 Unicode 标量。快照仍为 Dictionary/Array/String；这些特殊字符串是内部编码形式，不能宣称其 Godot 字符值等于来源的孤立 UTF16 字符值。`utf16_units` 还原来源码元，`source_length` 按来源 UTF16 逻辑长度验证，手写 JSON 字符串读写覆盖所有值和字典键，恢复真实来源的 `\u0000`、`\ud800` 等文本以及投降摘要。

原生 UI 对 legacy 名字、日志、船名等呈现调用 `display_text`；NUL 和孤立代理项以可见的 `\uXXXX` 形式显示，存档继续保留原码元。原生用户输入的更名内容先调用 `encode_native`，已有快照 ID 和其他内部字符串直接传回领域：

```gdscript
const LegacyText = preload("res://game/domain/legacy/utf16_text.gd")
label.text = LegacyText.display_text(voyage.snapshot().player.name)
voyage.command({"type":"rename","name":LegacyText.encode_native(name_input.text)})
var original_code_units = LegacyText.utf16_units(voyage.snapshot().player.name)
```

`Adventure.new(options)` 自动编码原生名字；可选第二参数 `true` 接收已由 native legacy JSON 解码的内部名字。`restore(raw_json)` 默认仍接收原始 JSON 文本；可选第三参数 `true` 接收内部编码的 JSON 文本，用于 fixture 中嵌套的来源存档字符串。辅助函数还提供 `from_units` 和 `source_trim`；后者按 JavaScript 空白码元修剪，NUL 不被当作空白。所有平台边界处理仅在 legacy 层，文件 I/O 和 v1/v2 路由仍由集成层承担。

## 四小游戏

全部为纯 `RefCounted` 状态引擎，共有 `snapshot`, `reset`, `retreat`。来源 RNG 的 uint32 LCG、难度归一、快照深拷贝、结算冻结保持原语义。

| 文件 | 构造及命令 | 已迁移内容 |
|---|---|---|
| `encounters/duel.gd` | `new(seed, difficulty="normal", boarding_context=null)`；`action(action)`、`step(seconds)` | 60Hz 整步余数、敌预告、上/下防守、闪避、招架反击窗口、体力、伤害、船员/士气上下文、胜负/撤退 |
| `encounters/land_battle.gd` | `new(seed,difficulty="normal")`；`select(id)`、`move(x,y)`、`attack(id)`、`endTurn`/`end_turn` | 原 9×7 地图、BFS 移动、单位占位、超覆盖视线墙角阻挡、掩体减伤、回合行动预算、原确定性敌 AI 与完整胜负 |
| `encounters/treasure.gd` | `new(seed,difficulty="normal",target_site_id=null)`；`move(direction)`、`dig()` | 原随机墙/藏点、九宫揭露、守卫碰撞、三次挖掘、移动计分、伤势、成功/失败/撤退 |
| `encounters/banquet.gd` | `new(seed,difficulty="normal")`；`action(direction)`、`step(seconds)` | 原节拍序列、补偿求和时钟、完美/普通/错拍/漏拍、连击、重复输入去重、60% 成功门槛与社交奖励 |

决斗非法上下文拒绝初始化：`last_error` 非空、空快照、命令拒绝。原 JavaScript 异常在原生调用方改为显式失败。未传决斗上下文在原生构造使用 null。

## 当前直接验证

开发期 exporter 通过 TypeScript 内存转译执行固定原源码；校验 source HEAD、相关源路径无 diff、记录源码 SHA256，只向 Godot 目标写常量/fixture。原网页 source writes 为 0。成品无需这些 exporter。

- `legacy-reference.json`：20 个来源场景、229 步。每步对照完整 state/meta、命令结果、原 preview 及未改状态、navalSetup、环境船 setup/waypoint、投降报价。包含六章抵达第七章并得“台湾功臣”退休，三支线、全部船型/装备/军官、失败/重试/去重、恢复继续、非整数伤势与投降摘要、靠港锚定同步、暂停/恢复、365 日老化；新增原源码生成的 `1e-7`、`1e-6`、阈值前浮点数、17 位有效数和 `1e-100` 收据，以及 NUL、孤立高/低代理项、成对代理项、私用标记、混合名字的真实待确认投降收据。
- `encounter-reference.json`：16 个来源场景、422 步，全三档难度、真实陆战胜利和失败、原决斗/寻宝/宴会胜负、终态冻结、撤退/重置、无效指令及时间、错手势。另验证 8 秒一步与 480 个 1/60 秒步结果相同，非法接舷上下文拒绝。
- v1：368 个源接受/拒绝判定，含逐层删字段/置 null、重复身份、整数/容量/日历边界、原可选字段兼容、UTF16 名字限制、24/25 个孤立代理项边界、仅 NUL 名字、空白名字、特殊 UTF16 metadata 和字典键、结局文本的 1000/1001 UTF16 码元边界、伪造投降摘要/损失/tick、相同数值改写摘要记法、相邻浮点船体篡改、严格 JSON 语法和小数溢出/下溢；每次拒绝验证实例原字节等效不变；接受后再对照原 naval/ambient APIs、原生往返和投降摘要字节完全相等。
- 153 个实际 JavaScript 数字文本样本，以原始 8 字节重建输入，逐字节对照 `JSON.stringify` 并验证解析回相同 binary64。含正负零、整数精度边界、`1e-6`/`1e21` 记法边界、最小次正规数、最小正规数、最大有限值及 128 个确定性随机有限位模式。
- 121 个实际 JavaScript 字符串接受/拒绝样本，验证来源 UTF16 码元、JSON 输出文本和无损往返；含全 32 个控制码元、NUL、孤立代理项、成对代理项、引号/斜杠/反斜杠、原始私用标记、64 个确定性混合码元样本、错误 escape/Unicode escape 和原始控制字符。另对照特殊字典键文档及原源码接受的 metadata，专门验证私用标记和异常码元不碰撞。三项最终 headless 测试没有 Unicode 替换提示或解析错误。
- 三套对照共享数值比较：整数精确相等、所有数值须有限；仅非整数浮点允许 `1e-12` 相对误差。专门回归 `4294967295` 与 `4294967294` 不相等，以及超过浮点整数精度的原生 int 不被错误转换成相等。
- 验证额外覆盖 Godot 原生 int 船体/船员占比，避免整除误放行接舷；准备事务有效提交、无效事务原子拒绝。

Godot `4.7.2.stable.official.ed1daf0bf`，下列三个独立 headless 命令均退出 0，且没有脚本/资源错误：

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script tests/test_legacy_adventure.gd
# legacy source golden: PASS (0)
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script tests/test_encounter_rules.gd
# encounter source golden: PASS (0)
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script tests/test_legacy_save.gd
# legacy save v1: PASS (0)
```

结局字段额外进行限定回归：原网页 `session.ts:641` 按 `career.ending.length <= 1000` 验证 JavaScript UTF16 码元。冻结源码实际恢复产生 10 个 oracle，包含 ASCII 1000/1001、NUL 500/1000/1001、孤立高代理项 1000/1001，以及成对 emoji 1000/1001/1002 码元。修复前原生测试有 5 个接受判定差异；改为 `Text.source_length` 后，接受实例的完整 state/meta 与原码元无损往返、拒绝实例的序列化字节和快照原子性均通过。定向审计 legacy 剩余 `.length()`：其用途为 ASCII 数字/JSON 关键字解析、内部编码遍历、非空判断，没有其他业务文本限长钩子漏迁移。

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script tests/test_legacy_ending_boundary.gd
# LEGACY_ENDING_BOUNDARY_PASS assertions=41 cases=10 failures=0
```

## 集成边界

本任务完成规则、数据、v1 实例恢复及四小游戏引擎。菜单/港口/舰队/战术/接舷/小游戏原生 UI、海战 runtime 对接、v1/v2 文件槽与导入路由、画面/声音、原生入口端到端验收由后续集成承担。本任务未运行完整项目测试套件、GUI、Windows 导出或网页程序，不能据此宣称这些入口已验收。`mingqi`、v2 codec、物理层、runtime/UI、原网页与 Git 状态均未修改。
