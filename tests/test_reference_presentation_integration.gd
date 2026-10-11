extends SceneTree
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const View = preload("res://game/presentation/world/naval_world_view.gd")
var failures := 0
var assertions := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",reason)
func _run() -> void:
	var height := func(_x: float,_z: float): return -30.0
	var runtime := Runtime.new()
	runtime.configure(height)
	var view := View.new(); root.add_child(view)
	var native: Dictionary = runtime.snapshot().naval
	native.time = 8.0
	native.wind = {"direction":{"x":0.0,"y":1.0},"speed":19.0}
	view.configure(height,[],runtime.sample_water_height,native,{"resolution":4,"chunk_radius":0,"vegetation":false})
	var id: String = native.playerId
	check(view.world.get_ocean().material_override.get_shader_parameter("surface_wind_speed") == 19.0,"real naval world forwards actual weather to fragment layers")
	check(view.ships[id].has_method("damage_diagnostics") and view.has_method("_on_ship_presentation"),"damage timing and event integration implemented")
	if not view.ships[id].has_method("damage_diagnostics") or not view.has_method("_on_ship_presentation"):
		view.dispose(); view.free(); runtime.dispose()
		print("REFERENCE_PRESENTATION_INTEGRATION_TESTS assertions=",assertions," failures=",failures)
		quit(1); return
	check(view.ships[id].damage_diagnostics().accepted_time == native.time,"ship damage and ocean share authoritative absolute time")
	check(view.ships[id].presentation_event.is_connected(view._on_ship_presentation),"damage key events reach finite combat effects")
	var native_before := native.duplicate(true)
	view._on_ship_presentation({"type":"destruction-explosion","id":"integration-explosion","shipId":id,"time":8.0,"position":{"x":0.0,"y":3.0,"z":0.0}})
	check(view.effects.diagnostics().puffs > 0,"destruction event produces visible bounded feedback")
	var puffs: int = view.effects.diagnostics().puffs
	view._on_ship_presentation({"type":"destruction-explosion","id":"integration-explosion","shipId":id,"time":8.0,"position":{"x":0.0,"y":3.0,"z":0.0}})
	check(view.effects.diagnostics().puffs == puffs,"repeated presentation key never replays explosion")
	check(native == native_before,"presentation events never alter authority snapshots")
	view.dispose(); view.queue_free(); runtime.dispose()
	await process_frame
	print("REFERENCE_PRESENTATION_INTEGRATION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
