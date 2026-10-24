# 全章插图接入调查

日期：2026-10-24。先完成只读调查，后按主线程明确分工实施有界支持。未运行旧版 assemble/adopt/export、未启动服务、未改正式源。CodeGraph 本轮由主线程确认无索引，源码以 RTK 查询。下文调查建议保留决策过程，最终采用接口及验证见末尾“实施结果”。

## 结论

现有阅读器已能按 `afterParagraph` 插入多幅图。最小稳妥方案：保持六部22章及 `narrativeContract.revision=9`，每章 `illustrations` 放两项，`scene.image` 和 `act.cover` 保持空；新图仅放 `images/illustrated-2026-10-24/`。无需新增第二套渲染器。

须补齐的边界：独立 illustrated 源版本/导出入口/验证分支、正确报告插图模式、下载稿图片相对路径、44项来源与资源核验。正文不改，旧图不重新引用，历史文字版的零图合同不放宽。

当前正式源实测 SHA-256：`ff49298756869eb372fac8503a9a246eff213d7db592fc06bd2361b18d4ce53a`；版本 `historical-reboot-polish-2026-10-24`；343段、22章、63个旧别名。

## 已有入口与确切位置

|文件/行|现有行为|接入影响|
|---|---|---|
|`zheng-zhilong/app.js:14-22`|图片只接受本地 `images/` 下 PNG/JPEG/WebP/AVIF；拒绝 `..`|新资源命名可直接使用；验证器也须采用同一安全边界|
|`app.js:24-64` `normalize`|读取章图 `image`、段后 `illustrations`；frame必须有图片、图注、合法整数段位|两图均放 `illustrations`；每项独立ID和有效图注|
|`app.js:45,51-55`|正文会过滤空段；段位却按原数组长度验证|当前343段全非空；新验证须继续禁空段，避免段位漂移|
|`app.js:61-75`|保存并解析旧 `zheng` / `yiguan` 别名；historical模式按edition识别|保持edition、全部IDs及63个映射，书签无需迁移|
|`app.js:96-115` `createIllustration/openImage`|宽高可从frame读取，懒加载、错误提示、放大对话框已有|填写实际像素宽高；当前alt为图注加“叙事插画”|
|`app.js:121-143` `renderScene`|先显示 `scene.image`，每到对应段后再显示frames|同一图不要同时填主图与frame，否则重复；推荐只用frames|
|`app.js:219-235` `render`|historical通知写死“全卷精修”；`text-edition`类别按historical设置|更新通知为本次插图版本；该CSS类别实际只调封面/部首间距，无隐藏正文插图，不必为改名字重构布局|
|`app.js:384-429` `runSelfCheck`|已有结构/63别名/图数/段后figure数量检查；429行historical固定报text-only|把模式按实际明确状态/合格图数判定，追加illustrated专属44幅/每章2幅断言；保留旧text-only零图检查|
|`app.js:364-366`|打印前给main图设eager并调用decode|已有打印加载入口；仍须浏览器真实检验44幅|
|`styles.css:10,17-22,73,107`|正文插图、移动端图注、打印图形已有样式|无需先改布局；用实际3:2图核验后按证据修正|
|`tools/zheng-story-contract.mjs:14-40`|historical结构锁定revision9、6部、[4,4,4,4,3,3]、zzl；校验63个直接别名|插图不是结构改版；保留合同即可，无须加revision10|
|`tools/zheng-story-contract.test.mjs:6-14`|结构缩减、未知版式、丢旧别名、链式别名等已有负例|继续运行；另加插图专属测试，不改这些预期|
|`tools/build-zheng-story.mjs:13-33`|纯序列化器与同字节JSON镜像构建|可供新入口复用；源不应从旧候选文件恢复|

## 导出与验证风险

