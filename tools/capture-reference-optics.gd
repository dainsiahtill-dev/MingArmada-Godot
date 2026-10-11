extends "res://tools/capture-reference-water.gd"
func _initialize() -> void:
	directory = "res://docs/migration/evidence/reference-implementation-optics"
	super._initialize()
func compare(label: String) -> void:
	var before: Dictionary = scene.runtime.snapshot()
	var ocean = scene.sea.world.get_ocean()
	ocean.set_reflection_enabled(false); ocean.set_refraction_enabled(false)
	await capture(label+"-baseline")
	ocean.set_refraction_enabled(true)
	await capture(label+"-refraction")
	ocean.set_reflection_enabled(true)
	await capture(label+"-both")
	check(before == scene.runtime.snapshot(),"optics pair uses identical canonical state")
func run() -> void:
	root.unresizable = true
	await frames(3)
	root.size = Vector2i(1600,900); root.content_scale_size=root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var prefix := "user://tests/reference-optics-%d" % OS.get_process_id()
	scene = Legacy.new(); scene.storage=Storage.new(prefix+"-career.json"); scene.settings_storage=Settings.new(prefix+"-settings.json")
	root.add_child(scene); scene.set_physics_process(false)
	await frames(6)
	check(scene.startup_receipt.get("ok",false),"actual career starts optics acceptance")
	if not scene.startup_receipt.get("ok",false): quit(1); return
	scene.interface.visible=false
	coast_camera(); await compare("shore-overhead")
	scene.sea.camera.position=Vector3(-255,15,10)
	scene.sea.camera.look_at(Vector3(-320,5,-40)); scene.sea.world.get_ocean().update_projection()
	await compare("shore-low-angle")
	check(scene._command({"type":"depart"}).get("ok",false),"actual departure")
	scene.runtime.set_held("KeyW",true); await advance(180); scene.runtime.set_held("KeyW",false)
	var ship: Dictionary = scene.runtime.snapshot().naval.ships[0]
	var p: Dictionary = ship.visual.position
	var point := Vector3(p.x,p.y+2,p.z)
	scene.sea.camera.position=point+Vector3(22,12,-28); scene.sea.camera.look_at(point)
	scene.sea.world.get_ocean().update_projection()
	await compare("flagship-close")
	var ocean = scene.sea.world.get_ocean()
	ocean.set_surface_quality("low"); await capture("flagship-low-quality")
	check(not ocean.get_surface_optics_diagnostics().reflection_enabled,"low quality disables SSR")
	ocean.set_surface_quality("high"); await capture("flagship-high-quality")
	check(ocean.get_surface_optics_diagnostics().reflection_steps == 24,"high quality has bounded SSR")
	scene.queue_free(); await frames(6)
	print("REFERENCE_OPTICS_CAPTURE_COMPLETE captures=",captures," failures=",failures)
	quit(1 if failures else 0)
