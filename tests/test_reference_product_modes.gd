extends SceneTree
const Legacy = preload("res://game/runtime/legacy_runtime.gd")
const Mingqi = preload("res://game/runtime/mingqi_runtime.gd")
var failures := 0
var assertions := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",detail)
func _run() -> void:
	for script in [Legacy,Mingqi]:
		var runtime = script.new()
		check(runtime.has_method("enable_reference_enhancements"),"product runtime has an explicit reference-enhancement profile")
		if runtime.has_method("enable_reference_enhancements"):
			runtime.enable_reference_enhancements()
			check(runtime.configure(func(_x: float,_z: float): return -30.0).ok,"enhanced product configure succeeds")
			check(runtime.simulation.encounter.config.get("referenceHandling",false),"product uses responsive handling budget")
			check(runtime.simulation.encounter.config.get("referenceGunnery",false),"product uses paced and safe broadsides")
			var saved: Dictionary = runtime.export_save() if script == Legacy else runtime.export_save("2026-10-11T00:00:00.000Z")
			check(saved.get("ok",false),"enhanced opening exports a real safe checkpoint")
			if saved.get("ok",false) and saved.get("json") is String:
				check(runtime.adopt_save(saved.json).ok,"product save reload accepted")
				check(runtime.simulation.encounter.config.get("referenceHandling",false) and runtime.simulation.encounter.config.get("referenceGunnery",false),"reloading keeps the same product profile")
			runtime.dispose()
	print("REFERENCE_PRODUCT_MODE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
