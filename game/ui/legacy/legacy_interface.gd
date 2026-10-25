extends CanvasLayer
## Detached canonical presentation. All decisions and mutations stay in Runtime.
signal command_requested(intent:Dictionary)
signal view_requested(tactical:bool)
const Catalog=preload("res://game/domain/legacy/catalog.gd")
const Text=preload("res://game/domain/legacy/utf16_text.gd")
const ThemeFactory=preload("res://game/ui/legacy/legacy_theme.gd")
const Parchment=preload("res://game/ui/shared/parchment_theme.gd")
const Chart=preload("res://game/ui/legacy/legacy_chart.gd")
const Gunnery=preload("res://modules/naval_simulation/combat/cannon_system.gd")
const C=Catalog.DATA
const PANELS={"market":"港口市场","shipyard":"修船与船坞","recruit":"船员与军需","officers":"舰队军官","quests":"委托簿","people":"港口人物","fleet":"我的舰队","factions":"势力关系","chart":"六港海图","log":"航海日志","save":"航程存档","settings":"设置与归航"}
const FACTIONS={"zheng":"郑氏水师","qing":"清廷","voc":"荷兰商馆","pirates":"海上群雄"}
const AMMO={"solid":"实心弹","chain":"链弹","grape":"葡萄弹"}
const SYSTEMS={"hull":"船体","cannons":"火炮","sails":"帆装","equipment":"操船装备"}
const SETTINGS_FIELDS=["quality","music","sound","reducedMotion","musicVolume","soundVolume"]
const PEOPLE={"merchant":{"name":"许秋棠 · 行商掌柜","image":"merchant-woman","words":"货随潮走，人凭信立。船长，远来的风把什么消息送进港了？"},"captain":{"name":"林正衡 · 水师联络官","image":"zheng-captain","words":"帆影归港便是好消息。海上每一袋军粮、每一艘护航船，都有人在等。"},"voc":{"name":"范德维克 · 荷兰商船代表","image":"voc-captain","words":"船长，海风不认旗号，码头却有各自的规矩。让我们从一桩公平的买卖谈起。"}}
var _packet:Dictionary={}
var _provider:Callable
var _screen:Control
var _hud:PanelContainer
var _operation:PanelContainer
var _menu:PanelContainer
var _result:PanelContainer
var _pages:Dictionary={}
var _watchers:Array[Callable]=[]
var _form:Dictionary={}
var _settings_dirty:Dictionary={}
var _generation=-1
var _mount=0
var _signature=""
var _panel="market"
var _panel_open=false
var _menu_open=false
var _layout_queued=false
var _recent:Dictionary={}
var _pending:Dictionary={}
var _dispatching:Dictionary={}
var _request_serial=0
var _quotes:Dictionary={}
var _revision=-1
var _dialog:FileDialog
var _retirement=false
var _leave_warning=false
func _ready():
	layer=20;process_mode=Node.PROCESS_MODE_ALWAYS;_build()
func _state()->Dictionary:return _packet.get("adventure",{})
func _runtime()->Dictionary:return _packet.get("runtime",{})
func _save_receipt()->Dictionary:return _runtime().get("saveStatus",_runtime().get("lastSaveReceipt",{}))
func _fleet()->Array:return _state().get("fleet",[])
func _ship(id)->Dictionary:
	for ship in _fleet():
		if ship.id==id:return ship
	return {}
func _flag()->Dictionary:return _ship(_state().get("flagshipId",""))
func _native()->Dictionary:
	for ship in _packet.get("naval",{}).get("ships",[]):
		if ship.get("id")==_state().get("flagshipId"):return ship
	return {}
func _display(value)->String:return Text.display_text(str(value))
func _port(id)->Dictionary:
	for port in C.PORTS:
		if port.id==id:return port
	return {}
func _port_name(id)->String:return _display(_port(id).get("name","海上航程"))
func _cargo(cargo:Dictionary)->String:
	var parts:PackedStringArray=[]
	for good in C.GOODS:
		if cargo.get(good,0)>0:parts.append(C.GOOD_NAMES[good]+" "+str(cargo[good]))
	return " · ".join(parts) if not parts.is_empty() else "货舱空置"
func _token()->String:return str(_generation)+":"+str(_mount)
func set_readiness_provider(provider:Callable):_provider=provider;_refresh()
static func command_signature(intent:Dictionary)->String:
	var keys=intent.keys();keys.sort();var canonical={}
	for key in keys:canonical[key]=intent[key]
	return JSON.stringify(canonical,"",false)
func _preview(intent:Dictionary)->Dictionary:
	if _provider.is_valid():
		var value=_provider.call(intent.duplicate(true))
		if value is Dictionary:return value
	var facts=_runtime().get("previews",{});var key=command_signature(intent)
	return facts.get(key,{"ok":false,"reason":"等待航况核验。"}).duplicate(true)
func apply_snapshot(packet:Dictionary):
	_packet=packet.duplicate(true)
	var generation=int(_runtime().get("generation",0));var revision=int(_runtime().get("revision",0))
	var generation_changed=generation!=_generation
	if revision!=_revision:_pending.clear();_revision=revision
	var signature=str(generation)
	for ship in _fleet():signature+="|s:"+str(ship.id)
	for quest in _state().get("quests",[]):signature+="|q:"+str(quest.id)
	for ship in _packet.get("naval",{}).get("ships",[]):signature+="|n:"+str(ship.id)
	if generation_changed:
		_form.clear();_settings_dirty.clear();_recent.clear();_pending.clear();_retirement=false;_leave_warning=false
	_generation=generation
	_hydrate_settings(generation_changed)
	if not _screen:return
	if signature!=_signature:_signature=signature;_build()
	_refresh()
