# Godot native migration: physics, naval simulation and rendering inventory

审计日期：2026-10-11。来源：`C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada`，只读确认 HEAD `9ad6a44daecd4ec36a8172d83ff27493feffe5dd`。以下源路径均相对此来源。目标：`C:/Users/dains/Documents/Git/ming-armada`，原生 Godot/GDScript；不依赖 Three、WebView、Node 服务或浏览器运行。原 Three 工程未修改。

CodeGraph 首次查询返回源目录 UNINDEXED；依照要求未创建索引，使用 RTK 源码读取。此次完成源码/GLB JSON chunk/manifest/SHA256 审计；未启动原游戏、未运行测试或 Godot、未生成数值 reference 文件。下文“现有测试期待值”是读到的原测试断言，不是此次运行通过的声明。

## 1. 依赖分层及原模块归属

迁移依赖方向：`contracts` 为底；`physics_engine` 依赖合同；`naval_simulation` 调用物理；`scene_engine` 依赖合同和注入的采样器；`game/domain` 保留纯业务；`runtime` 组合上述模块、拥有唯一时间；`presentation/UI` 订阅合同并提交意图。物理模块不 import UI、scene 或业务目录；scene 不反向读取 campaign、save 或 naval 实例。

| 原路径/符号 | Godot 建议归属 | 移植边界/注入点 |
| --- | --- | --- |
| `packages/physics-core/src/math.ts`, `types.ts`, `shipParams.ts`; `index.ts:213-307` config/visual/controls | `modules/contracts/{units,numeric_vectors,physics_state,physics_controls,wave_descriptor}.gd` | 纯 scalar float/可序列化数据；不含 Node3D、Mesh、RID、域对象。单位写入字段名和断言。 |
| `packages/physics-core/src/index.ts:350-1308` `NormPhysicsEngine` | `modules/physics_engine/marine/{ship_dynamics,buoyancy,sail_aerodynamics,hydrodynamics,manual_forces}.gd` | 完整移植原数值状态、运算顺序和 setters。注入 `wave_height(x,z,accepted_time)`，不得由物理查 scene shader。 |
| `packages/physics-core/src/{ocean,DescribedOcean}.ts` | `modules/physics_engine/ocean/{gerstner_ocean,described_ocean}.gd` | 注入不可变 wave descriptor 数组；返回 height/normal。描述符类型在 contracts。 |
| `packages/scene-engine/src/engine/water/oceanWaves.js` 原 authored 常量 | `modules/contracts/original_wave_set.gd` 或独立数据资源 | scene/physics/wake 共同消费；常量不得留在 scene 后令 physics 反向 import。CPU/GPU 共相位。 |
| `packages/physics-core/src/{collision,cannon,projectile,events,terrain}.ts`; `index.ts:862-962,1312-1354` | `modules/physics_engine/{collision,ballistics,events}` | 这是 AP/HE 通用武器路径；注入 terrain sampler、目标 shape、damage/impulse 输出；不是当前 naval 三弹种路径。 |
| `packages/physics-core/src/dynamics/articulated.ts` | `modules/physics_engine/crew/articulated_reference.gd` | 独立 120Hz 数值 oracle；world-space numeric topology/contact/water 合同。保留比较入口，Jolt 替换不能伪称逐数相等。 |
| `packages/naval-core/src/types.ts` | `modules/contracts/naval/{commands,snapshots,events,reconcile_policy}.gd` | 保留 battleId/tick/time/controlsSequence，以及命令拒绝原因、detached snapshots。 |
| `packages/naval-core/src/encounter.ts` | `modules/naval_simulation/{encounter,ship_factory,commands,combat,orders,navigation}.gd` | 编排船、AI、炮战、连续战斗、ownership policy；只调用 physics 合同。`sampleTerrainHeight`、waves、contact resolver 为注入项。 |
| `packages/naval-core/src/{route-planner,tactical-orders,manualHandling,collision}.ts` | `modules/naval_simulation/{wet_route_planner,tactical_decisions,manual_policy,projectile_sweep}.gd` | 保留路线预算、阵营/目标规则和当前武器 hit authority；`sweepMovingBox` 不依赖实际模型。 |
| `apps/game-client/src/simulation/{SailingSimulation,ManualSailingAssist}.ts` | `modules/runtime/{simulation_clock,input_bridge}` + `modules/naval_simulation/manual_assist.gd` | 拆出唯一 accumulator/accepted tick；手动 assist 是 policy，数值转矩在 physics。UI 只提供 intent，不直接写船姿态。 |
| `apps/game-client/src/simulation/world-layout.ts`; `packages/adventure-core/src/mingqi/geography.ts` | `modules/game/domain/world_data.gd` + `modules/contracts/terrain_provider.gd` | 几何数据与 terrain 数学可放独立纯 provider；runtime 给 naval 和 scene 注入同一实例。scene 不能 import domain/campaign。 |
| `packages/scene-engine/src/engine/terrain/terrainHeight.js`, `utils/math.js` | `modules/scene_engine/terrain` 的纯采样 provider +原生图像 loader | 去掉 `window`, `fetch`, canvas 解码、全局 customSampler；`Image` 适配器单独。Mingqi 地形不是默认 simplex 地形。 |
| `packages/scene-engine/src/engine/world/{World,Chunk,IslandMesh,IslandRegistry,IslandVegetationManager,BeachDecorationManager,vegetationExclusions}.js`, `utils/QuadTree.js` | `modules/scene_engine/world/{world_view,terrain_chunks,terrain_mesh,vegetation,registry}.gd` | ArrayMesh/SurfaceTool、MultiMesh、静态碰撞资源；World 原来的 input、camera、clock、副作用须拆开。 |
| `packages/scene-engine/src/engine/water/{ProjectedWaterSurface,ProjectedWaterShader}.js` | `modules/scene_engine/water/{projected_grid.gd,projected_water.gdshader}` | 重写 Three GPU/BufferGeometry API；移植波形、法线纹理采样、颜色、foam、fog 数学。time/waves/camera/sun 全注入。 |
| `packages/scene-engine/src/engine/water/{WaterSurface,LODWaterSurface,OriginalWaterSurface,FFTOceanSurface}.js` | `modules/scene_engine/water` 可选 native profiles | 当前 CONFIG 默认为 projected。原 Water.js 镜面RTT、FFT/FBO 不能 copy JS 即运行；如保留所有水模式必须逐个原生化。 |
| `packages/scene-engine/src/utils/physicsPose.js` | `modules/scene_engine/adapters/ship_pose.gd` | 唯一物理坐标到 GLB pose seam；不要把转换散进 UI、rig、Jolt、camera。 |
| `apps/game-client/src/simulation/NavalSceneView.ts`, `SceneResources.ts` | `modules/scene_engine/naval/{naval_view,asset_catalog,resource_owner}.gd` | 只消费 presentation snapshot/events；资源生命周期、LOD、vessel identity、dedupe、异步generation仍需原生实现。 |
| `apps/game-client/src/simulation/{SailRig,CombatVisuals,WakeTexture}.ts` | `modules/scene_engine/naval/{sail_rig,sail_damage,cannon_recoil,projectile_view,wake_view}.gd` | 读取模型named nodes/blend shapes；只更新显示；禁止产生damage/hit/弹药变化。 |
| `apps/game-client/src/simulation/SailorDeckView.ts` | `modules/scene_engine/crew/{asset_catalog,deck_stations,crew_view}.gd` | Skeleton3D/AnimationPlayer/AnimationTree 替代 SkeletonUtils/Mixer；crew只是权威 crew count 的限额表示。deck provider由runtime注入。 |
| `apps/game-client/src/simulation/SailorImpactPhysics.ts`, `NavalDeckSupport.ts` | 渲染rig适配在 `scene_engine/crew`；contact bridge在 `physics_engine/jolt` | 将骨骼资产转换为 detached `ArticulatedBodyDefinition`；物理不能遍历可见mesh。甲板三角/shape由asset import provider给physics，pose由合同给scene。 |
| `apps/game-client/src/simulation/{SailingAudio,WeatherVisuals}.ts`, `MingqiSceneHelpers.ts` | `modules/scene_engine/{audio,weather,camera}`；事件路由由runtime | 原WebAudio、Three sprites、camera/orbit均需Godot API重写。音乐文件可copy。weather只取注入的天气状态。 |

