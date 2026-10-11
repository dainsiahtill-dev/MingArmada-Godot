extends SceneTree
var assertions := 0
var failures := 0
class CaptureProbe extends Node:
	var save_calls := 0
	var snapshot_calls := 0
	var cancel_on_save: Callable
	func save_frame(path: String) -> Dictionary:
		save_calls += 1
		if cancel_on_save.is_valid(): cancel_on_save.call()
		await get_tree().process_frame
		return {"ok":true,"path":path,"width":1,"height":1}
	func inspection_snapshot() -> Dictionary:
		snapshot_calls += 1
		return {}
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL ",message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var path := "res://game/scenes/reference_island_water/reference_island_water.tscn"
	check(ResourceLoader.exists(path),"native reference scene is available")
	if not ResourceLoader.exists(path): finish(); return
	var packed: PackedScene = load(path)
	var scene: Control = packed.instantiate(); root.add_child(scene)
	await process_frame
	check(scene.startup_receipt.get("ok",false),"direct port startup confirms terrain and ocean")
	check(scene.field.width == 120 and scene.field.height == 140,"actual source Cat Island index dimensions")
	check(scene.field.extent == 160 and scene.field.terrainResolution == 160,"original display extent and drawing resolution")
	check(scene.camera.fov == 45 and is_equal_approx(scene.camera.near,0.3) and scene.camera.far == 1200,"original perspective parameters")
	var initial: Dictionary = scene.inspection_snapshot()
	check(initial.state.strength == 1 and initial.state.tide == 0 and initial.state.foamWidth == 1.5,"source app initial state")
	scene.set_process(false)
	scene.advance_time(0.2,true)
	check(scene.seconds == 0.05,"same source maximum frame dt")
	scene.set_state({"paused":true}); scene.advance_time(0.02,true)
	check(scene.seconds == 0.05,"paused accepted clock does not move")
	scene.set_state({"paused":false}); scene.advance_time(0.02,false)
	check(scene.seconds == 0.05,"hidden window does not move accepted clock")
	scene.advance_time(0.02,true)
	check(is_equal_approx(scene.seconds,0.07),"active accepted clock resumes")
	scene.set_state({"preset":"storm"})
	check(scene.state.strength == 1.8,"source storm preset changes amplitude")
	scene.set_state({"preset":"sunset"})
	check(scene.state.strength == 0.65,"source sunset preset changes amplitude")
	scene.set_state({"tide":8.0,"strength":-1.0,"foamWidth":0.0})
	check(scene.state.tide == 4 and scene.state.strength == 0 and scene.state.foamWidth == 0.3,"source UI range bounds")
	var frozen: Dictionary = scene.state.duplicate(true)
	check(not scene.set_state({"tide":NAN}),"nonfinite input is rejected")
	check(scene.state == frozen,"rejected state does not partially mutate")
	scene.set_state({"preset":"clear","tide":0,"waves":false,"reflection":false,"foam":false,"caustics":false})
	check(not scene.state.waves and not scene.state.reflection and not scene.state.foam and not scene.state.caustics,"original four effect toggles")
	var reset_state: Dictionary = scene.state.duplicate(true); var reset_time: float = scene.seconds
	scene.orbit.azimuth = 1; scene.orbit.distance = 250; scene.reset_camera()
	check(scene.orbit.azimuth == -0.65 and scene.orbit.elevation == 0.68 and scene.orbit.distance == 185,"original orbit reset")
	check(scene.state == reset_state and scene.seconds == reset_time,"source reset only changes orbit")
	var snapshot: Dictionary = scene.inspection_snapshot(); snapshot.state.tide = -3
	check(scene.state.tide == 0,"inspection cannot mutate live state")
	check(scene.find_child("WaterPreset",true,false) != null and scene.find_child("WaterPause",true,false) != null,"actual native controls exist")
	scene.dispose(); scene.dispose()
	check(scene.ocean == null and scene.world == null,"idempotent scene cleanup releases preview world")
	scene.queue_free(); await process_frame
	await launch_route()
	await capture_cancellation()
	finish()