func _hydrate_settings(generation_changed=false):
	var confirmed=_packet.get("settings",{})
	if not confirmed is Dictionary:return
	for key in SETTINGS_FIELDS:
		if not confirmed.has(key):continue
		var control=_screen.find_child("setting_"+key if key in ["music","sound","reducedMotion"] else key,true,false) if _screen else null
		if not generation_changed and control is SpinBox and control.get_line_edit().has_focus():continue
		var value=confirmed[key]*100.0 if key in ["musicVolume","soundVolume"] else confirmed[key]
		if _settings_dirty.has(key):
			var matches=is_equal_approx(float(_form[key]),float(value)) if value is float else _form[key]==value
			if not matches:continue
			_settings_dirty.erase(key)
		_form[key]=value
		if control is OptionButton:
			for index in control.item_count:
				if control.get_item_metadata(index)==value:control.select(index);break
		elif control is CheckBox:control.set_pressed_no_signal(value)
		elif control is SpinBox:control.set_value_no_signal(value)
func _setting_edited(key:String):
	if key in SETTINGS_FIELDS:_settings_dirty[key]=true
func _refresh():
	if not _screen:return
	if _leave_warning and _save_receipt().get("ok",false):_leave_warning=false
	_quotes.clear()
	for watcher in _watchers:watcher.call()
	_queue_layout()
func acknowledge_command(intent:Dictionary,receipt:Dictionary):
	if not receipt.has("ok") or intent.get("generation")!=_generation:return
	var request_id=str(intent.get("uiRequestId",""))
	if not request_id.begins_with(_token()+":"):return
	var payload=intent.duplicate(true);payload.erase("generation");payload.erase("expectedRevision");payload.erase("uiRequestId")
	var key=command_signature(payload)+":"+str(intent.get("expectedRevision",-1))
	if _pending.get(key)!=request_id:return
	_pending.erase(key)
func _send(payload:Dictionary,token:String,gate=false):
	if token!=_token() or not is_inside_tree() or _state().is_empty():return
	if gate and not _preview(payload).get("ok",false):return
	var signature=command_signature(payload);var key=signature+":"+str(_revision);var now=Time.get_ticks_msec()
	if _dispatching.has(signature):return
	var continuous=payload.get("type") in ["set-sails","trim","navigate","handling-mode","settings","pause","menu","panel","select-ship"]
	if not continuous and (_pending.has(key) or now-int(_recent.get(signature,-1000))<250):return
	_request_serial+=1
	var intent=payload.duplicate(true);intent.generation=_generation;intent.expectedRevision=_revision;intent.uiRequestId=_token()+":"+str(_request_serial)
	if not continuous:_recent[signature]=now;_pending[key]=intent.uiRequestId
	_dispatching[signature]=true
	command_requested.emit(intent)
	_dispatching.erase(signature)
func captures_keyboard()->bool:
	if not _screen:return false
	var focus=_screen.get_viewport().gui_get_focus_owner()
	return focus!=null and _screen.is_ancestor_of(focus) and ((focus is LineEdit and focus.editable) or (focus is TextEdit and focus.editable))
func get_selected_panel()->String:return _panel
func is_panel_open()->bool:return _panel_open
func is_menu_open()->bool:return _menu_open
func open_panel(id:String):
	id={"crew":"recruit","missions":"quests","settings-career":"settings"}.get(id,id)
	if not PANELS.has(id):return
	_panel=id;_panel_open=true
	if _operation:_operation.show();_screen.find_child("panel_heading",true,false).text=PANELS[id]
	for key in _pages:_pages[key].visible=key==id
	_send({"type":"panel","value":id},_token());_refresh()
func close_panel():
	_panel_open=false
	if _operation:_operation.hide();_screen.get_viewport().gui_release_focus()
	_send({"type":"panel","value":false},_token());_queue_layout()
func open_menu():
	_menu_open=true
	if _menu:_menu.show()
	_send({"type":"menu","value":true},_token())
func close_menu():
	_menu_open=false
	if _menu:_menu.hide();_screen.get_viewport().gui_release_focus()
	_send({"type":"menu","value":false},_token())
func request_shortcut(code:String):
	if captures_keyboard():return
	match code:
		"KeyI":open_panel("quests")
		"KeyM":open_panel("chart")
		"KeyF":
			if _state().get("currentPortId")!=null:open_panel("market")
			else:
				var nearest=C.PORTS[0];var position=_state().get("position",{})
				for port in C.PORTS:
					if Vector2(port.x,port.z).distance_to(Vector2(position.get("x",0),position.get("z",0)))<Vector2(nearest.x,nearest.z).distance_to(Vector2(position.get("x",0),position.get("z",0))):nearest=port
				_send({"type":"dock","portId":nearest.id},_token(),true)
		"KeyB":open_panel("fleet")
		"Escape":
			if _runtime().get("surrenderQuote")!=null and _runtime().get("pendingSurrenderReceipt")==null:_send({"type":"cancel-surrender","token":_runtime().surrenderQuote.get("token",{})},_token())
			elif _menu_open:close_menu()
			elif _panel_open:close_panel()
			else:open_menu()
