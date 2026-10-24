# 生产资源图鉴独立审计

审计日期：2026-10-22。范围为 `tools/build-production-resource-library.mjs`、其生成的 `assets/production/catalog.json`，以及解释图像身份和依赖所必需的分册、生成记录与图鉴展示代码。未修改编译器、分册、图像、图鉴UI或其他共享文件；未运行会重写输出的构建器。

首次检查目录快照为 `2026-10-22T08:20:17.063Z`；图像/UI修复复核快照为 `2026-10-22T08:28:12.109Z`；最终依赖复核快照为 `generatedAt = 2026-10-22T08:36:32.710Z`。以下状态以最终复核结果为准，本报告在该快照冻结。

- 最终复核编译器SHA256：`c264b157554ad7ce5efac5d1409b61b72ec7788a42eb4b8b46b9182d8f3f0e08`
- 最终复核目录SHA256：`2b8100fb11732bb4d096367d6dd4d089ccfb0c7c2d9c19a861795fbcea7b4621`

若后续编译器或目录已经重建，应按修复后的快照复核下列问题；这些哈希限定本次结论的证据范围。

## 当前问题与修复复核

结论：本次发现的3项问题均已复核关闭，当前没有未关闭审计项。未发现剧情情境图被误升为专用图，未发现仅提及人物被当作历史肖像；资源与旧基模计数边界保持正确。

### 已修复（原P2）：`item-art` 原图角色未纳入首图与证据分类

位置：`tools/build-production-resource-library.mjs:81`、`:84`、`:85`、`:87`。

首次检查时白名单和正则识别 `portrait`、`icon`、`goods`、`ammo` 等角色，但不识别分册实际使用的 `item-art`。因此9个已有独立物品PNG全部被分类为 `technical-sketch`，并将SVG选为首图；原PNG虽保留在列表，图鉴的“专用原图”筛选不能找到这些已有原图。

实际受影响ID：

- `ammo-solid`、`ammo-chain`、`ammo-grape`
- `prop-cloth-bale`、`prop-grain-sack`、`prop-porcelain-jar`
- `prop-timber-stock`、`prop-iron-stock`、`prop-spices`

这些图的原始路径分别为 `assets/art/ammo/*-v1.png` 与 `assets/art/goods/*-v1.png`；源说明明确写“既有原创物品PNG”，并保留边缘、缩略图和生产溯源待复验的限制。

建议统一采用显式角色表，把 `item-art` 识别为已有单物件原图候选，继续保留 `existing-original-review` 复验状态；不要仅凭文件名中含有 `ammo` 或 `goods` 推断。剧情情境角色仍必须排除。该问题是漏认既有原图，没有导致本次目录把剧情图夸成专用原图。

复核：当前编译器 `:87` 已明确认可 `item-art`。这9项均改为既有原图候选，目录 `dedicated-original` 从8变为17、以草图为首选的条目从97变为88。没有增加实际图像文件数量。

### 已修复（原P2）：`modelRequired=false` 的非人物装配被显示成“仅保留信息图像”

位置：`docs/production/resource-library/app.js:141`、`:152`。这条属于目录字段在图鉴中的实际解释错误，不是编译器的数值错误。

首次检查时 `modelRequired=false` 统一显示“当前不要求身体模型，仅保留信息图像候选”。该字段也用于命名建筑prefab、场景地图、地形、材质和天气条件；28条环境装配/非独立基模资源因此显示人物身体模型措辞，并被误解为仅需信息图片。

例如 `building-fujian-residence`、`building-macau-warehouse` 是构件装配的空间资源，`map-shipboard-mother` 是共享船上场景，`nature-island-terrain` 是程序式地形。它们都不等于“仅保留信息图像”。

建议仅对 `appearance === 'mentioned-only'` 的人物使用身体模型说明；其他资源按 `assetKind` 显示“共享构件装配，不另增独立基模”或“地图/地形/材质/条件资源”。保留现有明确的 `modelStrategy`。

复核：当前 `app.js:141`—`:157` 已按人物出现方式和非人物 `assetKind` 分支，非人物显示对应装配/地图/地形/材质条件，不再显示身体模型措辞。本轮复核为代码分支检查，没有替代修复后的浏览器回归。

### 已修复（原P2）：少数共享场景的跨资源依赖只有文字，没有结构化链接

位置：目录条目 `map-shipboard-mother.dependencies`、`nature-island-terrain.dependencies`；编译器当前 `:73`—`:74` 只检查已填写依赖是否存在。

首次检查时有两个可直接复现的缺口：

- `map-shipboard-mother` 的模型策略写明引用船舶分册的船壳/舱口，但 `dependencies` 为空。图鉴没有船型选择/引用链接；用户无法从该条进入所需船型。
- `nature-island-terrain` 的模型策略明确“岩块实例引用nature-rock”，但 `dependencies` 为空，图鉴缺少这一项实际构件依赖。

