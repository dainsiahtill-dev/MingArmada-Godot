extends CanvasLayer
const Parchment=preload("res://game/ui/shared/parchment_theme.gd")
signal command_requested(intent: Dictionary)
signal view_requested(tactical: bool)
const Runtime=preload("res://game/runtime/visual_qa_runtime.gd")
var _panel: PanelContainer
var _screen: Control
var _status: Label
var _diagnostic: Label
var _scenario: OptionButton
var _playback: OptionButton
var _handling: OptionButton
var _sails: HSlider
var _buttons: Dictionary={}
var _applying:=false
var _packet: Dictionary={}
func _ready() -> void:
	_screen=Control.new(); _screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _screen.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(_screen)
	var theme:=Parchment.create(); theme.default_font_size=14; _screen.theme=theme
	_panel=PanelContainer.new(); _panel.position=Vector2(12,12); _screen.add_child(_panel)
	_panel.add_theme_stylebox_override("panel",Parchment.panel(12))
	var scroll:=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.follow_focus=true; _panel.add_child(scroll)
	var column:=VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",8); scroll.add_child(column)
	_status=_label(column,"真实引擎画面验收")
	_scenario=OptionButton.new(); _scenario.name="scenario"; _scenario.fit_to_longest_item=false; _scenario.clip_text=true; column.add_child(_scenario)
	for title: String in Runtime.LABELS: _scenario.add_item(title)
	_scenario.item_selected.connect(func(index):
		if not _applying: command_requested.emit({"type":"scenario","value":Runtime.SCENARIOS[index]}))
	_playback=OptionButton.new(); _playback.name="playback"; column.add_child(_playback)
	for pair in [[1.0,"正常速度"],[0.25,"四倍慢放"],[0.1,"十倍慢放"],[4.0,"四倍推进 · 岸线脱困"]]:
		_playback.add_item(pair[1]); _playback.set_item_metadata(_playback.item_count-1,pair[0])
	_playback.item_selected.connect(func(index):
		if not _applying: command_requested.emit({"type":"playback","value":_playback.get_item_metadata(index)}))
	_handling=OptionButton.new(); _handling.name="handling"; _handling.add_item("真实操船（本次 QA）"); _handling.add_item("均衡操船（本次 QA）"); column.add_child(_handling)
	_handling.item_selected.connect(func(index):
		if not _applying: command_requested.emit({"type":"handling","value":"realistic" if index==0 else "assisted"}))
	_sails=HSlider.new(); _sails.name="sails"; _sails.max_value=100; _sails.step=1; column.add_child(_sails)
	_sails.value_changed.connect(func(value):
		if not _applying: command_requested.emit({"type":"sails","value":value/100.0}))
	var cannons:=HFlowContainer.new(); column.add_child(cannons)
	button(cannons,"fire_port","左舷 Q",{"type":"fire","side":"port"}); button(cannons,"fire_starboard","右舷 E",{"type":"fire","side":"starboard"})
	var ammunition:=HFlowContainer.new(); column.add_child(ammunition)
	for pair in [["solid","实心弹 1"],["chain","链弹 2"],["grape","葡萄弹 3"]]: button(ammunition,pair[0],pair[1],{"type":"select-ammo","ammo":pair[0]})
	var controls:=HFlowContainer.new(); column.add_child(controls)
	button(controls,"trim","自动调帆 R",{"type":"trim"}); button(controls,"pause","暂停",{"type":"pause"}); button(controls,"resume","继续",{"type":"resume"})
	var views:=HFlowContainer.new(); column.add_child(views)
	button(views,"captain_view","船长视角",{}).pressed.connect(func(): view_requested.emit(false))
	button(views,"tactical_view","高位视角",{}).pressed.connect(func(): view_requested.emit(true))
	var actions:=HFlowContainer.new(); column.add_child(actions)
	button(actions,"restart","重新开始",{"type":"restart"}); button(actions,"settings","设置",{"type":"open-settings"}); button(actions,"main_menu","返回主菜单",{"type":"main-menu"})
	button(column,"export","导出原始性能 JSON",{"type":"export"})
	_label(column,"W/S 升降帆 · A/D 转舵 · [ / ] 帆角\nQ/E 左右舷 · 空格最近目标 · Esc 暂停\n弱炮击：火力 2%，真实 hit 驱动原生受击\n基准：20秒预热，60秒采样，结束自动暂停\nCPU 仿真与海景更新分开；海景内含区块更新。\n渲染提交与 GPU 完成耗时未单独测量。")
	_diagnostic=_label(column,""); _diagnostic.name="diagnostics"; _diagnostic.add_theme_font_size_override("font_size",11)
	get_viewport().size_changed.connect(_layout); _layout()
func _label(parent: Node,value: String) -> Label:
	var label:=Label.new(); label.text=value; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; parent.add_child(label); return label
func button(parent: Node,id: String,title: String,intent: Dictionary) -> Button:
	var control:=Button.new(); control.name=id; control.text=title; control.custom_minimum_size.y=34; control.focus_mode=Control.FOCUS_NONE; parent.add_child(control); _buttons[id]=control
	control.pressed.connect(func():
		if not intent.is_empty(): command_requested.emit(intent.duplicate(true)))
	return control
func _layout() -> void:
	var viewport:=get_viewport().get_visible_rect().size
	_panel.size=Vector2(minf(370,maxf(100,viewport.x-24)),minf(830,maxf(100,viewport.y-24)))
func apply_snapshot(packet: Dictionary,detail: Dictionary) -> void:
	_packet=packet.duplicate(true); _applying=true
	var state: Dictionary=packet.runtime; var native: Dictionary=packet.naval; var player: Dictionary=native.ships.filter(func(s): return s.id==native.playerId)[0]
	_scenario.select(Runtime.SCENARIOS.find(state.scenario)); _handling.select(0 if state.handlingMode=="realistic" else 1)
	for index in _playback.item_count:
		if _playback.get_item_metadata(index)==state.playback: _playback.select(index)
	_playback.disabled=state.scenario=="benchmark"; _playback.set_item_disabled(3,state.scenario!="shore-escape")
	_sails.value=player.sailDeployment*100; _sails.editable=not state.paused
	_status.text="QA · %s · %s\n模拟 %.2fs · tick %d · 船体高度 %.3fm\n船体 %.2f · 帆 %.2f · 船员 %.2f\n弹药 %d/%d/%d · 基准 %.1fs\n%s" % [state.scenario,state.phase,native.time,native.tick,player.visual.position.y,player.hull,player.sail,player.crew,player.ammo.solid,player.ammo.chain,player.ammo.grape,state.benchmarkSeconds,state.notice]
	if state.waypoint!=null:
		var p: Dictionary=player.visual.position
		_status.text+="\n船位 %.2f, %.2f · 航向 %.1f°\n目标距离 %.2fm" % [p.x,p.z,rad_to_deg(player.visual.heading),Vector2(p.x-state.waypoint.x,p.z-state.waypoint.z).length()]
	if "wave" in state.pauseReasons: _status.text+="\n原海浪 4.60 秒波峰已定格"
	for id in ["fire_port","fire_starboard","solid","chain","grape","trim"]: _buttons[id].disabled=state.paused
	_buttons.resume.visible=state.paused; _buttons.pause.visible=not state.paused
	_diagnostic.text=JSON.stringify(detail,"  "); _applying=false; _layout()
