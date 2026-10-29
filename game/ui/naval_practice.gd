extends CanvasLayer
## Practice HUD consumes canonical snapshots; emits intents only.
signal command_requested(intent: Dictionary)
signal view_requested(tactical: bool)
signal owned_popup_focus_changed
const Chart=preload("res://game/ui/charts/nautical_chart.gd")
const ChartFrame=preload("res://game/ui/charts/floating_chart_frame.gd")
const Parchment=preload("res://game/ui/shared/maritime_art_theme.gd")
const Cannon=preload("res://modules/naval_simulation/combat/cannon_system.gd")
const Fire=preload("res://modules/naval_simulation/combat/fire_control.gd")
var chart: Control
var _screen: Control
var _panel: PanelContainer
var _status: Label
var _notice: Label
var _gunnery: Label
var _sails: HSlider
var _modal: PanelContainer
var _modal_title: Label
var _buttons: Dictionary={}
var _snapshot: Dictionary={}
var _menu:=false
var _applying:=false
var _heading: Label
var _sail_readout: Label
var _command_panel: PanelContainer
var _help_panel: PanelContainer
var _fire_panel: PanelContainer
var _fire_target: OptionButton
var _fire_state: Label
var _fire_stores: Label
var _fire_advice: Label
var _fire_target_id: String=""
var _fire_targets: Array=[]
var _fire_open:=false
var _fire_popup_active:=false

