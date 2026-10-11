extends Control
## Native ShipViewer: original GLB assets, orbit camera and authored sail/cannon rigs.
signal main_menu_requested
const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
const ThemeFactory = preload("res://game/ui/legacy/legacy_theme.gd")
const SHIPS = [
	{"id":"fuchuan","name":"郑氏福船","role":"水师主力战舰","length":32,"beam":9,"draft":2,"description":"高艉楼、三桅翼帆与舷侧炮位，兼顾火力与近海机动。"},
	{"id":"fisherman","name":"福建渔舟","role":"沿海捕鱼与探索","length":14,"beam":4.2,"draft":1,"description":"低舷轻船、单桅小帆与尾橹，适于浅水湾与沿岸航行。"},
	{"id":"merchant","name":"贸易福船","role":"大宗货物运输","length":36,"beam":10,"draft":2.8,"description":"宽腹货舱、起货桅与坚实甲板，穿行在东亚商路之间。"},
	{"id":"voc","name":"荷兰武装商船","role":"远洋贸易与护航","length":40,"beam":11,"draft":3.2,"description":"方帆、艏斜桅与高艉廊，搭载远洋货物和舷炮。"},
	{"id":"patrol","name":"轻快战船","role":"追击与近海巡防","length":24,"beam":6,"draft":1.4,"description":"轻长船身、双翼帆和低艉楼，擅长快速接近与浅水航行。"},
	{"id":"heavy","name":"荷兰重型战舰","role":"远洋火力旗舰","length":52,"beam":14.5,"draft":4.2,"description":"九帆、大型舷炮列和三层艉楼，火力强但对深水航道要求更高。"}
]
const ANGLES = ["quarter","bow","starboard","stern","port","underwater"]
var startup_options: Dictionary = {}
var startup_receipt: Dictionary = {}
var settings_storage: RefCounted
var ship_model: Node3D
var camera: Camera3D
var sea: MeshInstance3D
var _library := Library.new()
var _world: Node3D
var _view: SubViewportContainer
var _viewport: SubViewport
var _sidebar: PanelContainer
var _ship_choice: OptionButton
var _lod_choice: OptionButton
var _angle_choice: OptionButton
var _furl_slider: HSlider
var _description: Label
var _status: Label
var _furl_label: Label
var _kind := "fuchuan"
var _lod := 0
var _attempted_kind := "fuchuan"
var _attempted_lod := 0
var _angle := "quarter"
var _furl := 0.0
var _center := Vector3.ZERO
var _target := Vector3.ZERO
var _scale := 50.0
var _distance := 100.0
var _yaw := 0.0
var _pitch := 0.0
var _time := 0.0
var _recoil_left := 0.0
var _barrel_rest: Dictionary = {}
var _rudder_rest: Dictionary = {}
var _leaving := false
func _ready() -> void:
	theme=ThemeFactory.create(); set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_world(); _build_controls(); resized.connect(_layout); _layout()
	startup_receipt=select_ship(str(startup_options.get("kind","fuchuan")),int(startup_options.get("lod",0)))
	if not startup_receipt.ok: _status.text="船只载入失败："+str(startup_receipt.reason)
func _build_world() -> void:
	_view=SubViewportContainer.new(); _view.name="ModelView"; _view.stretch=true; add_child(_view); _view.gui_input.connect(_camera_input)
	_viewport=SubViewport.new(); _viewport.name="ShipViewport"; _viewport.own_world_3d=true; _view.add_child(_viewport)
	_world=Node3D.new(); _viewport.add_child(_world)
	var environment:=WorldEnvironment.new(); var lighting:=Environment.new()
	lighting.background_mode=Environment.BG_COLOR; lighting.background_color=Color("9ebfc0")
	lighting.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; lighting.ambient_light_color=Color("e0f1e6"); lighting.ambient_light_energy=.8
	lighting.tonemap_mode=Environment.TONE_MAPPER_ACES; environment.environment=lighting; _world.add_child(environment)
	var sun:=DirectionalLight3D.new(); sun.light_color=Color("ffe8bf"); sun.light_energy=3.4; sun.rotation_degrees=Vector3(-55,-40,0); sun.shadow_enabled=true; _world.add_child(sun)
	sea=MeshInstance3D.new(); sea.name="InspectionSea"; var plane:=PlaneMesh.new(); plane.size=Vector2(1000,1000); sea.mesh=plane
	var material:=StandardMaterial3D.new(); material.albedo_color=Color("387e79"); material.roughness=.45; material.metallic=.08; sea.material_override=material; _world.add_child(sea)
	camera=Camera3D.new(); camera.name="InspectionCamera"; camera.fov=45; camera.near=.5; camera.far=1000; _world.add_child(camera); camera.current=true
func _label(parent: Node, text: String) -> Label:
	var label:=Label.new(); label.text=text; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; parent.add_child(label); return label
