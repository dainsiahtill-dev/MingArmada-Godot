extends SceneTree
const Session = preload("res://game/domain/legacy/adventure_session.gd")
var failures = 0
var assertions = 0
var emitted: Array = []
func check(value, message):
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ", message)
func _initialize(): call_deferred("run")
func press(ui, id):
	var b = ui.find_child(id, true, false)
	check(b is Button and not b.disabled, "enabled Control " + id)
	if b is Button and not b.disabled: b.pressed.emit()
func run():
	var path = "res://game/ui/legacy/legacy_interface.gd"
	check(ResourceLoader.exists(path), "native legacy interface exists")
	if not ResourceLoader.exists(path): finish(); return
	var script = load(path)
	check(script != null and script.can_instantiate(), "interface compiles")
	if not script or not script.can_instantiate(): finish(); return
	var ui = script.new(); root.add_child(ui); await process_frame
	var session = Session.new(); check(session.command({"type":"dock","portId":"xiamen"}).ok, "real domain docks")
	ui.command_requested.connect(func(intent): emitted.append(intent))
	var packet = {"adventure":session.snapshot(),"naval":{"ships":[]},"runtime":{"generation":1,"revision":1,"paused":false,"canSave":true}}
	var original = packet.duplicate(true)
	ui.apply_snapshot(packet)
	for window_name in ["hud", "operation", "menu_panel", "result_panel"]:
		var floating: PanelContainer = ui.find_child(window_name,true,false)
		check(floating != null and floating.get_theme_stylebox("panel").has_method("get_edge_style"), "legacy floating window has generated frame: "+window_name)
	for page in ["market","shipyard","recruit","officers","quests","people","fleet","factions","chart","log","save","settings"]:
		ui.open_panel(page)
		check(ui.find_child("panel_"+page,true,false) is Control, "real page "+page)
		check(ui.get_selected_panel()==page, "selected page "+page)
	ui.open_panel("market")
	check(ui.find_child("buy_grain",true,false).disabled, "arithmetic cannot enable trade without authority")
	check(not ui.find_child("buy_grain_reason",true,false).text.is_empty(), "missing authority visible")
	ui.set_readiness_provider(func(intent): return session.preview(intent))
	for good in Session.C.GOODS:
		press(ui,"buy_"+good)
		check(emitted.back().type=="buy" and emitted.back().good==good and emitted.back().quantity==1, "original good command "+good)
		check(emitted.back().generation==1 and emitted.back().expectedRevision==1,"fresh request fence")
	var quantity = ui.find_child("quantity_grain",true,false)
	quantity.get_line_edit().grab_focus(); await process_frame
	check(ui.captures_keyboard(),"editable quantity protects typing")
	quantity.get_line_edit().text="7"
	packet.runtime.revision=2; ui.apply_snapshot(packet)
	check(quantity==ui.find_child("quantity_grain",true,false) and quantity.get_line_edit().text=="7" and quantity.get_line_edit().has_focus(),"refresh preserves Control focus and uncommitted input")
	quantity.get_line_edit().release_focus()
	ui.find_child("pause",true,false).grab_focus(); await process_frame
	check(not ui.captures_keyboard(),"button focus allows sailing")
	ui.open_panel("shipyard")
	for kind in Session.C.SHIP_PROFILES: check(ui.find_child("buy_ship_"+kind,true,false) is Button,"all source ship types "+kind)
	for system in ["hull","cannons","sails","equipment"]: check(ui.find_child("upgrade_"+system,true,false) is Button,"all source upgrades "+system)
	ui.open_panel("recruit"); press(ui,"recruit")
	check(emitted.back().type=="recruit" and emitted.back().count==1,"recruit original count")
	for ammo in ["solid","chain","grape"]: check(ui.find_child("resupply_"+ammo,true,false) is Button,"ammo supply "+ammo)
	ui.open_panel("officers")
	for role in Session.C.OFFICERS: check(ui.find_child("hire_"+role,true,false) is Button,"source officer "+role)
	ui.open_panel("quests"); check(ui.find_child("quest_filter",true,false) is OptionButton,"quest filter")
	var q = packet.adventure.quests[0]; press(ui,"quest_"+q.id)
	check(emitted.back().type=="accept-quest" and emitted.back().questId==q.id,"quest original id")
	ui.open_panel("people"); check(ui.find_child("person",true,false).item_count==3,"all source people")
	ui.set_readiness_provider(func(intent): return {"ok":intent.type=="start-encounter"})
	press(ui,"banquet"); check(emitted.back().kind=="banquet" and emitted.back().targetId=="xiamen","banquet source target")
	ui.open_panel("fleet")
	check(ui.find_child("transfer_from",true,false) is OptionButton and ui.find_child("transfer_cargo",true,false) is Button,"owned ship and cargo transfer controls")
	check(ui.find_child("fleet_player",true,false).text.contains("最低"),"actual minimum crew visible")
	ui.open_panel("factions"); check(ui.find_child("relations",true,false).text.contains("郑氏"),"actual four relations")
	ui.open_panel("chart")
	check(ui.find_child("world_chart",true,false) is Control,"native chart")
	for port in Session.C.PORTS: press(ui,"waypoint_"+port.id); check(emitted.back().point.x==port.x and emitted.back().point.z==port.z,"canonical port waypoint")
	for site in Session.C.LAND_SITES: check(ui.find_child("visit_"+site.id,true,false) is Button,"every land site reachable")
	ui.open_panel("save"); press(ui,"save")
	check(emitted.back().type=="save","save intent")
	press(ui,"export_backup"); check(emitted.back().type=="export-save" and emitted.back().kind=="backup","verified backup export")
	var editor=ui.find_child("import_json",true,false); editor.text=session.serialize(); editor.text_changed.emit(); editor.grab_focus(); await process_frame
	check(ui.captures_keyboard(),"paste import protects keyboard")
	press(ui,"import_paste"); check(emitted.back().json==session.serialize(),"import actual JSON unchanged")
	ui.open_panel("settings"); check(ui.find_child("captain_name",true,false) is LineEdit,"rename edit")
	check(ui.find_child("retire_confirm",true,false) is Button,"retirement explicit confirmation")
	ui.close_panel(); packet.adventure.log.append({"id":100,"day":1,"message":"新航况"}); ui.apply_snapshot(packet)
	check(not ui.is_panel_open(),"closed panel persists across new snapshot")
	ui.open_menu(); check(ui.is_menu_open(),"menu opens"); ui.close_menu(); check(not ui.is_menu_open(),"menu closes")
	var stale=ui.find_child("waypoint_xiamen",true,false); var count=emitted.size(); packet.runtime.generation=2; ui.apply_snapshot(packet); stale.pressed.emit()
	check(emitted.size()==count,"old generation callback cannot issue")
	check(original.adventure==session.snapshot(),"UI never changes source session")
	var queries:Array=[]
	ui.open_panel("market")
	ui.set_readiness_provider(func(intent):queries.append(intent.duplicate());return session.preview(intent))
	check(queries.all(func(intent):return intent.type in ["buy","sell","depart"]),"hidden pages never query costly gameplay readiness")
	queries.clear();ui.close_panel();ui.apply_snapshot(packet)
	check(queries.all(func(intent):return intent.type=="depart"),"closed panels leave only visible HUD readiness")
	ui.set_readiness_provider(Callable())
	var quote_packet=packet.duplicate(true);quote_packet.runtime.surrenderQuote={"token":{"battleId":"source-battle"},"terms":{"captor":{"name":"对手"},"silver":{"loss":15,"after":35}}}
	ui.apply_snapshot(quote_packet);ui.request_shortcut("Escape")
	check(emitted.back().type=="cancel-surrender" and emitted.back().token.battleId=="source-battle","Escape cancels current actual surrender quote")
	ui.apply_snapshot(packet)
	var failed=packet.duplicate(true);failed.runtime.lastSaveReceipt={"ok":false,"reason":"实际磁盘写入失败"};ui.apply_snapshot(failed);ui.open_menu();var count_before_leave=emitted.size();press(ui,"menu_leave")
	check(emitted.size()==count_before_leave,"failed-save menu refuses immediate departure")
	check(ui.find_child("leave_warning",true,false).text.contains("未成功"),"failed-save recovery warning visible")
	press(ui,"menu_leave_unsaved");check(emitted.back().type=="main-menu" and emitted.back().discardUnsaved==true,"explicit failed-save discard choice")
	ui.close_menu();ui.apply_snapshot(packet)
	await verify_layout(ui,packet)
	verify_source_commands(ui)
	await verify_native_controls(ui)
	await verify_completed_requests()
	await verify_confirmed_settings()
	ui.free(); await process_frame
	finish()