func _ready() -> void:
	# Secondary folios must own pointer input above the compact chart (layer 22),
	# while scene settings (50) and entry overlays (100) retain their priority.
	layer=24
	_screen=Control.new(); _screen.name="PracticeScreen"; _screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _screen.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(_screen)
	_screen.theme=Parchment.create()
	_panel=PanelContainer.new(); _panel.name="NavigationSummary"; _panel.add_theme_stylebox_override("panel",Parchment.panel(14)); _screen.add_child(_panel)
	var summary:=VBoxContainer.new(); summary.add_theme_constant_override("separation",4); _panel.add_child(summary)
	_heading=Label.new(); _heading.name="PracticeHeading"; _heading.add_theme_font_override("font",Parchment.title_font()); _heading.add_theme_font_size_override("font_size",28); _heading.add_theme_color_override("font_color",Parchment.INK); _heading.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; summary.add_child(_heading)
	_status=Label.new(); _status.name="NavigationStatus"; _status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _status.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _status.add_theme_font_size_override("font_size",16); _status.add_theme_color_override("font_color",Parchment.INK); summary.add_child(_status)
	_notice=Label.new(); _notice.name="PracticeNotice"; _notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _notice.max_lines_visible=2; _notice.add_theme_font_size_override("font_size",16); _notice.add_theme_color_override("font_color",Parchment.DANGER); summary.add_child(_notice); _notice.hide()
	_panel.minimum_size_changed.connect(func(): _panel.size.y=_panel.get_combined_minimum_size().y)

	_command_panel=PanelContainer.new(); _command_panel.name="CommandPanel"; _command_panel.add_theme_stylebox_override("panel",Parchment.panel(12)); _screen.add_child(_command_panel)
	var scroll:=ScrollContainer.new(); scroll.name="CommandScroll"; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.follow_focus=true; _command_panel.add_child(scroll)
	var commands:=VBoxContainer.new(); commands.size_flags_horizontal=Control.SIZE_EXPAND_FILL; commands.add_theme_constant_override("separation",8); scroll.add_child(commands)
	var handling:=HFlowContainer.new(); handling.name="HandlingCommands"; handling.add_theme_constant_override("h_separation",6); handling.add_theme_constant_override("v_separation",6); commands.add_child(handling)
	var sail_control:=HBoxContainer.new(); sail_control.name="SailControl"; sail_control.custom_minimum_size=Vector2(218,38); sail_control.add_theme_constant_override("separation",8); handling.add_child(sail_control)
	var sail_label:=Label.new(); sail_label.text="帆面"; sail_label.add_theme_font_size_override("font_size",16); sail_control.add_child(sail_label)
	_sails=HSlider.new(); _sails.name="sails"; _sails.min_value=0; _sails.max_value=100; _sails.step=1; _sails.custom_minimum_size.x=112; _sails.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _sails.tooltip_text="帆面展开比例 · W / S 升帆与收帆"; sail_control.add_child(_sails)
	_sails.value_changed.connect(func(value):
		if not _applying: command_requested.emit({"type":"sails","value":value/100.0}))
	_sail_readout=Label.new(); _sail_readout.name="SailReadout"; _sail_readout.text="100%"; _sail_readout.custom_minimum_size.x=40; _sail_readout.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; _sail_readout.add_theme_font_size_override("font_size",16); sail_control.add_child(_sail_readout)
	var fight_fire:=button(handling,"fight_fire","扑救火灾",{});fight_fire.hide();fight_fire.pressed.connect(_request_fire_work)
	fight_fire.tooltip_text="水手自动前往扑救，火灭后自动归位；期间会暂时占用部分炮手。"
	button(handling,"stop_sailing","停船",{"type":"stop-sailing"}).tooltip_text="中键停止持续航行"
	button(handling,"trim","调帆 R",{"type":"trim"}).tooltip_text="自动调整帆角"
	button(handling,"pause","暂停",{"type":"pause"})
	var captain:=button(handling,"captain_view","船长",{}); captain.tooltip_text="船长视角"; captain.pressed.connect(func(): view_requested.emit(false))
	var tactical:=button(handling,"tactical_view","高位",{}); tactical.tooltip_text="高位视角"; tactical.pressed.connect(func(): view_requested.emit(true))
	button(handling,"open_chart","航图 M",{"type":"chart","value":true})
	var help:=button(handling,"help","操船手册",{}); help.pressed.connect(_toggle_help)
	var cannons:=HFlowContainer.new(); cannons.name="GunneryCommands"; cannons.add_theme_constant_override("h_separation",6); cannons.add_theme_constant_override("v_separation",6); commands.add_child(cannons)
	button(cannons,"fire_port","左舷开炮 Q",{"type":"fire","side":"port"})
	button(cannons,"fire_starboard","右舷开炮 E",{"type":"fire","side":"starboard"})
	for entry in [["solid","实心弹 1"],["chain","链弹 2"],["grape","葡萄弹 3"]]:
		var ammo:=button(cannons,entry[0],entry[1],{"type":"select-ammo","ammo":entry[0]}); ammo.toggle_mode=true
	_gunnery=Label.new(); _gunnery.name="GunneryStatus"; _gunnery.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _gunnery.add_theme_font_size_override("font_size",16); _gunnery.add_theme_color_override("font_color",Parchment.MUTED); commands.add_child(_gunnery)
	var fire_toggle:=button(handling,"toggle_fire","火攻",{});fire_toggle.pressed.connect(_toggle_fire)
	_build_fire_panel()

	_help_panel=PanelContainer.new(); _help_panel.name="SailingManual"; _help_panel.add_theme_stylebox_override("panel",Parchment.panel(16,"folio")); _screen.add_child(_help_panel)
	var help_layout:=VBoxContainer.new(); help_layout.name="SailingManualLayout"; help_layout.add_theme_constant_override("separation",10); _help_panel.add_child(help_layout)
	var help_title:=Label.new(); help_title.name="SailingManualHeading"; help_title.text="操船手册"; help_title.add_theme_font_override("font",Parchment.title_font()); help_title.add_theme_font_size_override("font_size",26); help_layout.add_child(help_title)
	var help_scroll:=ScrollContainer.new(); help_scroll.name="SailingManualScroll"; help_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; help_scroll.follow_focus=true; help_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; help_layout.add_child(help_scroll)
	var help_column:=VBoxContainer.new(); help_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; help_column.add_theme_constant_override("separation",10); help_scroll.add_child(help_column)
	var hint:=Label.new(); hint.name="MouseSailingHint"; hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; hint.text="左键点海面持续航行 · 中键停船\n按住右键拖动视角 · 滚轮缩放\nF 恢复跟船 · W / S 升帆与收帆\nA / D 转舵 · [ / ] 调整帆角\n空格 朝最近敌舰开炮 · M 航图\nEsc 打开航行菜单"; hint.add_theme_font_size_override("font_size",16); hint.add_theme_color_override("font_color",Parchment.INK); help_column.add_child(hint)
	var actions:=HFlowContainer.new(); help_column.add_child(actions)
	button(actions,"settings","航海设置",{"type":"open-settings"})
	button(actions,"surrender","降旗投降",{"type":"begin-surrender"})
	var close_help:=button(help_column,"close_help","收起手册",{}); close_help.pressed.connect(_toggle_help); _help_panel.hide()

	_modal=PanelContainer.new(); _modal.name="PracticeModal"; _modal.add_theme_stylebox_override("panel",Parchment.panel(16,"folio")); _screen.add_child(_modal)
	var modal_column:=VBoxContainer.new(); modal_column.add_theme_constant_override("separation",12); _modal.add_child(modal_column)
	_modal_title=Label.new(); _modal_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _modal_title.add_theme_font_size_override("font_size",28); _modal_title.add_theme_font_override("font",Parchment.title_font()); _modal_title.add_theme_color_override("font_color",Parchment.CINNABAR); modal_column.add_child(_modal_title)
	button(modal_column,"resume","继续航行",{"type":"resume"})
	button(modal_column,"confirm_surrender","确认降旗",{"type":"confirm-surrender"})
	button(modal_column,"cancel_surrender","继续抵抗",{"type":"cancel-surrender"})
	button(modal_column,"restart","重新开始",{"type":"restart"}); button(modal_column,"main_menu","返回主菜单",{"type":"main-menu"})
	chart=Chart.new(); chart.name="PracticeChart"; _screen.add_child(chart); chart.hide()
	var chart_frame:=ChartFrame.new(); chart_frame.name="PracticeChartFrame"; _screen.add_child(chart_frame); _screen.move_child(chart_frame,chart.get_index())
	chart_frame.follow(chart,Parchment.window_edge("folio"))
	button(chart,"close_chart","收起航图",{"type":"chart","value":false}).position=Vector2(12,8)
	get_viewport().size_changed.connect(_layout); _layout(); _modal.hide()

