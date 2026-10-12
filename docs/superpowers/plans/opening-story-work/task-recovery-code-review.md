# 部分损失后继续出航：独立 Spec / Standards 审查

2026-10-12。只读生产与独立scoped包；Spec由本审完成，Standards由独立子审查员另核。不重跑作者相同测试，不启动GPU、性能或美术工作；Root正式旅程与全量strict suite运行期间不修改源码。CodeGraph已无索引，RTK定向读取。

**结论：当前冻结范围未发现可操作的新代码问题。** 两条既有恢复死路的有限解决方案成立；正常双船、旧v2和原历史保留。全部沉船替租、死亡补员、第三次委托仍未实现，不把本审写成完整经营游戏已经完成。

## 交付身份

- [Recovery scoped patch](recovery-scoped.patch)：388行，SHA256 `19fba02b859d9ab6a61b999fa5444bde0a16ddaab349b1b6d6c677e5a8688430`；[六文件身份](recovery-source-hashes.json)全部与实际文件一致。四production是Campaign、SaveCodec、OpeningStory、NativeReadiness；其余是一处原目标测试期望及完整新测试。
- 本审使用各 `.recovery-before` 与实际源码重新生成四production unified diff，均逐字匹配交付patch，未纳入其他dirty范围。此前Encounter操舵修复没有被Recovery更改。
- [Root scoped patch](root-integration-scoped.patch)最新QA增量后为499行，SHA256 `c7e28ff297b851eca8606a7ee45bf57f9f236270a72cddc4c1f41d33e73eef32`；[Root五文件身份](root-integration-source-hashes.json)全部匹配。Runtime另由Root拥有；Recovery所记录观察SHA `2824661d6a63af6580874eeb89037ddc2434791605b26831a705c129dfef4dea`与实际相符。生产未变，QA driver SHA `65fe06d3a2d6c6472331459dedb229f6aeae3af58abd386257b5f7b5d2c9203c`，截图工具 SHA `79c684c74bde13615cdb462dcb455a9c45ad5394536833738bd51a202265e36c`。此前472行阶段的 `15863c…`/driver `2779c…` 属于已记录历史，不冒认为新checkpoint guard来源。

## Spec

- **正常双船保留。** [Campaign](../../../../game/domain/mingqi/campaign.gd)289–320仍要求实际安全金门、20粮库存、两艘存活原船各自准备好；加载10+10、20库存扣减、原零追加租费、1200秒期限、原voyage ID顺序与load收据。额外lease/满载吃水校验没有换pose/船员/权限或静默丢下尚活着的原船。
- **只有真正一船沉没才走单船20。** 遍历两个原ID，hull0须有真loss/sunk-casualty/sink历史；仍活但离港、人数不足、作业中、有货或未完成原航程的船不能省略。幸存原粮船须有原付租凭证、锚定、足够人手、空舱和满载路线准入。两艘均失去明确拒绝 `convoy-transports-sunk`；没有复活、替船或伪造交付。
- **原死亡与新任务奖金分开。** 单船002的criticalPersonIds只从实际承运船上仍活着的原管事导出；001两人名单、死亡和已经失去的奖金保持。SaveCodec按接受时的死亡先后保留当时活人，后来遇难不能通过删critical person取得新50奖金。正常双船仍使用原两人名单。
- **原始付租证据限定。** `genuine_lease`只接受house-lin原grain-a/b/flagship/fast、canonical首航accept、real40装货、paid50、exact原四船roster。普通背景house-lin、foreign或无付租凭证的船没有治疗租权。
- **临床服务不成为航行授权。** 原租船below minimum且在实际声明港口、停住、舵帆0、55m内，进入service-only模式，仍同时locked+disabledMotion。治疗仍要求真实native锚定和旗舰/港口安全；报价1人检查实际可支付/伤员/容量，真正数量仍由原报价和命令再次验证。4两/人、30 accepted秒/人，付款只预约，不立即恢复；完成只wounded→able，不恢复死亡。
- **离港门禁一致。** Domain显式拒绝below-min/disabled/locked旗舰，既有active work门禁保留；Root `snapshot.canDepart`与该条件相同。临床服务使其进入controllable集合时，UI提示和实际depart均不能误放行。
- **会面保持可选。** [OpeningStory](../../../../game/domain/mingqi/opening_story.gd)首航正数claim、002offered且尚未first-return时优先回金门/会面目标；港外不说已见到账房，港内文本仍先要求安全锚定，真正按钮由Runtime强门禁控制。直接接002会跳过会面目标，没有新锁任务或收费要求；补给文字说明真实库存、单船集中风险与全部沉船无替租来源。
- **原UI可以到达新路径。** 原 `contract_accept_<id>`按钮发送真实accept-convoy/contractId，不硬编码必须两粮船；服务船选择消费新policy/readiness。因此本轮未改UI并不把单船接单藏在只可调用的私有API里。实际按钮/整段旅程验收仍由Root负责。