func _box(parent,id:String)->VBoxContainer:
	var box=VBoxContainer.new();box.name=id;box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_constant_override("separation",9);parent.add_child(box);return box
func _label(parent,id:String,text="",watch=Callable())->Label:
	var label=Label.new();label.name=id;label.text=text;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(label)
	if id.ends_with("_heading"):label.add_theme_font_override("font",Parchment.title_font());label.add_theme_font_size_override("font_size",24)
	if watch.is_valid():_watchers.append(func():label.text=_display(watch.call()))
	return label
func _button(parent,id:String,label:String,action:Callable,gate=false)->Button:
	var target=parent
	if parent is HFlowContainer:
		target=VBoxContainer.new();target.name=id+"_group";parent.add_child(target)
	var button=Button.new();button.name=id;button.text=label;button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;target.add_child(button);_size_button(button,label);var token=_token()
	button.pressed.connect(func():
		if token==_token() and is_inside_tree() and not button.disabled:_send(action.call(),token,gate))
	if gate:
		var reason=_label(target,id+"_reason");reason.add_theme_color_override("font_color",Parchment.CINNABAR)
		_watchers.append(func():
			if not button.is_visible_in_tree():return
			var payload=action.call();var key=command_signature(payload)
			if not _quotes.has(key):_quotes[key]=_preview(payload)
			var quote=_quotes[key];button.disabled=not quote.get("ok",false);button.tooltip_text=_display(quote.get("reason",""));reason.text=button.tooltip_text;reason.visible=not reason.text.is_empty()
			button.text=label+(" · %s 两"%quote.cost if quote.has("cost") and quote.get("ok",false) else " · %s 两"%quote.reward if quote.has("reward") and quote.get("ok",false) else ""))
	return button
func _local_button(parent,id:String,label:String,callback:Callable)->Button:
	var button=Button.new();button.name=id;button.text=label;button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(button);_size_button(button,label);var token=_token()
	button.pressed.connect(func():
		if token==_token() and is_inside_tree() and not button.disabled:callback.call())
	return button
func _size_button(button:Button,title:String):
	var font=button.get_theme_default_font();var font_size=button.get_theme_default_font_size()
	button.custom_minimum_size=Vector2(max(76.0,font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x+24),38)
func _number(parent,id:String,title:String,initial=1,min_value=1,max_value=1000000,step=1)->SpinBox:
	_label(parent,id+"_label",title);var spin=SpinBox.new();spin.name=id;spin.min_value=min_value;spin.max_value=max_value;spin.step=step;spin.value=_form.get(id,initial);spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(spin);var token=_token()
	_form[id]=spin.value;spin.value_changed.connect(func(value):
		if token==_token():_form[id]=value;_setting_edited(id);_refresh())
	return spin
func _select(parent,id:String,title:String,choices:Dictionary,initial="")->OptionButton:
	_label(parent,id+"_label",title);var option=OptionButton.new();option.name=id;option.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(option);var chosen=_form.get(id,initial);var index=0
	for key in choices:
		option.add_item(_display(choices[key]));option.set_item_metadata(index,key)
		if key==chosen:option.select(index)
		index+=1
	for i in option.item_count:
		if option.get_item_metadata(i)==chosen:option.select(i)
	_form[id]=option.get_item_metadata(option.selected) if option.item_count>0 else ""
	var token=_token();option.item_selected.connect(func(i):
		if token==_token():_form[id]=option.get_item_metadata(i);_setting_edited(id);_refresh())
	return option
func _image(parent,path:String,height=110)->TextureRect:
	var image=TextureRect.new();image.texture=load(path);image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;image.custom_minimum_size=Vector2(0,height);parent.add_child(image);return image
