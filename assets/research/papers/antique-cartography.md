# 东洋南海古航图：地理数据与墨刻表现

- 课题 ID：`antique-cartography`；2026-10-26，前瞻工程研究。
- 状态：待集成（`integration-ready`）；独立 CPU／GPU 已验证，正式菜单接线由父任务继续，不能把这里的独立证据当作已集成验收。
- 摘要：有来源的经纬度海岸、纸纹与墨刻在独立场景通过54条合同及38张真实GPU原帧；中文标签、港口选择和三档窗口可用。没有跨洋航行或整场FPS结论。
- Demo：`res://game/research/demos/antique_cartography.gd`，已在显式 allowlist 注册；普通首页实验室可选择课题。
- 数据／来源：`res://assets/data/cartography/`，Natural Earth 50m land 与 10m populated places，public domain；来源和散列另记 `provenance.json`。
- 证据目录：`docs/design/2026-10-26-ming-maritime/atlas/`，新 run 保留 RED、CPU、GPU 原帧，不覆写历史海图证据。

## 问题与假设

既有 `nautical_chart.gd` 使用压缩游戏米坐标，只覆盖三港或六港局部岛群，不是跨区域世界地图。旧网页的手写 SVG 不具备经纬度权威。

H1：固定经纬度与相同投影下，纸纹、岸线墨刻、山形及罗盘只改变表现，港口不位移，project/unproject 误差低于 1e-5 度。H2：裁切后保拓扑简化的物理陆地在 1600×1000、640×960 和最小 320×480 的真实 GPU 画面中保留中国东岸、朝鲜、日本、台湾、吕宋、婆罗洲、苏门答腊与爪哇的可辨识轮廓，且港口详情、返回及缩放不会溢出。320px 使用单独港口选择行和工具行，港口志允许滚动。

坐标是 WGS84 经度、纬度（度）；北朝上，不使用本地 `{x,z}`。图面采用标准纬线 25° 的等距圆柱投影；不绘现代国界，不宣称十七世纪岸线复原。固定 seed=0（无随机数）；宿主唯一拥有实验接受时间，浏览本身不推进游戏权威或 RNG。

## 方案比较

1. 整张 AI 地图：艺术整合快，但无法保证海岸、地名与点选一致，弃用。
2. 旧网页 SVG：体积小，但港口为像素示意、无地理来源，弃用。
3. Natural Earth 物理陆地矢量 + 原生中文 + 独立无字纸纹：地理来源可核对，投影和点选共享同一合同，采用。用公开数据仅做近现代地形参考，历史地名为游戏叙事层，不绘无据疆界。

## 算法与实现

`world_atlas.gd` 只拥有地理阅览、绘制与选择；`antique_cartography.gd` 为实验室 Node3D 适配，固定初态并暴露 configure/advance/reset/pause/inspection/dispose。数据构建脚本只裁切、保拓扑简化及舍入，不手绘替代岸线。运行时328个多边形、4590顶点、3934三角形，源数据约104KB；全局原件gzip留源约532KB，不在游戏运行时展开。

图面 map_rect 使用同一投影、逆投影与点选；zoom_at 围绕指针保位并夹在 1–6 倍；pan_pixels 在数据范围内夹限。选择端口深复制，未知 ID 拒绝，既有选中保持。返回发 signal。宽屏右侧港口志，窄屏下方港口志；详情使用真实 Control/ScrollContainer。地图没有 navigate 意图、自动航行或存档写入。

## 实验设计

实施顺序：先写缺失 atlas 的 RED；准备可追溯地理数据；实现投影/选择/输入和宽窄屏排版；登记独立 Demo；执行 CPU；冻结代码/数据散列后真实 GPU 成对捕图；审阅原帧再报告可集成。

预定判据：

- CPU：数据带来源、经纬度有限且落在区域范围；保留主岛覆盖；默认原点、四角和港位投影往返误差 <1e-5°；缩放指针锚点 <1e-5°；拖动有界；非有限输入拒绝且状态不变；unknown port 不伪造点；快照脱离；实际 Control 点击选港且不会导航；返回一次；释放清空资源。
- Demo：同输入重置确定；暂停与镜头/图面操作不推进 tick/time；接受固定步为 1/32s；dispose 释放 atlas，无生产存档/设置。
- 负载：区域 <12000 顶点，<24000 个三角形；不在每帧重建地理网格。仅记录隔离 CPU build 和 draw call 数，不能推断整场 FPS。
- GPU：固定 engine/backend/viewport/seed，纸纹/墨刻开关在相同海岸和选港下成对；全图、港口选中/放大、连续平移、窄屏原帧、连续32帧序列；无 Godot ERROR，完成 marker 与退出0；所有资源和源 SHA256 写入 manifest。实看可读中文与关键岛形，不能只凭 headless。

## 结果与证据

最终独立冻结批次：

