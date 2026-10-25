extends Control
const Parchment = preload("res://game/ui/shared/parchment_theme.gd")
## Direct island-water/app.mjs scene contract, independent from the sailing simulation.
signal main_menu_requested
const Model = preload("res://modules/scene_engine/reference_island_water/reference_island_model.gd")
const Ocean = preload("res://modules/scene_engine/reference_island_water/ocean_renderer.gd")
const TerrainShader = preload("res://modules/scene_engine/reference_island_water/reference_terrain.gdshader")
const DEFAULT_ORBIT := {"azimuth":-0.65,"elevation":0.68,"distance":185.0}
const DEFAULT_STATE := {"preset":"clear","strength":1.0,"tide":0.0,"foamWidth":1.5,"waves":true,"reflection":true,"foam":true,"caustics":true,"paused":false}
var startup_options: Dictionary = {}
var startup_receipt: Dictionary = {"ok":false,"reason":"reference-scene-not-ready"}
var field: Dictionary = {}
var state: Dictionary = DEFAULT_STATE.duplicate(true)
var orbit: Dictionary = DEFAULT_ORBIT.duplicate(true)
var seconds := 0.0
var world: Node3D
var ocean: Node3D
var camera: Camera3D
var view: SubViewport
var _view_container: SubViewportContainer
var _terrain_material: ShaderMaterial
var _preset: OptionButton
var _pause: Button
var _status: Label
var _title: Label
var _sliders: Dictionary = {}
var _values: Dictionary = {}
var _toggles: Dictionary = {}
var _updating_ui := false
var _dragging := false
var _disposed := false

func _ready() -> void:
	_build_ui()
	field = Model.load_field()
	if field.is_empty(): _fail("海岛高度数据读取失败。"); return
	view.world_3d = World3D.new()
	world = Node3D.new(); world.name = "ReferenceWorld"; view.add_child(world)
	camera = Camera3D.new(); camera.name = "ReferenceCamera"
	camera.fov = 45.0; camera.near = 0.3; camera.far = 1200.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT; world.add_child(camera); camera.make_current()
	_update_camera()
	var terrain := MeshInstance3D.new(); terrain.name = "CatIsland"
	terrain.mesh = Model.terrain_mesh(field,160)
	var apron := MeshInstance3D.new(); apron.name = "SeabedApron"
	apron.mesh = Model.seabed_mesh(field,160)
	if terrain.mesh == null or apron.mesh == null: _fail("海岛网格生成失败。"); return
	_terrain_material = ShaderMaterial.new(); _terrain_material.shader = TerrainShader
	for item: MeshInstance3D in [terrain,apron]:
		item.material_override = _terrain_material
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(item)
	field.heightTexture = Model.height_texture(field,160)
	ocean = Ocean.new(); ocean.name = "ReferenceOcean"; world.add_child(ocean)
	if not ocean.configure(field,camera,state): _fail("海水渲染器初始化失败。"); return
	var environment_node := WorldEnvironment.new(); environment_node.name = "ReferenceEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new(); sky.sky_material = ocean.get_sky_material(); environment.sky = sky
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	environment.fog_enabled = false
	environment_node.environment = environment; world.add_child(environment_node)
	_render()
	startup_receipt = {"ok":true,"mode":"water-study","source":"island-water/demo","terrainVertices":terrain.mesh.surface_get_array_len(0),"seabedVertices":apron.mesh.surface_get_array_len(0)}
	_status.text = "已就绪 · 拖动旋转 / 滚轮缩放"
	if not startup_options.get("staged",false): activate_entry()

func _fail(message: String) -> void:
	startup_receipt = {"ok":false,"reason":"reference-scene-startup-failed","message":message}
	_status.text = message
	set_process(false)

func activate_entry() -> void:
	if _disposed or not startup_receipt.ok: return
	camera.make_current(); _render()
	get_window().title = "海上明旗 · 海岛与海面"

func _process(delta: float) -> void:
	if _disposed or not startup_receipt.ok: return
	advance_time(delta,is_visible_in_tree() and get_window().has_focus())

func advance_time(delta: float, active: bool) -> void:
	if _disposed or not is_finite(delta): return
	if active and not state.paused: seconds += minf(0.05,maxf(0.0,delta))
	_render()