func _build():
	_mount+=1;_watchers.clear();_pages.clear()
	if _screen:_screen.get_parent().remove_child(_screen);_screen.queue_free()
	_screen=Control.new();_screen.name="legacy_screen";_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_screen.mouse_filter=Control.MOUSE_FILTER_IGNORE;_screen.theme=ThemeFactory.create();add_child(_screen)
	_hud=PanelContainer.new();_hud.name="hud";_screen.add_child(_hud);var hud_scroll=ScrollContainer.new();hud_scroll.name="hud_scroll";hud_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_hud.add_child(hud_scroll);var h=_box(hud_scroll,"hud_content");h.minimum_size_changed.connect(_queue_layout)
	_label(h,"identity","",func():return "%s · 第 %s 日 · %s"%[_state().get("player",{}).get("name","船长"),_state().get("day",1),_port_name(_state().get("currentPortId"))])
	_label(h,"balances","",func():return "银两 %s · 士气 %s · 粮食 %s\n名望 %s · 日耗粮 %s / 薪银 %s"%[_state().get("player",{}).get("silver",0),_state().get("player",{}).get("morale",0),_state().get("player",{}).get("supplies",0),_state().get("player",{}).get("fame",0),_state().get("supplyPerDay",0),_state().get("wagesPerDay",0)])
	_label(h,"notice","",func():return _runtime().get("notice",""))
	_label(h,"broadside_status","",func():return "左舷 Q · %s\n右舷 E · %s" % [Gunnery.broadside_status(_packet.get("naval",{}),str(_state().get("flagshipId","")),"port").label,Gunnery.broadside_status(_packet.get("naval",{}),str(_state().get("flagshipId","")),"starboard").label])
	var row=HFlowContainer.new();h.add_child(row)
	_local_button(row,"open_quests","委托 [I]",func():open_panel("quests"));_local_button(row,"open_chart","海图 [M]",func():open_panel("chart"));_local_button(row,"open_fleet","舰队",func():open_panel("fleet"));_local_button(row,"menu","菜单",open_menu)
	_button(row,"pause","暂停 / 继续",func():return {"type":"pause","value":not _runtime().get("paused",false)})
	_button(row,"depart","扬帆离港",func():return {"type":"depart"},true)
	_sailing_controls(h)
	_operation=PanelContainer.new();_operation.name="operation";_screen.add_child(_operation);var outer=_box(_operation,"operation_content")
	_label(outer,"panel_heading",PANELS[_panel]);_local_button(outer,"close_panel","返回航程",close_panel)
	var tabs=HFlowContainer.new();tabs.name="panel_tabs";tabs.size_flags_horizontal=Control.SIZE_EXPAND_FILL;outer.add_child(tabs)
	for id in PANELS:_local_button(tabs,"tab_"+id,PANELS[id],func():open_panel(id))
	var scroll=ScrollContainer.new();scroll.name="panel_scroll";scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;outer.add_child(scroll);var content=_box(scroll,"all_pages")
	for id in PANELS:var page=_box(content,"panel_"+id);_pages[id]=page;page.visible=id==_panel
	_market();_shipyard();_recruit();_officers();_quests();_people();_fleet_page();_factions();_chart();_log();_save(_pages.save);_settings()
	_menu=PanelContainer.new();_menu.name="menu_panel";_screen.add_child(_menu);var menu_scroll=ScrollContainer.new();menu_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_menu.add_child(menu_scroll);var menu=_box(menu_scroll,"menu_content")
	_label(menu,"menu_heading","航程暂停与返回");_local_button(menu,"menu_resume","继续航程",close_menu)
	_button(menu,"menu_save","保存航程",func():return {"type":"save"})
	_button(menu,"menu_save_exit","保存并返回主菜单",func():return {"type":"save-and-menu"})
	_local_button(menu,"menu_leave","返回主菜单",func():
		if _save_receipt().get("ok",true)==false:_leave_warning=true;_refresh()
		else:_send({"type":"main-menu"},_token()))
	_label(menu,"leave_warning","",func():return "存档未成功。请重试保存或导出当前航程后离开。" if _leave_warning else "")
	_button(menu,"menu_export","导出当前航程",func():return {"type":"export-save","kind":"current"})
	_button(menu,"menu_backup","导出已核验备份",func():return {"type":"export-save","kind":"backup"})
	_local_button(menu,"menu_leave_unsaved","放弃本次未保存变动并离开",func():_send({"type":"main-menu","discardUnsaved":true},_token()))
	_watchers.append(func():menu.find_child("menu_leave_unsaved",true,false).visible=_leave_warning)
	_watchers.append(func():
		menu.find_child("menu_save",true,false).disabled=not _runtime().get("canSave",false)
		menu.find_child("menu_save_exit",true,false).disabled=not _runtime().get("canSave",false))
	_result=PanelContainer.new();_result.name="result_panel";_screen.add_child(_result);var result_scroll=ScrollContainer.new();result_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_result.add_child(result_scroll);var result=_box(result_scroll,"result_content")
	_label(result,"result_heading");_label(result,"result_detail")
	_button(result,"surrender_confirm","确认投降",func():return {"type":"confirm-surrender","token":_runtime().get("surrenderQuote",{}).get("token",{})})
	_button(result,"surrender_cancel","取消投降",func():return {"type":"cancel-surrender","token":_runtime().get("surrenderQuote",{}).get("token",{})})
	_button(result,"result_acknowledge","确认结果并继续航程",func():return {"type":"acknowledge-result"})
	_button(result,"result_save","重试保存",func():return {"type":"save"})
	_button(result,"result_export","导出当前航程",func():return {"type":"export-save","kind":"current"})
	_button(result,"result_backup","导出已核验备份",func():return {"type":"export-save","kind":"backup"})
	_button(result,"career_menu","返回主菜单",func():return {"type":"main-menu"})
	_watchers.append(_refresh_result)
	_dialog=FileDialog.new();_dialog.name="import_file_dialog";_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;_dialog.access=FileDialog.ACCESS_FILESYSTEM;_dialog.filters=PackedStringArray(["*.json ; 航程存档 JSON"]);_screen.add_child(_dialog);var token=_token()
	_dialog.theme=_screen.theme
	_dialog.file_selected.connect(func(path):_send({"type":"import-save","path":path},token))
	_operation.visible=_panel_open;_menu.visible=_menu_open;_screen.get_viewport().size_changed.connect(_queue_layout,CONNECT_REFERENCE_COUNTED)
	_hud.minimum_size_changed.connect(_queue_layout);_refresh()