func button(parent: Node,id: String,title: String,intent: Dictionary) -> Button:
	var control:=Button.new(); control.name=id; control.text=title; control.custom_minimum_size.y=38; control.focus_mode=Control.FOCUS_NONE; control.size_flags_horizontal=Control.SIZE_EXPAND_FILL; parent.add_child(control); _buttons[id]=control
	control.pressed.connect(func():
		if intent.is_empty(): return
		var request:=intent.duplicate(true)
		if request.type=="pause" and "blur" in _snapshot.get("runtime",{}).get("pauseReasons",[]): request.type="resume"
		if request.type=="confirm-surrender": request.request=_snapshot.get("runtime",{}).get("surrenderQuote",{}).get("request",{}).duplicate(true)
		command_requested.emit(request))
	return control

func _toggle_help() -> void:
	_help_panel.visible=not _help_panel.visible
	if _help_panel.visible:_fire_open=false
	_buttons.help.text="收起手册" if _help_panel.visible else "操船手册"
	_layout()

func _build_fire_panel()->void:
	_fire_panel=PanelContainer.new();_fire_panel.name="FirePanel";_fire_panel.add_theme_stylebox_override("panel",Parchment.panel(16,"folio"));_screen.add_child(_fire_panel)
	var scroll:=ScrollContainer.new();scroll.name="FireScroll";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.follow_focus=true;_fire_panel.add_child(scroll)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",10);scroll.add_child(column)
	var heading:=HBoxContainer.new();column.add_child(heading)
	var title:=Label.new();title.text="火攻";title.add_theme_font_override("font",Parchment.title_font());title.add_theme_font_size_override("font_size",26);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(title)
	var close:=button(heading,"close_fire","收起",{});close.size_flags_horizontal=0;close.pressed.connect(_toggle_fire)
	_fire_state=_fire_label(column,"FireState",Parchment.INK)
	_fire_stores=_fire_label(column,"FireStores",Parchment.MUTED)
	var target_label:=_fire_label(column,"FireTargetLabel",Parchment.INK);target_label.text="投送目标"
	_fire_target=OptionButton.new();_fire_target.name="FireTarget";_fire_target.custom_minimum_size.y=38;_fire_target.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_fire_target.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;column.add_child(_fire_target)
	_fire_target.item_selected.connect(func(index):
		_fire_target_id=str(_fire_target.get_item_metadata(index))
		if not _snapshot.is_empty():_apply_fire(_snapshot)
		_release_fire_target_focus())
	_fire_target.get_popup().about_to_popup.connect(func():
		_fire_popup_active=true
		owned_popup_focus_changed.emit())
	_fire_target.get_popup().popup_hide.connect(func():
		_fire_popup_active=false
		call_deferred("_release_fire_target_focus")
		owned_popup_focus_changed.emit())
	_fire_target.get_popup().focus_exited.connect(func():owned_popup_focus_changed.emit())
	var payloads:=HFlowContainer.new();payloads.add_theme_constant_override("h_separation",6);payloads.add_theme_constant_override("v_separation",6);column.add_child(payloads)
	for entry in [["fire_ball","引火球","fire-ball"],["thorn_ball","蒺藜火球","thorn-ball"]]:
		var control:=button(payloads,entry[0],entry[1],{})
		var payload:String=entry[2]
		control.pressed.connect(func():
			if not _fire_target_id.is_empty():command_requested.emit({"type":"launch-fire","payload":payload,"targetId":_fire_target_id}))
	_fire_advice=_fire_label(column,"FireAdvice",Parchment.MUTED)
	var hint:=_fire_label(column,"FireTactics",Parchment.MUTED)
	hint.text="靠近敌舰至70米内投送。\n本船起火时，点击操船栏的「扑救火灾」。\n水手自动前往，火灭后自动归位。"
	_fire_panel.hide()