func choose(ui,id,value):
	var option=ui.find_child(id,true,false)
	check(option is OptionButton,"actual selector "+id)
	if not option is OptionButton:return
	for i in option.item_count:
		if option.get_item_metadata(i)==value:option.select(i);option.item_selected.emit(i);return
	check(false,"selector retains original id "+value)
func verify_source_commands(ui):
	var decoded=load("res://game/domain/legacy/json_numbers.gd").new().decode(FileAccess.get_file_as_string("res://tests/fixtures/legacy-reference.json"));check(decoded.ok,"source oracle decodes exact numbers and UTF16");var reference=decoded.value
	var seen={};var generation=20;var successes=0;var rejections=0
	for scenario in reference.scenarios:
		if scenario.name not in ["business","chapters","equipment"]:continue
		var before=scenario.initial;var saved=scenario.initialSave
		for step in scenario.steps:
			if step.kind=="command":
				var command=step.args;var family=command.type+":"+str(command.get("system",command.get("role",command.get("ammo",command.get("kind","")))))+":"+str(step.result.ok)
				var controls={"dock":"dock_"+str(command.get("portId","")),"depart":"depart","rename":"rename","buy":"buy_"+str(command.get("good","")),"sell":"sell_"+str(command.get("good","")),"repair":"repair","upgrade":"upgrade_"+str(command.get("system","")),"buy-ship":"buy_ship_"+str(command.get("kind","")),"recruit":"recruit","resupply-ammo":"resupply_"+str(command.get("ammo","")),"hire-officer":"hire_"+str(command.get("role","")),"divide-plunder":"divide_plunder","accept-quest":"quest_"+str(command.get("questId","")),"complete-quest":"quest_"+str(command.get("questId","")),"select-flagship":"flagship_"+str(command.get("shipId","")),"sell-ship":"sell_ship_"+str(command.get("shipId","")),"transfer-crew":"transfer_crew","transfer-cargo":"transfer_cargo","visit-land":"visit_"+str(command.get("siteId","")),"retire":"retire_confirm"}
				if controls.has(command.type) and not seen.has(family):
					seen[family]=true;generation+=1
					# Recorded original source preview is the authority oracle for this exact command.
					# Other controls stay unverified; no mocked game mutation or success is generated.
					ui.set_readiness_provider(func(intent):return step.preview if intent==command else {"ok":false,"reason":"未查询的操作"})
					var packet={"adventure":before,"naval":{"ships":[]},"runtime":{"generation":generation,"revision":17,"canSave":true}}
					ui.apply_snapshot(packet)
					var pages={"dock":"chart","depart":"market","rename":"settings","buy":"market","sell":"market","repair":"shipyard","upgrade":"shipyard","buy-ship":"shipyard","recruit":"recruit","resupply-ammo":"recruit","hire-officer":"officers","divide-plunder":"recruit","accept-quest":"quests","complete-quest":"quests","select-flagship":"fleet","sell-ship":"fleet","transfer-crew":"fleet","transfer-cargo":"fleet","visit-land":"chart","retire":"settings"}
					ui.open_panel(pages[command.type])
					if command.type=="retire":press(ui,"retire_open")
					if command.type in ["buy","sell"]:ui.find_child("quantity_"+command.good,true,false).value=command.quantity
					if command.type=="recruit":ui.find_child("recruit_count",true,false).value=command.count
					if command.type=="resupply-ammo":ui.find_child("ammo_quantity_"+command.ammo,true,false).value=command.quantity
					if command.type=="rename":var e=ui.find_child("captain_name",true,false);e.text=command.name;e.text_changed.emit(e.text)
					if command.type in ["transfer-crew","transfer-cargo"]:
						choose(ui,"transfer_from",command.fromShipId);choose(ui,"transfer_to",command.toShipId)
						if command.type=="transfer-crew":ui.find_child("transfer_count",true,false).value=command.count
						else:choose(ui,"transfer_good",command.good);ui.find_child("transfer_quantity",true,false).value=command.quantity
					var button=ui.find_child(controls[command.type],true,false)
					check(button is Button,"source original Control "+family)
					check(not button.disabled==step.result.ok,"source actual acceptance/rejection "+family)
					if step.result.ok:
						button.pressed.emit();var actual=emitted.back().duplicate();actual.erase("generation");actual.erase("expectedRevision");actual.erase("uiRequestId");check(actual==command,"source exact command fields "+family);successes+=1
					else:check(not button.tooltip_text.is_empty(),"source rejection visible "+family);rejections+=1
			before=step.state;saved=step.save
	check(successes>=24 and rejections>=8,"source UI parity exercised families and refusal branches")
	print("LEGACY_UI_SOURCE families=",seen.size()," accepted=",successes," refused=",rejections)