func set_state(patch: Dictionary) -> bool:
	var next := state.duplicate(true)
	for key: String in patch:
		if not DEFAULT_STATE.has(key): return false
		var value: Variant = patch[key]
		if key == "preset":
			if value not in ["clear","sunset","storm"]: return false
			next.preset = value
			next.strength = 1.8 if value == "storm" else 0.65 if value == "sunset" else 1.0
		elif key in ["strength","tide","foamWidth"]:
			if not (value is float or value is int) or not is_finite(float(value)): return false
			next[key] = clampf(float(value),0.0,2.0) if key == "strength" else clampf(float(value),-3.0,4.0) if key == "tide" else clampf(float(value),0.3,4.0)
		else:
			if not value is bool: return false
			next[key] = value
	state = next; _sync_ui(); _render(); return true

func reset_camera() -> void:
	orbit = DEFAULT_ORBIT.duplicate(true); _update_camera(); _render()

func _update_camera() -> void:
	if not is_instance_valid(camera): return
	var a := float(orbit.azimuth); var e := float(orbit.elevation); var d := float(orbit.distance)
	camera.position = Vector3(sin(a)*cos(e)*d,sin(e)*d,cos(a)*cos(e)*d)
	camera.look_at(Vector3.ZERO,Vector3.UP)

func _render() -> void:
	if _disposed or not is_instance_valid(ocean) or not is_instance_valid(camera): return
	var sunset: bool = state.preset == "sunset"
	var sun := Vector3(-0.8,0.18,-0.45).normalized() if sunset else Vector3(-0.5,0.8,0.3).normalized()
	var sun_color := Vector3(1.0,0.65,0.35) if sunset else Vector3(1.0,0.95,0.82)
	_terrain_material.set_shader_parameter("u_time",seconds)
	_terrain_material.set_shader_parameter("u_tide",float(state.tide))
	_terrain_material.set_shader_parameter("u_eye",camera.global_position)
	_terrain_material.set_shader_parameter("u_sun",sun)
	_terrain_material.set_shader_parameter("u_sun_color",sun_color)
	_terrain_material.set_shader_parameter("u_caustics",state.caustics)
	_terrain_material.set_shader_parameter("u_clip",true)
	ocean.render(state,camera,seconds)

func _view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed; _view_container.accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var delta_y := -120.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 120.0
			orbit.distance = clampf(float(orbit.distance)*exp(delta_y*0.001),70.0,280.0)
			_update_camera(); _render(); _view_container.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		orbit.azimuth -= event.relative.x*0.006
		orbit.elevation = clampf(float(orbit.elevation)+event.relative.y*0.004,0.22,1.25)
		_update_camera(); _render(); _view_container.accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed: _dragging = false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE: main_menu_requested.emit(); get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE: set_state({"paused":not state.paused}); get_viewport().set_input_as_handled()

func inspection_snapshot() -> Dictionary:
	return {"time":seconds,"state":state.duplicate(true),"orbit":orbit.duplicate(true),"startup":startup_receipt.duplicate(true),"ocean":ocean.diagnostics() if is_instance_valid(ocean) else {},"viewport":[view.size.x,view.size.y] if is_instance_valid(view) else [],"scope":"Direct Godot island-water demo port; no sailing simulation or FPS claim."}

func save_frame(path: String) -> Dictionary:
	if DisplayServer.get_name() == "headless" or not is_instance_valid(view): return {"ok":false,"reason":"rendered-frame-unavailable"}
	_render(); await RenderingServer.frame_post_draw
	if _disposed or not is_instance_valid(view): return {"ok":false,"reason":"rendered-frame-unavailable"}
	var image := view.get_texture().get_image()
	var error := image.save_png(path)
	return {"ok":error == OK,"path":ProjectSettings.globalize_path(path),"width":image.get_width(),"height":image.get_height(),"reason":"image-save-failed" if error != OK else "saved"}

func _save_requested() -> void:
	var directory := "user://screenshots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory+"/island-water-%d.png" % Time.get_unix_time_from_system()
	var receipt: Dictionary = await save_frame(path)
	_status.text = "画面已保存："+receipt.path if receipt.ok else "画面保存失败。"

func dispose() -> void:
	if _disposed: return
	_disposed = true; set_process(false); _dragging = false
	if is_instance_valid(ocean): ocean.dispose()
	if is_instance_valid(world): world.free()
	world = null; ocean = null; camera = null; _terrain_material = null
	field.clear()

func _exit_tree() -> void: dispose()

func _label(parent: Node, text: String, font_size: int=16) -> Label:
	var label := Label.new(); label.text = text; label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",Parchment.INK)
	if font_size>=20:
		label.add_theme_font_override("font",Parchment.title_font()); label.add_theme_color_override("font_color",Parchment.CINNABAR)
	parent.add_child(label); return label

