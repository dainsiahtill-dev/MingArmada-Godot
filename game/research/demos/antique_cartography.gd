extends Node3D
## Independent 2D geographic atlas inside the lab's isolated SubViewport.
## The host alone accepts time; geography/selection never touch a voyage.
const Atlas = preload("res://game/ui/charts/world_atlas.gd")
const STEP := 1.0/32.0
const DEFAULTS := {"engraving":true,"paused":false,"camera_mode":"overview"}
var _options: Dictionary=DEFAULTS.duplicate(true)
var atlas: Control
var _configured:=false
var _disposed:=true
var _tick:=0
var _remainder:=0.0

func _ready() -> void:
	set_process(false); set_physics_process(false)
	get_viewport().size_changed.connect(_layout)
	if _configured and not _disposed: _build()

func get_default_options() -> Dictionary: return DEFAULTS.duplicate(true)

func configure(options: Dictionary) -> Dictionary:
	var next:=DEFAULTS.duplicate(true); next.merge(options,true)
	if not next.engraving is bool or not next.paused is bool or next.camera_mode not in ["overview","fujian","nanyang"]:
		return {"ok":false,"reason":"unsupported-cartography-option"}
	dispose(); _configured=true; _disposed=false; _options=next; _tick=0; _remainder=0
	if is_inside_tree(): _build()
	return {"ok":true,"ready":is_instance_valid(atlas),"pending":not is_inside_tree()}

func _build() -> void:
	atlas=Atlas.new(); atlas.name="IndependentWorldAtlas"; atlas.size=get_viewport().get_visible_rect().size; add_child(atlas)
	atlas.configure({"engraving":_options.engraving}); _layout(); set_camera_mode(_options.camera_mode)

func _layout() -> void:
	if is_instance_valid(atlas): atlas.size=get_viewport().get_visible_rect().size

func reset_experiment(options: Dictionary = {}) -> Dictionary:
	var next:=_options.duplicate(true); next.merge(options,true); return configure(next)

func advance(delta: float) -> void:
	if _disposed or _options.paused or not is_finite(delta) or delta<=0: return
	_remainder+=minf(delta,0.25)
	while _remainder+1e-12>=STEP: _tick+=1; _remainder-=STEP

func set_paused(value: bool) -> void: _options.paused=value

func control_spec() -> Array:
	return [{"id":"engraving","label":"纸上墨刻（关闭看地理基线）","type":"toggle","value":_options.engraving},
		{"id":"camera_mode","label":"固定图面","type":"choice","value":_options.camera_mode,"choices":[{"value":"overview","label":"东洋南海全图"},{"value":"fujian","label":"福建与台湾"},{"value":"nanyang","label":"南洋与爪哇"}]}]

func set_parameter(id: String, value: Variant) -> Dictionary:
	if id=="engraving" and value is bool:
		_options.engraving=value
		if is_instance_valid(atlas): atlas.set_engraving(value)
		return {"ok":true,"id":id,"value":value,"reset_required":false}
	if id=="camera_mode" and value in ["overview","fujian","nanyang"]:
		set_camera_mode(value); return {"ok":true,"id":id,"value":value,"reset_required":false}
	return {"ok":false,"reason":"unsupported-cartography-option"}

func set_camera_mode(value: String) -> void:
	if value not in ["overview","fujian","nanyang"]: return
	_options.camera_mode=value
	if not is_instance_valid(atlas): return
	if value=="overview": atlas.reset_view()
	else: atlas.select_port("xiamen" if value=="fujian" else "java"); atlas.focus_selected()

func orbit_camera(yaw_delta: float, pitch_delta: float) -> void:
	if is_instance_valid(atlas): atlas.pan_pixels(Vector2(yaw_delta*200,pitch_delta*200))

func zoom_camera(amount: float) -> void:
	if is_instance_valid(atlas) and is_finite(amount): atlas.zoom_at(exp(-amount))

func inspection_snapshot() -> Dictionary:
	var state: Dictionary=atlas.inspection_snapshot() if is_instance_valid(atlas) else {}
	return {"ready":not _disposed and state.get("ready",false),"disposed":_disposed,"parameters":_options.duplicate(true),"paused":_options.paused,"tick":_tick,"time":_tick*STEP,"fixed_step":STEP,"seed":0,"atlas":state,"camera":{"type":"2D-geographic-view","mode":_options.camera_mode,"view_bounds":state.get("view_bounds",Rect2())},"telemetry":state.get("geometry",{}),"resources":{"atlas":1 if is_instance_valid(atlas) else 0},"scope":"Independent geographic reading atlas; no session, campaign, game clock, save, settings or network access."}

func dispose() -> void:
	_disposed=true
	if is_instance_valid(atlas): atlas.dispose(); atlas.free()
	atlas=null

func _exit_tree() -> void: dispose()
