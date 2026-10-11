extends SceneTree
const Main=preload("res://game/scenes/main/main_scene.gd")
const Router=preload("res://game/runtime/game_router.gd")
const Storage=preload("res://game/persistence/save_coordinator.gd")
const Settings=preload("res://game/persistence/user_settings.gd")
var assertions:=0
var failures:=0
var requests: Array=[]
class RuntimeProbe extends RefCounted:
	var snapshots:=0
	func snapshot() -> Dictionary: snapshots+=1; return {"probe":true}
class SceneProbe extends Node:
	var runtime:=RuntimeProbe.new()
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,reason: String) -> void:
	assertions+=1
	if not ok: failures+=1; printerr("FAIL: ",reason)
func _make_main() -> Node:
	var main: Node=Main.new()
	var prefix: String="user://tests/release-entry-%d-%d" % [OS.get_process_id(),assertions]
	main.router=Router.new({"mingqi_storage":Storage.new(prefix+"-v2.json"),"legacy_storage":Storage.new(prefix+"-v1.json"),"settings_storage":Settings.new(prefix+"-settings.json")})
	root.add_child(main)
	return main
func _run() -> void:
	var main: Node=_make_main(); await process_frame
	check(main.has_method("_request_startup_game"),"release game entry uses an ordinary bundled main-menu method")
	if failures: main.free(); _finish(); return
	main.menu.intent_requested.disconnect(main._handle_intent)
	main.menu.intent_requested.connect(func(request: Dictionary): requests.append(request.duplicate(true)))
	for mode: String in ["mingqi","career","sail","duel","fleet"]:
		requests.clear()
		check(main._request_startup_game(PackedStringArray(["--start-game="+mode])),"normal release route accepts "+mode)
		check(requests.size()==1 and requests[0].type=="start" and requests[0].mode==mode,"CLI emits the actual menu button's gameplay intent")
		check(requests[0].generation==main.router.generation and requests[0].nonce is int and requests[0].nonce>0,"actual menu supplies generation and nonce authority")
		var prepared: Dictionary=main.router.prepare_entry(requests[0])
		check(prepared.ok and main.router.is_current(prepared) and prepared.mode==mode,"actual router accepts the normal CLI menu request")
		main.router.cancel(); main.menu.apply_view_model(main.router.view_model(),main.router.generation)
	for arguments: PackedStringArray in [PackedStringArray(),PackedStringArray(["--start-game=qa"]),PackedStringArray(["--start-game=ships"]),PackedStringArray(["--start-game=sail","--start-game=fleet"]),PackedStringArray(["--start-game=","--start-game=sail"]),PackedStringArray(["--start-game=sail","--game-capture=relative.png"]),PackedStringArray(["--start-game=sail","--game-capture=user://capture.png"]),PackedStringArray(["--start-game=sail","--game-capture=C:/capture.txt"]),PackedStringArray(["--water-study","--start-game=sail"])]:
		requests.clear()
		check(not main._request_startup_game(arguments),"invalid or conflicting release arguments preserve the menu")
		check(requests.is_empty() and main.menu.visible,"invalid release arguments do not bypass the actual menu/router")
	requests.clear()
	check(main._request_startup_game(PackedStringArray(["--start-game=sail","--game-capture=C:/absolute folder/capture.png"])),"absolute PNG path with spaces is accepted")
	check(requests.size()==1 and main._startup_game_capture_path=="C:/absolute folder/capture.png","capture argument remains literal until the actual menu request")
	main.free()
	await _capture_cancellation()
	_finish()
func _capture_cancellation() -> void:
	var main: Node=_make_main(); await process_frame
	var path: String="user://tests/cancelled-game-capture-%d.png" % OS.get_process_id()
	var request: Dictionary=main.router.prepare_entry({"type":"start","mode":"sail","generation":main.router.generation,"nonce":200})
	main._capture_startup_game(path,request)
	main.router.cancel(); await process_frame
	var later:=SceneProbe.new(); main.add_child(later); main.current_scene=later
	for frame in 12: await process_frame
	check(later.runtime.snapshots==0,"cancelled waiting capture cannot inspect a later scene")
	check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".json"),"cancelled waiting capture cannot write PNG or metadata")
	main.current_scene=null; later.free()
	request=main.router.prepare_entry({"type":"start","mode":"sail","generation":main.router.generation,"nonce":201})
	var first:=SceneProbe.new(); main.add_child(first); main.current_scene=first
	main._active_scene_request=request.duplicate(true)
	main._capture_startup_game(path,request)
	await process_frame; await process_frame
	var replacement:=SceneProbe.new(); main.add_child(replacement); main.current_scene=replacement
	for frame in 12: await process_frame
	check(first.runtime.snapshots==0 and replacement.runtime.snapshots==0,"identity changes during warmup cannot inspect either scene")
	check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".json"),"identity changes cannot write a capture")
	main.free()
func _finish() -> void:
	print("RELEASE_GAME_ENTRY_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