func _sailing_controls(parent):
	var box=_box(parent,"ship_controls");_watchers.append(func():box.visible=not _native().is_empty())
	_label(box,"ship_stats","",func():
		var ship=_native();return "船体 %s/%s · 帆装 %s/%s · 船员 %s/%s\n航速 %.1f 米/秒 · 每舷火炮 %s · 调帆 %s"%[ceil(ship.get("hull",0)),ceil(ship.get("maxHull",100)),ceil(ship.get("sail",0)),ceil(ship.get("maxSail",100)),ship.get("crew",0),ship.get("maxCrew",0),_state().get("speed",0),ship.get("cannonsPerSide",0),"自动" if ship.get("autoTrim",false) else "手动"])
	var sails=HSlider.new();sails.name="ship_sails";sails.min_value=0;sails.max_value=1;sails.step=.05;sails.tooltip_text="升帆 / 收帆";box.add_child(sails);var token=_token()
	sails.value_changed.connect(func(value):_send({"type":"set-sails","value":value},token,true))
	_watchers.append(func():
		if not sails.has_focus():sails.set_value_no_signal(_native().get("sailDeployment",0))
		if box.visible:sails.editable=_preview({"type":"set-sails","value":sails.value}).get("ok",false))
	var actions=HFlowContainer.new();box.add_child(actions)
	_button(actions,"ship_trim","自动 / 手动调帆",func():return {"type":"trim"},true)
	for side in ["port","starboard"]:
		var button=_button(actions,"ship_fire_"+side,"左舷齐射 [Q]" if side=="port" else "右舷齐射 [E]",func():return {"type":"native-action","action":{"type":"fire","shipId":_state().get("flagshipId"),"side":side}},true)
		_watchers.append(func():
			if not box.visible:return
			var ship=_native();var refusal=""
			if ship.get("cannonsPerSide",0)<=0:refusal="此船没有火炮。"
			elif ship.get("ammo",{}).get(ship.get("ammoType","solid"),0)<=0:refusal="所选弹药已用尽。"
			elif ship.get("cooldownSeconds",{}).get(side,0)>0:refusal="本舷仍在装填，请稍候。"
			if not refusal.is_empty():button.disabled=true;button.tooltip_text=refusal;var reason=actions.find_child("ship_fire_"+side+"_reason",true,false);reason.text=refusal;reason.show())
	var ammo=HFlowContainer.new();box.add_child(ammo)
	for kind in AMMO:
		var button=_button(ammo,"ammo_"+kind,AMMO[kind],func():return {"type":"native-action","action":{"type":"select-ammo","shipId":_state().get("flagshipId"),"ammo":kind}},true)
		_watchers.append(func():button.text=("● " if _native().get("ammoType")==kind else "")+AMMO[kind]+" "+str(_native().get("ammo",{}).get(kind,0)))
func _market():
	var page=_pages.market;_image(page,"res://assets/art/ports/xiamen-harbor-v1.png",100)
	_label(page,"market_intro","买卖装入旗舰。实际报价计入行情、当地关系及港税。")
	for good in C.GOODS:
		var box=_box(page,"good_"+good);_image(box,"res://assets/art/goods/"+good+"-v1.png",56)
		_label(box,"stock_"+good,"",func():return "%s · 港内 %s / 旗舰 %s"%[C.GOOD_NAMES[good],_state().get("markets",{}).get(str(_state().get("currentPortId")),{}).get(good,0),_flag().get("cargo",{}).get(good,0)])
		_number(box,"quantity_"+good,"交易数量")
		for type in ["buy","sell"]:_button(box,type+"_"+good,"买入" if type=="buy" else "卖出",func():return {"type":type,"good":good,"quantity":_form["quantity_"+good]},true)
func _shipyard():
	var page=_pages.shipyard;_label(page,"shipyard_status","",func():return "%s · 船体 %s/%s · 帆装 %s/%s"%[_flag().get("name","旗舰"),ceil(_flag().get("hull",0)),ceil(_flag().get("maxHull",100)),ceil(_flag().get("sail",0)),ceil(_flag().get("maxSail",100))])
	_button(page,"repair","修复船体与帆装",func():return {"type":"repair"},true)
	for system in SYSTEMS:_button(page,"upgrade_"+system,SYSTEMS[system]+"升级",func():return {"type":"upgrade","system":system},true)
	_label(page,"buy_ship_intro","新船没有船员，须调配至最低人数后离港。")
	for kind in C.SHIP_PROFILES:
		var profile=C.SHIP_PROFILES[kind];_label(page,"profile_"+kind,"%s · 货舱 %s · 船员 %s–%s · 每舷火炮 %s"%[profile.name,profile.capacity,profile.minCrew,profile.crew,profile.cannons]);_button(page,"buy_ship_"+kind,"购置 "+profile.name,func():return {"type":"buy-ship","kind":kind},true)
func _recruit():
	var page=_pages.recruit;_label(page,"recruit_status","",func():return "旗舰船员 %s/%s · 出航最低 %s 人"%[_flag().get("crew",0),_flag().get("maxCrew",0),C.SHIP_PROFILES.get(_flag().get("kind","fuchuan"),{}).get("minCrew",0)])
	_number(page,"recruit_count","招募人数");_button(page,"recruit","招募水手",func():return {"type":"recruit","count":_form.recruit_count},true)
	for ammo in AMMO:
		_image(page,"res://assets/art/ammo/"+{"solid":"solid-shot","chain":"chain-shot","grape":"grape-shot"}[ammo]+"-v1.png",45);_label(page,"ammo_stock_"+ammo,"",func():return "%s · 旗舰 %s · 港内 %s · 每组 %s 两"%[AMMO[ammo],_flag().get("ammo",{}).get(ammo,0),_state().get("ammoStocks",{}).get(str(_state().get("currentPortId")),{}).get(ammo,0),C.AMMO_PRICES[ammo]])
		_number(page,"ammo_quantity_"+ammo,"补充组数",10,1,200);_button(page,"resupply_"+ammo,"补充 "+AMMO[ammo],func():return {"type":"resupply-ammo","ammo":ammo,"quantity":_form["ammo_quantity_"+ammo]},true)
	_button(page,"divide_plunder","分给船员两成银两",func():return {"type":"divide-plunder"},true)
