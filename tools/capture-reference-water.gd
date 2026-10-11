extends SceneTree
## Product runtime commands and actual GPU pixels. Fixed accepted ticks are
## visual acceptance only, never a wall-time performance measurement.
const Legacy = preload("res://game/scenes/legacy/legacy_scene.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
var scene: Node3D
var failures := 0
var captures := 0
var directory := "res://docs/migration/evidence/reference-water"
var shot_receipt: Dictionary = {}
func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
	if not ok: failures += 1; printerr("FAIL: ",description)
func frames(count: int = 4) -> void:
	for i in count: await process_frame
func advance(count: int) -> void:
	for i in count:
		scene.sea.observe_projectiles(scene.runtime.native_snapshot())
		var consumed: float = scene.runtime.advance(1.0/60.0)
		check(consumed > 0.0,"real source accepts sailing tick")
		if consumed <= 0.0: return
		scene._present(consumed)
		await process_frame
func coast_camera() -> void:
	scene.sea.camera.position = Vector3(-280,80,70)
	scene.sea.camera.look_at(Vector3(-320,0,-40))
	scene.sea.world.get_ocean().update_projection()
func splash_camera(p: Vector2) -> void:
	scene.sea.camera.position=Vector3(p.x+22,25,p.y-30)
	scene.sea.camera.look_at(Vector3(p.x,0,p.y))
	scene.sea.world.get_ocean().update_projection()
func capture(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var pixels := root.get_texture().get_image()
	var destination := directory+"/"+label+".png"
	check(pixels.save_png(destination)==OK,"GPU screenshot saved")
	var metadata := {"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"size":[pixels.get_width(),pixels.get_height()],"imageSha256":FileAccess.get_sha256(destination),"packet":scene.runtime.snapshot(),"wakes":scene.sea.wakes.diagnostics(),"effects":scene.sea.effects.diagnostics(),"optics":scene.sea.world.get_ocean().get_surface_optics_diagnostics(),"camera":str(scene.sea.camera.global_transform),"shotReceipt":shot_receipt,"scope":"Actual product LegacyScene GPU render with real depart, held-key, pause and cannon commands; accepted fixed ticks for visual sampling only; not performance or complete journey evidence."}
	var file := FileAccess.open(directory+"/"+label+".json",FileAccess.WRITE)
	check(file!=null,"metadata saved")
	if file: file.store_string(JSON.stringify(metadata,"\t")); file.close()
	captures += 1
func run() -> void:
	root.unresizable = true
	await frames(3)
	root.size = Vector2i(1600,900); root.content_scale_size=root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var prefix := "user://tests/reference-water-%d" % OS.get_process_id()
	scene = Legacy.new(); scene.storage=Storage.new(prefix+"-career.json"); scene.settings_storage=Settings.new(prefix+"-settings.json")
	root.add_child(scene); scene.set_physics_process(false)
	await frames(6)
	check(scene.startup_receipt.get("ok",false),"actual career startup")
	if not scene.startup_receipt.get("ok",false): quit(1); return
	scene.interface.visible=false
	coast_camera(); await capture("coast-docked")
	check(scene.sea.wakes.diagnostics().trails==0,"stationary boats have no wake rectangle")
	check(scene._command({"type":"depart"}).get("ok",false),"real departure")
	scene.runtime.set_held("KeyW",true)
	await advance(720)
	check(scene.sea.wakes.diagnostics().trails>0,"real 60Hz sailing leaves a continuous wake")
	await capture("sailing-straight")
	scene.runtime.set_held("KeyD",true)
	await advance(240)
	scene.runtime.set_held("KeyD",false)
	await capture("sailing-turn")
	scene.runtime.set_held("KeyW",false)
	coast_camera(); await capture("coast-wave-a")
	await advance(27); coast_camera(); await capture("coast-wave-b")
	await advance(27); coast_camera(); await capture("coast-wave-c")
	check(scene._command({"type":"pause","reason":"player","value":true}).get("ok",false),"real pause command")
	var before: Dictionary = scene.runtime.snapshot()
	await frames(15); coast_camera(); await capture("coast-paused")
	check(before==scene.runtime.snapshot(),"paused runtime retains same authoritative state")
	check(scene._command({"type":"pause","reason":"player","value":false}).get("ok",false),"real resume command")
	scene._present(0.0)
	shot_receipt=scene._command({"type":"native-action","action":{"type":"fire","shipId":scene.runtime.snapshot().naval.playerId,"side":"port"}})
	check(shot_receipt.get("ok",false),"real broadside accepted")
	var found := false
	for tick in 360:
		await advance(1)
		if scene.sea.effects.diagnostics().splashes > 0:
			found=true
			# Focus the actual event surface, not a synthetic spray demonstration.
			var water = scene.sea.effects.get_node("WaterSplashes")
			var actual: Dictionary = water._splashes[0]
			var p: Vector2 = actual.origin
			splash_camera(p)
			await capture("real-cannon-splash")
			await advance(11); splash_camera(p)
			await capture("real-cannon-splash-peak")
			await advance(19); splash_camera(p)
			await capture("real-cannon-splash-fading")
			break
	check(found,"real fired projectile produces textured splash")
	scene.queue_free(); await frames(6)
	print("REFERENCE_WATER_CAPTURE_COMPLETE captures=",captures," failures=",failures)
	quit(1 if failures else 0)