func _button(parent: Node, id: String, text: String, callback: Callable) -> Button:
	var button:=Button.new(); button.name=id; button.text=text; parent.add_child(button); button.pressed.connect(callback); return button
func _build_controls() -> void:
	_sidebar=PanelContainer.new(); _sidebar.name="ShipBookPanel"; add_child(_sidebar)
	var margin:=MarginContainer.new(); for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
	_sidebar.add_child(margin)
	var scroll:=ScrollContainer.new(); scroll.follow_focus=true; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; margin.add_child(scroll)
	var content:=VBoxContainer.new(); content.size_flags_horizontal=Control.SIZE_EXPAND_FILL; content.add_theme_constant_override("separation",10); scroll.add_child(content)
	_button(content,"MainMenu","‹ 返回主菜单",_leave)
	var title:=_label(content,"船坞检阅"); title.add_theme_font_size_override("font_size",28)
	_label(content,"观其形，知其用。")
	_label(content,"选择船型")
	_ship_choice=OptionButton.new(); _ship_choice.name="ShipKind"; content.add_child(_ship_choice)
	for ship: Dictionary in SHIPS: _ship_choice.add_item(ship.name)
	_ship_choice.item_selected.connect(func(index): select_ship(SHIPS[index].id,_lod))
	_label(content,"观察角度")
	_angle_choice=OptionButton.new(); _angle_choice.name="CameraAngle"; content.add_child(_angle_choice)
	for angle in ["全貌","船首","右舷","船尾","左舷","水下船壳"]: _angle_choice.add_item(angle)
	_angle_choice.item_selected.connect(func(index): set_angle(ANGLES[index]))
	var qa:=VBoxContainer.new(); qa.name="LODControls"; qa.visible=startup_options.get("dev",OS.has_feature("debug")) or startup_options.get("qa",false); content.add_child(qa)
	_label(qa,"模型距离版本")
	_lod_choice=OptionButton.new(); _lod_choice.name="ShipLOD"; qa.add_child(_lod_choice)
	for lod in ["近景 LOD0","中景 LOD1","远景 LOD2"]: _lod_choice.add_item(lod)
	_lod_choice.item_selected.connect(func(index): select_ship(_kind,index))
	_description=_label(content,""); _description.name="ShipDescription"
	_furl_label=_label(content,"帆面部署 100%")
	_furl_slider=HSlider.new(); _furl_slider.name="Furl"; _furl_slider.min_value=0; _furl_slider.max_value=1; _furl_slider.step=.05; content.add_child(_furl_slider); _furl_slider.value_changed.connect(set_furl)
	_button(content,"TurnShip","换个方向观察",turn_ship); _button(content,"CannonRecoil","试验火炮后座",test_recoil)
	_label(content,"拖动环视 · 滚轮缩放\n舵与帆可活动，船壳包含水下部分。")
	_status=_label(content,""); _status.name="LoadStatus"
	_button(content,"RetryModel","重试载入",func(): select_ship(_attempted_kind,_attempted_lod))
func select_ship(kind: String, lod: int = 0) -> Dictionary:
	if _leaving: return {"ok":false,"reason":"ship-book-disposed"}
	var index: int = -1
	for n in SHIPS.size():
		if SHIPS[n].id==kind: index=n; break
	if index<0 or lod not in [0,1,2]: return {"ok":false,"reason":"invalid-ship-selection"}
	_attempted_kind=kind; _attempted_lod=lod
	var model: Node3D = _library.instantiate_model("res://assets/models/ships/%s-lod%d.glb"%[kind,lod])
	if model==null:
		if _status: _status.text="船只载入失败；可重试。"
		return {"ok":false,"reason":"ship-model-unavailable"}
	if ship_model: ship_model.free()
	ship_model=model; _world.add_child(ship_model); _kind=kind; _lod=lod; _furl=0; _recoil_left=0; _barrel_rest.clear(); _rudder_rest.clear()
	var box:=AABB(); var has_box:=false
	for node in model.find_children("*","Node3D",true,false):
		if node is MeshInstance3D and node.mesh:
			var bounds: AABB = node.global_transform*node.get_aabb()
			box=box.merge(bounds) if has_box else bounds; has_box=true
		if String(node.name).begins_with("barrel_"): _barrel_rest[node.get_instance_id()]=node.position.z
		if String(node.name)=="rudder_pivot": _rudder_rest[node.get_instance_id()]=node.rotation.y
	_center=box.get_center(); _scale=maxf(1,maxf(box.size.x,maxf(box.size.y,box.size.z)))
	_ship_choice.select(index); _lod_choice.select(lod); _furl_slider.set_value_no_signal(0)
	var ship: Dictionary=SHIPS[index]
	_description.text="%s\n%s\n%s\n船长 %s m · 船宽 %s m · 吃水 %s m"%[ship.name,ship.role,ship.description,ship.length,ship.beam,ship.draft]
	_status.text=""; set_furl(0); set_angle(_angle)
	return {"ok":true,"kind":kind,"lod":lod}