func verify_layout(ui,packet):
	ui.set_readiness_provider(Callable());ui.open_panel("market")
	for width in [1600,1100,600,400]:
		root.size=Vector2i(width,900);root.content_scale_size=Vector2i.ZERO
		for frame in 8:await process_frame
		var hud=ui.find_child("hud",true,false);var operation=ui.find_child("operation",true,false)
		check(hud.size.y<400,"HUD compact after natural layout "+str(width))
		check(operation.position.x>=hud.position.x+hud.size.x+10 or operation.position.y>=hud.position.y+hud.size.y+10,"actual Controls do not overlap "+str(width))
		check(operation.position.x+operation.size.x<=width and operation.position.y+operation.size.y<=900,"native panel fits viewport "+str(width))
		for id in ["open_quests","open_chart","open_fleet","menu","pause","tab_market","tab_shipyard","tab_settings"]:
			var button=ui.find_child(id,true,false)
			check(button.size.x>=70 and button.size.y<=60,"actual button text occupies readable pixels "+id+":"+str(width))
		check(ui.find_child("tab_settings",true,false).position.y>ui.find_child("tab_market",true,false).position.y,"twelve tabs actually wrap "+str(width))
	ui.open_menu();ui.find_child("menu_export",true,false).grab_focus();await process_frame
	check(not ui.captures_keyboard(),"menu button focus allows sailing")
	ui.close_menu();ui.close_panel();packet.runtime.generation+=1;ui.apply_snapshot(packet)
	check(not ui.is_panel_open() and not ui.is_menu_open(),"structural rebuild retains closed state")
