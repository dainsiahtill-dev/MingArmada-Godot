extends Node3D
## Playable native migration checkpoint. F6 runs independently of the ocean lab.

const Runtime = preload("res://game/runtime/sailing_runtime.gd")
const HeightField = preload("res://modules/scene_engine/terrain/height_field.gd")
const WorldView = preload("res://modules/scene_engine/world/world_view.gd")
const ShipView = preload("res://game/presentation/ships/ship_view.gd")
const Hud = preload("res://game/ui/sailing_hud.gd")
const WaveDescriptor = preload("res://modules/contracts/wave_descriptor.gd")
const CrewView = preload("res://game/presentation/crew/crew_view.gd")
const SeaChartOverlay = preload("res://game/scenes/common/sea_chart_overlay.gd")
const NauticalChart = preload("res://game/ui/charts/nautical_chart.gd")
const Wakes = preload("res://game/presentation/water/wake_trails.gd")
const WaterPacket = preload("res://game/presentation/world/source_water_packet.gd")
const ShadowRenderer = preload("res://modules/scene_engine/fidelity_fx/source_shadow_renderer.gd")
const RigidCasters = preload("res://game/presentation/world/target_rigid_shadow_caster.gd")

var runtime := Runtime.new()
var heights := HeightField.new()
var world: Node3D
var ship: Node3D
var camera: Camera3D
var hud: CanvasLayer
var tactical := false
var capture_mode := false
var capture_index := 0
var previous: Dictionary
var crew: Node3D
var mini_chart: CanvasLayer
var chart_layer: CanvasLayer
var expanded_chart: Control
var chart_caption: Label
var chart_close: Button
var chart_open := false
var _pause_before_chart := false
var wakes: Node3D
var source_shadows: RefCounted
var _rigid_casters := RigidCasters.new()
var _shadow_capability: Dictionary = {}
var _sun: DirectionalLight3D

func _ready() -> void:
	DisplayServer.window_set_title("海上明旗 · Godot 航行迁移")
	Engine.physics_ticks_per_second = 120
	get_viewport().msaa_3d = Viewport.MSAA_4X
	capture_mode = "--capture" in OS.get_cmdline_user_args()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	if not parsed is Array:
		push_error("Invalid sailing geography")
		get_tree().quit(1)
		return
	heights.configure_ports(parsed,true,preload("res://game/scenes/common/reference_geography.gd").options())
	if not runtime.configure(heights.sample_height):
		push_error("Native ship solver configuration failed")
		get_tree().quit(1)
		return
	var environment := WorldEnvironment.new()
	var lighting := Environment.new()
	lighting.background_mode = Environment.BG_COLOR
	lighting.background_color = Color("87ceeb")
	lighting.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	lighting.ambient_light_color = Color("a0c8ff")
	lighting.ambient_light_energy = 0.65
	lighting.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = lighting
	add_child(environment)
	var sun := DirectionalLight3D.new()
	_sun=sun
	add_child(sun)
	sun.position = Vector3(300, 150, 100)
	sun.look_at(Vector3.ZERO)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.fov = 55
	camera.far = 4000
	camera.near = 0.5
	_update_camera(runtime.snapshot())
	world = WorldView.new()
	add_child(world)
	if not world.configure(heights.sample_height, WaveDescriptor.original_descriptors(), {"camera": camera, "ports": parsed, "resolution": 64, "chunk_radius": 2, "collision": false, "visual_style": 1}):
		push_error("World composition failed")
		get_tree().quit(1)
		return
	world.bind_environment(lighting,sun)
	var sky_material:ShaderMaterial=world.get_ocean().get_sky_material()
	if sky_material:
		var sky:=Sky.new();sky.sky_material=sky_material;lighting.sky=sky;lighting.background_mode=Environment.BG_SKY
	camera.environment=lighting
	ship = ShipView.new()
	add_child(ship)
	if not ship.configure("fuchuan"):
		get_tree().quit(1)
		return
	crew = CrewView.new()
	ship.add_child(crew)
	if not crew.configure("fuchuan", ship.get_model()):
		push_error("Original crew model/deck initialization failed")
		get_tree().quit(1)
		return
	crew.set_environment(runtime.sample_water_height)
	wakes=Wakes.new();add_child(wakes);wakes.configure(runtime.sample_water_height)
	wakes.configure_surface_filter(func(x:float,z:float)->bool:return heights.sample_height(x,z)<0.0)
	if heights.has_method("begin_sampling_scope"):wakes.configure_sampling_scope(Callable(heights,"begin_sampling_scope"))
	source_shadows=ShadowRenderer.new();_shadow_capability=source_shadows.configure(self,camera)
	hud = Hud.new()
	add_child(hud)
	hud.command_requested.connect(_trial_command)
	hud.view_requested.connect(func(value: bool): tactical = value)
	_configure_charts(parsed)
	_apply_snapshot(0.0)
	if capture_mode:
		if "--shore-loop" in OS.get_cmdline_user_args(): _capture_shore_loop.call_deferred()
		else: _capture_route.call_deferred()