func _officers():
	var page=_pages.officers
	for role in C.OFFICERS:
		var officer=C.OFFICERS[role];_label(page,"officer_"+role,"%s · 聘金 %s 两 / 每日 %s 两\n%s"%[officer.name,officer.price,officer.dailyWage,officer.description]);_button(page,"hire_"+role,"聘任 "+officer.name,func():return {"type":"hire-officer","role":role},true)
func _quests():
	var page=_pages.quests;_select(page,"quest_filter","查看",{"active":"正在进行","port":"此港委托","all":"所有委托"},"all")
	for quest in _state().get("quests",[]):
		var id=quest.id;var box=_box(page,"quest_row_"+id)
		var current=func():
			for q in _state().get("quests",[]):
				if q.id==id:return q
			return {}
		_label(box,"quest_text_"+id,"",func():
			var q=current.call();return "%s · %s\n%s\n进度 %s/%s · 酬银 %s / 名望 %s · 发布 %s · 期限 %s"%[q.get("title",""),{"available":"可接取","active":"进行中","ready":"可交付","completed":"已完成","failed":"失败"}.get(q.get("status"),""),q.get("description",""),q.get("progress",0),q.get("required",0),q.get("reward",0),q.get("fame",0),_port_name(q.get("issuerPortId")),q.get("deadlineDay","无")])
		_button(box,"quest_"+id,"接取 / 交付委托",func():return {"type":"complete-quest" if current.call().get("status") in ["active","ready"] else "accept-quest","questId":id},true)
		_button(box,"quest_waypoint_"+id,"标记委托航向",func():
			var q=current.call();var port=_port(q.get("destinationPortId",q.get("issuerPortId")));return {"type":"navigate","point":{"x":port.get("x",0),"z":port.get("z",0)}})
		_watchers.append(func():
			var q=current.call();box.visible=_form.quest_filter=="all" or (_form.quest_filter=="active" and q.get("status") in ["active","ready"]) or (_form.quest_filter=="port" and (q.get("issuerPortId")==_state().get("currentPortId") or q.get("destinationPortId")==_state().get("currentPortId"))))
func _people():
	var page=_pages.people;var choices={}
	for id in PEOPLE:choices[id]=PEOPLE[id].name
	_select(page,"person","交谈对象",choices,"merchant");var image=_image(page,"res://assets/art/characters/merchant-woman-v1.png",170)
	_select(page,"topic","交谈话题",{"welcome":"码头相逢","trade":"说说港口买卖","waters":"这片海域有何规矩","commission":"可有水师差事"},"welcome")
	_label(page,"dialogue","",func():return "粮、木、铁是航程根本，丝绸、瓷器、香料须看各港行情。请在市场核对实付银两。" if _form.topic=="trade" else "%s · 六港各有旗号。护航须与受护船同行，登岸须抵达对应锚地。"%_port_name(_state().get("currentPortId")) if _form.topic=="waters" else "委托簿记着各港发布人、去处和期限。跑完一程，再来相见。" if _form.topic=="commission" else PEOPLE[_form.person].words)
	_watchers.append(func():image.texture=load("res://assets/art/characters/"+PEOPLE[_form.person].image+"-v1.png"))
	_local_button(page,"people_commission","查看水师差事",func():open_panel("quests"))
	_label(page,"banquet_fee","赴宴三十两；依实际席间表现增加士气、人缘及名望。")
	_button(page,"banquet","赴港口宴会",func():return {"type":"start-encounter","kind":"banquet","targetId":_state().get("currentPortId")},true)
func _fleet_page():
	var page=_pages.fleet;var choices={}
	for ship in _fleet():
		var id=ship.id;choices[id]=ship.name
		_label(page,"fleet_"+id,"",func():
			var s=_ship(id);return "%s · %s\n船体 %s/%s · 帆装 %s/%s · 船员 %s/%s / 最低 %s\n%s"%[s.get("name",""),"旗舰" if id==_state().get("flagshipId") else C.SHIP_PROFILES.get(s.get("kind"),{}).get("name",""),ceil(s.get("hull",0)),ceil(s.get("maxHull",100)),ceil(s.get("sail",0)),ceil(s.get("maxSail",100)),s.get("crew",0),s.get("maxCrew",0),C.SHIP_PROFILES.get(s.get("kind"),{}).get("minCrew",0),_cargo(s.get("cargo",{}))])
		_button(page,"flagship_"+id,"设为旗舰",func():return {"type":"select-flagship","shipId":id},true);_button(page,"sell_ship_"+id,"出售船只",func():return {"type":"sell-ship","shipId":id},true)
	_select(page,"transfer_from","调出船",choices,_state().get("flagshipId",""));_select(page,"transfer_to","接收船",choices,choices.keys()[1] if choices.size()>1 else "")
	_number(page,"transfer_count","调配船员人数");_button(page,"transfer_crew","调配船员",func():return {"type":"transfer-crew","fromShipId":_form.transfer_from,"toShipId":_form.transfer_to,"count":_form.transfer_count},true)
	_select(page,"transfer_good","调配货物",C.GOOD_NAMES,"grain");_number(page,"transfer_quantity","调配货物数量")
	_button(page,"transfer_cargo","调配货物",func():return {"type":"transfer-cargo","fromShipId":_form.transfer_from,"toShipId":_form.transfer_to,"good":_form.transfer_good,"quantity":_form.transfer_quantity},true)
	_label(page,"boarding_heading","海上接舷目标")
	for ship in _packet.get("naval",{}).get("ships",[]):
		if ship.get("team")!="hostile":continue
		var id=ship.id;_label(page,"boarding_name_"+id,_display(ship.get("name",id)));_button(page,"board_"+id,"接舷决斗",func():return {"type":"start-encounter","kind":"duel","targetId":id},true)
