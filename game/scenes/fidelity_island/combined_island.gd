extends Control
## The actual game's shared natural world, retained sea and source surf.
signal main_menu_requested
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Geography = preload("res://game/scenes/common/reference_geography.gd")
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const WaveField = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Waves = preload("res://modules/contracts/wave_descriptor.gd")
var startup_options: Dictionary = {}
var startup_receipt: Dictionary = {"ok":false}
var seconds := 12.0
var paused := false
var sea: Node3D
var world: Node3D
var camera: Camera3D
var view: SubViewport
var heights := Height.new()
var waves := WaveField.new()
var orbit := {"yaw":-0.18,"elevation":0.72,"distance":490.0}
var focus := Vector3(-415.0,5.0,-45.0)
var _packet: Dictionary = {}
var _disposed := false
var _dragging := false
var _status: Label
func _ready() -> void:
	_build_ui()
	var geography: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/reference/mingqi-geography.json"))
	if not heights.configure_ports(geography.ports,true,Geography.options()): _fail("海岛生成失败"); return
	if not waves.configure(heights.sample_height,Waves.original_descriptors()): _fail("原海面初始化失败"); return
	var encounter := Encounter.new({"mode":"continuous","sampleTerrainHeight":heights.sample_height,"waveSampler":waves,"wind":{"direction":{"x":-1.0,"y":0.0},"speed":12.0},"ships":[{"id":"player","kind":"fuchuan","team":"player","crew":36.0,"position":{"x":-230.0,"z":-45.0},"heading":0.8,"sailDeployment":0.8}]})
	_packet = encounter.snapshot()
	view.world_3d = World3D.new()
	sea = Sea.new(); view.add_child(sea)
	if not sea.configure(heights.sample_height,geography.ports,_water,_packet,{"quality":"high"}): _fail("组合海岛场景初始化失败"); return
	world = sea.world; camera = sea.camera
	sea.apply_settings({"cameraFollow":false,"cameraShake":0.0,"quality":"high"})
	sea.set_camera_controller(_update_camera)
	startup_receipt = {"ok":true,"mode":"fidelity-island","source":"shared natural game terrain + retained five-wave sea + source surf"}
	_render()
	if not startup_options.get("staged",false): activate_entry()
func _water(x: float,z: float,time: float) -> float: return waves.sample_height(x,z,time)
func _render() -> void:
	if _disposed or not startup_receipt.ok: return
	var packet := _packet.duplicate(true); packet.time = seconds
	for ship: Dictionary in packet.ships:
		var p: Dictionary = ship.visual.position
		p.y = _water(float(p.x),float(p.z),seconds)
		var gradient: Vector2=waves.sample(float(p.x),float(p.z),seconds).gradient
		var forward:=Vector2(cos(float(ship.visual.heading)),sin(float(ship.visual.heading)))
		ship.visual.pitch=atan(gradient.dot(forward))
		ship.visual.heel=atan(gradient.dot(Vector2(-forward.y,forward.x)))
	sea.apply_snapshot(packet,[],0.0)
	_status.text = "新海岛与森林 · 原海水 · 动态岸浪 · 拖动环绕 / 滚轮缩放"
func _update_camera() -> void:
	if not is_instance_valid(camera): return
	var distance := float(orbit.distance); var yaw := float(orbit.yaw); var elevation := float(orbit.elevation)
	camera.position = focus+Vector3(sin(yaw)*cos(elevation)*distance,sin(elevation)*distance,-cos(yaw)*cos(elevation)*distance)
	camera.look_at(focus,Vector3.UP)
func _process(delta: float) -> void:
	if not paused and not _disposed and get_window().has_focus(): seconds += minf(maxf(delta,0.0),0.05)
	_render()
func _view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: _dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			orbit.distance = clampf(float(orbit.distance)*(0.86 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.16),100.0,1600.0); _update_camera()
	elif event is InputEventMouseMotion and _dragging:
		orbit.yaw = float(orbit.yaw)-event.relative.x*0.006
		orbit.elevation = clampf(float(orbit.elevation)+event.relative.y*0.004,0.20,1.35); _update_camera()
func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new(); column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(column)
	var toolbar := HBoxContainer.new(); toolbar.add_theme_constant_override("separation",16); column.add_child(toolbar)
	var title := Label.new(); title.text = "海上明旗 · 海岛与航海实景"; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; toolbar.add_child(title)
	for entry in [["厦门",Vector3(-415,5,-45),490.0],["金门",Vector3(420,5,160),420.0],["列岛",Vector3(-60,5,390),270.0]]:
		var button := Button.new(); button.text = entry[0]
		var point: Vector3 = entry[1]; var distance: float = entry[2]
		button.pressed.connect(func(): focus = point; orbit.distance = distance; _render()); toolbar.add_child(button)
	var pause := Button.new(); pause.text = "暂停"; pause.pressed.connect(func(): paused = not paused; pause.text = "继续" if paused else "暂停"); toolbar.add_child(pause)
	var back := Button.new(); back.text = "返回"; back.pressed.connect(func(): main_menu_requested.emit()); toolbar.add_child(back)
	var container := SubViewportContainer.new(); container.stretch = true; container.size_flags_vertical = Control.SIZE_EXPAND_FILL; column.add_child(container)
	view = SubViewport.new(); view.size = Vector2i(1280,720); view.msaa_3d = Viewport.MSAA_4X; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; container.add_child(view)
	container.gui_input.connect(_view_input)
	_status = Label.new(); column.add_child(_status)
func activate_entry() -> void:
	if startup_receipt.ok: camera.make_current(); get_window().title = "海上明旗 · 新海岛与原海水"; _render()
func inspection_snapshot() -> Dictionary:
	return {"startup":startup_receipt.duplicate(true),"time":seconds,"paused":paused,"orbit":orbit.duplicate(true),"focus":focus,"cameraPosition":camera.global_position if is_instance_valid(camera) else null,"world":world.fidelity_diagnostics() if is_instance_valid(world) else {},"seaShader":"retained reference_game_water","scope":"Actual game presentation modules; visual preview has no campaign or save writes."}
func save_frame(path: String) -> Dictionary:
	if _disposed or not startup_receipt.ok or not is_instance_valid(view): return {"ok":false,"reason":"rendered-frame-unavailable"}
	_render(); await RenderingServer.frame_post_draw
	if _disposed or not is_instance_valid(view): return {"ok":false,"reason":"rendered-frame-unavailable"}
	var image := view.get_texture().get_image()
	if image == null or image.is_empty(): return {"ok":false,"reason":"rendered-frame-unavailable"}
	var error := image.save_png(path)
	return {"ok":error == OK,"path":ProjectSettings.globalize_path(path),"width":image.get_width(),"height":image.get_height(),"reason":"image-save-failed" if error != OK else "saved"}
func _fail(reason: String) -> void: startup_receipt = {"ok":false,"reason":reason}; _status.text = reason; set_process(false)
func dispose() -> void:
	if _disposed: return
	_disposed = true; set_process(false)
	if is_instance_valid(sea): sea.dispose(); sea.free()
	sea = null; world = null; camera = null; _packet.clear()
func _exit_tree() -> void: dispose()
