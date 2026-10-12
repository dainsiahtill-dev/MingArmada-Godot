extends Control
## Visual baseline only. No campaign, ports, artificial channels or save writes.
const Field=preload("res://modules/scene_engine/terrain/natural_island_field.gd")
const Terrain=preload("res://modules/scene_engine/terrain/natural_island_mesh.gd")
const Ocean=preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const Shore=preload("res://modules/scene_engine/ocean/shore_field.gd")
const Waves=preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Descriptors=preload("res://modules/contracts/wave_descriptor.gd")
const Trees=preload("res://modules/scene_engine/fidelity_island/vegetation.gd")
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Encounter=preload("res://modules/naval_simulation/encounter.gd")
var ready_receipt:={"ok":false}
var field: RefCounted
var terrain: Node3D
var ocean: MeshInstance3D
var trees: Node3D
var ship: Node3D
var camera: Camera3D
var view: SubViewport
var stage: Node3D
var waves: RefCounted
var shore: RefCounted
var seed_value:=1661
var seconds:=12.0
var paused:=false
var orbit:={"yaw":-0.38,"elevation":0.69,"distance":850.0}
var focus:=Vector3(0,12,0)
var forest_visible:=true
var _dragging:=false
var _disposed:=false
var _label: Label
var _packet: Dictionary={}
var _forest_pattern: FastNoiseLite
func _ready() -> void:
	_build_ui(); _build_world()
func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column:=VBoxContainer.new(); column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(column)
	var toolbar:=HBoxContainer.new(); toolbar.add_theme_constant_override("separation",14); column.add_child(toolbar)
	var title:=Label.new(); title.text="海上明旗 · 自然海岛实景"; title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; toolbar.add_child(title)
	for seed_number in [1661,1662,1663]:
		var button:=Button.new(); button.text="海岛 %d" % seed_number
		button.pressed.connect(func(): seed_value=seed_number; _clear_world(); _build_world()); toolbar.add_child(button)
	var forest:=Button.new(); forest.text="显示地形"; forest.pressed.connect(func(): forest_visible=not forest_visible; forest.text="显示地形" if forest_visible else "显示森林"; _render()); toolbar.add_child(forest)
	var pause:=Button.new(); pause.text="暂停"; pause.pressed.connect(func(): paused=not paused; pause.text="继续" if paused else "暂停"); toolbar.add_child(pause)
	var container:=SubViewportContainer.new(); container.stretch=true; container.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(container)
	view=SubViewport.new(); view.size=Vector2i(1600,900); view.msaa_3d=Viewport.MSAA_4X; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; view.world_3d=World3D.new(); container.add_child(view)
	stage=Node3D.new(); view.add_child(stage)
	container.gui_input.connect(_view_input)
	_label=Label.new(); column.add_child(_label)
func _build_world() -> void:
	_disposed=false; ready_receipt={"ok":false}
	field=Field.new()
	if not field.configure({"seed":seed_value,"radius":220.0,"peak":58.0,"resolution":257}): _fail("自然地形生成失败"); return
	terrain=Terrain.new(); stage.add_child(terrain)
	if not terrain.configure(field): _fail("自然地形网格生成失败"); return
	var environment:=WorldEnvironment.new(); stage.add_child(environment)
	var settings:=Environment.new(); settings.background_mode=Environment.BG_COLOR; settings.background_color=Color("87c8e6")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color=Color("b3d2cf"); settings.ambient_light_energy=0.55
	settings.tonemap_mode=Environment.TONE_MAPPER_LINEAR; settings.tonemap_exposure=1.0; settings.fog_enabled=false
	environment.environment=settings
	var sun:=DirectionalLight3D.new(); sun.basis=Basis.looking_at(-Vector3(-.5,.8,.3).normalized(),Vector3.UP); sun.light_color=Color(1,.95,.82); sun.light_energy=1.1; sun.shadow_enabled=true; stage.add_child(sun)
	camera=Camera3D.new(); camera.fov=49.0; camera.near=.5; camera.far=5000.0; stage.add_child(camera); camera.current=true; _camera_pose()
	ocean=Ocean.new(); stage.add_child(ocean)
	ocean.configure(camera,load("res://assets/textures/waternormals.jpg"),96,3000.0)
	ocean.set_wave_descriptors(Descriptors.original_descriptors()); ocean.set_visual_style(1); ocean.set_surface_quality("high")
	ocean.configure_reflection(camera); ocean.enable_surface_optics(true); ocean.set_projection_padding(.10)
	shore=Shore.new()
	if not shore.configure(field.sample_triangle_height,field.bounds(),257): _fail("自然岸线生成失败"); return
	ocean.set_shore_field(shore.get_texture(),shore.get_bounds(),shore.get_coast_texture())
	ocean.set_near_shore_field(shore.get_texture(),shore.get_bounds())
	ocean.material_override.set_shader_parameter("mask_dry_terrain",true)
	ocean.material_override.set_shader_parameter("display_fog_density",.00035)
	ocean.material_override.set_shader_parameter("surface_visual_scale",1.0)
	var sky_material: ShaderMaterial=ocean.get_sky_material()
	if sky_material!=null:
		var sky:=Sky.new(); sky.sky_material=sky_material; settings.sky=sky; settings.background_mode=Environment.BG_SKY
	camera.environment=settings
	waves=Waves.new(); waves.configure(field.sample_triangle_height,Descriptors.original_descriptors())
	trees=Trees.new(); stage.add_child(trees)
	_forest_pattern=FastNoiseLite.new(); _forest_pattern.seed=seed_value+9217; _forest_pattern.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH; _forest_pattern.frequency=.022; _forest_pattern.fractal_octaves=2
	# This mapping spaces original 3D canopy prototypes across new terrain;
	# it supplies no source island heightmap, harbor or material mask.
	var mapping:={"id":"natural","width":329,"height":193,"sourceCenter":Vector2(164,96),"sourceOutward":Vector2.RIGHT,"islandCenter":Vector2.ZERO,"inward":Vector2.LEFT,"scale":2.3}
	if not trees.configure(mapping,_forest_ground,{"mode":"mapped","adaptive_population":true,"forest_spacing":5.8,"forest_seed":seed_value,"canopy_height":10.0,"palm_height":13.0,"forest_min_height":2.0,"forest_max_slope":1.1}): _fail("原始三维植被生成失败"); return
	ship=Ship.new(); stage.add_child(ship)
	if not ship.configure("fuchuan"): _fail("旗舰模型加载失败"); return
	var encounter:=Encounter.new({"mode":"continuous","sampleTerrainHeight":field.sample_triangle_height,"waveSampler":waves,"wind":{"direction":{"x":-1.0,"y":0.0},"speed":12.0},"ships":[{"id":"player","kind":"fuchuan","team":"player","crew":36.0,"position":{"x":-270.0,"z":-210.0},"heading":.7,"sailDeployment":.8}]})
	if encounter.snapshot().ships.is_empty(): _fail("旗舰状态初始化失败："+encounter.last_error); return
	_packet=encounter.snapshot().ships[0].duplicate(true)
	ready_receipt={"ok":true,"scope":"Independent natural-island visual baseline; no campaign or save writes"}
	_render()
