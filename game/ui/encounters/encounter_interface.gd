extends Control
## Renders the coordinator's detached model. Never advances models or computes rewards.
signal command_requested(intent:Dictionary)
const Parchment=preload("res://game/ui/shared/parchment_theme.gd")
const Text=preload("res://game/domain/legacy/utf16_text.gd")
const TITLES={"duel":"船长决斗","landBattle":"登岸交锋","treasure":"孤岛寻宝","banquet":"港口雅宴"}
const DIRECTIONS={"up":"↑ 举手","down":"↓ 俯身","left":"← 左揖","right":"→ 右揖"}
const ACTIONS={"high":"上段斩 [J]","low":"下段斩 [K]","thrust":"突刺 [L]","guard-high":"上段防守 [U]","guard-low":"下段防守 [I]","parry":"招架反击 [O]","dodge":"侧身闪避 [空格]"}
const EVENTS={"ready":"准备就绪","hit":"刀锋命中","enemy-blocked":"对手挡下这一击","counterattack":"反击命中","enemy-windup":"对手起手，准备防守","parried":"招架成功，趁势反击","dodged":"成功避开攻势","blocked":"挡住了这一击","injured":"受到攻击","moved":"已抵达新位置","guard-repelled":"守卫阻止通行，请绕行","empty-dig":"此处没有宝藏","treasure-found":"寻获宝藏","perfect":"正中节拍","good":"应和成功","missed":"错过这一拍","off-beat":"尚未到拍，请等金色窗口","wrong-gesture":"手势方向不符"}
var _packet:Dictionary={}
var _revision=0
var _serial=0
var _token=""
var _panel:PanelContainer
var _content:VBoxContainer
var _bindings:Array[Callable]=[]
var _kind=""
var _identity=""
var _disposed=false
func _ready():
	theme=Parchment.create();mouse_filter=Control.MOUSE_FILTER_IGNORE;set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);visible=false;resized.connect(_layout)
func _exit_tree():_disposed=true;_token="disposed"
func _state()->Dictionary:return _packet.get("state",_packet.get("model",{}))
func _active()->bool:return _state().get("phase")=="active" and not _packet.get("paused",false)
func apply_snapshot(packet:Dictionary,revision=0):
	_packet=packet.duplicate(true);_revision=revision
	if _packet.is_empty():visible=false;return
	var identity=str(_packet.get("generation",0))+":"+str(_packet.get("id",""))+":"+str(_packet.get("kind",_state().get("kind","")))
	visible=true
	if identity!=_identity or not _panel:
		_identity=identity;_serial+=1;_token=identity+":"+str(_serial);_kind=_packet.get("kind",_state().get("kind",""));_build()
	for binding in _bindings:binding.call()
	_layout()
func _emit(payload:Dictionary,token:String):
	if token!=_token or _disposed or not is_inside_tree():return
	var intent=payload.duplicate(true);intent.id=_packet.get("id");intent.generation=_packet.get("generation",0);intent.expectedRevision=_revision;command_requested.emit(intent)
func _action(action,token:String):
	if _active():_emit({"type":"encounter-action","action":action},token)
func _label(id:String,watch:Callable)->Label:
	var label=Label.new();label.name=id;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if id=="encounter_heading":
		label.add_theme_font_override("font",Parchment.title_font());label.add_theme_font_size_override("font_size",24);label.add_theme_color_override("font_color",Parchment.CINNABAR)
	elif id=="encounter_context":
		label.add_theme_font_size_override("font_size",14);label.add_theme_color_override("font_color",Parchment.MUTED)
	_content.add_child(label);_bindings.append(func():label.text=Text.display_text(str(watch.call())));return label
func _button(parent,id:String,title:String,callback:Callable,enabled:Callable)->Button:
	var b=Button.new();b.name=id;b.text=title;b.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(b);var font=b.get_theme_default_font();b.custom_minimum_size=Vector2(max(76.0,font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,b.get_theme_default_font_size()).x+24),38);var token=_token;b.pressed.connect(func():
		if token==_token and not b.disabled:callback.call(token))
	_bindings.append(func():b.disabled=not enabled.call());return b
