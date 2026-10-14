extends SceneTree
const Demo = preload("res://game/research/demos/weather_shadow_experiment.gd")
var assertions := 0
var failures := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL weather transform lab: ", detail)
func _initialize() -> void: run.call_deferred()
func rendered(demo) -> Array:
	var result: Array = []
	for records in [demo.get("_sky_records"), demo.get("_cloud_records"), demo.get("_shadow_records")]:
		for record in records:
			result.append({"transform": record.node.global_transform, "visible": record.node.visible, "uv": record.material.get_shader_parameter("original_uv_matrix"), "color": record.material.get_shader_parameter("original_material"), "bounds": record.node.custom_aabb})
	return result
func run() -> void:
	var demo := Demo.new()
	check(demo.configure({"cpu_transform_batching": false}).get("ok", false), "existing weather lab exposes independent baseline factor")
	if failures: demo.free(); finish(); return
	var viewport := SubViewport.new(); viewport.size = Vector2i(960, 640); viewport.own_world_3d = true
	root.add_child(viewport); viewport.add_child(demo)
	for _step in 8: demo.advance(1.0/32.0)
	demo.set_paused(true)
	var held: Dictionary = demo.inspection_snapshot()
	var baseline := rendered(demo)
	check(demo.set_parameter("cpu_transform_batching", true).ok, "candidate enables while paused")
	check(var_to_bytes(rendered(demo)) == var_to_bytes(baseline), "candidate retains all paused material and node outputs")
	check(demo.inspection_snapshot().environment == held.environment, "factor never consumes source RNG or history")
	demo.reset_experiment({"cpu_transform_batching": true, "paused": false})
	for _step in 8: demo.advance(1.0/32.0)
	check(var_to_bytes(rendered(demo)) == var_to_bytes(baseline), "fresh candidate timeline exactly matches original complete render output")
	check(demo.inspection_snapshot().environment == held.environment, "same initial epoch regenerates exact authoritative environment")
	demo.dispose(); viewport.free(); finish()
func finish() -> void:
	print("LABORATORY_WEATHER_TRANSFORM_PASS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