func _factions():
	_label(_pages.factions,"relations","",func():
		var lines:PackedStringArray=[]
		for faction in FACTIONS:lines.append("%s · 关系 %s"%[FACTIONS[faction],_state().get("relations",{}).get(faction,0)])
		return "\n".join(lines))
	_label(_pages.factions,"faction_intro","关系影响当地贸易与入港。敌对行为、委托与宴会依实际回执改变人缘。")
func _chart():
	var page=_pages.chart;var chart=Chart.new();chart.name="world_chart";page.add_child(chart);var token=_token();chart.waypoint_requested.connect(func(point):_send({"type":"navigate","point":point},token));_watchers.append(func():chart.apply_snapshot(_state()))
	for port in C.PORTS:
		_button(page,"waypoint_"+port.id,"标记航向 · "+port.name,func():return {"type":"navigate","point":{"x":port.x,"z":port.z}})
		_button(page,"dock_"+port.id,"靠泊 "+port.name,func():return {"type":"dock","portId":port.id},true)
	for site in C.LAND_SITES:
		_label(page,"site_"+site.id,site.name+" · "+_port_name(site.portId));_button(page,"site_waypoint_"+site.id,"标记地点",func():return {"type":"navigate","point":{"x":site.x,"z":site.z}})
		_button(page,"visit_"+site.id,"登岸踏查",func():return {"type":"visit-land","siteId":site.id},true)
		if site.kind!="clue":_button(page,"encounter_"+site.id,"寻宝" if site.kind=="treasure" else "攻取炮台",func():return {"type":"start-encounter","kind":"treasure" if site.kind=="treasure" else "landBattle","targetId":site.id},true)
func _log():
	_label(_pages.log,"log_entries","",func():
		var lines:PackedStringArray=[]
		for entry in _state().get("log",[]):lines.append("第 %s 日 · %s"%[entry.get("day",1),entry.get("message","")])
		return "\n\n".join(lines))
func _save(page):
	_label(page,"save_intro","导入前核验完整航程，核验失败保留当前航程。备份仅导出已核验的检查点。")
	var save=_button(page,"save","保存当前航程",func():return {"type":"save"});_watchers.append(func():save.disabled=not _runtime().get("canSave",false))
	_label(page,"save_reason","",func():return _runtime().get("saveReason","") if not _runtime().get("canSave",false) else "")
	_label(page,"save_status","",func():
		var receipt=_runtime().get("saveStatus",_runtime().get("lastSaveReceipt",{}));return "存档未成功："+str(receipt.get("reason","请重试保存或导出航程。")) if receipt.get("ok",true)==false else "")
	_button(page,"export_current","导出当前航程",func():return {"type":"export-save","kind":"current"});_button(page,"export_backup","导出已核验备份",func():return {"type":"export-save","kind":"backup"})
	_local_button(page,"import_file","导入 JSON 文件",func():_dialog.popup_centered_ratio(.8))
	var editor=TextEdit.new();editor.name="import_json";editor.custom_minimum_size=Vector2(0,130);editor.placeholder_text="粘贴已导出的完整 JSON 存档";editor.text=_form.get("import_json","");page.add_child(editor);var token=_token();editor.text_changed.connect(func():
		if token==_token():_form.import_json=editor.text;_refresh())
	var paste=_button(page,"import_paste","核验并载入此航程",func():return {"type":"import-save","json":_form.get("import_json","")});_watchers.append(func():paste.disabled=_form.get("import_json","").strip_edges().is_empty())
func _settings_payload()->Dictionary:
	var confirmed=_packet.get("settings",{});var values={}
	for key in SETTINGS_FIELDS:
		values[key]=confirmed[key] if confirmed.has(key) and not _settings_dirty.has(key) else _form[key]/100.0 if key in ["musicVolume","soundVolume"] else _form[key]
	return values