func capture_cancellation() -> void:
	var main = load("res://game/scenes/main/main_scene.gd").new()
	root.add_child(main); await process_frame
	var path := "user://migration-verification/cancelled-capture-%d.png" % OS.get_process_id()
	var pending: Dictionary = main.router.prepare_entry({"type":"water-study","generation":main.router.generation,"nonce":50})
	check(pending.ok and main.router.is_current(pending),"capture fixture starts with a valid entry token")
	main._capture_startup_preview(path,pending)
	main.router.cancel(); await process_frame
	var later := CaptureProbe.new(); main.add_child(later); main.current_scene = later
	for frame in 12: await process_frame
	check(later.save_calls == 0,"cancelled waiting capture cannot save a later preview")
	main.current_scene = null; later.free()
	var active: Dictionary = main.router.prepare_entry({"type":"water-study","generation":main.router.generation,"nonce":51})
	check(active.ok and main.router.is_current(active),"second capture fixture has its own valid request token")
	var returning := CaptureProbe.new(); returning.cancel_on_save = main.router.cancel
	main.add_child(returning); main.current_scene = returning
	main._capture_startup_preview(path,active)
	for frame in 12: await process_frame
	check(returning.save_calls == 1 and returning.snapshot_calls == 0,"cancellation during awaited save prevents subsequent snapshot access")
	check(not FileAccess.file_exists(path+".json"),"cancelled screenshot request cannot write metadata")
	main.free()

func launch_route() -> void:
	var packed: PackedScene = load("res://game/scenes/main/main_scene.tscn")
	var main: Node = packed.instantiate()
	var Router = load("res://game/runtime/game_router.gd")
	var Storage = load("res://game/persistence/save_coordinator.gd")
	var Settings = load("res://game/persistence/user_settings.gd")
	var prefix := "user://migration-verification/island-water-launch-%d" % OS.get_process_id()
	main.router = Router.new({"mingqi_storage":Storage.new(prefix+"-v2.json"),"legacy_storage":Storage.new(prefix+"-v1.json"),"settings_storage":Settings.new(prefix+"-settings.json")})
	root.add_child(main); await process_frame
	check(main.has_method("_request_startup_preview"),"release preview has a normal user-argument entry without path overrides")
	if not main.has_method("_request_startup_preview"):
		main.free(); return
	main._request_startup_preview(PackedStringArray(["--unrelated"]))
	await process_frame
	check(main.current_scene == null and main.menu.visible,"unrelated startup arguments preserve normal menu")
	main._request_startup_preview(PackedStringArray(["--water-study"]))
	for frame in 180:
		if main.current_scene: break
		await process_frame
	check(main.current_scene != null,"normal preview argument uses actual staged menu/router entry")
	if not main.current_scene:
		main.free(); return
	var preview: Node = main.current_scene
	check(preview.startup_receipt.get("ok",false) and preview.startup_receipt.get("mode") == "water-study","argument entry has actual native terrain/ocean startup receipt")
	check(not main.menu.visible,"menu hides only after actual preview startup")
	check(not FileAccess.file_exists(prefix+"-v2.json") and not FileAccess.file_exists(prefix+"-v1.json"),"preview entry does not create gameplay saves")
	main._request_startup_preview(PackedStringArray(["--water-study"]))
	await process_frame
	check(main.current_scene == preview,"repeated startup request does not replace active preview")
	preview.main_menu_requested.emit()
	await process_frame; await process_frame
	check(main.current_scene == null and main.menu.visible and not is_instance_valid(preview),"preview return releases scene and restores actual menu")
	main._request_startup_preview(PackedStringArray())
	await process_frame
	check(main.current_scene == null,"empty startup arguments leave returned menu active")
	main.free()
func finish() -> void:
	print("REFERENCE_DEMO_SCENE_COMPLETE assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