1. `full-polish-2026-10-24/export.mjs:8` 绑定旧版本和旧报告目录；16行会覆写空 `illustration-manifest.json`。保持旧入口不动，不执行它生产新插图版。
2. `tools/verify-zheng-reboot.mjs:19,28,39,60` 明确要求text-only、无封面/章图/frames，报告expectedIllustrations=0。不要用放宽检查的方式把旧文字版证据“升级”为插图版。
3. `zheng-zhilong/verify-reader.mjs:34-39` 与 `tools/verify-zheng-story.mjs:179-181` 目前把所有historical版送到该零图验证器。需先分流明确的illustrated版本；其余historical仍按原文字合同。
4. `tools/render-zheng-reboot-exports.mjs:3-6` 只从 `editorialRevision.report` 定位工作目录。建议新加 `illustrationRevision.report='illustrated-2026-10-24/DELIVERY.md'`，让有界的illustrated入口优先选它；原文学修订元数据留存。
5. `renderRebootExports:20` 的 `novel.md` 只输出段落；若下载小说也应有图，须在同一段后插图，不能只接网页后声称下载稿完整。`game-scenes.md` 是制作输入，保留文本即可。
6. `tools/render-zheng-screenplay.mjs:41` 对所有historical版写“文字新作，没有采用旧版插图”；插图版需准确说明当前为新增当代生成图、文学重建。保持历史文字版本文案不变。
7. `renderScreenplay:55,65,68-70` 已能输出图片，但链接写为 `zheng-zhilong/images/...`。`renderRebootExports:28` 只修正research链接；输出文件位于reader内部，图片链接应为 `images/...`，否则多一层目录。新导出入口须修正或参数化图片基路径。
8. `zheng-zhilong/README.md:12` 仍称当前文字版。`index.html:9-11` 的资源版本仍为full-polish。新入口需更新这些发布说明/缓存标识；无需把旧报告覆盖为新报告。

## 建议数据形状

保留原 `narrativeContract`、`editorialRevision`、所有正文/史注/编辑字段。版本使用 `historical-reboot-illustrated-2026-10-24`；root/act/scene统一设 `illustrationStatus: 'illustrated'`，避免子项仍写text-only造成元数据矛盾。无图片的act仍不填cover。

```json
{
  "illustrationRevision": {
    "date": "2026-10-24",
    "report": "illustrated-2026-10-24/DELIVERY.md",
    "baselineVersion": "historical-reboot-polish-2026-10-24",
    "baselineSourceSha256": "ff49298756869eb372fac8503a9a246eff213d7db592fc06bd2361b18d4ce53a",
    "generator": "ChatGPT image_gen",
    "expectedImages": 44
  },
  "illustrations": [
    {
      "id": "zzl_a1_s1_illustration_01",
      "image": "images/illustrated-2026-10-24/zzl_a1_s1_01.png",
      "caption": "采用已审分镜的实际场景图注",
      "alt": "采用已审分镜的具体人物、动作与环境描述",
      "afterParagraph": 4,
      "width": 1536,
      "height": 1024,
      "illustrationStatus": "illustrated"
    }
  ]
}
```

示例段位/尺寸只说明类型，不能照抄作成图事实；实际值从分镜与解码结果填写。`alt`目前不会进入normalize，若采用独立alt需补齐frame归一化、缩略图及放大图传递；或直接让图注具体描述动作，沿用已有alt生成。不要仅在JSON写alt却宣称页面已用。

图注与正文分开。每章两图应对应不同已发生段落，两个 `afterParagraph` 严格递增；索引是1基“第几段之后”。文件名、ID、SHA-256独立；不将一张拼贴裁为两张，不重复引用首张当封面。

## 最小实现边界

