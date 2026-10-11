extends SceneTree
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
var failures := 0
var assertions := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ", detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	# Catches presenter retaining sold/superseded vessels, advancing paused water,
	# changing injected authority poses, or freeing caller-owned scene nodes.
	var path := "res://game/presentation/world/naval_world_view.gd"
	var script = load(path) if ResourceLoader.exists(path) else null
	check(script != null, "shared naval presentation is required for all native voyage modes")
	if script:
		var ports: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
		var heights := Height.new(); heights.configure_ports(ports)
		var runtime := Runtime.new(); runtime.configure(heights.sample_height)
		var view = script.new(); root.add_child(view)
		var unrelated := Node3D.new(); view.add_child(unrelated)
		var native: Dictionary = runtime.snapshot().naval
		var unchanged := native.duplicate(true)
		check(view.configure(heights.sample_height, ports, runtime.sample_water_height, native, {"resolution":12,"chunk_radius":0,"vegetation":false}), "shared view composes real ocean, fleet and deck crews")
		check(view._environment.tonemap_mode == Environment.TONE_MAPPER_LINEAR and view._environment.tonemap_exposure == 1.0,"formal sea keeps the reference display/linear color contract without ACES darkening")
		check(view._environment.background_mode == Environment.BG_SKY and view._environment.sky != null and view._environment.sky.sky_material is ShaderMaterial,"formal sailing binds the same reference procedural sky as planar reflection")
		check(view.ships.size() == 5 and view.sailors.size() == 5, "all five opening fleet snapshots obtain independent imported models")
		check(native == unchanged, "presentation never mutates canonical native state")
		var id: String = native.playerId
		var player: Dictionary = {}
		for ship: Dictionary in native.ships:
			if ship.id == id: player = ship
		var point: Dictionary = player.visual.position
		check(view.ships[id].position.is_equal_approx(Vector3(point.x,point.y,point.z)), "flagship uses authoritative waterline pose")
		var budget := 0
		for crew in view.sailors.values(): budget += crew.get_visible_count()
		check(budget > 0 and budget <= 120, "shared presentation enforces combined crew budget")
		native.time = 7.25
		view.apply_snapshot(native, [], 0.0)
		check(float(view.world.get_ocean().get("_simulation_time")) == 7.25, "ocean follows accepted authority time despite zero wall delta")
		var camera_before: Vector3 = view.camera.position
		view.apply_snapshot(native, [], 0.0)
		check(view.camera.position == camera_before, "pause does not drift following camera")
		native.wind={"direction":{"x":0.6,"y":0.8},"speed":6.5}
		view.apply_snapshot(native,[],0.0)
		var old_mirror: WeakRef=weakref(view.world.get_ocean().get_reflection_viewport())
		view.apply_settings({"quality":"high"})
		var rebuilt: MeshInstance3D=view.world.get_ocean()
		var rebuilt_wind: Variant=rebuilt.material_override.get_shader_parameter("surface_wind_direction")
		check(rebuilt_wind is Vector2 and rebuilt_wind.is_equal_approx(Vector2(0.6,0.8)) and rebuilt.material_override.get_shader_parameter("surface_wind_speed")==6.5,"paused quality rebuild retains the accepted wind for natural surface detail")
		check(rebuilt._simulation_time==7.25 and old_mirror.get_ref()==null,"quality rebuild preserves accepted sea clock and releases old planar target")
		check(view._environment.sky.sky_material==rebuilt.get_sky_material(),"quality rebuild rebinds the same sky used by the new mirror")
		view.apply_settings({"cameraFollow":false})
		player.visual.position.x += 40.0
		view.apply_snapshot(native,[],1.0/60.0)
		check(view.camera.position == camera_before,"disabled camera follow keeps the chart viewpoint while the ship moves")
		view.tactical = true
		view.apply_snapshot(native,[],1.0/60.0)
		var tactical_before: Vector3 = view.camera.position
		player.visual.position.x += 40.0
		view.apply_snapshot(native,[],0.5)
		check(view.camera.position.x > tactical_before.x,"tactical command view follows the flagship despite captain follow option")
		view.tactical = false; view.apply_settings({"cameraFollow":true,"horizonStability":0.0,"reducedMotion":true,"cameraShake":1.0})
		player.visual.heel = 0.8
		view.apply_snapshot(native,[],0.0)
		var stable_up: Vector3 = view.camera.global_basis.y
		player.visual.heel = -0.8
		view.apply_snapshot(native,[],0.0)
		check(view.camera.global_basis.y.is_equal_approx(stable_up),"reduced motion prevents hull roll from rocking the camera horizon")
		view.apply_snapshot(native,[],0.1)
		var flags: Array = view.ships[id].get_model().find_children("flag_*","Node3D",true,false)
		check(not flags.is_empty(),"real imported flagship exposes source flag presentation")
		for flag: Node3D in flags: check(absf(flag.rotation.z) < 1e-8,"reduced motion also stops authored flag movement")
		native.ships = [player]
		view.apply_snapshot(native, [], 0.0)
		check(view.ships.size() == 1 and view.sailors.size() == 1, "sold or reconciled vessels and crew are removed")
		var previous_effects: WeakRef = weakref(view.effects)
		native.battleId = "new-encounter"
		view.apply_snapshot(native,[],0.0)
		check(previous_effects.get_ref() == null and view.ships.size() == 1,"replacing authority identity clears old event and impact presentation")
		var previous_ship: WeakRef = weakref(view.ships[id])
		player.kind = "fisherman"
		view.apply_snapshot(native,[],0.0)
		check(previous_ship.get_ref() == null,"same id with a new ship kind replaces model and deck adapters")
		view.dispose(); view.dispose()
		check(view.ships.is_empty() and view.sailors.is_empty(), "disposing releases every imported vessel and crew adapter")
		check(is_instance_valid(unrelated) and unrelated.get_parent() == view, "dispose preserves caller-owned additions")
		view.apply_settings({"quality":"low"})
		check(view.configure(heights.sample_height, ports, runtime.sample_water_height, runtime.snapshot().naval, {"resolution":12,"chunk_radius":0,"vegetation":false}), "reentry creates a fresh presentation without old cache ownership")
		check(not view._sun.shadow_enabled,"preconfigured low quality disables expensive shadows on scene entry")
		view.dispose(); view.queue_free(); runtime.dispose()
		await process_frame; await process_frame
	print("NAVAL_WORLD_VIEW_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