func verify_native_controls(ui):
	var runtime=load("res://game/runtime/legacy_runtime.gd").new()
	check(runtime.configure(func(_x,_z):return -30.0,{"initialDock":false}).ok,"real sailing runtime configures")
	ui.set_readiness_provider(runtime.preview_command);ui.close_panel();ui.apply_snapshot(runtime.snapshot())
	var sails=ui.find_child("ship_sails",true,false)
	check(sails is HSlider,"actual sail deployment Control")
	if not sails is HSlider:runtime.dispose();return
	check(ui.find_child("ship_stats",true,false).text.contains("48"),"actual native crew stats")
	sails.value=.5;check(emitted.back().type=="set-sails" and emitted.back().value==.5,"native sail value intent")
	check(runtime.command(emitted.back()).ok,"actual runtime accepts UI sails")
	ui.apply_snapshot(runtime.snapshot());press(ui,"ship_trim");check(runtime.command(emitted.back()).ok,"actual trim request accepted")
	ui.apply_snapshot(runtime.snapshot());press(ui,"ammo_chain");check(emitted.back().action=={"type":"select-ammo","shipId":"player","ammo":"chain"},"source actual ammo action")
	check(runtime.command(emitted.back()).ok,"actual ammo switch accepted")
	ui.apply_snapshot(runtime.snapshot());press(ui,"ship_fire_port");check(emitted.back().action=={"type":"fire","shipId":"player","side":"port"},"source actual broadside action")
	check(runtime.command(emitted.back()).ok,"actual native broadside accepted")
	ui.apply_snapshot(runtime.snapshot());check(ui.find_child("ship_fire_port",true,false).disabled,"real reloading disables duplicate broadside")
	runtime.set_pause("player",true);ui.apply_snapshot(runtime.snapshot());check(ui.find_child("ship_trim",true,false).disabled,"actual runtime pause disables manual action")
	for width in [1600,600,400]:
		root.size=Vector2i(width,900)
		for frame in 8:await process_frame
		check(ui.find_child("hud",true,false).size.y<400,"actual paused ship HUD remains compact "+str(width))
	runtime.dispose()