func _fire_label(parent:Node,id:String,color:Color)->Label:
	var label:=Label.new();label.name=id;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;label.add_theme_font_size_override("font_size",16);label.add_theme_color_override("font_color",color);parent.add_child(label);return label

func _toggle_fire()->void:
	_fire_open=not _fire_open
	if not _fire_open:_release_fire_target_focus()
	if _fire_open:_help_panel.hide();_buttons.help.text="操船手册"
	if not _snapshot.is_empty():_apply_fire(_snapshot)
	_layout()

func _release_fire_target_focus()->void:
	if is_instance_valid(_fire_target) and not _fire_target.get_popup().visible:_fire_target.release_focus()

func is_fire_popup_active()->bool:return _fire_popup_active
func fire_popup_has_focus()->bool:
	return is_instance_valid(_fire_target) and _fire_target.get_popup().visible and _fire_target.get_popup().has_focus()

func _request_fire_work()->void:
	if _snapshot.is_empty() or _buttons.fight_fire.disabled:return
	var native:Dictionary=_snapshot.naval
	var player:Dictionary=native.ships.filter(func(s):return s.id==native.playerId)[0]
	var control:Dictionary=player.fireControl
	var workers:int=Fire.reserved_crew(control,int(player.crew))
	var returning:bool=workers>0 and control.pendingFirefighters>0 and (control.supplies==0 or control.heat==0)
	command_requested.emit({"type":"fire-control","crew":0 if returning else 4})