func _build():
	_bindings.clear()
	if _panel:remove_child(_panel);_panel.queue_free()
	_panel=PanelContainer.new();_panel.name="encounter_panel";add_child(_panel)
	var scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_panel.add_child(scroll)
	_content=VBoxContainer.new();_content.name="encounter_content";_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_content.add_theme_constant_override("separation",12);scroll.add_child(_content)
	_label("encounter_heading",func():return TITLES.get(_kind,"挑战")+" · "+("演练" if _packet.get("practice",false) else "生涯挑战"))
	_label("encounter_context",func():return "难度："+{"easy":"简单","normal":"标准","hard":"困难"}.get(_packet.get("difficulty","normal"),"标准")+" · "+str(_packet.get("context",{}).get("opponent",{}).get("name","")))
	match _kind:
		"duel":_duel()
		"landBattle":_land()
		"treasure":_treasure()
		"banquet":_banquet()
	_label("feedback",func():return EVENTS.get(_state().get("lastEvent"),"行动已记录"))
	_label("encounter_result",func():
		var result=_state().get("result");return "" if result==null else "%s · 实际得分 %s · 伤势 %s%%"%[{"won":"挑战获胜","lost":"挑战失利","retreated":"已撤退"}.get(_state().get("phase"),"已结束"),result.get("score",0),result.get("injury",0)])
	_label("settlement_notice",_settlement_text)
	var actions=HFlowContainer.new();_content.add_child(actions)
	_button(actions,"encounter_pause","暂停 / 继续挑战",func(token):_emit({"type":"encounter-pause","value":not _packet.get("paused",false)},token),func():return _state().get("phase")=="active")
	_button(actions,"retreat","退出挑战",func(token):_emit({"type":"encounter-retreat"},token),_active)
	if _kind=="duel":
		for disposition in ["capture","plunder","release"]:
			_button(actions,"settle_"+disposition,{"capture":"俘获敌舰","plunder":"掠取货物","release":"释放敌舰"}[disposition],func(token):_emit({"type":"encounter-settle","disposition":disposition},token),func():return _state().get("phase")=="won" and not _packet.get("practice",false) and not _packet.get("settled",false))
	_button(actions,"settle","确认实际结果",func(token):_emit({"type":"encounter-settle"},token),func():return _state().get("phase")!="active" and not _packet.get("settled",false) and not (_kind=="duel" and _state().get("phase")=="won" and not _packet.get("practice",false)))
	_button(actions,"retry","再次演练",func(token):_emit({"type":"encounter-retry"},token),func():return _state().get("phase")!="active" and _packet.get("practice",false))
	_button(actions,"encounter_close","返回航程",func(token):_emit({"type":"encounter-close"},token),func():return _state().get("phase")!="active" and _packet.get("settled",false))
func _duel():
	_label("duel_stats",func():return "船长生命 %s · 对手生命 %s · 体力 %s\n连击 %s · 收招 %.2f 秒"%[_state().get("playerHealth",0),_state().get("enemyHealth",0),snapped(_state().get("stamina",0),.1),_state().get("combo",0),_state().get("cooldown",0)])
	_label("duel_telegraph",func():return "对手起手：%s · 防守窗口 %.2f 秒"%[{"high":"上段","low":"下段","thrust":"突刺"}.get(_state().get("telegraph"),"尚未起手"),_state().get("actionWindow",0)])
	_label("duel_guard",func():return "对手守势："+{"high":"上段","low":"下段"}.get(_state().get("enemyGuard"),"未知"))
	var actions=HFlowContainer.new();_content.add_child(actions)
	for action in ACTIONS:
		_button(actions,"duel_"+action,ACTIONS[action],func(token):_action(action,token),func():return _active() and _state().get("cooldown",0)<=0 and _state().get("stamina",0)>=(18 if action=="parry" else 22 if action=="dodge" else 8 if action.begins_with("guard") else 14))
func _settlement_text()->String:
	var settlement=_packet.get("settlement",{})
	if settlement.is_empty():return str(_packet.get("notice",""))
	if settlement.get("mode")=="practice":return "演练结果已确认。生涯银两、士气与关系保持原状。"
	var before=settlement.get("before",{});var after=settlement.get("after",{})
	return "生涯宴会 · 评分 %s/100 · 实付 %s 两\n士气 %s 至 %s · 名望 %s 至 %s · 当地关系 %s 至 %s\n实际银两 %s 至 %s"%[settlement.get("score",0),settlement.get("paid",0),before.get("morale",0),after.get("morale",0),before.get("fame",0),after.get("fame",0),before.get("relation",0),after.get("relation",0),before.get("silver",0),after.get("silver",0)] if _kind=="banquet" else "生涯结果已确认 · 实付 %s 两 · 银两 %s 至 %s"%[settlement.get("paid",0),before.get("silver",0),after.get("silver",0)]