func verify_completed_requests():
	var Runtime=load("res://game/runtime/legacy_runtime.gd");var Storage=load("res://game/persistence/save_coordinator.gd")
	var runtime=Runtime.new();runtime.configure(func(_x,_z):return -30.0,{"initialDock":true})
	var ui=load("res://game/ui/legacy/legacy_interface.gd").new();root.add_child(ui);await process_frame
	var storage=Storage.new("res://project.godot/review.json",Runtime.validate_save)
	var requests:Array=[];var receipts:Array=[];var completed:Array=[];var acknowledge=[true]
	ui.set_readiness_provider(runtime.preview_command)
	ui.command_requested.connect(func(intent):
		if intent.type=="menu":runtime.set_pause("menu",intent.value);ui.apply_snapshot(runtime.snapshot());return
		requests.append(intent.duplicate(true))
		var receipt=runtime.save_checkpoint(storage) if intent.type=="save" else runtime.command(intent)
		receipts.append(receipt);completed.append(intent.duplicate(true))
		if acknowledge[0] and ui.has_method("acknowledge_command"):ui.acknowledge_command(intent,receipt)
		# Completion may refresh and activate the same Control synchronously.
		ui.apply_snapshot(runtime.snapshot())
		if intent.type=="save":ui.find_child("menu_save",true,false).pressed.emit())
	ui.apply_snapshot(runtime.snapshot());ui.open_menu();var revision=runtime.snapshot().runtime.revision
	press(ui,"menu_save");press(ui,"menu_save")
	check(requests.size()==1 and receipts[0].ok==false,"completed failed write keeps immediate duplicate/reentrancy fenced")
	check(runtime.snapshot().runtime.revision==revision,"failed save does not invent business revision")
	storage.path="user://legacy-ui-retry-"+str(Time.get_ticks_usec())+".json"
	await wait_request_debounce();press(ui,"menu_save")
	check(requests.size()==2 and receipts.back().ok,"same actual Save Control retries after storage recovery")
	check(storage.read_checkpoint().ok,"second actual write is read back and validated")
	var old_intent=completed[0];acknowledge[0]=false
	await wait_request_debounce();press(ui,"menu_save");var pending_count=requests.size();var current_intent=completed.back()
	await wait_request_debounce()
	if ui.has_method("acknowledge_command"):ui.acknowledge_command(old_intent,receipts[0])
	press(ui,"menu_save");check(requests.size()==pending_count,"stale completion cannot release newer request at unchanged revision")
	if ui.has_method("acknowledge_command"):ui.acknowledge_command(current_intent,receipts.back())
	acknowledge[0]=true;press(ui,"menu_save");check(requests.size()==pending_count+1,"matching completion releases current request")
	press(ui,"menu_export");await wait_request_debounce();var count=requests.size();press(ui,"menu_export")
	check(requests.size()==count+1 and receipts.back().ok,"completed export can repeat without revision change")
	ui.open_panel("save");var editor=ui.find_child("import_json",true,false);editor.text="invalid source save";editor.text_changed.emit()
	press(ui,"import_paste");await wait_request_debounce();count=requests.size();press(ui,"import_paste")
	check(requests.size()==count+1 and not receipts.back().ok,"completed unchanged invalid import can retry")
	ui.close_panel();acknowledge[0]=false;await wait_request_debounce();press(ui,"menu_export");var old_generation_intent=completed.back()
	runtime.configure(func(_x,_z):return -30.0,{"initialDock":true});ui.apply_snapshot(runtime.snapshot());press(ui,"menu_export");var fresh_intent=completed.back();count=requests.size()
	if ui.has_method("acknowledge_command"):ui.acknowledge_command(old_generation_intent,{"ok":true})
	await wait_request_debounce();press(ui,"menu_export")
	check(requests.size()==count,"old generation/mount completion cannot release fresh mounted request")
	if ui.has_method("acknowledge_command"):ui.acknowledge_command(fresh_intent,{"ok":true})
	press(ui,"menu_export");check(requests.size()==count+1,"fresh generation matching completion releases request")
	for suffix in ["",".backup",".rollback",".staged"]:
		if FileAccess.file_exists(storage.path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(storage.path+suffix))
	ui.free();runtime.dispose();await process_frame
func wait_request_debounce():
	var until=Time.get_ticks_msec()+300
	while Time.get_ticks_msec()<until:await process_frame