| 类型 | 记录 | 实际结果 |
| --- | --- | --- |
| CPU 合同 | `docs/design/2026-10-26-ming-maritime/atlas/cpu-final-03/world-atlas.json` | Godot4.7.2 headless；`WORLD_ATLAS_TESTS assertions=54 failures=0`，退出0，无Godot错误。涵盖地理主岛内部、投影往返、锚点缩放、夹限、拒绝NaN/Inf、实际选港/返回、320工具分行、窄→宽恢复、staged隐藏入口及实验时间/释放。 |
| 研究目录 | 同目录 `laboratory-catalog.json` | `LABORATORY_CATALOG_TESTS assertions=123 failures=0`，退出0；9课题，原默认保持hull-contact。 |
| 独立 GPU | `docs/design/2026-10-26-ming-maritime/atlas/gpu-final-02/GPU_VERIFY.json` | Godot4.7.2 / Vulkan1.4.325 / Forward+ / Intel Arc130T；`WORLD_ATLAS_GPU_COMPLETE captures=38 assertions=50 failures=0`，退出0。初态seed0、overview、厦门；实际端口点选和返回输入。 |
| 连续画面 | 同目录 `SEQUENCE_VALIDATION.json` | 32张连续原PNG，tick1–32、接受时间1/32–1秒；每次相邻原帧都有地图区域像素改变，图外不变，32项0失败。不是帧率测量。 |
| 进程观察 | 同目录 `PROCESS_OBSERVATION.json` | 保存工具最终输出块与真实exit0；设备、源hash、每帧snapshot及PNG hash在GPU manifest，逐项重算均相符。 |

真实 GPU 原帧包括关闭墨刻的同地理基线、开启候选、平户实点/详情、爪哇南部、640×960、320×480和32帧平移。亲看全图、320小窗、窄→宽末帧及此前平户/640原帧；未声称逐像素地理考古复原。320的图面缩小后只画选中港名，港口选择仍可用，港口志滚动。

失败与修改保留：`cpu-red-02` 的缺失实现、`cpu-red-demo` 的缺失独立实验、`cpu-red-drag` 的图外释放拖动残留、`cpu-red-staged` 的入口尺寸、`cpu-red-responsive` 的320工具重叠/窄宽反馈。最初`cpu-red`自身类型推断错误不算有效算法RED。`cpu-green-04`撞上父任务新secondary纹理尚未导入的共享资源错误，导入后最终CPU无此错误。`gpu-01`和`gpu-final`保留早期表现；后者虽50前的断言通过，人工审图发现宽窄切换后的详情内容伸长，因此不作为最终响应式验收。最终使用`gpu-final-02`。

H1由CPU的独立坐标值与GPU相同数据/视图/端口成对证明，H2以最终三档原帧及输入合同通过。多边形/顶点预算通过；未测GPU frame-time、驱动耗时或完整游戏FPS。父任务如再添加静态插画，须另录该版本正式入口GPU；这里的源码hash只对应本冻结批次。

## 局限与失败

Natural Earth 是现代小比例尺物理数据，不能说明明代海岸细节或古港泊位；端口采用城市／港区地理定位，历史港址精确复原范围外。50m 岸线和简化会遗漏小岛。山形是固定地理底图内的装饰排线，不包含 DEM 高程，不代表真实山峰位置或海拔；船和罗盘也是装饰，不是实际舰队联系人。世界海图是只读图志，不是已完成的跨洋航行系统。既有游戏六港 x/z 压缩坐标不向全图投射为假实时船位。

## 集成与复现

CPU：`rtk proxy node tools/verify-godot.mjs --filter world_atlas --output Temp/research/<new-run>/world-atlas.json`。

父任务通过原菜单/router lifecycle 接入；本子任务不改菜单、router、theme 或船模。运行时全部读本地资源，无网络。回退可移除新入口并保留本课题及原帧，旧局部航图不变。

Scene API：`startup_options`、同步ready后的`startup_receipt`、`main_menu_requested`。Control在零尺寸顶级入口自动填充logical viewport；staged隐藏/禁process不创建CanvasLayer。通用API：`configure(options)->Dictionary`、`project(Vector2(lon,lat))->Vector2`、`unproject(pixel)->Vector2`、`select_port(id)->bool`、`zoom_at(factor,pixel)->bool`、`pan_pixels(delta)->bool`、`reset_view()`、`focus_selected()`、`inspection_snapshot()`、`dispose()`。`port_selected`只返回脱离字典，`return_requested`与`main_menu_requested`是同次返回的两个可选监听面，调用方接一个。

真实GPU复现必须使用不存在的新目录：

```powershell
rtk proxy $env:GODOT_EXE --path . --script res://tools/capture-world-atlas.gd -- --output=res://docs/design/2026-10-26-ming-maritime/atlas/<new-run>
```

捕图器拒绝已有输出目录；manifest记录source与所有PNG散列。CPU runner默认发现全tests；本子任务只执行world_atlas和catalog聚焦，父任务承担正式入口及全套回归，后续不可将本报告的独立通过等同完整游戏通过。
