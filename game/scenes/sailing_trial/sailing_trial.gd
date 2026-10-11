extends Node3D
## Playable native migration checkpoint. F6 runs independently of the ocean lab.

const Runtime = preload("res://game/runtime/sailing_runtime.gd")
const HeightField = preload("res://modules/scene_engine/terrain/height_field.gd")
const WorldView = preload("res://modules/scene_engine/world/world_view.gd")
const ShipView = preload("res://game/presentation/ships/ship_view.gd")
const Hud = preload("res://game/ui/sailing_hud.gd")
const WaveDescriptor = preload("res://modules/contracts/wave_descriptor.gd")
const CrewView = preload("res://game/presentation/crew/crew_view.gd")

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

func _ready() -> void:
	DisplayServer.window_set_title("海上明旗 · Godot 航行迁移")
	Engine.physics_ticks_per_second = 120
	get_viewport().msaa_3d = Viewport.MSAA_4X
	capture_mode = "--capture" in OS.get_cmdline_user_args()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/water-probe-terrain.json"))
	if not parsed is Dictionary or not parsed.get("ports") is Array:
		push_error("Invalid source geography fixture")
		get_tree().quit(1)
		return
	heights.configure_ports(parsed.ports)
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
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://assets/textures/waternormals.jpg"))
	image.generate_mipmaps()
	if not world.configure(heights.sample_height, WaveDescriptor.original_descriptors(), {"camera": camera, "normal_texture": ImageTexture.create_from_image(image), "ports": parsed.ports, "resolution": 64, "chunk_radius": 2, "collision": false, "visual_style": 1}):
		push_error("World composition failed")
		get_tree().quit(1)
		return
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
	hud = Hud.new()
	add_child(hud)
	hud.command_requested.connect(runtime.command)
	hud.view_requested.connect(func(value: bool): tactical = value)
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
	hud.apply_snapshot(previous)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
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
	if is_instance_valid(crew): crew.dispose()
	if is_instance_valid(world): world.dispose()
	if is_instance_valid(ship): ship.dispose()