func _apply_fire(packet:Dictionary)->void:
	var native:Dictionary=packet.naval;var state:Dictionary=packet.runtime
	var player:Dictionary=native.ships.filter(func(s):return s.id==native.playerId)[0]
	var equipped:bool=player.has("fireLauncher") and Fire.valid(player.get("fireControl"))
	_buttons.toggle_fire.visible=equipped
	_buttons.fight_fire.visible=equipped
	_fire_panel.visible=equipped and _fire_open and not _modal.visible and not chart.visible
	_buttons.toggle_fire.text="收起火攻" if _fire_panel.visible else "火攻"
	if not equipped:return
	var control:Dictionary=player.fireControl;var launcher:Dictionary=player.fireLauncher
	var workers:int=Fire.reserved_crew(control,int(player.crew))
	var phase:String="正在归位" if control.transferTicks>0 and control.pendingFirefighters==0 else "赶往火场" if control.transferTicks>0 else "扑救中" if control.heat>0 and workers>0 and control.supplies>0 else "扑救受阻" if control.heat>0 and workers>0 else "起火待扑救" if control.heat>0 else "未起火"
	_fire_state.text="本船火情：%s\n扑救占用：%d名水手"%[phase,workers]
	_fire_state.add_theme_color_override("font_color",Parchment.DANGER if control.heat>0 else Parchment.INK)
	_fire_stores.text="扑救储备 %d份%s\n火攻准备 %.1f秒"%[control.supplies," · 已耗尽" if control.supplies==0 else "",launcher.cooldownSeconds]
	var targets:Array=[]
	for enemy:Dictionary in native.ships:
		if enemy.team=="hostile" and enemy.hull>0:targets.append({"id":enemy.id,"name":enemy.name})
	if targets!=_fire_targets:
		_fire_targets=targets.duplicate(true);_fire_target.clear()
		for enemy:Dictionary in targets:
			_fire_target.add_item(enemy.name);_fire_target.set_item_metadata(_fire_target.item_count-1,enemy.id)
		if not targets.any(func(t):return t.id==_fire_target_id):_fire_target_id=targets[0].id if not targets.is_empty() else ""
		for index:int in _fire_target.item_count:
			if str(_fire_target.get_item_metadata(index))==_fire_target_id:_fire_target.select(index)
	_fire_target.disabled=state.paused or _fire_target.item_count==0
	var blocked:bool=state.paused or native.status in ["victory","defeat","surrendered"]
	var reasons:Array[String]=[]
	for entry in [["fire_ball","引火球","fire-ball"],["thorn_ball","蒺藜火球","thorn-ball"]]:
		var quote:Dictionary=state.get("fireQuotes",{}).get(_fire_target_id,{}).get(entry[2],{"ok":false,"reason":"target-unavailable"})
		var reason:String=_fire_reason(quote.get("reason",""))
		_buttons[entry[0]].text="%s · %d"%[entry[1],launcher.ammo[entry[2]]]
		_buttons[entry[0]].disabled=blocked or not quote.ok
		_buttons[entry[0]].tooltip_text=reason if not quote.ok else "占用4名水手2秒；真实命中后起火。"
		if not quote.ok and not reason in reasons:reasons.append(reason)
	_fire_advice.text="无可投送的敌舰。" if _fire_target_id.is_empty() else "可投送；命中后持续燃烧。" if reasons.is_empty() else "\n".join(reasons)
	var fight_reason:String="水手自动前往扑救，火灭后自动归位；期间会暂时占用部分炮手。"
	var can_fight:bool=true
	var can_return:bool=workers>0 and control.pendingFirefighters>0 and (control.supplies==0 or control.heat==0)
	_buttons.fight_fire.text="返回岗位" if can_return else "扑救火灾"
	if blocked:can_fight=false;fight_reason="暂停或战斗结束时无法下令。"
	elif can_return:fight_reason="扑救已无法继续，点击让水手返回原岗位；火情仍按实际状态结算。"
	elif control.transferTicks>0 or workers>0:can_fight=false;fight_reason=phase+"，无需重复派遣。"
	elif control.heat<=0:can_fight=false;fight_reason="本船未起火。"
	elif control.supplies<=0:can_fight=false;fight_reason="扑救储备已耗尽。"
	elif int(player.get("availableCrew",player.crew))<4:can_fight=false;fight_reason="可用水手不足；投送操作结束后再试。"
	_buttons.fight_fire.disabled=not can_fight
	_buttons.fight_fire.tooltip_text=fight_reason

static func _fire_reason(reason:String)->String:
	return preload("res://game/runtime/naval_practice_runtime.gd").fire_reason(reason)

func configure_chart(ports: Array,height: Callable) -> bool: return chart.configure(ports,height,{"title":"近海航图"})

func _layout() -> void:
	var viewport:=get_viewport().get_visible_rect().size
	var margin:=12.0 if viewport.x<600 else 18.0
	_panel.position=Vector2(margin,margin); _panel.size=Vector2(minf(430,viewport.x-margin*2),0)
	var command_height:=minf(220,viewport.y*0.46) if viewport.x<600 else minf(164,viewport.y*0.34)
	_command_panel.size=Vector2(minf(1020,viewport.x-margin*2),command_height); _command_panel.position=Vector2((viewport.x-_command_panel.size.x)/2,viewport.y-margin-command_height)
	_help_panel.size=Vector2(minf(380,viewport.x-margin*2),minf(320,viewport.y-command_height-margin*3))
	_help_panel.position=Vector2(viewport.x-_help_panel.size.x-margin,margin)
	_modal.size=Vector2(minf(360,viewport.x-28),minf(310,viewport.y-28)); _modal.position=(viewport-_modal.size)/2
	chart.size=Vector2(clampf(viewport.x-44,240,960),minf(500,viewport.y-44)); chart.position=(viewport-chart.size)/2
	if _fire_panel:
		_fire_panel.size=Vector2(minf(360,viewport.x-margin*2),maxf(100,viewport.y-command_height-margin*3))
		_fire_panel.position=Vector2(viewport.x-_fire_panel.size.x-margin,margin)
		_panel.visible=not (_fire_panel.visible and viewport.x<720)
		if _fire_panel.visible and viewport.x>=720:_panel.size.x=minf(_panel.size.x,_fire_panel.position.x-margin*2)

