extends Control
signal main_menu_requested
const Runtime = preload("res://game/runtime/practice_runtime.gd")
const EncounterInterface = preload("res://game/ui/encounters/encounter_interface.gd")
const ThemeFactory = preload("res://game/ui/legacy/legacy_theme.gd")
const KINDS = ["duel","landBattle","treasure","banquet"]
var startup_options: Dictionary = {}
var startup_receipt: Dictionary = {}
var settings_storage: RefCounted
var runtime := Runtime.new()
var encounter_ui: Control
var _status: Label
var _header: HFlowContainer
var _begin: Button
var _kind := "duel"
var _leaving := false
var _last_result: Dictionary = {}
func _ready() -> void:
	theme=ThemeFactory.create(); set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background:=ColorRect.new(); background.color=Color("173e3e"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	encounter_ui=EncounterInterface.new(); add_child(encounter_ui); encounter_ui.command_requested.connect(_command)
	var header:=HFlowContainer.new(); _header=header; header.name="PracticeHeader"; add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE); header.offset_left=12; header.offset_right=-12; header.offset_top=10
	header.add_theme_constant_override("h_separation",14)
	var back:=Button.new(); back.name="MainMenu"; back.text="返回主菜单"; header.add_child(back); back.pressed.connect(_leave)
	var select:=OptionButton.new(); select.name="PracticeKind"
	for label in ["接舷决斗","登陆陆战","登岸寻宝","港口宴会"]: select.add_item(label)
	header.add_child(select)
	_kind=str(startup_options.get("kind","duel"))
	if _kind not in KINDS: _kind="duel"
	select.select(KINDS.find(_kind)); select.item_selected.connect(func(index): _kind=KINDS[index]; _last_result.clear(); runtime.start(_kind); _refresh())
	var retry:=Button.new(); retry.name="Restart"; retry.text="重新进入练习"; header.add_child(retry); retry.pressed.connect(func(): _last_result.clear(); runtime.start(_kind); _refresh())
	_begin=Button.new(); _begin.name="Begin"; header.add_child(_begin)
	_begin.pressed.connect(func():
		var packet:Dictionary=runtime.snapshot()
		if not packet.is_empty(): _command({"type":"encounter-begin","id":packet.id}))
	_status=Label.new(); _status.text="练习场景 · 可反复体验 · 不影响生涯"; header.add_child(_status)
	startup_receipt=runtime.start(_kind); resized.connect(_refresh); _refresh()
func _process(delta: float) -> void:
	if _leaving: return
	runtime.advance(delta); _refresh()
func _command(intent: Dictionary) -> void:
	if _leaving: return
	var current:Dictionary=runtime.snapshot()
	var close_result = current.get("result")
	var receipt: Dictionary = runtime.command(intent)
	if not receipt.ok: _status.text=str(receipt.get("reason","行动暂不可用"))
	elif intent.get("type")=="encounter-close" and close_result is Dictionary: _last_result=close_result.duplicate(true)
	elif intent.get("type")=="encounter-retry": _last_result.clear()
	_refresh()
func _refresh() -> void:
	if not encounter_ui or _leaving: return
	var packet: Dictionary = runtime.snapshot()
	if not packet.is_empty() and packet.state.phase!="active" and not packet.settled:
		runtime.command({"type":"encounter-settle","id":packet.id}); packet=runtime.snapshot()
	var waiting:bool=not packet.is_empty() and not packet.started
	_begin.visible=waiting; _begin.disabled=waiting and packet.paused
	_begin.text="开始决斗" if _kind=="duel" else "开始宴会"
	var presentation:=packet.duplicate(true)
	if waiting: presentation.paused=true
	encounter_ui.apply_snapshot(presentation,packet.get("revision",0))
	if waiting:
		for control in encounter_ui.find_children("*","Button",true,false):
			if control.name=="encounter_pause": control.disabled=true
	if encounter_ui._panel:
		var viewport:=get_viewport_rect().size
		encounter_ui._panel.position.y=maxf(62,_header.position.y+_header.size.y+16)
		encounter_ui._panel.size.y=maxf(120,viewport.y-encounter_ui._panel.position.y-16)
	if packet.is_empty():
		_status.text="练习结束；可重新进入练习。" if _last_result.is_empty() else "%s · 实际得分 %s · 伤损 %s%%"%["挑战完成" if _last_result.success else "已返回",_last_result.score,_last_result.injury]
	elif _last_result.is_empty(): _status.text="等待开始 · 阅读操作后点击开始" if waiting else "练习场景 · 可反复体验 · 不影响生涯"
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or _leaving or event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
	var focus=get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or focus is OptionButton: return
	var packet:Dictionary=runtime.snapshot()
	if packet.is_empty() or (event.echo and packet.kind!="treasure"): return
	var key:int=event.physical_keycode if event.physical_keycode else event.keycode
	var direction:String={KEY_W:"up",KEY_UP:"up",KEY_S:"down",KEY_DOWN:"down",KEY_A:"left",KEY_LEFT:"left",KEY_D:"right",KEY_RIGHT:"right"}.get(key,"")
	var action:Variant=null
	if packet.kind in ["treasure","banquet"] and not direction.is_empty():
		action={"type":"move","direction":direction} if packet.kind=="treasure" else direction
	elif packet.kind=="treasure" and key==KEY_E: action={"type":"dig"}
	elif packet.kind=="landBattle":
		if key in [KEY_1,KEY_2]: action={"type":"select","id":"player-melee" if key==KEY_1 else "player-musketeer"}
		elif key==KEY_E: action={"type":"end-turn"}
	if action!=null:
		_command({"type":"encounter-action","id":packet.id,"action":action}); get_viewport().set_input_as_handled(); return
	var code:String={KEY_J:"KeyJ",KEY_K:"KeyK",KEY_L:"KeyL",KEY_U:"KeyU",KEY_I:"KeyI",KEY_O:"KeyO",KEY_SPACE:"Space",KEY_UP:"ArrowUp",KEY_DOWN:"ArrowDown",KEY_LEFT:"ArrowLeft",KEY_RIGHT:"ArrowRight"}.get(key,"")
	if not code.is_empty(): encounter_ui.request_key(code); get_viewport().set_input_as_handled()
	elif key==KEY_ESCAPE:
		if not event.echo and packet.started: _command({"type":"encounter-pause","id":packet.id,"value":not packet.paused})
		get_viewport().set_input_as_handled()
func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT: runtime.set_suspended(true)
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN: runtime.set_suspended(false)
func _leave() -> void:
	if _leaving or not is_inside_tree(): return
	_leaving=true; runtime.dispose(); main_menu_requested.emit()
func _exit_tree() -> void: runtime.dispose()