func _forest_ground(x: float,z: float) -> float:
	var h: float=field.sample_triangle_height(x,z)
	if not is_finite(h) or h<2.0: return NAN
	var dx: float=(field.sample_triangle_height(x+1,z)-field.sample_triangle_height(x-1,z))*.5
	var dz: float=(field.sample_triangle_height(x,z+1)-field.sample_triangle_height(x,z-1))*.5
	var grade:=Vector2(dx,dz).length()
	# Reserve visible rock on exposed upper ridges, and coherent small clearings.
	# Accepted roots keep the exact same terrain height; no ground is moved.
	if h>42.0 or h>24.0 and grade>.36: return NAN
	if h>6.0 and _forest_pattern.get_noise_2d(x,z)>.31: return NAN
	return h
func _camera_pose() -> void:
	if not is_instance_valid(camera): return
	var distance: float=orbit.distance; var yaw: float=orbit.yaw; var elevation: float=orbit.elevation
	camera.position=focus+Vector3(sin(yaw)*cos(elevation)*distance,sin(elevation)*distance,-cos(yaw)*cos(elevation)*distance); camera.look_at(focus,Vector3.UP)
func _render() -> void:
	if _disposed or not ready_receipt.get("ok",false): return
	_camera_pose(); ocean.set_surface_wind(Vector2(-1,0),12.0); ocean.set_simulation_time(seconds); ocean.update_projection()
	terrain.sync_surface_state(ocean.material_override,{"time":seconds})
	trees.apply_snapshot({"time":seconds,"visible":forest_visible,"lighting":{"lightDirection":Vector3(.5,-.8,-.3).normalized(),"lightColor":Vector3(1,.95,.82),"ambient":Vector3(.35,.40,.30),"customFog":false}})
	var packet:=_packet.duplicate(true); packet.time=seconds
	packet.visual.position.y=waves.sample_height(float(packet.visual.position.x),float(packet.visual.position.z),seconds)
	ship.apply_snapshot(packet,{"direction":{"x":-1.0,"y":0.0},"speed":12.0},0.0)
	_label.text="自然山脊 · 原始三维树木 · 保留旧海水 · 拖动环绕 / 滚轮缩放"
func _process(delta: float) -> void:
	if not paused and not _disposed and get_window().has_focus(): seconds+=minf(maxf(delta,0.0),.05)
	_render()
func _view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT: _dragging=event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: orbit.distance=clampf(float(orbit.distance)*(.86 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.16),250,1800)
	elif event is InputEventMouseMotion and _dragging:
		orbit.yaw=float(orbit.yaw)-event.relative.x*.006; orbit.elevation=clampf(float(orbit.elevation)+event.relative.y*.004,.25,1.40)
func inspect() -> Dictionary:
	return {"scope":"Visual baseline; formal game terrain is not switched","ready":ready_receipt.duplicate(true),"seed":seed_value,"time":seconds,"orbit":orbit.duplicate(),"focus":focus,"terrain":field.get_diagnostics(),"forest":trees.diagnostics(),"sea":"retained five-wave reference_game_water","artificial_channels":false,"ports":0}
func _fail(message: String) -> void:
	ready_receipt={"ok":false,"reason":message}; _label.text=message; printerr(message); set_process(false)
func _clear_world() -> void:
	ready_receipt={"ok":false}
	if is_instance_valid(trees): trees.dispose()
	if is_instance_valid(ship): ship.dispose()
	if is_instance_valid(terrain): terrain.dispose()
	for node in stage.get_children(): node.free()
	field=null; terrain=null; ocean=null; trees=null; ship=null; camera=null; waves=null; shore=null; _forest_pattern=null; _packet.clear()
func dispose() -> void:
	if _disposed: return
	_disposed=true; set_process(false)
	if is_instance_valid(stage): _clear_world()
func _exit_tree() -> void: dispose()