func is_menu_open() -> bool: return _menu

func apply_snapshot(packet: Dictionary) -> void:
	_snapshot=packet.duplicate(true)
	var native: Dictionary=packet.naval; var state: Dictionary=packet.runtime; var player: Dictionary=native.ships.filter(func(s): return s.id==native.playerId)[0]
	var speed:=Vector2(player.visual.velocity.x,player.visual.velocity.z).length()*1.943844
	_heading.text="%s · %s" % [{"duel":"单舰炮战","fleet":"舰队遭遇","sail":"自由试航","fire":"火攻交锋"}[state.mode],player.name]
	_status.text="航向 %03d°   航速 %.1f 节   风速 %.0f m/s\n船体 %d%%   风帆 %d%%   水手 %d" % [fposmod(rad_to_deg(player.visual.heading),360),speed,native.wind.speed,player.hull/player.maxHull*100,player.sail/player.maxSail*100,player.crew]
	if player.get("fireControl",{}).get("heat",0.0)>0.0:
		var fire_state:Dictionary=player.fireControl
		_status.text+="\n本船起火 · "+("水手正在扑救" if fire_state.assignedFirefighters>0 or fire_state.pendingFirefighters>0 else "扑救储备已耗尽" if fire_state.supplies==0 else "点击「扑救火灾」")
	_notice.text=state.notice; _notice.visible=not _notice.text.is_empty(); _notice.tooltip_text=_notice.text
	_applying=true; _sails.value=player.sailDeployment*100; _sail_readout.text="%d%%" % (player.sailDeployment*100); _applying=false
	var terminal: bool=native.status in ["victory","defeat","surrendered"]
	var quote: Dictionary=state.surrenderQuote; _menu="menu" in state.pauseReasons
	_modal.visible=_menu or terminal or not quote.is_empty()
	_modal_title.text="向%s降旗？" % quote.get("captorName","") if not quote.is_empty() else {"victory":"海战获胜","defeat":"旗舰战败","surrendered":"已降旗投降"}.get(native.status,"航行暂停")
	_buttons.resume.visible=_menu and not terminal and quote.is_empty()
	_buttons.confirm_surrender.visible=not quote.is_empty(); _buttons.cancel_surrender.visible=not quote.is_empty()
	_buttons.restart.visible=quote.is_empty(); _buttons.main_menu.visible=quote.is_empty()
	for id in ["fire_port","fire_starboard","solid","chain","grape","trim","surrender","stop_sailing"]: _buttons[id].disabled=state.paused or terminal
	_buttons.stop_sailing.disabled=_buttons.stop_sailing.disabled or player.hull<=0 or player.crew<=0
	var gunnery_lines: Array[String] = []
	for side in ["port","starboard"]:
		var readiness := Cannon.broadside_status(native,player.id,side)
		var control: Button = _buttons["fire_"+side]
		control.tooltip_text = readiness.label
		control.disabled = control.disabled or readiness.phase in ["unavailable","no-guns","not-operational","reloading","no-ammo","blocked"]
		gunnery_lines.append(("左舷" if side == "port" else "右舷") + " · " + readiness.label)
	_gunnery.text = "   /   ".join(gunnery_lines)
	var ammunition_labels := {"solid":"实心弹 1","chain":"链弹 2","grape":"葡萄弹 3"}
	var ammunition_help := {"solid":"船壳 / 射程250米","chain":"风帆 / 射程190米","grape":"水手 / 射程80米"}
	for ammo: String in ammunition_labels:
		_buttons[ammo].text = "%s · %d" % [ammunition_labels[ammo],player.ammo[ammo]]
		_buttons[ammo].set_pressed_no_signal(player.ammoType == ammo)
		_buttons[ammo].tooltip_text = ("当前炮弹 · " if player.ammoType == ammo else "") + ammunition_help[ammo]
	_buttons.surrender.visible=state.mode!="sail"; _sails.editable=not state.paused and not terminal
	_buttons.pause.text="继续" if "player" in state.pauseReasons or "blur" in state.pauseReasons else "暂停"
	chart.visible="chart" in state.pauseReasons; chart.apply_naval_snapshot(native); _apply_fire(packet);_layout()