func _settings():
	var page=_pages.settings;_select(page,"handling","操船方式",{"assisted":"均衡","realistic":"真实"},_runtime().get("handlingMode","assisted"));_button(page,"apply_handling","应用操船方式",func():return {"type":"set-handling-mode","mode":_form.handling})
	_label(page,"handling_explanation","均衡辅助升收帆、转舵与迎风脱困；真实保留风帆响应。切换后重新按操船键。")
	var save_exit=_button(page,"save_exit","保存并返回主菜单",func():return {"type":"save-and-menu"});_watchers.append(func():save_exit.disabled=not _runtime().get("canSave",false))
	_select(page,"quality","画面质量",{"balanced":"均衡","high":"精细","low":"流畅"},"balanced")
	for setting in ["music","sound","reducedMotion"]:
		var check=CheckBox.new();check.name="setting_"+setting;check.text={"music":"背景音乐","sound":"炮火与风浪音效","reducedMotion":"减少装饰动画"}[setting];check.button_pressed=_form.get(setting,setting!="reducedMotion");_form[setting]=check.button_pressed;page.add_child(check);var token=_token();check.toggled.connect(func(value):
			if token==_token():_form[setting]=value;_setting_edited(setting))
	for setting in ["musicVolume","soundVolume"]:_number(page,setting,"音乐音量 %" if setting=="musicVolume" else "音效音量 %",70,0,100,.01)
	_button(page,"apply_settings","应用画面与声音",func():return {"type":"settings","value":_settings_payload()})
	_label(page,"captain_name_label","船长姓名");var name_edit=LineEdit.new();name_edit.name="captain_name";name_edit.max_length=24;name_edit.text=_form.get("captain_name",_display(_state().get("player",{}).get("name","")));_form.captain_name=name_edit.text;page.add_child(name_edit);var token=_token();name_edit.text_changed.connect(func(value):
		if token==_token():_form.captain_name=value;_refresh())
	_button(page,"rename","更改姓名",func():return {"type":"rename","name":_form.captain_name},true)
	_label(page,"keys","W/S 升收帆 · A/D 操舵 · Q/E 两舷齐射\n1/2/3 弹种 · R 调帆 · I 委托 · M 海图 · F 靠港 · B 接舷 · Esc 菜单")
	_button(page,"begin_surrender","请求投降条款",func():return {"type":"begin-surrender"},true)
	_local_button(page,"retire_open","归航退休",func():_retirement=true;_refresh())
	_label(page,"retire_question","",func():return "确认结束这次生涯并依实际战果生成最终评定？" if _retirement else "")
	var confirm=_button(page,"retire_confirm","结束生涯并评定",func():return {"type":"retire"},true);_watchers.append(func():confirm.visible=_retirement)
	_local_button(page,"retire_cancel","继续逐浪",func():_retirement=false;_refresh())
func _refresh_result():
	var receipt=_runtime().get("pendingSurrenderReceipt",_state().get("pendingSurrenderReceipt"));var quote=_runtime().get("surrenderQuote");var retired=_state().get("career",{}).get("retired",false);var status=_packet.get("naval",{}).get("status","")
	_result.visible=receipt!=null or quote!=null or retired or status in ["victory","defeat"]
	if not _result.visible:return
	var heading=_result.find_child("result_heading",true,false);var detail=_result.find_child("result_detail",true,false)
	for id in ["surrender_confirm","surrender_cancel"]:_result.find_child(id,true,false).visible=quote!=null and receipt==null
	_result.find_child("result_acknowledge",true,false).visible=not retired and (receipt!=null or status in ["victory","defeat"])
	_result.find_child("career_menu",true,false).visible=retired
	if retired:heading.text="归航生涯评定";detail.text=_display(_state().career.get("ending",""))+"\n实际评定："+str(_state().career.get("score",0))+" 分"
	elif quote!=null or receipt!=null:
		heading.text="投降损失已执行" if receipt!=null else "确认投降条款"
		var terms=(receipt.get("quote",{}).get("terms",{}) if receipt!=null else quote.get("terms",{}));var lines:PackedStringArray=[]
		lines.append("俘获方："+_display(terms.get("captor",{}).get("name","敌舰")))
		lines.append("损失银两 %s · 剩余 %s · 士气 %s · 名望 %s"%[terms.get("silver",{}).get("loss",0),terms.get("silver",{}).get("after",0),terms.get("morale",{}).get("after",0),terms.get("fame",{}).get("after",0)])
		for ship in terms.get("shipLosses",[]):lines.append("%s · 货物损失 %s · 船体 %s/%s · 船员 %s"%[_display(ship.get("name","")),_cargo(ship.get("loss",{})),ceil(ship.get("hull",0)),ceil(ship.get("maxHull",100)),ship.get("crew",0)])
		for ship in terms.get("lostShips",[]):lines.append("失船："+_display(ship.get("name",ship.get("id",""))))
		for quest in terms.get("failedQuests",[]):lines.append("失败委托："+_display(quest.get("title","")))
		lines.append("返回厦门后船况不自动修复，请按实际损失整备。");detail.text="\n".join(lines)
	else:heading.text="海战获胜" if status=="victory" else "海战失利";detail.text="结果来自实际战况。确认后继续航程。"
func _queue_layout():
	if _layout_queued:return
	_layout_queued=true;call_deferred("_layout")
func _layout():
	_layout_queued=false
	if not _screen or not is_inside_tree():return
	var viewport=_screen.get_viewport_rect().size;var width=min(430.0,max(220.0,viewport.x-24));_hud.position=Vector2(12,12);var h=_hud.find_child("hud_content",true,false);_hud.size=Vector2(width,min(380.0,min(viewport.y*.43,h.get_combined_minimum_size().y+28)))
	var op_width=min(650.0,viewport.x-24);var op_x=viewport.x-op_width-12;var op_y=12.0
	if viewport.x<1120:op_x=12;op_y=_hud.position.y+_hud.size.y+12
	_operation.position=Vector2(op_x,op_y);_operation.size=Vector2(op_width,max(120.0,viewport.y-op_y-12))
	_menu.position=Vector2(max(12,(viewport.x-460)/2),24);_menu.size=Vector2(min(460.0,viewport.x-24),max(120.0,viewport.y-48))
	_result.position=Vector2(max(12,(viewport.x-600)/2),24);_result.size=Vector2(min(600.0,viewport.x-24),max(120.0,viewport.y-48))
