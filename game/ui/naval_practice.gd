extends CanvasLayer
## Practice HUD consumes canonical snapshots; emits intents only.
signal command_requested(intent: Dictionary)
signal view_requested(tactical: bool)
const Chart=preload("res://game/ui/charts/nautical_chart.gd")
const Cannon=preload("res://modules/naval_simulation/combat/cannon_system.gd")
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
func _ready() -> void:
	_screen=Control.new(); _screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _screen.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(_screen)
	var theme:=Theme.new(); var font:=SystemFont.new(); font.font_names=PackedStringArray(["Microsoft YaHei","sans-serif"]); theme.default_font=font; theme.default_font_size=17; _screen.theme=theme
	var panel:=PanelContainer.new(); _panel=panel; panel.position=Vector2(18,18)
	var style:=StyleBoxFlat.new(); style.bg_color=Color(0.035,0.13,0.14,0.94); style.border_color=Color("c5a46b"); style.set_border_width_all(1); style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel",style); _screen.add_child(panel)
	var scroll:=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.follow_focus=true; panel.add_child(scroll)
	var column:=VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",10); scroll.add_child(column)
	_status=Label.new(); _status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _status.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _status.add_theme_color_override("font_color",Color("f1e6cb")); column.add_child(_status)
	_sails=HSlider.new(); _sails.name="sails"; _sails.min_value=0; _sails.max_value=100; _sails.step=1; column.add_child(_sails)
	_sails.value_changed.connect(func(value):
		if not _applying: command_requested.emit({"type":"sails","value":value/100.0}))
	var cannons:=HFlowContainer.new(); column.add_child(cannons)
	button(cannons,"fire_port","左舷开炮 Q",{"type":"fire","side":"port"}); button(cannons,"fire_starboard","右舷开炮 E",{"type":"fire","side":"starboard"})
	_gunnery=Label.new(); _gunnery.name="GunneryStatus"; _gunnery.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _gunnery.add_theme_font_size_override("font_size",14); column.add_child(_gunnery)
	var ammo:=HFlowContainer.new(); column.add_child(ammo)
	for entry in [["solid","实心弹 1"],["chain","链弹 2"],["grape","葡萄弹 3"]]: button(ammo,entry[0],entry[1],{"type":"select-ammo","ammo":entry[0]})
	var sailing:=HFlowContainer.new(); column.add_child(sailing)
	button(sailing,"trim","自动调帆 R",{"type":"trim"}); button(sailing,"pause","暂停",{"type":"pause"})
	var views:=HFlowContainer.new(); column.add_child(views)
	var captain:=button(views,"captain_view","船长视角",{}); captain.pressed.connect(func(): view_requested.emit(false))
	var tactical:=button(views,"tactical_view","高位视角",{}); tactical.pressed.connect(func(): view_requested.emit(true))
	var actions:=HFlowContainer.new(); column.add_child(actions)
	button(actions,"surrender","降旗投降",{"type":"begin-surrender"}); button(actions,"settings","设置",{"type":"open-settings"})
	var hint:=Label.new(); hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; hint.text="W/S 升帆与收帆 · A/D 转舵\n空格 朝最近敌舰开炮 · M 航图\n[ / ] 调整帆角 · Esc 菜单"; hint.add_theme_font_size_override("font_size",14); hint.add_theme_color_override("font_color",Color("d2c6a7")); column.add_child(hint)
	_notice=Label.new(); _notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _notice.add_theme_color_override("font_color",Color("e7c887")); column.add_child(_notice)
	_modal=PanelContainer.new(); _modal.add_theme_stylebox_override("panel",style.duplicate()); _screen.add_child(_modal)
	var modal_column:=VBoxContainer.new(); modal_column.add_theme_constant_override("separation",12); _modal.add_child(modal_column)
	_modal_title=Label.new(); _modal_title.add_theme_font_size_override("font_size",24); modal_column.add_child(_modal_title)
	button(modal_column,"resume","继续航行",{"type":"resume"})
	button(modal_column,"confirm_surrender","确认降旗",{"type":"confirm-surrender"})
	button(modal_column,"cancel_surrender","继续抵抗",{"type":"cancel-surrender"})
	button(modal_column,"restart","重新开始",{"type":"restart"}); button(modal_column,"main_menu","返回主菜单",{"type":"main-menu"})
	chart=Chart.new(); chart.name="PracticeChart"; _screen.add_child(chart); chart.hide()
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
func configure_chart(ports: Array,height: Callable) -> bool: return chart.configure(ports,height,{"title":"近海航图"})
func _layout() -> void:
	var viewport:=get_viewport().get_visible_rect().size
	_panel.size=Vector2(minf(390,viewport.x-36),minf(460,viewport.y-36))
	_modal.size=Vector2(minf(360,viewport.x-28),310); _modal.position=(viewport-_modal.size)/2
	chart.size=Vector2(clampf(viewport.x-44,240,960),minf(500,viewport.y-44)); chart.position=(viewport-chart.size)/2
