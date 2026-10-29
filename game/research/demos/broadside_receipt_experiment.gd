extends Node3D
## Isolated fixture, not an actual battle or a gameplay acceptance result.
const ReceiptProjection = preload("res://game/research/demos/broadside_receipt_projection.gd")
const Maritime = preload("res://game/ui/shared/maritime_art_theme.gd")
const STEP := 1.0 / 32.0
const DEFAULTS := {"candidate_enabled":true,"paused":false,"camera_mode":"fixed"}
const EVENTS := [
	{"tick":4,"event":{"id":"e1","type":"fire","shipId":"flag","side":"starboard","projectileId":"p1"}},
	{"tick":8,"event":{"id":"e2","type":"fire","shipId":"flag","side":"starboard","projectileId":"p2"}},
	{"tick":12,"event":{"id":"e3","type":"fire","shipId":"flag","side":"starboard","projectileId":"p3"}},
	{"tick":14,"event":{"id":"e4","type":"fire","shipId":"flag","side":"starboard","projectileId":"p4"}},
	{"tick":16,"event":{"id":"e5","type":"hit","shipId":"flag","targetId":"enemy","projectileId":"p1"}},
	{"tick":20,"event":{"id":"e6","type":"splash","shipId":"flag","projectileId":"p2"}}
]
var _options := DEFAULTS.duplicate(true)
var _projection = ReceiptProjection.new()
var _tick := 0
var _accumulator := 0.0
var _cursor := 0
var _naive := ""
var _configured := false
var _disposed := false
var _panel: PanelContainer
var _label: Label

func _ready() -> void:
	set_process(false); set_physics_process(false)
	if _configured and not _disposed: _build()
func get_default_options() -> Dictionary: return DEFAULTS.duplicate(true)
func configure(options: Dictionary) -> Dictionary:
	var candidate := DEFAULTS.duplicate(true)
	for key in options:
		if not DEFAULTS.has(key): return {"ok":false,"reason":"unknown-parameter"}
	candidate.merge(options,true)
	if not candidate.candidate_enabled is bool or not candidate.paused is bool or candidate.camera_mode != "fixed": return {"ok":false,"reason":"invalid-parameter"}
	dispose(); _options = candidate; _configured = true; _disposed = false
	_tick = 0; _accumulator = 0.0; _cursor = 0; _naive = ""
	_projection.reset("fixture-1","flag",{"hostileTargets":{"flag":["enemy"]},"capturedShipIds":[]},{"flag":{"name":"旗舰","team":"player"},"enemy":{"name":"倭船","team":"hostile"}})
	set_process(false); set_physics_process(false)
	if is_inside_tree(): _build()
	return {"ok":true,"ready":is_inside_tree(),"pending":not is_inside_tree(),"options":_options.duplicate(true)}
func reset_experiment(options: Dictionary = {}) -> Dictionary:
	var next := _options.duplicate(true); next.merge(options,true)
	var result := configure(next)
	if result.ok: result.snapshot = inspection_snapshot()
	return result
func control_spec() -> Array:
	return [{"id":"candidate_enabled","label":"显示齐射结果","type":"toggle","value":_options.candidate_enabled}]
func set_parameter(id: String, value: Variant) -> Dictionary:
	if id != "candidate_enabled" or not value is bool: return {"ok":false,"reason":"invalid-parameter","reset_required":false}
	_options[id] = value; _refresh()
	return {"ok":true,"reset_required":false,"id":id,"value":value}
func advance(delta: float) -> void:
	if not is_instance_valid(_label) or _disposed or _options.paused or not is_finite(delta) or delta <= 0: return
	_accumulator += minf(delta,STEP*8)
	while _accumulator + 1.0e-12 >= STEP:
		_tick += 1; _accumulator -= STEP
		while _cursor < EVENTS.size() and int(EVENTS[_cursor].tick) == _tick:
			var event: Dictionary = EVENTS[_cursor].event.duplicate(true)
			_projection.consume(event,_tick*STEP)
			if event.type == "hit": _naive = "右舷命中 · 敌船倭船"
			elif event.type == "splash": _naive = "右舷炮弹未命中"
			_cursor += 1
	_refresh()
func set_paused(value: bool) -> void: _options.paused = value
func set_camera_mode(_value: String) -> void: pass
func orbit_camera(_yaw: float,_pitch: float) -> void: pass
func zoom_camera(_amount: float) -> void: pass
func _build() -> void:
	_panel = PanelContainer.new(); _panel.name = "BroadsideReceiptPaper"; _panel.theme = Maritime.create()
	# The painted frame and its shadow extend outside the panel's native rect.
	_panel.position = Vector2(20,44); _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size.x = 240 # Keep the frame stable when the receipt appears.
	_panel.add_theme_stylebox_override("panel",Maritime.panel(8)); add_child(_panel)
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation",2); _panel.add_child(content)
	var title := Label.new(); title.name = "BroadsideFixtureTitle"; title.text = "模拟齐射 · 非真实海战"; title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size",15); title.add_theme_color_override("font_color",Maritime.MUTED); content.add_child(title)
	var status := Label.new(); status.name = "BroadsideFixtureStatus"; status.text = "右舷 E · 可齐射"; status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_font_size_override("font_size",17); content.add_child(status)
	_label = Label.new(); _label.name = "BroadsideReceiptFixture"; _label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size",17); _label.custom_minimum_size.y = 26; content.add_child(_label); _refresh()
func _refresh() -> void:
	if not is_instance_valid(_label): return
	var result: Dictionary = _projection.snapshot(_tick*STEP)
	_label.text = str(result.text if _options.candidate_enabled else "")
func inspection_snapshot() -> Dictionary:
	var result: Dictionary = _projection.snapshot(_tick*STEP)
	return {"topic":"broadside-receipt-readability","ready":is_instance_valid(_label) and not _disposed,"disposed":_disposed,"tick":_tick,"time":_tick*STEP,"step_seconds":STEP,"paused":_options.paused,"parameters":_options.duplicate(true),"camera_mode":"fixed","fixture_events":_cursor,"receipt":result,"visible_receipt":result.text if _options.candidate_enabled else "","naive_text":_naive,"resources":{"labels":1 if is_instance_valid(_label) else 0,"runtime":0,"storage":0},"scope":"fixed synthetic events; no gameplay or GPU acceptance"}
func dispose() -> void:
	_disposed = true
	if is_instance_valid(_panel): remove_child(_panel); _panel.free()
	_panel = null; _label = null; _accumulator = 0.0
func _exit_tree() -> void: dispose()