func _grid(kind:String):
	var grid=GridContainer.new();grid.name="grid";grid.columns=9;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_theme_constant_override("h_separation",2);grid.add_theme_constant_override("v_separation",2);_content.add_child(grid)
	for y in 7:
		for x in 9:
			var b=_button(grid,"cell_%s_%s"%[x,y],"",func(token):
				if kind=="landBattle":
					var unit=_unit_at(x,y)
					_action({"type":"select","id":unit.id} if unit.get("side")=="player" else {"type":"attack","id":unit.id} if not unit.is_empty() else {"type":"move","x":x,"y":y},token),func():return _active() and kind=="landBattle")
			b.custom_minimum_size=Vector2(0,42);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;b.add_theme_font_size_override("font_size",13)
			for style_name in ["normal","hover","pressed","disabled","focus"]:
				var compact_style=b.get_theme_stylebox(style_name).duplicate()
				compact_style.set_content_margin_all(2)
				b.add_theme_stylebox_override(style_name,compact_style)
			_bindings.append(func():
				var terrain=_state().get("terrain",[]);var value=str(terrain[y][x]) if terrain.size()>y and terrain[y].size()>x else "ground";var unit=_unit_at(x,y)
				if kind=="treasure":
					var revealed=_state().get("revealed",[]);var known=revealed.size()>y and revealed[y][x];b.text="？" if not known else "船长" if _state().get("position",{})=={"x":x,"y":y} else "守卫" if _state().get("guard",{})=={"x":x,"y":y} else "墙" if value=="wall" else "古石" if _state().get("treasure",{})=={"x":x,"y":y} else "·"
				else:
					b.text=("我" if unit.get("side")=="player" else "敌")+("刀" if unit.get("role")=="melee" else "铳")+"\n"+str(unit.get("health",0)) if not unit.is_empty() else "墙" if value=="wall" else "掩体" if value=="cover" else "·"
					b.modulate=Color("b9d0cb") if unit.get("id")==_state().get("selectedUnitId") else Color("e4b5a4") if unit.get("side")=="enemy" else Color.WHITE
				b.tooltip_text="第%s列，第%s行：%s"%[x+1,y+1,b.text.replace("\n"," ")])
func _unit_at(x,y)->Dictionary:
	for unit in _state().get("units",[]):
		if unit.get("x")==x and unit.get("y")==y:return unit
	return {}
func _land():
	_label("land_stats",func():
		var selected={}
		for unit in _state().get("units",[]):
			if unit.id==_state().get("selectedUnitId"):selected=unit
		return "第 %s 回合 · %s · 剩余移动 %s / 攻击 %s"%[_state().get("turn",1),"我方刀兵" if selected.get("role")=="melee" else "我方鸟铳手",selected.get("movesLeft",0),selected.get("attacksLeft",0)])
	_label("land_help",func():return "点击我军选择部队，空地移动，敌军攻击。城墙阻挡；掩体减轻鸟铳伤害。")
	_grid("landBattle");_button(_content,"end_turn","结束回合 · 敌军行动",func(token):_action({"type":"end-turn"},token),_active)
func _treasure():
	_label("treasure_clue",func():return _state().get("clue",""))
	_label("treasure_stats",func():return "生命 %s · 剩余挖掘 %s · 已走 %s 步"%[_state().get("playerHealth",0),_state().get("digsLeft",0),_state().get("moves",0)])
	_grid("treasure");var directions=HFlowContainer.new();_content.add_child(directions)
	for direction in DIRECTIONS:_button(directions,"move_"+direction,DIRECTIONS[direction],func(token):_action({"type":"move","direction":direction},token),_active)
	_button(_content,"dig","在当前位置掘土",func(token):_action({"type":"dig"},token),_active)
func _banquet():
	_label("banquet_stats",func():return "得分 %s · 连击 %s / 最高 %s · 命中 %s · 失误 %s\n经过 %.2f / %.2f 秒"%[_state().get("score",0),_state().get("combo",0),_state().get("maxCombo",0),_state().get("hits",0),_state().get("mistakes",0),_state().get("elapsed",0),_state().get("duration",0)])
	_label("banquet_cues",func():
		var lines:PackedStringArray=[]
		for cue in _state().get("cues",[]):
			if cue.get("status")=="pending" and cue.time>=_state().get("elapsed",0)-_state().get("hitWindow",0):
				lines.append("%s · %.2f 秒%s"%[DIRECTIONS.get(cue.direction,""),cue.time," · 应和窗口" if abs(cue.time-_state().get("elapsed",0))<=_state().get("hitWindow",0) else ""])
				if lines.size()==4:break
		return "\n".join(lines))
	var directions=HFlowContainer.new();_content.add_child(directions)
	for direction in DIRECTIONS:_button(directions,"gesture_"+direction,DIRECTIONS[direction],func(token):_action(direction,token),_active)
func request_key(code:String):
	if not _active():return
	if _kind=="duel":
		var action={"KeyJ":"high","KeyK":"low","KeyL":"thrust","KeyU":"guard-high","KeyI":"guard-low","KeyO":"parry","Space":"dodge"}.get(code)
		if action!=null:_action(action,_token)
	elif _kind in ["treasure","banquet"]:
		var direction={"ArrowUp":"up","ArrowDown":"down","ArrowLeft":"left","ArrowRight":"right"}.get(code)
		if direction!=null:_action(direction if _kind=="banquet" else {"type":"move","direction":direction},_token)
func _layout():
	if not _panel:return
	var viewport=get_viewport_rect().size;var width=min(780.0,max(200.0,viewport.x-24));_panel.position=Vector2((viewport.x-width)/2,16);_panel.size=Vector2(width,max(120,viewport.y-32))
