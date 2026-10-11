extends SceneTree
const QA = preload("res://game/scenes/visual_qa/visual_qa.tscn")
var scene: Node
var records: Dictionary = {}
var enabled := false
func _initialize() -> void: run.call_deferred()
func sampled(kind: String, sampler: Callable, x: float,z: float,t: float) -> float:
	if not enabled: return float(sampler.call(x,z,t))
	var start := Time.get_ticks_usec()
	var result := float(sampler.call(x,z,t))
	var record: Dictionary = records.get(kind,{"calls":0,"microseconds":0})
	record.calls += 1; record.microseconds += Time.get_ticks_usec()-start
	records[kind]=record
	return result
func filtered(sampler: Callable,x:float,z:float) -> float:
	if not enabled: return float(sampler.call(x,z))
	var start := Time.get_ticks_usec()
	var result := float(sampler.call(x,z))
	var record: Dictionary = records.get("surface_filter",{"calls":0,"microseconds":0})
	record.calls += 1; record.microseconds += Time.get_ticks_usec()-start
	records.surface_filter=record
	return result
func run() -> void:
	root.size=Vector2i(1600,900); root.content_scale_size=root.size
	scene=QA.instantiate(); scene.startup_options={"dev":true,"scenario":"fleet"}; root.add_child(scene)
	for frame in 6: await process_frame
	var water: Callable = scene.runtime.sample_water_height
	var height: Callable = scene.heights.sample_height
	scene.sea.wakes._water=func(x:float,z:float,t:float):return sampled("wakes",water,x,z,t)
	scene.sea.effects.get_node("WaterSplashes")._water=func(x:float,z:float,t:float):return sampled("splashes",water,x,z,t)
	scene.sea._height=func(x:float,z:float):return filtered(height,x,z)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<15000: await process_frame
	var valid := true; var frames := 0; var source_start: int = scene.runtime.snapshot().naval.tick
	enabled=true; start=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<20000:
		await process_frame; frames+=1
		valid=valid and root.has_focus() and not scene.runtime.is_paused()
	enabled=false
	var result := {"valid":valid,"frames":frames,"wallMs":Time.get_ticks_msec()-start,"counts":records,"nativeTicks":scene.runtime.snapshot().naval.tick-source_start,"wakes":scene.sea.wakes.diagnostics(),"scope":"Actual native fleet route and wrapped original samplers. Microsecond probes and dictionaries add overhead; this diagnoses CPU sampling, not acceptance FPS or GPU completion."}
	var file:=FileAccess.open("res://docs/migration/evidence/reference-implementation-performance/sampling-profile.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t")); file.close()
	scene.queue_free(); await process_frame
	print("REFERENCE_SAMPLING_PROFILE ",JSON.stringify(result)); quit(0 if valid else 1)
