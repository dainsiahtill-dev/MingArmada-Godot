extends SceneTree
const Menu = preload("res://game/ui/menu/main_menu.gd")
const Router = preload("res://game/runtime/game_router.gd")
const Main = preload("res://game/scenes/main/main_scene.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
var assertions := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",reason)
func _run() -> void:
	var menu := Menu.new(); root.add_child(menu)
	menu.apply_view_model({"dev":false,"qa":false},1)
	await process_frame
	var visible: Array = []
	for entry: String in menu._buttons:
		if menu._buttons[entry].is_visible_in_tree(): visible.append(entry)
	visible.sort()
	check(visible == ["duel","fidelity-island","fire","fleet","laboratory","mingqi","mingqi-continue","quit","sail","ships","story","story-continue","world-atlas"],"ordinary menu exposes gameplay, fire skirmish, geographic atlas, laboratory, mainline entries and one shared-world visual acceptance entry")
	var emitted: Array = []
	menu.intent_requested.connect(func(request: Dictionary): emitted.append(request))
	for internal: String in ["career","continue","water-study","fidelity-source","qa","practice"]:
		menu.find_child(internal,true,false).pressed.emit()
	check(emitted.is_empty(),"stale callbacks cannot expose internal examples or historical campaign in ordinary menu")
	menu.apply_view_model({"dev":true,"qa":false,"hasLegacySave":true},2)
	for internal: String in ["career","continue","water-study","fidelity-source","qa","practice"]:
		check(menu.find_child(internal,true,false).is_visible_in_tree(),"explicit development menu preserves internal route "+internal)
	menu.free()
	var router := Router.new()
	var nonce := 0
	for internal: String in ["career","continue","water-study","fidelity-source","qa","practice"]:
		nonce += 1
		var denied: Dictionary = router.prepare_entry({"type":internal,"generation":router.generation,"nonce":nonce,"dev":true,"qa":true})
		check(denied.get("reason") == "entry-developer-only","request flags cannot expose internal router route "+internal)
	var prepared: Dictionary = router.prepare_entry({"type":"fidelity-island","generation":router.generation,"nonce":nonce+1})
	var made: Dictionary = router.create_scene(prepared)
	check(made.ok and made.scene.get_script() == preload("res://game/scenes/fidelity_island/combined_island.gd"),"single public preview constructs existing formal NavalWorldView composition")
	check(made.ok and made.scene.has_method("save_frame"),"sole public preview supports the existing native startup capture contract")
	if made.get("scene") is Node: made.scene.free()
	prepared.mode = "fidelity-source"
	var forged: Dictionary = router.create_scene(prepared)
	check(forged.get("reason") == "entry-developer-only","forged prepared candidate cannot construct internal source example")
	if forged.get("scene") is Node: forged.scene.free()
	var prefix := "user://tests/menu-consolidation-%d" % OS.get_process_id()
	var main := Main.new()
	main.router = Router.new({"mingqi_storage":Storage.new(prefix+"-v2.json"),"legacy_storage":Storage.new(prefix+"-v1.json"),"settings_storage":Settings.new(prefix+"-settings.json")})
	root.add_child(main); await process_frame
	main.menu.intent_requested.disconnect(main._handle_intent)
	var requests: Array = []
	main.menu.intent_requested.connect(func(request: Dictionary): requests.append(request.duplicate(true)))
	main._request_startup_preview(PackedStringArray(["--water-study"]))
	check(requests.is_empty(),"legacy standalone demo launch remains internal in ordinary mode")
	main._request_startup_preview(PackedStringArray(["--sea-island"]))
	check(requests.size() == 1 and requests[0].type == "fidelity-island","normal sea-island argument uses sole public preview button")
	main.router.cancel(); main.menu.apply_view_model(main.router.view_model(),main.router.generation); requests.clear()
	main._request_startup_preview(PackedStringArray(["--sea-island","--water-study"]))
	check(requests.is_empty(),"conflicting preview arguments preserve menu authority")
	main.free()
	print("MENU_CONSOLIDATION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