func _physics_process(delta: float) -> void:
	if not world or capture_mode: return
	var current: Dictionary = runtime.snapshot()
	if not current.paused:
		var turn := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		runtime.command({"type": "turn", "value": turn})
		var change := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
		runtime.command({"type": "sail", "value": current.ship.sailDeployment + change * delta * 0.35})
		var trim := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
		runtime.command({"type": "trim", "value": current.ship.sailAngle + trim * delta * 0.5})
	var consumed := runtime.advance(delta)
	_apply_snapshot(consumed)

func _update_camera(state: Dictionary) -> void:
	var point: Dictionary = state.ship.position
	var target := Vector3(point.x, point.y + 3, point.z)
	camera.position = target + (Vector3(80, 115, -110) if tactical else Vector3(33, 24, -39))
	camera.look_at(target)

func _apply_snapshot(consumed: float) -> void:
	previous = runtime.snapshot()
	_update_camera(previous)
	world.apply_snapshot(previous, consumed)
	ship.apply_snapshot(previous.ship, previous.wind, consumed)
	ship.set_lod_distance(camera.position.distance_to(ship.position))
	if crew:
		crew.set_ship_model(ship.get_model())
		crew.set_lod_distance(camera.position.distance_to(ship.position))
		crew.apply_snapshot(previous.ship, previous.wind, consumed)
	var state:Dictionary=previous.ship.duplicate(true)
	state.id="trial-player";state.time=previous.time
	var native:={"time":previous.time,"environment":previous.get("environment",{}),"ships":[state]}
	var actors:={"trial-player":ship}
	if wakes:wakes.apply_snapshot(WaterPacket.compose(native,actors,camera))
	if source_shadows:
		var gpu:Dictionary=source_shadows.diagnostics().get("gpu",{})
		var stencil_active:=bool(_shadow_capability.get("activeCompositor",false)) and bool(gpu.get("initialized",false)) and str(gpu.get("error","")).is_empty()
		var packet:=_rigid_casters.compose(native,actors,-_sun.global_basis.z,stencil_active)
		source_shadows.apply_snapshot(packet.native,packet.actors,native.environment)
	hud.apply_snapshot(previous)
	_present_charts(previous)

func _configure_charts(ports: Array) -> void:
	mini_chart = SeaChartOverlay.new()
	add_child(mini_chart)
	mini_chart.configure(ports,heights.sample_height)
	mini_chart.chart_requested.connect(func(): _set_chart_open(true))
	chart_layer = CanvasLayer.new(); chart_layer.layer = 28; add_child(chart_layer)
	var backdrop := ColorRect.new(); backdrop.name = "trial_chart_backdrop"
	backdrop.color = Color(0.025,0.065,0.07,0.86)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chart_layer.add_child(backdrop)
	expanded_chart = NauticalChart.new(); expanded_chart.name = "trial_chart"
	chart_layer.add_child(expanded_chart)
	expanded_chart.configure(ports,heights.sample_height,{"title":"大明沿海航图"})
	# Trial runtime has no Navigator. Geographic display never emits route intent.
	expanded_chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chart_caption = Label.new(); chart_caption.text = "试航模式 · 航位显示"
	chart_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chart_caption.add_theme_color_override("font_color",Color("f0d6a1"))
	chart_caption.add_theme_font_size_override("font_size",20)
	chart_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chart_layer.add_child(chart_caption)
	chart_close = Button.new(); chart_close.name = "trial_chart_close"
	chart_close.text = "关闭海图  ·  M / Esc"
	chart_layer.add_child(chart_close)
	chart_close.pressed.connect(func(): _set_chart_open(false))
	# The chart recalculates its intrinsic minimum after width changes.
	expanded_chart.minimum_size_changed.connect(_layout_chart)
	get_viewport().size_changed.connect(_layout_chart)
	chart_layer.hide(); _layout_chart()

func _chart_native(state: Dictionary) -> Dictionary:
	return {"playerId":"trial","ships":[{"id":"trial","team":"player","visual":{"position":state.ship.position.duplicate(true),"heading":state.ship.heading}}]}

func _present_charts(state: Dictionary) -> void:
	if not mini_chart: return
	var native := _chart_native(state)
	mini_chart.present(native,{},chart_open or not hud.visible)
	if expanded_chart: expanded_chart.apply_naval_snapshot(native)