- 新 `illustrated-2026-10-24/export.mjs`：校验明确版本与源基线，构建story-data/镜像、插图下载稿、manifest和新目录的导出证据；资源全在场后才发布最终源。
- 新插图验证入口：复用结构合同和实际源校验；把文字内容守恒、manifest、段位、文件、哈希、解码结果作为单独illustrationValidation。保持原 `verifyReboot` 对文字版的严格零图语义。
- 两个通用verify入口先识别准确illustrated版本，再调用新入口。未知插图状态/版本应失败；不能依靠有 `illustrations` 就自动放行。
- reader只修改状态文案/模式报告，以及需要时的独立alt；保留原段后渲染和导航。
- 导出器按明确illustrated模式增加图像支持与读者目录相对链接，旧文字版输出应逐字保持。

## 有意义的自动验收

1. 固定本次文字基线文件和SHA，按字段白名单只允许version、插图状态、illustrationRevision及图片字段变化。所有22章 `paragraphs` 数组逐元素严格相等且顺序不变，合计仍343段；再比对标题、summary、readerTeaser、dialogue、choices、history、dramaticBeat、人物、伏笔、结局等完整非插图内容。
2. 保持6部、22章、同一22个ID、同一63个别名映射；`aliasIssues`通过还不够，须与基线映射完全相等，以免有效但错跳年代。
3. 逐章至少2幅；本轮计划严格2幅/章、总计44幅。frame ID、路径、内容哈希均44个唯一；路径只可指向本轮目录，禁止空路径、远程地址、路径穿越和旧图目录。
4. 每frame有非空图注；索引为合法整数、严格递增、位于1..paragraphs.length。资源manifest与源frame双向一一对应：无缺图、无额外引用、无错章、无错段、尺寸与实测一致。
5. 图片逐个完整解码，验证实际格式/尺寸/哈希。仅比较文件存在或图片头不足。生成来源及提示词记录必须来自实际工具调用，文件哈希不能证明生成来源或历史准确性。
6. 源JSON与下载镜像同字节，`story-data.js`执行后对象同源。小说/剧本每章保持原文顺序，图像Markdown链接全部能相对于下载稿定位44个文件，章前不重复首幅。生成稿内容与renderer预期完全一致。
7. 负例须覆盖：删一图、重复同一图字节、把一图挪错章、索引0/越界/非整数、引用旧图、改一字正文、改别名目标、manifest错哈希、写错图片尺寸、将文字版标为illustrated但无图。每种应明确失败。
8. 浏览器真实检查桌面/手机：22章44个 `main img`、每章恰2个 `figure[data-process]`、无普通章头图、没有unavailable占位；每个image `decode()`通过且naturalWidth/naturalHeight匹配。按DOM遍历核对每图之前实际累计正文段数等于afterParagraph，同时抽取每章 `.scene-prose > p` 与源逐段相等。
9. 检查放大图与对应src/alt，打印入口、搜索、旧书签跳转、目录、横向溢出。需全量加载图后再核对计数；懒加载未解码不能当缺图或成功。
10. 若交付包括公网入口，分别记录44个实际URL的HTTP状态与响应SHA、网页数据版本。当地文件/静态通过不替代公网或实际画面证据。

## 解码工具实测

当前Python有Pillow **12.2.0**；`features.check`确认PNG/zlib、JPEG、WebP、AVIF支持均为True。`ffprobe`也可用。可用Pillow `Image.open(...).verify()`后重新open并 `load()`做逐图完整解码；读取尺寸，另算文件SHA-256。此处仅证实工具能力，未验证尚未生成的44张新图。

已有 `tools/verify-zheng-story.mjs:39-133` 的 `inspectImage`支持PNG/JPEG结构检查，PNG还检查CRC与解压栅格；不等同浏览器渲染。新图若统一PNG，可复用并补Pillow/浏览器解码；若WebP/AVIF，不能未经扩展调用该函数当作支持。

以上为实施前调查结论。完整生成、运行态与公网验证由主线程后续实际证据补齐。

## 实施结果

主线程选定合同：版本 `historical-reboot-illustrated-2026-10-24`，top/act/scene/frame的 `illustrationStatus='ready'`；`narrativeContract`完全不变。`editorialRevision.report`移至本轮目录，其余文学元数据不变。每章两项仅放 `illustrations`，保留实际width/height及独立alt。此决定取代上文建议中的 `illustrated` 状态值及保留旧report路径方案。