建议补齐明确构件依赖。船型属于按配置选择的依赖，可在结构中区分“共享必需构件”和“变体选择”，避免误表示母场景永远同时装入全部船型。当前依赖图没有无效ID或环；这里的问题是已写在制作策略中的关系没有完整进入可点击依赖。

最终复核：编译器 `:57`—`:58` 已在合并阶段补齐依赖，冻结的原分册文件没有被改写。`map-shipboard-mother` 现有5种船型候选引用：`ship-fast-junk`、`ship-merchant-junk`、`ship-fuchuan`、`ship-european-merchant`、`ship-european-warship`；`nature-island-terrain` 现引用 `nature-rock`、`nature-shore-materials`、`nature-ground-materials`。全部依赖ID存在，整个依赖图无环。两个条目仍为 `modelRequired=false`，模型策略仍明确83预算增量为0；此次补链没有新增资源或基模。该项关闭。

## 已核实通过的边界

### 资源与模型计数

- 目录有170个唯一资源ID；分类合计170，阶段合计170。
- 原生产清单83个基模ID全部映射，没有缺项或目录外旧基模ID。
- 170是人物身份、NPC职业、船型、武器部件、道具、构件、命名装配、地图、自然与条件等资源条目总数，不能改称170个新模型。
- 编译器 `scope`、`countingRules` 及生产目录说明都明确170与83的区别。`modelRequired` 的真值数量也不是独立基模数，不能另行相加替换83预算。
- 15个环境地图条目仍分为2二维图层、4共享母场景、9地域/战场差异包，未将43场剧情插图当作43套独立地图。

### 图像分类与人物身份

- 当前目录没有 `primaryImage.role` 为 `story-context`、`scene-context` 等情境角色，却被 `evidenceStatus` 标成 `dedicated-original` 或 `dedicated-concept` 的条目。
- 8个 `mentioned-only` 历史人物均为 `context-reference`，使用剧情上下文图；其 `historicalStatus` 明写未核出真实肖像。没有把仅被提及的人物从剧情画面中认成已核定的历史面貌。
- 角色图集的专用原图项带有 `portrait-atlas-crop` 和有效的归一化裁切字段；图鉴应用该裁切，未直接将完整六人图集当单人画面显示。
- 安东的新独立概念图覆盖首图，旧图集裁切只保留为之前迭代的参考。
- 21张新增图在生成记录中均标为 `adopted-concept-candidate`，目录图像角色为 `dedicated-concept`，附注与历史字段没有将其宣称为历史真实肖像、实测建筑、精确文物或完成模型。

### 新图、草图与来源

- 新增原生ImageGen概念文件恰为21个，ID、路径与文件内容均唯一。
- 21个归档概念PNG与生成记录所列原始生成文件逐字节一致，来源路径全部存在。
- 技术草图恰为108个不同路径/文件内容：环境46，装备道具62。其角色独立标为 `technical-sketch`，没有混入21张原生概念PNG数量。
- 新图在目录中关联23个资源，是2处合法复用造成：货栈概念用于门面模块与命名整栋货栈；轻炮总成概念用于轻炮与炮架。`generatedConcepts=21` 是实际新图数，不能把23个覆盖条目写成23张新原画。
- 全部393条图像关联的文件都存在，目录中的SHA256与当前文件内容一致；列出的旧模型路径也均存在。文件存在不等于形制、LOD、许可或运行验收通过。

## 图像计数应怎样对外说明

当前快照中的三个数字含义不同：

| 数值 | 实际含义 |
| --- | --- |
| 393 | 资源与图像的关联条数，同一张图可以服务多个条目 |
| 391 | 按归档路径去重的文件数，包含相同旧参考在不同资源目录中的副本 |
| 211 | 按SHA256去重的不同内容：82个旧参考、21张新概念PNG、108张SVG技术草图 |

`distinctImageFiles` 是路径计数，本身没有算错。但将391在文案中叫“391张独立原画”会夸大。复核编译器 `:117` 已增加 `distinctImageContents=211`，并增加 `archivedReferenceSources=82`。对外仍应直接报告“21张新增概念原画、108张技术草图，其他为既有参考”，不能把归档副本计成独立创作。

目录保留 `sourcePath`、图像SHA256、角色和权限待复验提示；这足以追踪本次归档来源，没有构成素材许可已经解决的证明。

## 实际执行的检查

检查包括当前编译器源代码、目录字段和角色分布、生成记录；全部图像哈希与文件存在性；21个生成源/归档副本一致性；新图/草图唯一性；旧83基模覆盖；170条资源ID；剧情和页面引用；依赖失效ID和有向环。没有运行重写型构建器，也没有修改上述共享文件。

未在本轮重新做全部图片的历史形制验收、图集身份人工重认、素材许可裁定、Godot原生运行或全站浏览器回归。源清单中的形制/许可/运行限制继续有效，不能以此次目录审计代替。