避免循环的实际风险：原 `SailingSimulation` 从 scene-engine import terrain/wave常量；原 `MingqiTerrainLease` import scene registry与adventure terrain；原 `NavalSceneView` 一类同时装载模型、更新骨骼、调用物理、播放声音；原 `SailorImpactPhysics` 由渲染mesh raycast产生contact。应将这些方向拆成 runtime 注入，不能机械地一文件变一Godot脚本。

## 2. 单位、坐标与时间合同

- 长度/坐标/吃水/波幅：米。质量：kg；速度：m/s；重力：9.81m/s²；力：N；转矩：N·m。风密度1.225、海水密度1025kg/m³。业务 hull/sail/crew 是游戏计量值，不能当kg或Jolt mass。
- 数值平面为 world XZ；原 `Vec2.y` 实为 world Z。heading连续累积，0指+X（东）、+π/2指+Z（南）。forward=`(cos(h),sin(h))`，starboard=`(-sin(h),cos(h))`。wind.direction 是气象**来向**，airflow=`-wind.direction*speed`；不可把风号反转两次。
- 原视觉合同 `PhysicsVisualState={position,heading,velocity,heel,pitch}`；velocity.y 当前固定0，不等于内部heaveRate。heel正值为右舷下沉；pitch正值为船艏上仰。
- GLB为Y-up、船艏+Z、右舷-X、水线0。原实际渲染 `Euler(-pitch, PI/2-heading, heel, 'YXZ')`；`physicsVisualToPose()`为yaw=`PI/2-heading`、pitch=`-pitch`。Godot应显式设置Basis或同YXZ顺序并核验四个cardinal heading；不要为Godot默认camera前向-Z再翻船坐标。
- `NormPhysicsEngine.step` 和 `stepBuoyancy`拒绝非有限/非正dt，cap=0.05s。`NavalEncounter.step`固定1/60s，输入单次cap=.1s，最多6ticks，epsilon1e-10，过载余数丢弃；snapshot.time=`tick/60`。`SailingSimulation.advance`另有1/60accumulator及cap=.1；Godot runtime应只保留一个时间owner，naval提供`fixed_tick()`，不能复刻双accumulator让两个Node各`_physics_process`。
- 船员 `ArticulatedPhysics`固定1/120s，共12同时body；以**accepted seconds**和区间结束phase积分。渲染插值time不可计费。`NavalSceneView:196-207`以同battleId/tick增长计算delta，重复render frame/暂停/rewind/epoch切换不补账；船员clip也是accepted time。Godot runtime负责60Hz naval、每tick2个120Hzcrew子步、snapshot interpolation、暂停和速度倍数。
- 原JS Number是double；GDScript scalar float也是64-bit，但默认Vector2/Vector3为32-bit。数值核心用scalar或自定义float字段结构，渲染/Jolt边界才转Vector3；否则长时间轨迹误差由迁移本身引入。数值比对用分字段绝对/相对误差，事件id/tick/状态/弹药必须精确。Godot官方：[float](https://docs.godotengine.org/en/latest/classes/class_float.html)、[Vector3](https://docs.godotengine.org/en/latest/classes/class_vector3.html)。

## 3. 原船物理必须移植的数学与状态

`NormPhysicsEngine` API主干：`setState`, `setBaseY`, `setSpeed`, `setControls`, `setWind`, `setSailAngle`, `setSailDeployment`, `setSailCondition`, `setSailPowerScale`, `setCargoMass`, `setDraftMeters`, `setWaveSampler`, `setConfig`, `getVisualState`, `getHorizontalMotion`, `getSailDebugInfo`, `getWaveSampleDebugInfo`, `stopHorizontalMotion`, `correctHorizontalMotion`, `resolveHorizontalContact`, `step`, `stepBuoyancy`。船初始化与装备变化必须调用原同义API，不重建body或重置浮力phase。

**四点浮力**，`index.ts:536-741`：半长=max(.5,length*.35)，半宽=max(.25,beam*.45)，顺序前右/前左/后左/后右。采样四点波高；首次reference offset=`baseY+heaveY-averageWaterHeight`。每点`k=m*9.81/draft/4`、`c=m*heaveDamp/4`；hullPointY=`baseY+heave-draft+x*sin(pitch)-z*sin(heel)`；vPoint=`heaveRate+x*pitchRate-z*heelRate`；`F=max(0,k*depth-c*vPoint)`，depth<=0无浮力。力矩分别`-z*F`与`x*F`，半隐式积分，pitch damping=.6，roll damping=.6。

限制：draft>=.05；pitch限±π/10，heel限±π/7*.99；generic heave限±2*draft，authored waves限±(7+2*draft)。不能用碰撞水plane把船root钳到波顶，也不能改成Godot默认浮力、纯视觉sin bob。水面与地形seaLevel独立；render projected基础为Y0。

**更新顺序**，`index.ts:1000-1308`：optional drive→帆力→空气/水二次drag→龙骨侧向lift及induced drag→侧漂指数阻尼→hard no-go→水力舵、船员低速stern force、manual torque→heave/pitch/heel→heading/position→通用weapons。顺序改变会改变轨迹。帆effective factor=`deployment*condition*powerScale`；speed upgrade给powerScale=`speedMultiplier²`，cargo加入实时mass，draft参与水阻与浮力而不是通过scale mesh调整。

重要默认：waterCd=.35，waterAreaFactor=.8，rudder lift3.5/stall30°/areaFactor.2/armFactor-.54，yawDamp=.5/maxYawRate.8，lateralDamp.08，keel lift5/stall22°/areaFactor.25/Cd0.03/induced.12，sailPressureScale5，no-go35°+fade15°，heaveDamp2.5。naval构造覆盖keelAreaFactor=`length/width/.8`、keelLiftSlope6、keelInducedDrag.08、sailPressureScale1、sailInducedDragFactor.08。帆原 liftSlope4.2、stall28°、Cd0.08、runCd1.4；帆翼力、帆压、parasitic dragCd=.5共同作用。不得只复制defaults遗漏naval overrides。

低速船员操纵：每crew200N（乘steeringMultiplier），核心force cap40000N、速度limit1.2、同向yaw rate taper .035rad/s、yaw accel limit.012rad/s²；stern力臂`-length/2`。manual assisted另沿dry yaw inertia施加bounded torque，跟踪gain4，max12°/s、16°/s²，powerFraction=`crewFraction*sqrt(hullFraction*sailFraction)`，neutral damping2.5；帆<=.05时brake=.20m/s²，loaded mass自然减弱刹车。

manual每船moving/slow/accel(°/s、°/s²)：fisherman12/6/16，patrol10/5.5/14，fuchuan8/5/11，merchant及voc6/4/8，heavy4.5/3/6。speed blend为(.3,1.5)。`ManualSailingAssist`反风停滞speed<.5、角度<=50°、持续1s触发安全heading恢复；恢复超时heavy24s/其他18s，出禁航后2s回帆，手动转舵/收帆/trim取消。fresh-forward语义必须保留，不能一直自动强迫修复方向。

## 4. 波形：CPU、GPU、尾迹与船员同一事实

当前产品`SailingSimulation.ts:28`默认 `ORIGINAL_PROJECTED_WAVES`；CONFIG.defaultWaterMode=`projected`，不是`OriginalWaterSurface`（Three Water.js profile）。`getWaterHeightAt()`只含前两层、忽略choppy，是旧helper，不能作为当前迁移oracle。

| amplitude | kx | kz | angular phase speed rad/s |
| --- | --- | --- | --- |
| 1 | .02 | .015 | .9 |
| 1 | .02 | -.015 | .1 |
| 1 | .05 | 0 | -.6 |
| .25 | .1 | .11 | 2.05 |
| .25 | .1 | -.11 | -.05 |

来源`packages/scene-engine/src/engine/water/oceanWaves.js:7-30`。由k归一direction，wavelength=`2π/hypot(kx,kz)`；h=`ΣA*sin(k·worldXZ+speed*t)`，gradient=`ΣA*k*cos(phase)`，normal=normalize(-dx,1,-dz)。描述符不随wind旋转。波crest-to-trough envelope=7m。最多8wave、允许负speed、wavelength>0、全部有限，输入与输出detached。

独立原shader公式：`2*sin(.02*x+.5*t)*cos(.015*z+.4*t)+sin(.05*x-.6*t)+.5*sin(.1*x+1*t)*cos(.11*z+1.05*t)`。此式与五sine展开等价，可做独立CPU/GPUgolden。`GerstnerOcean`备用5波为(A,λ,ω,headingOffset)：(1.1,28,5,0),(.55,14,9,.28π),(.35,9,12,-.22π),(.25,20,7,.5π),(.15,35,4,-.35π)；只有此备用波随wind airflow heading旋转。

authored ship spawn的baseY是**四支点平均波高**，不是中心采样，避免永久phase offset；reference capture必须包括初始baseY与随后heave/pitch/heel内部rates。`setDraftMeters`及装备更新不重置wave state/clock/reload/queued volleys。

## 5. Naval权限、战斗和航路

`NavalEncounter`公开入口：`reset`, `command`, `navigate`, `setWind`, `issueOrder`, `orderStatus`, `navigationStatus`, `setManualHandling`, `findManualRecoveryHeading`, `updateShipStats`, `reconcileShips`, `setPlayerId`, `isAnchored`, `hasPendingCombat`, `hasPendingAttacks`, `previewSurrender`, `snapshot`, `drainEvents`, `step`。迁移时retained policy必须覆盖controllable、hostileTargets、captured、anchored、locked、disabledMotion、orders、navigation；scene可见不意味着船可控制或可攻击。

| kind | length/width/draft/freeboard m | dry mass kg | sailArea m² | actual guns/side | max crew默认 |
| --- | --- | --- | --- | --- | --- |
| fuchuan | 32/9/2/1.9 | 95000 | 430 | 4 | 100 |
| fisherman | 14/4.2/1/1.15 | 18000 | 110 | 0 | 100 |
| merchant | 36/10/2.8/2.3 | 150000 | 450 | 0 | 100 |
| voc | 40/11/3.2/2.7 | 170000 | 580 | 4 | 100 |
| patrol | 24/6/1.4/1.35 | 50000 | 290 | 3 | 60 |
| heavy | 52/14.5/4.2/4.2 | 330000 | 950 | 8 | 160 |

实际物理规格来自`encounter.ts:15-26`，GLB fuchuan/voc每舷6门是显示资产；不能按模型炮节点数将实际4门改成6门。

| ammo | muzzle speed m/s | aim range m | blind elevation rad | ttl s | hull/sail/crew damage |
| --- | --- | --- | --- | --- | --- |
| solid | 65 | 250 | .25 | 8 | 8/1/1 |
| chain | 55 | 190 | .23 | 7 | 1.5/12/1 |
| grape | 42 | 80 | .1 | 4 | 1/1/12 |

每次broadside扣1库存，reload=`ceil(7*60*(1+(1-crew/maxCrew)*1.5)*reloadMultiplier)`ticks；首炮立即，后续每5tick一炮。±25°aim arc、velocity预测lead、低抛弹道解；chain aimY额外11m。grape5pellet offsets(azimuth,pitch)：(0,0),(-.036,-.018),(-.018,.018),(.018,.018),(.036,-.018)；damage分5份且乘cannonMultiplier，超过80m后damage*.15。

主战斗ballistics是无drag解析步进：`to=from+v*DT`, y另减`g*DT²/2`，之后vy减g*DT；和physics-core通用AP/HE半隐式drag/fuse/fragments不同，不得混用。hit权威是`naval-core/src/collision.ts` moving hull slab sweep：旋转每.015rad拆piece；hull box +上方rig box；按first TOI与water TOI排序；原箱忽略pitch/heel。TTL终止发splash。Physics/Jolt接触不能另扣hull/sail/crew，combat必须只输出一次event。

原船-船contact为XZ OBB SAT、4条axes、等分penetration与closing速度、无damage；shore为9点完整船底footprint、draft阈值、运动+旋转扫掠、16次binary first contact、移除inward velocity、保留沿岸运动和yaw stern pivot。`NormPhysicsEngine.resolveHorizontalContact`用point lever/实时mass/yaw inertia求inelastic impulse，不重置vertical pose。采用Jolt可替換contact实现，但这些无碰撞轨迹与靠岸/不穿岛/旋转接触不变量仍为验收oracle。

路线`planWetRoute`：hull膨胀radius=`hypot(length,width)/2+8`；grid32m，8邻接，最多4096nodes；footprint与segment4m采样，全局1000000sample budget；路径距离<=2048m、radius<=128m、abs coordinate<=1e7。阻塞reason必须保留，失败不teleport。重试120*2^failures cap1800ticks；30s且距进度不足5m重规划，waypoint距离<45m前进。船底depth阈值=`terrain<seaLevel-draft`。

航路：upwind tack±60°；风差10°或bearing离风>70°清tack；对准12°且speed>=1.2持续2s才起腿，45s或负progress才换腿；避让检测完整hull，失败收帆保heading。rudder=`clamp(error*1.8-yawRate*6)`，approachSpeed最高7；低速60°/40°hysteresis收帆，4s恢复。tactics六意图protect/intercept/keep-distance/focus/prepare-boarding/rally，几何输出point/target/fire/maxDeployment；reload/aim/damage仍naval authority。

## 6. 资产copy与必须重写的显示

源资产可直接copy **字节** 到Godot import目录：`apps/game-client/public/models/ships/{fuchuan,fisherman,merchant,voc,patrol,heavy}-lod{0,1,2}.glb`（18个）、`models/sailors/sailor-lod{0,1,2}.glb`（3个）、两个manifest、`textures/{waternormals.jpg,foam.png}`、`music/{大明逐浪.mp3,破浪赤焰.mp3}`、`assets/{button.png,cover.png,map.png}`、`art/{ammo,characters,goods,ports}/*.png`。无需重造GLB；Godot import后需要验证named nodes、vertex color、material roughness、blend shapes和clip track，没有运行期原Three加载器。

本次逐文件read/hash：21 GLB合计13,379,320bytes，全部SHA256匹配manifest。18船GLB均无skins、animations、images；每个都是named-node树、PBR/vertex-color几何、帆morph；3船员GLB均1skin/18bones/6animations/0images。没有embedded texture或外部贴图路径待修。

船模型LOD距0/220/650m；船员LOD hysteresis90/110及270/330m，每船近/中/远最多24/8/2、>1800m为0，总站立120人budget，按camera距+id稳定分配；actual crew count取floor且hull<=0为0。crew可视预算不改变业务crew。

船GLB接口：`deck`,`hull`,`mast_XX`,`sail_XX`（blend shapes `furl`,`inflate`）、`rudder_pivot`,`cannon_port_XX/cannon_starboard_XX`,`barrel_...`,`socket_smoke_...`,`socket_wake`,`flag_01`。帆mast local yaw=authoredYaw+π/2-sailAngle；furl=1-deployment；inflate=`inflationSign*min(1,windSpeed/18)*(sail/maxSail)*deployment`，inflationSign按表观风/帆法线，可能为负。rudder显示角=`rudder*.42`；炮管沿localZ recoil=-.6，exp(-9*delta)恢复；ship材质乘`.58+.42*hull/maxHull`。这些不在GLB clip内，必须写Godotadapter。

船员骨骼名：`sailor_root,hips,spine,chest,neck,head`；双侧`arm,elbow,wrist,thigh,knee,ankle`（均`sailor_`前缀和`_L/_R`后缀）。18bone topology与authored rest length必须保留。feetY0、forward+Z，高1.706m、vertex color衣料，无root motion。clips：idle4s/helm3s/haul2.4s/load-cannon3.2s/walk1.15s/lookout5s；clip work状态来自真实rudder、sail变化、fire/cooldown和motion，不能随机替换。动画相位acceptedTime+slot*.173、跨LOD连续，reducedMotion固定clip quarter phase。

船员deck stations从实际loaded hull/deck triangle raycast，不是freeboard常量；包含障碍排除、炮两侧worker及helm/haul/lookout/walk。Godot静态asset处理应生成共用walkable collider/metadata，而不是physical module查MeshInstance3D。`NavalDeckSupport.ts`与岸上入口的deck seam必须共用此事实。

`ProjectedWaterShader.js`必须翻译Godot `shader_type spatial`：world-spacevertex采样和normal/foam逻辑；Three `modelMatrix/viewMatrix/projectionMatrix/gl_FragColor/varying/texture2D`改Godot内置/`ALBEDO,ALPHA,EMISSION`/varyings/texture。原法线层UV worldXZ*.008、1/1.6/4倍；Fresnel power3、高光power250*1.5；foam smoothstep2/2.3、fog100..1500m、alpha=.45+.5*fresnel+foam。原shader自己linearizes颜色，Godot线性色彩与`source_color`需检查避免double gamma。ProjectedGrid为81×81vertices/80×80quads、camera ray投Y0、maxdistance=250*12；需ArrayMesh或GPU原生重投实现，不能简化远离camera后出现海边界。

`WakeTexture.ts`是128²CPU生成texture、8×16尾迹网格，船艉偏移length*.8；每顶点用同waves/time采样+.06m，speed>.35可见、opacity cap.36；不能平放Y0。帆破损`CombatVisuals.ts`以ship id FNV+LCG生成24tears，128²alpha/scorch masks，真实sail健康驱动；ShaderMaterial/ImageTexture应保留显示结果。

地形不是可copy网格资产：`world-layout.ts`legacy6椭圆岛；`mingqi/geography.ts`current3岛+航线shelf。岛body=`(1-d²)^1.65`、ridge两sin*2.2*body、deep=-24m；Mingqi浅滩中央最低depth2.4m，along32%..68%、半径135m、45m smoothstep band。同sampler决定渲染、航路、grounding。地形normalized为水下`.6+h/50`、陆地`.6+h/150`；`.6`是分类阈值，不是surfaceY。generic simplex为base .002/detail .008* .2/exponent3.5，默认随机permutation，不能无seed换FastNoiseLite后声称等地形。

`Chunk.js`250mchunk，terrain128（balanced64/low40/high96），远LOD max24或resolution/3、切换625m；植被是原procedural cylinder/cone/plane等 `Assets.js` 生成，并非GLB，需SurfaceTool/ArrayMesh/MultiMesh重建或离线导出后导入。港口box建筑、shore geometry/entry/bounds、weather sprites/lighting/camera均原生重写。原海上SFX由WebAudio noise/filter/bronze partial合成，没有可copy的炮声wav；可以GodotAudioStreamGenerator同样合成，或在构建阶段生成PCM，运行时不得调用Node/WebAudio。

## 7. Jolt integration seam

设置Godot内置 `Jolt Physics`。建议把Jolt adapter放 `modules/physics_engine/jolt`，提供 detached contact结果；从runtime注入physics world/provider，scene只装载可视资产。船非接触状态仍由原float marine solver拥有；collision body由适配器设置必要物理state、contact结果反馈XZ速度/yaw，浮力phase/heave/pitch/heel不重置。真正动态船body使用`custom_integrator`和`_integrate_forces`控制积分，避免double gravity/damping/position integration；验证具体同步时序，不能让render每帧重写RigidBody3D transform。

crew用`Skeleton3D` + `PhysicalBoneSimulator3D/PhysicalBone3D`（或分离rigid bodies+joints）实现native受击。air初速度grape7/solid-chain10m/s，vertical casualty5.5或speed>8时6，spin2.3；reducedMotion水平*.65、vertical*.7/spin.7。非致命kick水平.4/vertical.7/lifetime1.25，致命life7、wet expiry1.2；totalcap12。水面支持必须单向：出生水下不向上teleport，先前在water之上的node才可supported；water drag .94/step、deck .985/step、下沉offsetwet*.45m、fade尾.7s。命中event只启动表现，damage/crew loss由naval结算一次。

原articulated solver不是Jolt：18node、12轮distance+hinge约束、parent hard links exact length、整body平移防stretch。保留reference实现/fixtures；Jolt验收比较生命周期/无穿船/无拉伸/方向/水支持/预算/同accepted时间，不承诺每node轨迹位相等。不可同时让旧solver、PhysicalBoneSimulator和AnimationPlayer写相同bones。先动画采样当前pose，复制world rest transform/velocity到physics，暂停clip，Jolt接管；恢复非casualty时回站位并恢复clip。

Godot官方确认：custom_integrator禁用标准force integration但保留collision response；Jolt部分joint soft-limit参数不支持，contact impulse是估计值；raycast face index默认-1（需要时显式enable且有内存成本）。因此不要依赖原Raycaster face index稳定一对一，也不以Jolt estimated impulse直接作为游戏伤害。参考：[RigidBody3D](https://docs.godotengine.org/en/latest/classes/class_rigidbody3d.html)、[Using Jolt Physics](https://docs.godotengine.org/en/latest/tutorials/physics/using_jolt_physics.html)、[PhysicalBoneSimulator3D](https://docs.godotengine.org/en/latest/classes/class_physicalbonesimulator3d.html)。这些为latest文档，应按实际目标4.7安装确认API。

## 8. 可导出reference fixtures及验收顺序

建议fixtures统一JSON schema：`sourceHead,sourceCase,units,initialState,commands[{tick,payload}],samplerId,waveDescriptors,frames[{tick,time,state,debug,events}],assetHashes`。golden必须来自冻结原HEAD运行，不能用Godot新公式先生成自己再验证自己。JS whole-JSON SHA仅用来检验原oracle未变；GodotJSON序列化/浮点格式不同，比较numeric与exact事件字段，不用同digest作为跨语言断言。

| 原case位置 | 可导出内容/现有断言 | Godot关卡 |
| --- | --- | --- |
| `physics-core/test/described-ocean.test.ts` | samples `(0,0,0),(894.671,337.14,0),(23,-15,12.5),(-333,639,150),(1287,-750,1000)`；height/normal，envelope7；空waves、input mutation、invalid各case | CPU sample先通过；独立shader公式采样差与GPU vertex/normal后通过。 |
| `physics-core/test/heave-travel.test.ts` | 600tick静态level0→4；默认root1、扩大heave9后root2.8..3.2；3600tick无limit原SHA `5bea87de40610bed5eab7aa2d08c2a916449f0c7f4c600821e3ee1119316bd17` | scalar数学、四点sample、init offset、rates、clamp。 |
| `naval-core/test/original-wave-heave.test.ts` | 六船/四spawnphase0,6,12,18/60sGLB deck triangle+edge midpoint+centroid；minimum>.05、wetFrames0；reported fisherman tick275；storm/fisher/patrolfullsail14.4m/s | 真实GLB pose与wave alignment；不能只检查rootY。 |
| 同上generic轨迹case | seed1661、wind(-1,.3)9、fuchuan(13,-27)h.4/speed3/rudder.4/deploy.8、首tick前port火；3600tickSHA `0505b19a43bf7af3983fb5ce8cbcdc115b15ccc7d4f76c2448e8aa43b05407d0`（仅排除draftMeters/controlsSequence metadata） | ship动力、炮战、事件时序。 |
| 同上30/60/120callerHz及live装备1→1.3→1 | 12s等snapshot/event；更新不改变当下pose，后120tick等reference、保留4fire与reload/volley | runtime唯一clock、reconcile不重建body。 |
| `physics-core/test/{manual-handling,low-speed-steering,draft-update,horizontal-anchor,projectile-trajectory,cannon-system}.test.ts` | torque/crew/cargo/brake；anchor不改浮力；AP/HE轨迹/dispersion seededLCG/closest TOI | 物理公共API与lab武器。 |
| `physics-core/test/utils/authored-articulated.ts`, `articulated.test.ts` | 18node定义；freeflight/above-water/submerged/expired、30/60/120/2.5Hz batch、12body budget | crew numeric oracle，Jolt行为闸口独立。 |
| `physics-core/test/utils/frozen-sailor-impact.ts`及README | 原历史`c331ffed29b4074c620c14517f18c5f78e310586`byte-exact12236bytes、SHA `6228963c55ea245312fa713b6293ec7f5e1783902cc0ae2cf8e3d44881f9be9c`，独立Three历史oracle | 仅fixture生成/对比用，不带入Godotruntime，不“更新”成新solver。 |
| `naval-core/test/{collision,route-planner,navigation-review,mingqi-shallows,tactical-orders,ambient-ammo,pending-attacks,disabled-motion,surrender}.test.ts` | moving-box旋转、高速/closest目标、完整hull绕岛、route预算、浅滩draft、orders和pending volley投降清除 | naval authority/contacts，先physics headless再Jolt集成。 |
| `apps/game-client/src/simulation/{SailRig,SailorDeckView,SailorImpactPhysics,SailorPhaseContact,CombatVisuals,NavalDeckSupport,wake,assisted-sailing}.test.ts` | mast角、inflate sign、loadeddeck相位、accepted tick暂停/重复、recoil/holes、角色分配、尸体生命周期 | Godot asset import +显示seam；原TStest不等于native运行证据。 |

优先序列：①contracts+float math+原wave/terrain采样与golden；②完整marine numeric solver（无scene）及六船规格；③native naval fixed tick/commands/ballistics/sweeps/ownership/orders/routes；④runtime单时间owner与headless回放；⑤GLB import+pose/rig/wake/crewclips+projectedshader；⑥Jolt shipcontact及crewrig同步，单独collision/ragdoll验收；⑦shore/camera/weather/audio/resource生命周期；⑧完整玩家UI/存档接入后的实际Godot运行验收。任何阶段完成只能声明对应关卡，不以copy资产、解析脚本成功或可开窗替代完整迁移完成。

## 9. 最新优先目标：当前网页海面的独立 native probe

本节覆盖最新 steering：先验证 Godot 能实现当前网页海面，完整游戏移植暂不作为本轮实现范围。以上完整迁移顺序是后续 inventory；本轮实现建议收敛为 `contracts/original_wave_set`、独立 CPU sampler、`scene_engine/water/projected_grid`、native spatial shader 和最小 runtime/camera。probe 不需要提前接入 naval、业务 UI 或 Jolt 船体。不得借探针改五波 amplitude、frequency、phase 或基准 Y0。

精确源入口：`packages/scene-engine/src/config/constants.js:3-47`；`engine/water/ProjectedWaterSurface.js:58-176`；`engine/water/ProjectedWaterShader.js:9-111`；`engine/assets/Assets.js:47-83`；`engine/world/World.js:104-126,132-169,386-390`；`apps/game-client/src/components/adventure/MingqiScene.svelte:172-177,193-194`。本地 `node_modules/three/package.json:3` 为 **0.181.2**，与 game-client exact pin 相同；下述 dependency shader/pass 审计针对该版本。

### 9.1 Projected profile：完整像素数学

原 vertex：world XZ 已由 camera projected grid 写入 identity mesh；在原 Y0 上加第4节波高 H；`vWaveHeight=H`，`vWorldPosition` 为位移后的坐标。GLB/地形高度不是水 shader 的输入。fragment 的 shading normal 来自贴图组合，**没有使用五波 gradient，也没有把 GPU 几何 normal 与纹理法线混合**；physics 的解析 normal 是另一种用途，移植时不能拿它替换原视觉 normal。

以下 T(uv) 表示同一 `waternormals.jpg` 的重复纹理采样，`t` 是注入的秒，`X=worldPosition.xz`，`U=X*.008`。所有 normal 通道均按原 RGB 原值采样，不能用引擎自动 tangent-space normal mapping 代替。

| 项目 | 原公式/常数 | native 对照注意点 |
| --- | --- | --- |
| 三层 normal | `n1=T(U+(t*.015,t*.005)).rgb*2-1`；`n2=T(U*1.6-(t*.02,0)).rgb*2-1`；`n3=T(U*4+(t*.04,t*.04)).rgb*2-1`；`N=normalize(n1+.8*n2+.3*n3+(0,3.5,0))` | 权重、swizzle（原没有 xzy）、Y bias、双轴第三层 drift 均保留。 |
| view/light | `V=normalize(camera-worldPosition)`；`L=normalize(uSunPosition)`；`half=normalize(L+V)` | L 原来取 absolute sun position，不是 position minus target。 |
| Fresnel | `F=pow(1-max(dot(V,(0,1,0)),0),3)` | **用世界 up，不用 N**；远处增强浅色/alpha，无真实反射贴图。 |
| specular | `pow(max(dot(N,half),0),250)*1.5` | 直接白色加到 final RGB；不乘 sunColor、DirectionalLight intensity 或 diffuse。 |
| 深/浅/foam | CONFIG `new THREE.Color('#008991')`、`new THREE.Color('#00b6ad')`、`new THREE.Color(0xffffff)`；shader 对三个 uniform 再 `pow(color,2.2)` | 原存在二次线性化；不能自动“纠正”后声称视觉相同，见9.3。 |
| 波高调色 | `heightFactor=smoothstep(-2,3,H)`；`base=mix(deep,shallow,heightFactor*.6+.1)`；`water=mix(base,shallow*1.2,F*.6)` | H 是该世界点真实几何 wave height，不是 depth/noise。 |
| debris | `Duv=X*.04`；`D1=T(Duv+(t*.025,t*.01)).r`；`D2=T(Duv*.7+(-t*.015,t*.02)).g`；`D=smoothstep(.62,.66,D1)*smoothstep(.40,.80,D2)*(H*.2+.9)`；`water=mix(water,(.95,.98,1),D*.5)` | 白色碎波/漂浮噪声也取 normal 图；原 mix factor 没另 clamp。 |
| crest foam | `noise=T(U*8+(t*.1,t*.1)).r`；`coverage=smoothstep(2,2.3,H*.5+noise*.8)` | 不采样 foam.png；`uShoreFoamIntensity` 声明但未使用，shoreline 已删除（源注释 shoreMask 实际0）。 |
| final RGB | `mix(water,foam,coverage)+(specular,specular,specular)` | RGB 可超过1；让后处理的有/无行为决定显示，不能在 shader 提前 clamp RGB。 |
| 内建 shader fog | `d=length(camera.xz-X)`；`fogFactor=smoothstep(100,1500,d)`；`fogColor=pow((.53,.81,.92),2.2)`；`final=mix(final,fogColor,fogFactor)` | 是水平距离线性 smoothstep，与场景 FogExp2 无关；不要额外套 Godot fog。 |
| alpha | `clamp(.45+F*.5+coverage,0,1)` | 原 transparent=true、depthWrite=false、DoubleSide、renderOrder=1；需要 equivalent alpha blending、保留 depth test、禁止 water depth writes。 |

当前 shader 无 screen/depth sampler、reflection/refraction RTT、环境镜面、shadowmap sampling 或真实水下吸收。浅色 Fresnel 和透明 blend 本身构成当前视觉。把 SSR、屏幕折射、接岸 foam、PBR roughness/specular 加入 probe 都是新效果；先冻结相同输入比对当前 profile，再单独决策这些增强。

### 9.2 纹理、网格与时间的精确 seam

`apps/game-client/public/textures/waternormals.jpg` 是 **1024×1024 RGB**，248813bytes；`foam.png` 是 **512×512 indexed PNG**，16105bytes。`Assets.loadResources()` 加载两者，但 projected 只绑定 `tNormal=Assets.waterTexture`。该 source tree 中 `foamTexture` 仅声明/赋值，不能因为它存在就把 projected foam 改成该图。

`configureTexture` 设置 wrapS/T Repeat、minFilter LinearMipmapLinear、最大可用 anisotropy；Three Texture default magFilter Linear、NoColorSpace（没有给两图指定 sRGB）。native sampler 应采样原 data channels、repeat、mipmap，检查原图与 shader UV 的垂直方向；避免导入器自动识别为 normal map 后 swizzle、invert green、sRGB decode 或压缩重建通道。若原图缺失，source fallback 为1×1 RGB `(128,128,255)`（foam为白），视觉会变化，验收必须确认加载的是原文件。

Projected grid 默认 resolution80，因此81×81 vertices/80×80quads。每个 clip XY 使用 camera inverse projection/world matrix 的 far-NDC ray，与平面Y0相交；视线近水平/向上使用 fallback，远点 clamp 到 maxDistance=3000m（CONFIG.chunkSize250×12）；未给有效maxDistance时 fallback=2500m。原网格 camera/time threshold 都为0，每update重写 world vertex positions，frustumCulled=false。native可用 ArrayMesh CPU更新或等价GPU反投影；检查 horizon、俯视、抬头、侧移及3000m边界，不用普通小 PlaneMesh 替代其 coverage 结论。

时间链为 `MingqiScene` 的 `world.update(consumed,state.time)` → global `uTime=time` → `water.update(camera,time,dt)` → projected material `uTime=timeSeconds`。不是 wall clock、动画累计dt或 Godot shader TIME；`timeSeconds`非有限时原surface置0。probe clock由runtime明确提供，暂停冻结同一个time，seek重新给定time；scene不拥有新accumulator。camera/world/light uniforms必须同一个frame快照，CPU height、GPU vertex、未来wake/crew沿同一t；不得使用屏幕插值时间改变物理计费。

`World.updateChunks()` 使用船position（非flight）或camera作为target：sun world position=`(target.x+300,150,target.z+100)`、target point=`(target.x,0,target.z)`，global `uSunPosition`复制**position**。因此 shader `normalize(uSunPosition)`随绝对target坐标变化，即使实际DirectionalLight方向保持相同。高光 parity probe可同时显示 original position-derived L 和提议的正确固定方向，但原profile默认值必须保留前者；后者属于后续改进，不是无差异移植。

### 9.3 色彩与 pass 协调：当前源码的真实行为

Three 0.181.2 `ColorManagement.enabled=true`、workingColorSpace=LinearSRGB；`Color.setHex/Style`从sRGB转working space。未发现项目禁用此转换。因此 CONFIG 对应数值（四舍五入）为：deep uniform `(0,.250158285,.283148740)`，fragment pow2.2后 `(0,.047432144,.062291989)`；shallow uniform `(0,.467783796,.417885071)`，pow后 `(0,.187974692,.146664526)`；foam白保持1。这是对本地依赖公式的静态计算，不是截图取样。

Godot应选显式 numeric vec3 inputs（或只做一次明确sRGB→linear转换），然后保留 source pow；不能给 Color/source_color uniform 和手工转换一起叠加，再把hex字符串当作raw linear。normal sampler没有 source_color。Projected shader 自己没有 `<tonemapping_fragment>`、`<colorspace_fragment>`、`<fog_fragment>`；Three全局 renderer 设置并不会在它的 `gl_FragColor` 后自动插入这些执行语句。native manual shading应避免再接受引擎的太阳diffuse/specular、环境ambient和fog；RGB/alpha先在独立buffer/探针像素输出中确认。

Mingqi renderer 设置 outputColorSpace=SRGB、ACESFilmicToneMapping、exposure=1、shadowMap PCFSoft。World设置 scene background=`0x87CEEB`、FogExp2同色density=.0012；HemisphereLight sky=`0xffffff`、ground=`0x444444`、intensity=.6；DirectionalLight=`0xfff5e6`、intensity3.5、shadow bias=-.0005、extent±500m。光照影响标准岛/船材质；projected只读sun position，不读这些light colors/intensities/shadows。water自己的fog固定，不继承scene fog density/color。

World composer仅 `RenderPass` → `UnrealBloomPass`，**没有 OutputPass**。bloom阈值=.92、strength=.3、radius=.5；balanced/low关闭，high/legacy开启。依赖路径为 `node_modules/three/examples/jsm/postprocessing/{EffectComposer,RenderPass,UnrealBloomPass}.js`、`shaders/CopyShader.js`、`src/renderers/WebGLRenderer.js:2206-2214`：

- balanced/low：RenderPass是最后enabled pass，直接screen；projected自己的fragment未调用tone/color chunks，直接写shader输出。不能因renderer字段为ACES就声称当前水已应用ACES。
- high/legacy：RenderPass写HalfFloat composer buffer；WebGLRenderer对普通非screen RT不用ACES。Bloom以MeshBasicMaterial先把input buffer渲到screen（该标准材质执行tone/colorspace），随后threshold/多级blur/composite通过CopyShader additive写screen；CopyShader只 `gl_FragColor=opacity*texel`，无tone/color转换。因此质量档可能改变水的总体色调及高光呈现，并非只多一点glow。

Godot probe应固定质量档并分别保存balanced与high两种reference，输出raw manual water与完整frame各一张，避免把Godot Environment的ACES/glow当成同一Three pass链。尤其透明水混合时background/terrain色域与water色域要一起核对；单独看water ALBEDO正确不保证合成frame相同。上述为source可推导行为，原网页/GPU截图与native像素尚未在本次只读审计运行验证。

天气 `WeatherVisuals.ts:52-143` 明确保证 original projected water/shared sun inputs不改。storm background=`#596b75`、fog=`#798b92`；sphere sky horizon=`#798b92`、zenith=`#35434b`，cloud noise两尺度权重.65/.35、drift秒*.006/.003、brightness .72..1.18；Hemisphere intensity乘.8、Directional乘.3；scene fog density=`baseline/clamp(visibility,.15,1)`；雨线=`#c4d1d7`、alpha.32。projected仍维持上述水色、高光和自算fog。storm sky/rain时间原以accepted dt cap.1累积，与water的显式state.time不同；迁移runtime应明确提供视觉clock，不让scene再次拥有游戏clock。

### 9.4 OriginalWaterSurface：另一个可选镜面 profile

`OriginalWaterSurface.js:11-39` 的 Water.js plane为8000m×8000m、256×256segments、rotationX=-π/2；baseY=`CONFIG.waterLevel*150-75=15m`，default height偏移0。**没有五波vertex位移**，camera移动时plane XZ跟随camera。不要用它来代表当前projected，更不能把原五波CPU改成这一平面。默认params由 `constants.js:432-505` 设定：alpha .85、distortionScale4、size1.4、flowSpeed1、waterColor=`#0f7d99`、sunColor白；constructor的CONFIG deep color随后被applyParams覆盖。

Water.js `getNoise(X*size)` 四层 UV：`uv0=uv/103+(t/17,t/29)`；`uv1=uv/107-(t/-19,t/31)`；`uv2=uv/(8907,9803)+(t/101,t/97)`；`uv3=uv/(1091,1027)-(t/109,t/-113)`；noise=`.5*sum(T(uv0..3))-1`，surfaceNormal=`normalize(noise.xzy*(1.5,1,1.5))`。与projected不同，有xzy swizzle。

Original独立sun light：reflect(-sunDirection,N)，specular=`max(dot(V,reflection),0)^100*sunColor*2`；diffuse=`max(dot(sunDirection,N),0)*sunColor*.5`。distortion=`N.xz*(.001+1/distance)*4`，reflectionSample来自mirrorCoord投影UV+distortion；theta=`max(dot(V,N),0)`，Fresnel=`.3+.7*(1-theta)^5`；scatter=`max(dot(N,V),0)*waterColor`；albedo=`mix((sunColor*diffuse*.3+scatter)*shadowMask,(.1+reflection*.9+reflection*specular),Fresnel)`。输出alpha恒.85，再执行tone/colorspace/fog chunks。`time=runtimeTime*flowSpeed`，sunDirection复制global sun position并normalize；同样继承原absolute-position问题。没有foam.png、shore foam、refraction或五波height。

反射是1024²平面RTT。`Water.onBeforeRender`从water world plane反射当前camera position、target/up，复制projection并写oblique clip plane；构造bias*projection*view textureMatrix；临时隐藏water避免递归、关闭XR和shadowAutoUpdate、render scene到mirror target，再恢复target/visibility/viewport/state。native若保留这一profile需独立SubViewport/镜面camera/clip与visibility layer协调，screen texture或ReflectionProbe不自动等价。source Water ShaderMaterial 默认transparent=false/depthWrite=true；wrapper没有改变，只把uniform alpha设.85，因此实际blend行为不同于ProjectedWaterSurface的transparent true。constructor传的`format=outputColorSpace`字段也未被该Water.js读取，不应翻译成nativeRT格式设置。

### 9.5 海面 probe 的最小验收数据

保留第8节5个height/normal采样点，另取时刻0/6/12/18及camera低斜角/高俯视/抬头、origin/远处XZ。导出每frame `waveDescriptors,time,cameraTransform,sunPosition,quality,shaderColors,textureHashes`；CPU用第4节独立展开式算height，GPU只比较相同world点vertex高度与插值误差，不拿fragment贴图normal作为physics normal oracle。

检查顺序：①五波CPU parity与7m envelope；②native projected coverage和uniform freeze/seek；③原normal纹理采样方向、normal三层/debris/foam每项单独显示；④raw final RGB/alpha与fog，尤其高光和远处透明；⑤同一camera/背景/地形、balanced和high的完整pass/混合截图；⑥暂停/长时间seek/不同callerHz不改变给定time结果。compile/import成功、能显示蓝色plane或图片相似均不能代替这些数值和视觉证据。该审计止于文档，后续probe实现/运行验证由主任务继续。