func set_furl(value: float) -> void:
	if not is_finite(value): return
	_furl=clampf(value,0,1)
	if _furl_label: _furl_label.text="帆面部署 %d%%"%roundi((1-_furl)*100)
	if _furl_slider: _furl_slider.set_value_no_signal(_furl)
	animate_model(0)
func set_angle(angle: String) -> bool:
	if not ship_model or angle not in ANGLES or _leaving: return false
	_angle=angle; ship_model.rotation.y=0; _target=_center
	if angle=="underwater":
		var draft: float = 0
		for ship: Dictionary in SHIPS:
			if ship.id==_kind: draft=ship.draft; break
		_target=Vector3(0,-draft*.65,0)
	match angle:
		"bow": camera.position=Vector3(0,_center.y+_scale*.35,_scale*1.65)
		"stern": camera.position=Vector3(0,_center.y+_scale*.35,-_scale*1.65)
		"starboard": camera.position=Vector3(-_scale*1.65,_center.y+_scale*.35,0)
		"port": camera.position=Vector3(_scale*1.65,_center.y+_scale*.35,0)
		"underwater": camera.position=Vector3(-_scale*1.05,-_scale*.3,_scale*.75)
		_: camera.position=Vector3(_scale*1.25,_center.y+_scale*.6,_scale*1.3)
	sea.visible=angle!="underwater"; _angle_choice.select(ANGLES.find(angle))
	var offset:=camera.position-_target; _distance=offset.length(); _yaw=atan2(offset.x,offset.z); _pitch=asin(offset.y/_distance); _update_camera(); return true
func orbit(movement: Vector2) -> void:
	if _leaving or not movement.is_finite(): return
	_yaw-=movement.x*.008; _pitch=clampf(_pitch+movement.y*.008,-PI/2+.01,PI/2-.01); _update_camera()
func zoom(factor: float) -> void:
	if _leaving or not is_finite(factor) or factor<=0: return
	_distance=clampf(_distance*factor,_scale*.25,_scale*4); _update_camera()
func _update_camera() -> void:
	if not camera: return
	camera.position=_target+Vector3(sin(_yaw)*cos(_pitch),sin(_pitch),cos(_yaw)*cos(_pitch))*_distance
	camera.look_at(_target)
func turn_ship() -> void:
	if ship_model and not _leaving: ship_model.rotation.y+=PI/4
func test_recoil() -> void:
	if not _leaving: _recoil_left=.4; animate_model(0)
func animate_model(delta: float) -> void:
	if not ship_model or _leaving or not is_finite(delta) or delta<0: return
	_time+=delta; _recoil_left=maxf(0,_recoil_left-delta)
	for node in ship_model.find_children("*","Node3D",true,false):
		var id: int=node.get_instance_id()
		if _rudder_rest.has(id): node.rotation.y=_rudder_rest[id]+sin(_time/1.3)*.25
		if _barrel_rest.has(id): node.position.z=_barrel_rest[id]-.55*(_recoil_left/.4)
		if node is MeshInstance3D and node.mesh:
			for index in node.mesh.get_blend_shape_count():
				var morph: StringName=node.mesh.get_blend_shape_name(index)
				if morph==&"furl": node.set_blend_shape_value(index,_furl)
				elif morph==&"inflate": node.set_blend_shape_value(index,.7*(1-_furl))
func _process(delta: float) -> void: animate_model(delta)
func _camera_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_LEFT: orbit(event.relative); _view.accept_event()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: zoom(1/1.1); _view.accept_event()
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN: zoom(1.1); _view.accept_event()
func _layout() -> void:
	if not _view: return
	var bounds:=get_viewport_rect().size
	if bounds.x<=600:
		_sidebar.position=Vector2.ZERO; _sidebar.size=Vector2(bounds.x,228)
		_view.position=Vector2(0,228); _view.size=Vector2(bounds.x,maxf(1,bounds.y-228))
	else:
		var width:=230 if bounds.x<=760 else 300
		_sidebar.position=Vector2.ZERO; _sidebar.size=Vector2(width,bounds.y)
		_view.position=Vector2(width,0); _view.size=Vector2(maxf(1,bounds.x-width),bounds.y)
func snapshot() -> Dictionary:
	return {"kind":_kind,"lod":_lod,"path":"res://assets/models/ships/%s-lod%d.glb"%[_kind,_lod],"angle":_angle,"furl":_furl,"distance":_distance}
func _leave() -> void:
	if _leaving or not is_inside_tree(): return
	_leaving=true; main_menu_requested.emit()
func _exit_tree() -> void:
	_leaving=true; _library.dispose()
