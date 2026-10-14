extends "res://tools/profile-hull-dynamics-world.gd"
## Exact current World sequence with full native environment; first accepted-time
## component calls, no production timers, no scene population removal, no FPS claim.
class CompilerTimer:
	extends "res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd"
	var elapsed := {}
	var counts := {}
	func record(key: String, start: int) -> void:
		elapsed[key] = int(elapsed.get(key, 0)) + Time.get_ticks_usec() - start
		counts[key] = int(counts.get(key, 0)) + 1
	func _sample(group: Dictionary, time: float) -> Variant:
		var start := Time.get_ticks_usec(); var result: Variant = super._sample(group, time); record("sample", start); return result
	func _minimum_z(vertices: Array, world: Dictionary) -> float:
		var start := Time.get_ticks_usec(); var result: float = super._minimum_z(vertices, world); record("minimumZ", start); return result
	func _compose_transform(parent: Dictionary, local: Dictionary) -> Dictionary:
		var start := Time.get_ticks_usec(); var result: Dictionary = super._compose_transform(parent, local); record("composeTRS", start); return result
	func _texture_transform(desc: Dictionary, overrides: Dictionary = {}) -> PackedFloat32Array:
		var start := Time.get_ticks_usec(); var result: PackedFloat32Array = super._texture_transform(desc, overrides); record("texture", start); return result
	func _clock_time(controller: Dictionary, time: float, persistent: bool = false) -> float:
		var start := Time.get_ticks_usec(); var result: float = super._clock_time(controller, time, persistent); record("clock", start); return result
	func render_states(compiled: Dictionary, time: float = 0.0, outer: Dictionary = {}, animate: bool = false, camera: Dictionary = {}, include_vertices: bool = false, minimum_z: bool = false, persistent: bool = false) -> Array:
		var start := Time.get_ticks_usec(); var result: Array = super.render_states(compiled, time, outer, animate, camera, include_vertices, minimum_z, persistent); record("animated" if animate else "static", start); return result

func run() -> void:
	output = "res://Temp/world-components-baseline.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not check(not FileAccess.file_exists(output), "new output path"): quit(1); return
	create_timer(90.0).timeout.connect(func(): printerr("WORLD_COMPONENTS watchdog expired"); quit(1))
	root.size = Vector2i(1200, 900)
	var career := MemorySlot.new(); var legacy := MemorySlot.new()
	var settings := Settings.new("user://verification/world-components-no-write-%d.json" % OS.get_process_id())
	main = Main.new()
	main.router = Router.new({"mingqi_storage": career, "legacy_storage": legacy, "settings_storage": settings})
	root.add_child(main)
	for frame in 5: await process_frame
	main.menu.find_child("sail", true, false).pressed.emit()
	for frame in 400:
		await process_frame
		if is_instance_valid(main.current_scene) and bool(main.current_scene.get("startup_receipt").get("ok", false)): break
	if not check(is_instance_valid(main.current_scene), "public sail ready"): main.free(); quit(1); return
	game = main.current_scene
	freeze_callbacks(main)
	for reason in ["menu", "player", "blur"]: game.runtime.set_pause(reason, false)
	game._present(0.0)
	var compiler_timer: RefCounted
	if "--compiler-detail" in OS.get_cmdline_user_args():
		compiler_timer = CompilerTimer.new()
		game.sea.world.atmosphere.set("_render_compiler", compiler_timer)
	var rows: Array = []
	var samples: Dictionary = {}
	var initial: Dictionary = game.runtime.simulation.snapshot()
	var source_hashes := {}
	for path in ["modules/scene_engine/world/world_view.gd", "modules/scene_engine/terrain/natural_world.gd", "modules/scene_engine/terrain/natural_shore_surf.gd", "modules/scene_engine/fidelity_island/compiled_shore_sampler.gd", "modules/scene_engine/fidelity_fx/atmosphere.gd", "modules/scene_engine/fidelity_fx/cloud_render_compiler.gd"]: source_hashes[path] = FileAccess.get_sha256("res://" + path)
	for index in 40:
		var accepted: float = game.runtime.advance(STEP)
		var native: Dictionary = game.runtime.simulation.snapshot()
		check(accepted > 0 and native.time > game.sea.world.get("_simulation_time"), "first call at fresh accepted native time")
		game.sea._update_camera(native, accepted)
		var packet: Dictionary = game.sea._world_packet(native)
		check(packet.environment == native.environment, "full native environment retained")
		var costs := world_components(game.sea.world, packet, accepted)
		if index >= 8:
			for key in costs:
				if not samples.has(key): samples[key] = []
				samples[key].append(costs[key])
			rows.append({"time": native.time, "environmentTime": packet.environment.acceptedTime, "sourceCallIndex": packet.environment.sourceCallIndex, "stageMs": costs})
		game._present(accepted)
		await process_frame
	var summary := {}
	for key in samples: summary[key] = stats(samples[key])
	var natural = game.sea.world.get("_natural_world")
	var patch_count := 0
	for shore in natural.get("_dynamic_shore"): patch_count += shore.get("_materials").size()
	check(career.writes == 0 and legacy.writes == 0, "no save writes")
	var proof := {"scope": "Actual public sail entry; fixed accepted1/60; current World.apply_snapshot sequence split into first-call CPU components, full environment retained. Normal _present completion runs afterward at same time and is not part of measured samples. Headless CPU only, not FPS/GPU.", "engine": Engine.get_version_info().string, "sourceHashes": source_hashes, "warmup": 8, "sampleCount": rows.size(), "initialTime": initial.time, "shipCount": initial.ships.size(), "shorePatches": patch_count, "atmosphere": game.sea.world.atmosphere.diagnostics(), "stageMs": summary, "rows": rows, "failures": failures}
	if compiler_timer: proof.compilerInstrumentation = {"scope": "nested timers include overhead and all40 calls plus completion refresh; parent and children must not be summed", "totalUsec": compiler_timer.elapsed, "calls": compiler_timer.counts}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(proof, "\t")); file.close()
	print("WORLD_COMPONENTS_COMPLETE failures=", failures.size(), " stageMs=", JSON.stringify(summary))
	main.free(); quit(1 if not failures.is_empty() else 0)