func _set_chart_open(value: bool) -> void:
	if not chart_layer or value == chart_open: return
	chart_open = value
	if value:
		_pause_before_chart = bool(runtime.snapshot().paused)
		runtime.command({"type":"pause","value":true})
	else:
		runtime.command({"type":"pause","value":_pause_before_chart})
	chart_layer.visible = value
	_layout_chart()
	_present_charts(runtime.snapshot())

func _layout_chart() -> void:
	if not expanded_chart: return
	var viewport := get_viewport().get_visible_rect().size
	# Reserve caption and close control; preserve chart aspect on smaller windows.
	var width := maxf(160,minf(622,minf(viewport.x-48,(viewport.y-190)*NauticalChart.DEFAULT_BOUNDS.size.x/NauticalChart.DEFAULT_BOUNDS.size.y+44)))
	expanded_chart.size = Vector2(width,maxf(300,minf(500,(width-44)*NauticalChart.DEFAULT_BOUNDS.size.y/NauticalChart.DEFAULT_BOUNDS.size.x+86)))
	var top := maxf(12,(viewport.y-expanded_chart.size.y-84)/2)
	expanded_chart.position = Vector2((viewport.x-width)/2,top+36)
	chart_caption.position = Vector2(expanded_chart.position.x,top)
	chart_caption.size = Vector2(width,28)
	chart_close.position = Vector2(expanded_chart.position.x,expanded_chart.position.y+expanded_chart.size.y+10)
	chart_close.size = Vector2(width,38)

func _trial_command(intent: Dictionary) -> void:
	if chart_open: return
	runtime.command(intent)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var code: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if code == KEY_M:
		_set_chart_open(not chart_open)
		get_viewport().set_input_as_handled()
	elif chart_open and code in [KEY_ESCAPE,KEY_SPACE]:
		if code == KEY_ESCAPE: _set_chart_open(false)
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode if event.physical_keycode != 0 else event.keycode:
		KEY_SPACE: runtime.command({"type": "pause"})
		KEY_1: tactical = false
		KEY_2: tactical = true
		KEY_F12: _capture("manual-%d" % Time.get_unix_time_from_system())
		KEY_ESCAPE: get_tree().quit()

func _capture_route() -> void:
	for phase in 3:
		for tick in 120 * 10:
			runtime.command({"type": "turn", "value": 0.0 if phase != 1 else 0.5})
			runtime.advance(Runtime.STEP)
		_apply_snapshot(10.0)
		for frame in 8: await get_tree().process_frame
		await _capture("route-%d" % phase)
	tactical = true
	_apply_snapshot(0.0)
	for frame in 8: await get_tree().process_frame
	await _capture("tactical")
	print("NATIVE_SAILING_CAPTURE_COMPLETE ", JSON.stringify(runtime.snapshot()))
	get_tree().quit()

func _capture_shore_loop() -> void:
	tactical = true
	get_window().size = Vector2i(1000, 562)
	# Same real runtime and terrain; a fixed camera makes shore animation visible.
	for frame in 24:
		for tick in 30: runtime.advance(Runtime.STEP)
		_apply_snapshot(0.25)
		camera.position = Vector3(-215, 64, -76)
		camera.look_at(Vector3(-365, 1, -48))
		world.apply_snapshot(previous, 0.0)
		for settle in 2: await get_tree().process_frame
		await _capture("shore-loop-%02d" % frame)
	get_tree().quit()

func _capture(label: String) -> void:
	var directory := "res://docs/migration/evidence/sailing-trial"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		get_tree().quit(1)
		return
	await RenderingServer.frame_post_draw
	var pixels := get_viewport().get_texture().get_image()
	if pixels.save_png(directory + "/" + label + ".png") != OK:
		get_tree().quit(1)
		return
	var file := FileAccess.open(directory + "/" + label + ".json", FileAccess.WRITE)
	if file == null:
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify({"engine": Engine.get_version_info(), "gpu": RenderingServer.get_video_adapter_name(), "snapshot": runtime.snapshot(), "tactical": tactical, "camera": str(camera.global_transform), "utc": Time.get_datetime_string_from_system(true)}, "\t"))
	print("NATIVE_SAILING_VIEWPORT_SAVED ", label)

func _exit_tree() -> void:
	if source_shadows:source_shadows.dispose()
	_rigid_casters.dispose()
	if is_instance_valid(wakes):wakes.dispose()
	if chart_open: runtime.command({"type":"pause","value":_pause_before_chart})
	if is_instance_valid(mini_chart): mini_chart.dispose()
	if is_instance_valid(expanded_chart): expanded_chart.dispose()
	if is_instance_valid(crew): crew.dispose()
	if is_instance_valid(world): world.dispose()
	if is_instance_valid(ship): ship.dispose()