func verify_confirmed_settings():
	var Settings=load("res://game/persistence/user_settings.gd")
	var owner=Settings.new("user://legacy-ui-settings-"+str(Time.get_ticks_usec())+".json");var settings_path=owner.path
	check(owner.update_settings({"quality":"high","music":false,"sound":false,"reducedMotion":true,"musicVolume":.2,"soundVolume":.3}).ok,"actual settings owner confirms nondefault preferences")
	var ui=load("res://game/ui/legacy/legacy_interface.gd").new();root.add_child(ui);await process_frame
	var session=Session.new();session.command({"type":"dock","portId":"xiamen"})
	var packet={"adventure":session.snapshot(),"naval":{"ships":[]},"runtime":{"generation":7000,"revision":1,"canSave":true},"settings":owner.snapshot()}
	var calls:Array=[];var receipts:Array=[]
	ui.command_requested.connect(func(intent):
		if intent.type!="settings":return
		calls.append(intent.duplicate(true));var receipt=owner.update_settings(intent.value);receipts.append(receipt)
		if ui.has_method("acknowledge_command"):ui.acknowledge_command(intent,receipt)
		packet.settings=owner.snapshot();ui.apply_snapshot(packet))
	ui.apply_snapshot(packet);ui.open_panel("settings")
	var quality=ui.find_child("quality",true,false)
	check(quality.get_item_metadata(quality.selected)=="high","initial actual quality reflects confirmed settings")
	for key in ["music","sound","reducedMotion"]:check(ui.find_child("setting_"+key,true,false).button_pressed==owner.snapshot()[key],"initial confirmed toggle "+key)
	for key in ["musicVolume","soundVolume"]:check(ui.find_child(key,true,false).value==owner.snapshot()[key]*100,"initial confirmed volume "+key)
	choose(ui,"quality","low");ui.find_child("setting_sound",true,false).button_pressed=true
	var volume=ui.find_child("musicVolume",true,false);volume.get_line_edit().grab_focus();await process_frame;volume.get_line_edit().text="33"
	check(owner.update_settings({"soundVolume":.45}).ok,"actual external preference confirmation")
	packet.settings=owner.snapshot();ui.apply_snapshot(packet)
	check(quality.get_item_metadata(quality.selected)=="low" and ui.find_child("setting_sound",true,false).button_pressed,"ordinary confirmed snapshot preserves uncommitted settings drafts")
	check(volume.get_line_edit().has_focus() and volume.get_line_edit().text=="33","ordinary settings refresh preserves focused numeric text")
	check(ui.find_child("soundVolume",true,false).value==45,"untouched setting follows new confirmed snapshot")
	volume.value=33;volume.get_line_edit().release_focus();ui.close_panel();ui.open_panel("settings")
	check(quality.get_item_metadata(quality.selected)=="low" and volume.value==33,"reopening panel preserves drafts")
	press(ui,"apply_settings")
	check(calls.size()==1 and calls[0].value=={"quality":"low","music":false,"sound":true,"reducedMotion":true,"musicVolume":.33,"soundVolume":.45},"apply submits edits with other verified preferences intact")
	check(receipts[0].ok and Settings.new(settings_path).load_settings().settings==owner.snapshot(),"real settings write is persisted and validated")
	owner.update_settings({"quality":"high"});packet.settings=owner.snapshot();ui.apply_snapshot(packet)
	check(quality.get_item_metadata(quality.selected)=="high","acknowledged draft follows later confirmed preference")
	choose(ui,"quality","low");owner.path="res://project.godot/settings-review.json";press(ui,"apply_settings")
	check(not receipts.back().ok and quality.get_item_metadata(quality.selected)=="low","failed settings persistence preserves editable draft")
	volume.value=44;volume.get_line_edit().grab_focus();await process_frame;volume.get_line_edit().text="44"
	packet.runtime.generation+=1;ui.apply_snapshot(packet)
	quality=ui.find_child("quality",true,false)
	check(quality.get_item_metadata(quality.selected)==owner.snapshot().quality,"new generation rehydrates confirmed preferences")
	check(ui.find_child("musicVolume",true,false).value==owner.snapshot().musicVolume*100,"new generation resets even a focused old volume draft")
	owner.path=settings_path;owner.update_settings({"musicVolume":.203});packet.settings=owner.snapshot();packet.runtime.generation+=1;ui.apply_snapshot(packet)
	check(is_equal_approx(ui.find_child("musicVolume",true,false).value,20.3),"mounted volume preserves fractional confirmed percentage")
	press(ui,"apply_settings");check(is_equal_approx(calls.back().value.musicVolume,.203),"untouched fractional preference survives Apply after remount")
	for suffix in ["",".backup",".rollback",".staged"]:
		if FileAccess.file_exists(settings_path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path+suffix))
	ui.free();await process_frame
func finish():
	print("LEGACY_UI_TESTS assertions=",assertions," failures=",failures); quit(1 if failures else 0)
