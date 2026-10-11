extends SceneTree
const Text = preload("res://game/domain/legacy/utf16_text.gd")
var failures := 0
var assertions := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if not ResourceLoader.exists("res://game/ui/menu/main_menu.gd"):
		check(false,"native main menu exists and emits detached source entry intents"); _finish(); return
	var Menu = load("res://game/ui/menu/main_menu.gd")
	if Menu == null: check(false,"native menu script parses"); _finish(); return
	var menu = Menu.new(); root.add_child(menu); menu.build()
	var intents: Array = []; var settings: Array = []
	menu.intent_requested.connect(func(intent: Dictionary): intents.append(intent))
	menu.settings_requested.connect(func(): settings.append(true))
	var model := {"settings":{"captainName":"林正衡","music":false},"hasLegacySave":false,"mingqiSlot":"missing","dev":false,"qa":false}
	check(menu.apply_view_model(model,10),"first confirmed model hydrates menu")
	root.size = Vector2i(1600,900)
	for frame in 8: await process_frame
	var initial_scroll = menu.find_child("MenuScroll",true,false)
	check(initial_scroll.scroll_vertical == 0,"initial wide menu keeps title/name visible after layout/focus frames; scroll="+str(initial_scroll.scroll_vertical))
	check(menu.find_child("Captain",true,false).has_focus(),"initial name editor owns keyboard focus after first layout")
	model.settings.captainName = "外部修改"
	var captain = menu.find_child("Captain",true,false)
	check(captain is LineEdit and captain.text == "林正衡","native name input uses detached confirmed snapshot")
	check(intents.is_empty(),"snapshot hydration emits no business intent")
	check(menu.find_child("continue",true,false).disabled,"1661 continue disabled when slot absent")
	check(not menu.find_child("mingqi-continue",true,false).disabled,"1650 continue remains recovery entry with missing slot")
	check(not menu.find_child("qa",true,false).visible and not menu.find_child("practice",true,false).visible,"release hides both developer entry points")
	check(not menu.find_child("QASeed",true,false).get_parent().visible,"release hides QA seed")
	captain.text = "\uFEFF海\t \u3000上  明旗\u00A0"; captain.text_changed.emit(captain.text)
	menu.apply_view_model({"settings":{"captainName":"后到快照"},"mingqiSlot":"unreadable"},10)
	check(captain.text.contains("明旗"),"same-generation refresh preserves edited draft")
	menu.find_child("quit",true,false).grab_focus(); await process_frame; await process_frame
	check(initial_scroll.scroll_vertical > 0,"keyboard focus follows lower native control after stable initial layout")
	var start = menu.find_child("mingqi",true,false); start.pressed.emit(); start.pressed.emit()
	await process_frame; await process_frame
	check(initial_scroll.scroll_vertical == 0,"loading reset keeps status at top after lower-control keyboard scroll")
	check(intents.size() == 1 and intents[0].type == "start" and intents[0].mode == "mingqi" and intents[0].name == "海 上 明旗","new 1650 normalizes source whitespace and suppresses duplicate click")
	check(intents[0].generation == 10 and intents[0].nonce > 0,"entry carries owner generation and monotonic nonce")
	var first: Dictionary = intents[0].duplicate(true)
	menu.find_child("Settings",true,false).pressed.emit()
	check(settings.is_empty(),"settings blocked while loading")
	check(not menu.apply_status({"phase":"error","message":"旧回调"},9,first.nonce),"older generation callback rejected")
	check(not menu.apply_status({"phase":"error","message":"旧请求"},10,first.nonce+1),"foreign nonce callback rejected")
	check(menu.apply_status({"phase":"loading","progress":32,"message":"正在备帆"},10,first.nonce),"matching loading progress accepted")
	check(menu.find_child("Progress",true,false).value == 32,"actual progress control reflects owner progress")
	menu.apply_status({"phase":"error","message":"港口资源暂不可用"},10,first.nonce)
	check(menu.find_child("Status",true,false).text.contains("港口资源暂不可用") and menu.find_child("Retry",true,false).visible,"failure gives readable retry/back state")
	menu.find_child("Retry",true,false).pressed.emit(); menu.find_child("Retry",true,false).pressed.emit()
	check(intents.size() == 2 and intents[1].type == "retry" and intents[1].entryType == "start" and intents[1].mode == "mingqi" and intents[1].nonce > first.nonce,"retry retains attempted entry and owns fresh nonce once")
	check(not menu.apply_status({"phase":"complete"},10,first.nonce),"retry fences prior operation completion")
	var retry: Dictionary = intents[1].duplicate(true)
	check(menu.apply_status({"phase":"complete"},10,retry.nonce),"matching completion accepted")
	start.pressed.emit(); check(intents.size() == 2,"completion remains blocked until explicit acknowledgment")
	check(menu.acknowledge(10,retry.nonce),"owner acknowledges completion")
	menu.find_child("Settings",true,false).pressed.emit(); check(settings.size() == 1,"idle exposes shared settings signal")
	check(not menu.apply_status({"phase":"error"},10,retry.nonce),"acknowledged request no longer accepts callbacks")
	check(not menu.apply_view_model({"settings":{"captainName":"过期"}},9),"older model does not alter menu")
	menu.apply_view_model({"settings":{"captainName":"海".repeat(19)+"😀"},"dev":true,"hasLegacySave":true,"mingqiSlot":"present"},11)
	check(menu.find_child("qa",true,false).visible and menu.find_child("practice",true,false).visible and not menu.find_child("continue",true,false).disabled,"developer and legacy save gates follow confirmed model")
	start.pressed.emit()
	var expected: Array = Text.native_units("海".repeat(19)); expected.append(0xd83d)
	check(Text.utf16_units(intents[-1].name) == expected,"source slice20 preserves split astral surrogate losslessly")
	check(intents[-1].qaSeed == 1661,"source QA default seed remains1661")
	menu.apply_status({"phase":"error","message":"失败"},11,intents[-1].nonce)
	check(not menu.apply_status({"phase":"loading","progress":81},11,intents[-1].nonce),"error phase cannot regress from delayed progress")
	var before_back: Dictionary = intents[-1].duplicate(true)
	menu.find_child("Back",true,false).pressed.emit()
	check(intents[-1].type == "back" and intents[-1].generation == 11 and intents[-1].nextGeneration == 12,"back emits old-owner token plus new generation fence")
	check(not menu.apply_status({"phase":"loading","progress":91},11,before_back.nonce),"back rejects abandoned request progress")
	check(menu.apply_view_model({"settings":{"captainName":"  "},"qa":true,"hasLegacySave":false,"mingqiSlot":"missing"},12),"owner adopts back generation")
	var seed = menu.find_child("QASeed",true,false)
	seed.text = "4294967296"; start.pressed.emit()
	check(intents[-1].type == "back" and menu.find_child("SeedError",true,false).text.contains("范围"),"overflow seed refuses command with source reason")
	seed.text = "1e3"; start.pressed.emit()
	check(menu.find_child("SeedError",true,false).text.contains("十进制"),"nondecimal seed rejects")
	seed.text = "\t4294967295 "; start.pressed.emit()
	check(intents[-1].qaSeed == 4294967295 and intents[-1].name == "沈沧海","source uint32 maximum and empty name fallback")
	menu.apply_status({"phase":"complete"},12,intents[-1].nonce); menu.acknowledge(12,intents[-1].nonce)
	captain.text = "😀".repeat(12); captain.text_changed.emit(captain.text)
	check(Text.source_length(menu.draft_name()) == 20 and captain.text == "😀".repeat(10),"actual input limits astral text in UTF16 units")
	seed.text = " "; captain.text_submitted.emit(captain.text)
	check(not intents[-1].has("qaSeed"),"Enter starts1650 with random seed when blank")
	menu.apply_status({"phase":"complete"},12,intents[-1].nonce); menu.acknowledge(12,intents[-1].nonce)
	for mode in ["mingqi-continue","career","duel","fleet","sail","qa","ships","practice","quit"]:
		var count := intents.size(); menu.find_child(mode,true,false).pressed.emit()
		check(intents.size() == count+1 and (intents[-1].get("mode") == mode or intents[-1].type == mode),"native entry dispatches source mode: "+mode)
		menu.apply_status({"phase":"complete"},12,intents[-1].nonce); menu.acknowledge(12,intents[-1].nonce)
	menu.apply_view_model({"settings":{"captainName":Text.from_units([0xe000,0xd800,0])},"hasLegacySave":true},13)
	menu.find_child("continue",true,false).pressed.emit()
	check(Text.utf16_units(intents[-1].name) == [0xe000,0xd800,0] and intents[-1].mode == "continue","hydrated marker/lone surrogate/NUL remain source-exact in legacy continue payload")
	menu.apply_status({"phase":"complete"},13,intents[-1].nonce); menu.acknowledge(13,intents[-1].nonce)
	menu.find_child("ships",true,false).pressed.emit()
	var ships_nonce: int = intents[-1].nonce
	menu.apply_status({"phase":"error","message":"船册暂未打开"},13,ships_nonce)
	menu.find_child("Retry",true,false).pressed.emit()
	check(intents[-1].type == "retry" and intents[-1].entryType == "ships" and not intents[-1].has("mode"),"ship inspection retry preserves non-start entry target")
	menu.find_child("Back",true,false).pressed.emit(); menu.apply_view_model({"dev":false,"qa":false},14)
	var count_before_gate := intents.size()
	menu.find_child("qa",true,false).pressed.emit(); menu.find_child("practice",true,false).pressed.emit()
	check(intents.size() == count_before_gate,"hidden developer controls cannot bypass gate through stale native callbacks")
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT); menu.size = Vector2(320,480); menu.resized.emit()
	await process_frame; await process_frame
	var panel = menu.find_child("MenuPanel",true,false); var scroll = menu.find_child("MenuScroll",true,false)
	check(panel.size.x <= 320 and panel.size.y <= 480 and scroll.follow_focus and scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,"narrow native window uses bounded vertical scroll with keyboard focus")
	check(menu.find_child("Content",true,false).size.y > scroll.size.y,"narrow menu scroll actually has overflowing content")
	menu.queue_free(); await process_frame
	root.content_scale_size = Vector2i(320,480); root.size = Vector2i(320,480)
	var narrow_menu = Menu.new(); root.add_child(narrow_menu)
	narrow_menu.apply_view_model({"dev":true,"settings":{"captainName":"沈沧海"}},1)
	for frame in 8: await process_frame
	check(narrow_menu.find_child("MenuScroll",true,false).scroll_vertical == 0,"fresh narrow menu begins at title after actual layout frames")
	check(narrow_menu.find_child("Captain",true,false).has_focus(),"fresh narrow menu preserves initial keyboard focus")
	narrow_menu.queue_free(); await process_frame
	var detached_menu = Menu.new(); root.add_child(detached_menu); detached_menu.apply_view_model({},1)
	root.remove_child(detached_menu)
	for frame in 3: await process_frame
	check(not detached_menu.is_inside_tree(),"detaching during initial layout leaves menu detached without delayed focus")
	detached_menu.free()
	var freed_menu = Menu.new(); root.add_child(freed_menu); freed_menu.apply_view_model({},1); freed_menu.queue_free()
	for frame in 3: await process_frame
	check(not is_instance_valid(freed_menu),"freeing during initial layout cancels delayed focus cleanly")
	var superseded_menu = Menu.new(); root.add_child(superseded_menu); superseded_menu.apply_view_model({},1)
	await process_frame
	superseded_menu.apply_view_model({},2)
	for frame in 3: await process_frame
	check(not superseded_menu.find_child("Captain",true,false).has_focus(),"superseding generation during initial layout cancels stale focus acquisition")
	superseded_menu.queue_free(); await process_frame
	var reentered_menu = Menu.new(); root.add_child(reentered_menu); reentered_menu.apply_view_model({},1)
	root.remove_child(reentered_menu); root.add_child(reentered_menu)
	for frame in 3: await process_frame
	check(not reentered_menu.find_child("Captain",true,false).has_focus(),"tree reentry cannot resume canceled initial layout focus")
	reentered_menu.queue_free(); await process_frame; _finish()
func _finish() -> void:
	print("MAIN_MENU_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
