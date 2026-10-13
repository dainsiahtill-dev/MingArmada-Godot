extends SceneTree
const AudioCleanup = preload("res://tests/fixtures/audio_cleanup.gd")
## Formal fleet presentation must own the existing source clouds and thin land
## fog. Catches disconnected snapshots, per-quality duplicates and leaked nodes.
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Trial = preload("res://game/scenes/sailing_trial/sailing_trial.gd")
const Practice = preload("res://game/scenes/naval_practice/naval_practice.gd")
var assertions := 0
var failures := 0

func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL naval atmosphere: ", detail)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var ports: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var height := Height.new(); height.configure_ports(ports)
	var runtime := Runtime.new(); runtime.configure(height.sample_height)
	var native: Dictionary = runtime.snapshot().naval
	var unchanged := native.duplicate(true)
	var view: Node3D = Sea.new(); root.add_child(view)
	var unrelated := Node3D.new(); view.add_child(unrelated)
	check(view.configure(height.sample_height, ports, runtime.sample_water_height, native, {"resolution":8,"chunk_radius":0,"vegetation":false,"island_details":false}), "formal fleet configures real natural sea")
	var clouds: Node3D = view.world.get_node_or_null("OriginalCloudAndFog")
	check(clouds != null, "shared World configure instantiates original weather for every sailing entrance")
	if clouds != null:
		var atmosphere: RefCounted = view.world.get("atmosphere")
		var initial: Dictionary = atmosphere.diagnostics()
		check(initial.cloudClones == 30 and initial.cloudMeshes > 0, "formal world displays the original seeded cloud prototypes")
		check(initial.fogInstances == 3 and initial.fogMeshes == 60, "thin fog obtains explicit formal island placements")
		var cloud_count := 0
		for mesh: MeshInstance3D in clouds.get_children():
			check(mesh.get_world_3d() == view.world.get_ocean().get_reflection_viewport().world_3d, "cloud and fog geometry belongs to the same reflected world")
			if mesh.name.begins_with("OriginalCloud_"):
				cloud_count += 1
				var bounds: AABB = mesh.global_transform * mesh.get_aabb()
				check(bounds.position.y > 60.0, "meter-scale sky geometry stays above fleet and island navigation")
			elif mesh.name.begins_with("OriginalGroundFog_"):
				check(mesh.global_position.y > 0.0, "ground fog is anchored on accepted land rather than open water")
				check(float(mesh.material_override.get_shader_parameter("display_opacity")) <= 0.04, "clear-weather source fog stays below four percent opacity")
		check(cloud_count == initial.cloudMeshes and native == unchanged, "owned atmosphere preserves source meshes and canonical state")
		for reason in runtime.presentation_pause_reasons():runtime.set_pause(reason,false)
		for i in 29:runtime.advance(0.25)
		native=runtime.snapshot().naval;view.apply_snapshot(native, [], 0.0)
		var playing: Dictionary = atmosphere.diagnostics()
		check(is_equal_approx(playing.time,native.environment.acceptedTime) and playing.firstCloudRotation != initial.firstCloudRotation, "zero wall delta still consumes accepted native atmosphere time")
		view.apply_snapshot(native, [], 0.0)
		check(atmosphere.diagnostics().firstCloudRotation == playing.firstCloudRotation, "paused formal snapshot never drifts cloud rotation")
		view.zoom = 1.4; view.apply_snapshot(native, [], 0.0)
		check(atmosphere.diagnostics().skyOrigin.is_equal_approx(view.camera.global_position + Vector3(0,380,0)), "paused captain-camera changes reposition the same sky geometry")
		var retained_clouds: WeakRef = weakref(clouds)
		view.apply_settings({"quality":"high"})
		check(retained_clouds.get_ref() == clouds and view.world.get_node("OriginalCloudAndFog") == clouds and atmosphere.diagnostics().time == playing.time, "quality rebuild keeps one atmosphere and accepted weather history")
		view.apply_settings({"reducedMotion":true})
		for i in 7:runtime.advance(0.25)
		native=runtime.snapshot().naval;view.apply_snapshot(native, [], 0.0)
		check(atmosphere.diagnostics().time == native.environment.acceptedTime and atmosphere.diagnostics().firstCloudRotation == playing.firstCloudRotation, "reduced motion freezes weather animation while retaining accepted time")
		view.apply_settings({"reducedMotion":false})
		view.apply_snapshot(native, [], 0.0)
		check(atmosphere.diagnostics().firstCloudRotation != playing.firstCloudRotation, "restored motion rejoins authoritative atmosphere time")
		native=unchanged.duplicate(true);view.apply_snapshot(native, [], 0.0)
		check(atmosphere.diagnostics().firstCloudRotation == initial.firstCloudRotation, "formal rewind restores original cloud seed and source rotation")
		view.dispose(); view.dispose()
		check(retained_clouds.get_ref() == null, "dispose releases all owned source cloud and fog meshes")
		check(is_instance_valid(unrelated) and unrelated.get_parent() == view, "weather cleanup preserves caller-owned scene nodes")
		view.apply_settings({"quality":"low"})
		check(view.configure(height.sample_height, ports, runtime.sample_water_height, unchanged, {"resolution":8,"chunk_radius":0,"vegetation":false,"island_details":false}), "low-quality formal reentry composes source weather")
		check(view.world.get_node_or_null("OriginalCloudAndFog") != null and view.world.get("atmosphere").diagnostics().time == 0.0, "reentry replaces weather history without leaking prior clouds")
	view.dispose(); view.free(); runtime.dispose()
	await process_frame; await process_frame
	var trial := Trial.new(); root.add_child(trial)
	await process_frame; trial.set_physics_process(false)
	check(trial.world != null and trial.world.get_node_or_null("OriginalCloudAndFog") != null, "actual ordinary sailing trial consumes the same World weather owner")
	if trial.world != null and trial.world.get("atmosphere") != null:
		var trial_weather: RefCounted = trial.world.get("atmosphere")
		check(trial_weather.diagnostics().time == float(trial.previous.time), "trial startup passes actual accepted ship snapshot time to atmosphere")
		var trial_time := float(trial.previous.time)
		trial.runtime.advance(0.25); trial._apply_snapshot(0.0)
		check(absf(float(trial_weather.diagnostics().time)-trial_time-0.25)<0.000001, "actual trial runtime advances source weather despite zero display delta and no naval fields")
		var trial_clouds: WeakRef = weakref(trial.world.get_node("OriginalCloudAndFog"))
		trial.world.dispose(); trial.world.dispose()
		check(trial_clouds.get_ref() == null, "standalone trial World cleanup releases shared weather")
	trial.free(); await process_frame; await process_frame
	var practice := Practice.new(); practice.startup_options = {"mode":"duel","staged":true}
	root.add_child(practice); await process_frame; practice.set_physics_process(false)
	check(practice.startup_receipt.get("ok",false), "actual practice route starts for weather restart regression")
	if practice.startup_receipt.get("ok",false):
		practice.activate_entry()
		var practice_weather: RefCounted = practice.sea.world.get("atmosphere")
		for i in 8: practice._present(practice.runtime.advance(0.25))
		check(int(practice_weather.diagnostics().get("environmentRevision",0)) > 0, "real practice play consumes accepted weather revision")
		var old_epoch := String(practice.runtime.snapshot().naval.battleId)
		practice._command({"type":"restart"})
		check(String(practice.runtime.snapshot().naval.battleId) != old_epoch and practice_weather.diagnostics().time == 0.0, "actual Restart establishes a fresh accepted weather epoch")
		check(int(practice_weather.diagnostics().get("environmentRevision",-1)) == 0, "Restart drops previous encounter weather history rather than replaying it")
		practice._present(practice.runtime.advance(0.25))
		check(int(practice_weather.diagnostics().get("environmentRevision",-1)) == int(practice.runtime.snapshot().naval.environment.revision), "first restarted snapshot records only the new weather timeline")
	var playbacks: Array[WeakRef]=AudioCleanup.stop_players(practice)
	practice.free(); await process_frame; await process_frame
	check(await AudioCleanup.wait_for_release(self,playbacks),"weather practice shutdown releases actual stopped audio playbacks before exit")
	print("NAVAL_ATMOSPHERE_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