## Save / chronology

[SaveCodec](../../../../game/domain/persistence/save_codec.gd) `_contract_relations`允许002一或两原承运船，绑定exact load roster、voyage index ID、route/origin/destination/deadline；第一合同仍exact两船与原四船付租roster。单船缺失原船必须hull0，loss/sunk历史在load之前；当前健康遗漏、伪船/伪装载/伪voyage均拒绝。

house-lin治疗作业的payment须在真首航lease之后，且payment revision更大，ship在租赁roster内；其他原load关系已独立验证40/50及canonical身份。工作费用、时间、预留伤员、完成crew-transition仍由原校验执行。没有新根状态、版本、receipt kind、新船或新增租费；原v2双船 fixture继续通过。

## QA缺口关闭（源码），实际新旅程仍待结果

前次driver审查指出零炮/零命中仍可凭交粮绿灯。Root最终driver已：检查fire入队结果；在 **chronicle** 读取真实causeIds，near-fire首cause=flagship、near-hit/cargo-loss前两cause=[flagship,enemy]；manualmode分别要求两计数>0，写combatProof。queued=true不再等于实际炮击通过。`actualSafeReturn`同时要求 `runtime.canDock`、真dock.ok、真first-return.ok及实际金门；失败检查写入failures并决定exit1。

release_helm/captain_gun_course依旧只用真实W/S/A/D与Runtime命令，无state/health/cargo或completion写入。更长deadline只增加有界accepted-time观察窗口，不改任务期限、敌伤或船位。Root旧正式manual trial据报告16次fire、13次hit、敌0、旗舰100，但粮船仍underway，整体18/4；该失败不能改写为成功，也不把旧driver证据冒认最终guard版本。

## 验证边界

本审独立读取 [Recovery GREEN九脚本输出](recovery-green.json)：全部exit0、无SCRIPT/PARSE/ERROR诊断；计124+116+122+16+45+39+13=475条断言/0失败，另原healthy双委托golden及旧web-v2/伪造save oracle PASS(0)。[报告](task-recovery-report.md)明确三次有意义RED：42/6、110/1、112/1；恢复测试用deterministic native observations生成历史并跑真实1801tick治疗，**这些是单测fixtures，不是正式旅程画面或真实完成航次**。Root另外fresh124/0是其结果，本审未重跑。

独立Standards也未发现新质量问题：六Recovery/五Root身份匹配、正常双船/旧v2形状兼容、服务与运动分离、Root离港提示与Domain一致、QA失败不被吞。**实际正式地形manual战斗→交差→安全返港→002单船接续及全工程strict suite仍由Root验收，不在此提前宣布通过。**

## QA499增量复核：可续玩checkpoint与呈现harness

Root随后报告正式deep/manual首航27/0：真实40全交、16次旗舰fire/13次hit、敌沉没、1682秒安全dock+账房、银915/奖励500。本审读取当时return record，确实仍 `canSave=false / save-fleet-not-anchored:…grain-b`，并非可续玩checkpoint；普通metadata JSON.stringify默认精度还造成Catalog canonical double失真。这是QA记录/缺少全船锚定条件，未更改Catalog或游戏业务规则。旧rounded记录保留，不回填state来修证据。

最新driver写出使用full_precision=true；新增checkpoint变量只能来自正常 `runtime.export_save(...).json`。真实返港后，对实际controllable、存活且尚未isAnchored的船发送原rally；全部当前control船实际55m内且速度≤.75、runtime.canDock真时，再调用原dock。只有runtime.canSave真才正常export；`--return`最终额外要求confirmedCheckpointJson非空。rally/dock/export拒绝都会进入failures并非零退出，不能把局部返港绿灯写成可续玩。没有直接anchor、pose回填、资源恢复、codec或安全门禁绕过。

截图工具在冻结自动process的harness中调用同一 `scene._present(0)`，使日志打开/关闭后minimap按正常可见性规则更新；没有修改生产Scene、UI或Campaign。Root报告新9图56/0；本审核工具身份与源码，不另启GPU。Source-hash清单仍随图写出，图像metadata只供验收，不当作存档文件。

**该QA源码缺口已修复并复核；session33261最终新guard旅程与真实checkpoint仍运行中，须等Root读取有效checkpoint后确认。** Root另报生产fresh102/102 PASS，本审不重复其测试，也不以这一结果代替新实际航行/续玩保存证据。