func is_menu_open() -> bool: return _menu
func apply_snapshot(packet: Dictionary) -> void:
	_snapshot=packet.duplicate(true)
	var native: Dictionary=packet.naval; var state: Dictionary=packet.runtime; var player: Dictionary=native.ships.filter(func(s): return s.id==native.playerId)[0]
	var speed:=Vector2(player.visual.velocity.x,player.visual.velocity.z).length()*1.943844
	_status.text="%s · %s\n航向 %03d°   航速 %.1f 节\n船体 %d%%   风帆 %d%%   水手 %d\n帆面 %d%%   风速 %.0f m/s\n炮弹 %d / 链弹 %d / 葡萄弹 %d\n左舷 %.1fs   右舷 %.1fs" % [{"duel":"单舰炮战","fleet":"舰队遭遇","sail":"自由试航"}[state.mode],player.name,fposmod(rad_to_deg(player.visual.heading),360),speed,player.hull/player.maxHull*100,player.sail/player.maxSail*100,player.crew,player.sailDeployment*100,native.wind.speed,player.ammo.solid,player.ammo.chain,player.ammo.grape,player.cooldownSeconds.port,player.cooldownSeconds.starboard]
	_notice.text=state.notice; _applying=true; _sails.value=player.sailDeployment*100; _applying=false
	var terminal: bool=native.status in ["victory","defeat","surrendered"]
	var quote: Dictionary=state.surrenderQuote; _menu="menu" in state.pauseReasons
	_modal.visible=_menu or terminal or not quote.is_empty()
	_modal_title.text="向%s降旗？" % quote.get("captorName","") if not quote.is_empty() else {"victory":"海战获胜","defeat":"旗舰战败","surrendered":"已降旗投降"}.get(native.status,"航行暂停")
	_buttons.resume.visible=_menu and not terminal and quote.is_empty()
	_buttons.confirm_surrender.visible=not quote.is_empty(); _buttons.cancel_surrender.visible=not quote.is_empty()
	_buttons.restart.visible=quote.is_empty(); _buttons.main_menu.visible=quote.is_empty()
	for id in ["fire_port","fire_starboard","solid","chain","grape","trim","surrender"]: _buttons[id].disabled=state.paused or terminal
	var gunnery_lines: Array[String] = []
	for side in ["port","starboard"]:
		var readiness := Cannon.broadside_status(native,player.id,side)
		var control: Button = _buttons["fire_"+side]
		control.tooltip_text = readiness.label
		control.disabled = control.disabled or readiness.phase in ["unavailable","no-guns","not-operational","reloading","no-ammo","blocked"]
		gunnery_lines.append(("左舷" if side == "port" else "右舷") + " · " + readiness.label)
	_gunnery.text = "\n".join(gunnery_lines)
	var ammunition_labels := {"solid":"实心弹 1 · 船壳 / 250米","chain":"链弹 2 · 风帆 / 190米","grape":"葡萄弹 3 · 水手 / 80米"}
	for ammo: String in ammunition_labels:
		_buttons[ammo].text = ammunition_labels[ammo] + (" · 当前" if player.ammoType == ammo else "")
	_buttons.surrender.visible=state.mode!="sail"; _sails.editable=not state.paused and not terminal
	_buttons.pause.text="继续" if "player" in state.pauseReasons or "blur" in state.pauseReasons else "暂停"
	chart.visible="chart" in state.pauseReasons; chart.apply_naval_snapshot(native); _layout()