func world_components(world: Node3D, snapshot: Dictionary, consumed: float) -> Dictionary:
	var costs := {}
	var start := Time.get_ticks_usec()
	var epoch := str(snapshot.get("battleId", ""))
	if not epoch.is_empty() and epoch != world.get("_weather_epoch"):
		world.atmosphere.reset_timeline(); world.set("_weather_epoch", epoch)
	var seconds := float(snapshot.time)
	world.set("_simulation_time", seconds)
	var ocean: Node3D = world.get_ocean()
	ocean.set_simulation_time(seconds)
	var spray = world.get("_shore_spray")
	if is_instance_valid(spray): spray.set_simulation_time(seconds)
	var wind: Dictionary = snapshot.wind
	var direction: Dictionary = wind.get("direction", {})
	ocean.set_surface_wind(Vector2(float(direction.get("x", 1)), float(direction.get("y", direction.get("z", 0)))), float(wind.get("speed", 0)))
	var point: Variant = snapshot.focus
	var focus: Vector2 = point if point is Vector2 else Vector2(float(point.x), float(point.z))
	world._update_window(focus)
	world._sync_terrain_surface()
	ocean.update_projection()
	costs.surface = (Time.get_ticks_usec() - start) / 1000.0
	var details = world.get("_island_details")
	if details: measure(costs, "islandDetails", func(): details.apply_snapshot({"time": seconds, "focus": focus}, consumed))
	for trees in world.get("_fidelity_vegetation"): trees.apply_snapshot({"time": seconds, "focus": focus}, consumed)
	for surf in world.get("_fidelity_shores"):
		surf.sync_surface_state(ocean.material_override as ShaderMaterial); surf.apply_snapshot(seconds)
	var natural = world.get("_natural_world")
	if is_instance_valid(natural):
		var forest_state := {"time": seconds, "focus": focus, "lighting": {"lightDirection": Vector3(0.5, -0.8, -0.3).normalized(), "lightColor": Vector3(1, 0.95, 0.82), "ambient": Vector3(0.35, 0.40, 0.30), "customFog": false}}
		measure(costs, "forest", func():
			for trees in natural.get("_trees"): trees.apply_snapshot(forest_state, consumed))
		measure(costs, "naturalShore", func():
			for shore in natural.get("_dynamic_shore"): shore.apply_snapshot({"time": seconds, "focus": focus}, consumed))
	var environment: Dictionary = snapshot.get("environment", {})
	if environment.get("lighting", {}).get("target") is Dictionary: world.set("_source_lighting", environment.lighting.target.duplicate(true))
	world._apply_source_lighting()
	measure(costs, "atmosphere", func(): world.atmosphere.apply_snapshot(snapshot, world.get("_camera"), Vector3(focus.x, 0, focus.y)))
	return costs