func _button(parent: Node, name_: String, text: String, action: Callable) -> Button:
	var button := Button.new(); button.name = name_; button.text = text; button.custom_minimum_size.y = 42
	parent.add_child(button); button.pressed.connect(action); return button

func _build_ui() -> void:
	theme = Parchment.create()
	Parchment.background(self,"ledger","ReferenceWaterPaper")
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	add_child(margin)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",16); margin.add_child(column)
	var heading := HBoxContainer.new(); column.add_child(heading)
	_title = _label(heading,"海岛与海面",30); _title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(heading,"WaterBack","返回主菜单  Esc",func(): main_menu_requested.emit())
	var body := HBoxContainer.new(); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation",20); column.add_child(body)
	_view_container = SubViewportContainer.new(); _view_container.name = "WaterView"
	_view_container.stretch = true; _view_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _view_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view_container.custom_minimum_size = Vector2(320,280); body.add_child(_view_container)
	view = SubViewport.new(); view.name = "ReferenceViewport"; view.size = Vector2i(960,640)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_DISABLED; view.handle_input_locally = false
	_view_container.add_child(view); _view_container.gui_input.connect(_view_input)
	var panel := PanelContainer.new(); panel.custom_minimum_size.x = 290; body.add_child(panel)
	panel.add_theme_stylebox_override("panel",Parchment.panel(20))
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; panel.add_child(scroll)
	var controls := VBoxContainer.new(); controls.add_theme_constant_override("separation",14); controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(controls)
	_label(controls,"Cat Island · 效果预览",20)
	_preset = OptionButton.new(); _preset.name = "WaterPreset"; _preset.custom_minimum_size.y = 40
	for text in ["晴天","夕阳","风浪"]: _preset.add_item(text)
	controls.add_child(_preset); _preset.item_selected.connect(func(index: int): set_state({"preset":["clear","sunset","storm"][index]}))
	for item: Array in [["strength","海浪强度",0.0,2.0,0.01],["tide","潮位",-3.0,4.0,0.1],["foamWidth","泡沫覆盖",0.3,4.0,0.1]]:
		var row := HBoxContainer.new(); controls.add_child(row)
		var name_label := _label(row,item[1]); name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_values[item[0]] = _label(row,"")
		var slider := HSlider.new(); slider.name = "Water_"+item[0]
		slider.min_value = item[2]; slider.max_value = item[3]; slider.step = item[4]; slider.custom_minimum_size.y = 26
		controls.add_child(slider); _sliders[item[0]] = slider
		slider.value_changed.connect(_slider_changed.bind(item[0]))
	for item: Array in [["waves","三维波浪"],["reflection","海岛反射"],["foam","岸边泡沫"],["caustics","浅滩焦散"]]:
		var toggle := CheckBox.new(); toggle.name = "Water_"+item[0]; toggle.text = item[1]; controls.add_child(toggle); _toggles[item[0]] = toggle
		toggle.toggled.connect(_toggle_changed.bind(item[0]))
	_pause = _button(controls,"WaterPause","暂停波浪  Space",func(): set_state({"paused":not state.paused}))
	_button(controls,"WaterReset","重置视角",reset_camera)
	_button(controls,"WaterSave","保存画面 PNG",_save_requested)
	var help := _label(controls,"拖动旋转，滚轮拉近。\n改变潮位，观察岸线移动。",14); help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status = _label(column,"正在准备海岛与海面。",14); _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sync_ui()

func _slider_changed(value: float, key: String) -> void:
	if not _updating_ui: set_state({key:value})
func _toggle_changed(value: bool, key: String) -> void:
	if not _updating_ui: set_state({key:value})
func _sync_ui() -> void:
	if not is_instance_valid(_preset): return
	_updating_ui = true
	_preset.select(["clear","sunset","storm"].find(state.preset))
	for key: String in _sliders:
		_sliders[key].set_value_no_signal(float(state[key])); _values[key].text = ("%.2f" if key == "strength" else "%.1f") % float(state[key])
	for key: String in _toggles: _toggles[key].set_pressed_no_signal(state[key])
	_pause.text = "继续波浪  Space" if state.paused else "暂停波浪  Space"
	_title.text = "海岛与海面 · "+{"clear":"晴天","sunset":"夕阳","storm":"风浪"}[state.preset]
	_updating_ui = false
