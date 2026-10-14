extends SceneTree
const Trial = preload("res://game/research/demos/cloud_transform_trial.gd")
const Native = preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
var errors: Array = []
func _initialize() -> void: run.call_deferred()
func stats(values: Array) -> Dictionary:
	var sorted := values.duplicate(); sorted.sort()
	return {"count": values.size(), "p50": sorted[ceili(0.5*sorted.size())-1], "p95": sorted[ceili(0.95*sorted.size())-1], "min": sorted[0], "max": sorted[-1]}
func run() -> void:
	var output := "res://Temp/weather-transform-pair.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if FileAccess.file_exists(output): printerr("fresh output required"); quit(1); return
	var baseline := Trial.new(); baseline.batched = false
	var candidate := Trial.new(); candidate.batched = true
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_fx/manifest.json"))
	var assets := {}
	for entry in manifest.atmosphere.assets: assets[entry.file] = JSON.parse_string(FileAccess.get_file_as_string(entry.data_path))
	var ring := Native.create_cloud_ring(1)
	var jobs: Array = []
	for clone in ring.nodes:
		jobs.append({"a": baseline.compile_asset(assets[clone.prototype]), "b": candidate.compile_asset(assets[clone.prototype]), "animate": false, "outer": {"rotation": clone.rotation, "translation": Native.transform_vector(clone.rotation, [0,1,0]), "scale": 1.0}, "phase": 0.0})
	for i in 6: jobs.append({"a": baseline.compile_asset(assets["fx_groundfog01.nif"]), "b": candidate.compile_asset(assets["fx_groundfog01.nif"]), "animate": true, "outer": {}, "phase": i * 1.66666686534882})
	var camera := {"direction":[0.0,-1.0,0.0],"up":[0.0,0.0,1.0],"right":[1.0,0.0,0.0]}
	var times := {"baseline": [], "candidate": []}
	var rows: Array = []
	for step in 40:
		var results := {}
		var costs := {}
		for kind in (["baseline", "candidate"] if step%2 == 0 else ["candidate", "baseline"]):
			var compiler = baseline if kind == "baseline" else candidate
			var states: Array = []
			var started := Time.get_ticks_usec()
			for job in jobs: states.append(compiler.render_states(job.a if kind == "baseline" else job.b, step/32.0+job.phase, job.outer, job.animate, camera, false, not job.animate, true))
			costs[kind] = (Time.get_ticks_usec()-started)/1000.0
			results[kind] = var_to_bytes(states)
		if results.baseline != results.candidate: errors.append("byte mismatch at " + str(step))
		if step >= 8:
			times.baseline.append(costs.baseline); times.candidate.append(costs.candidate)
			rows.append({"time": step/32.0, "ms": costs, "exact": results.baseline == results.candidate})
	var proof := {"scope": "Headless isolated36 real source groups:30 sky clones+6 independent fog phases, all mesh/controller output. Alternating pair, 8warmup/32samples at1/32. Only batch-store factor differs; no FPS/GPU claim.", "baselineMs": stats(times.baseline), "candidateMs": stats(times.candidate), "rows": rows, "errors": errors, "sources": {}}
	for path in ["modules/scene_engine/fidelity_fx/cloud_transform_kernel.gd", "modules/scene_engine/fidelity_fx/cloud_render_compiler.gd", "game/research/demos/cloud_transform_trial.gd"]: proof.sources[path] = FileAccess.get_sha256("res://"+path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE); file.store_string(JSON.stringify(proof,"\t")); file.close()
	print("WEATHER_TRANSFORM_PAIR_COMPLETE errors=", errors.size(), " baseline=", proof.baselineMs, " candidate=", proof.candidateMs)
	quit(1 if not errors.is_empty() else 0)