实际修改：

- 新增 `tools/zheng-illustration-contract.mjs`，导出同步纯输入验证接口 `validateIllustrations({story, manifest, sourceSha256, baselineStory, baselineSourceSha256, readImage})`。候选阶段即可校验，不读/写正式源；`readImage(path)`返回PNG Buffer。结果为 `{valid, checks, failures, imageRecords, summary}`。
- 验证明确新版本、固定基线内容及SHA、除插图字段/版本/report之外全文数据深等、44图/22章/章至少2图、严格递增有效段位、唯一frame/path/内容SHA、当前目录安全路径、PNG结构与栅格、实际尺寸、manifest v2全部字段和当前源SHA。两项基线/全文守恒check为text scope，其余illustration scope。
- manifest元素逐项匹配 `id/sceneId/image/afterParagraph/caption/alt/width/height`，再核对实际 `sha256` 与生成来源标记。根路径严格限定 `images/illustrated-2026-10-24/[A-Za-z0-9_-]+.png`，不允许子目录、穿越、旧图或远程图。
- `verify-zheng-reboot.mjs`保持同入口，只有精确新version进入新合同；其他historical仍要求text-only及零图。不必修改verify-reader/verify-story调用方。当前源、镜像、script与同源导出旧检查保留。
- `render-zheng-reboot-exports.mjs`对新version在小说段后插图；`render-zheng-screenplay.mjs`新增可选imageBase，供reader内部下载稿使用正确 `images/...` 路径。图注与alt均保留。旧文字版三个下载稿的既有SHA完全不变。
- `app.js`保留版本与frame alt，图片和放大对话框都使用描述性alt；公告识别新版本，self-check按实际合格图片数报告模式，并单独检查historical文字版零图/插图版44图。原段后渲染、书签与结构合同保留。

`baselineStory`取 `full-polish-2026-10-24/candidate.json`；该文件实测原始SHA与本轮固定精修源SHA一致。校验器还重算已知基线JSON规范序列化的SHA，防止被改过的baseline对象借用原SHA通过。新report目录也单独校验，避免导出覆写上一轮因果索引。

先写失败测试：缺失validator接口、小说未插图、reader未保留alt/version均出现预期断言失败。进一步负例证明“改过基线对象但借用原SHA”及“报告仍写旧目录”原先可漏过，再补修至通过。

最终运行（2026-10-24）：

```text
rtk proxy node --test tools/zheng-illustration-contract.test.mjs tools/zheng-story-contract.test.mjs tools/zheng-reboot-aliases.test.mjs tools/verify-zheng-literary.test.mjs
58 tests, 58 passed, 0 failed
```

其中新插图测试35项，包含44个独立合法微型PNG的合成夹具，以及漏章、同图充数、段位错误、损坏PNG、错误manifest、全文/别名改变、旧版图像拒绝等负例。合成夹具仅证明程序行为，不能作为44幅实际插画的生成证据。

旧文字版 `verifyReboot({writeReport:false})`实测377/377通过：6部22章、343段、93条对白、正文34,827字，expected/present/unique图片均0。`node --check app.js`及 `git diff --check`退出0。未写旧版verification报告。

真实首幅 `images/illustrated-2026-10-24/zzl_a1_s1_01.png` 已独立检查：Node `inspectImage`完整PNG栅格通过，Pillow `verify()`及重新打开 `load()`通过；1536×1024 RGB，3,074,513 bytes，SHA-256 `21399fd651f69ef2dd9bfc5598a92801cb84009d3e9a01a566ecc5a4bf69382b`。

截至本次技术交接，仅确认首幅真实资源解码和上述程序回归。44幅生成、候选采纳、全部图解码、页面实际DOM/图像与公网验证仍由主线程在素材齐备后完成；不据单元测试宣称整卷插图交付完成。
