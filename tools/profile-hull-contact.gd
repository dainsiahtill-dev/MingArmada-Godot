extends SceneTree
## Fixed accepted-time replay. Headless measures contact CPU, never FPS.
## Example: godot --headless --path . --script tools/profile-hull-contact.gd -- --phase=baseline --ships=3 --distance=35
const Ship = preload("res://game/presentation/ships/ship_view.gd")
const Waves = preload("res://modules/physics_engine/ocean/wave_field.gd")
const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")
const Coastal = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Catalog = preload("res://game/domain/legacy/catalog.gd")
const Geography = preload("res://game/scenes/common/reference_geography.gd")
const Ocean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const BASELINE = "res://docs/migration/evidence/hull-dynamics-2026-10-14/baseline-source/hull_contact_froth.gd"
const CANDIDATE = "res://modules/scene_engine/water/hull_contact_froth.gd"
const OUT = "res://docs/migration/evidence/hull-dynamics-2026-10-14/performance"
const DT = 1.0 / 32.0
const WARMUP = 16
var phase := "baseline"
var ship_count := 1
var distance := 35.0
var kind := "fuchuan"
var frame_count := 128
var gpu := false
var native_route := false
var native_scoped := false
var route_probe := true
var trajectory := "cruise-turn"
var waves = Waves.new()
var native_waves = Coastal.new()
var heights = Height.new()
var world: Node3D
var camera: Camera3D
var ocean: MeshInstance3D
var ships: Array[Node3D] = []
var contacts: Array[RefCounted] = []
var query_count := 0
var query_sum := 0.0
var sampler_nonfinite := 0
var sea_count := 0
var failures: Array[String] = []
var prior_geometry_counts: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func sampled(x: float, z: float, seconds: float) -> float:
	query_count += 1
	var value: float = native_waves.sample_height(x, z, seconds) if native_route else waves.sample_height(x, z, seconds)
	query_sum += value
	if not is_finite(value): sampler_nonfinite += 1
	return value

func sea(x: float, z: float) -> bool:
	sea_count += 1
	return heights.sample_height(x, z) < 0.0 if native_route else true

func plain_height(x: float, z: float, seconds: float) -> float:
	return native_waves.sample_height(x, z, seconds) if native_route else waves.sample_height(x, z, seconds)

func parse_arguments() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="): phase = arg.trim_prefix("--phase=")
		elif arg.begins_with("--ships="): ship_count = int(arg.trim_prefix("--ships="))
		elif arg.begins_with("--distance="): distance = float(arg.trim_prefix("--distance="))
		elif arg.begins_with("--kind="): kind = arg.trim_prefix("--kind=")
		elif arg.begins_with("--frames="): frame_count = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--trajectory="): trajectory = arg.trim_prefix("--trajectory=")
		elif arg == "--gpu": gpu = true
		elif arg == "--native-water": native_route = true
		elif arg == "--native-scoped": native_route = true; native_scoped = true
		elif arg == "--skip-route-probe": route_probe = false
		else: check(false, "Unknown argument: " + arg)
	check(phase in ["baseline", "candidate"], "phase must be baseline or candidate")
	check(ship_count in [1, 3, 10], "ships must be 1, 3 or 10")
	check(is_finite(distance) and distance > 0.0, "distance must be finite positive metres")
	check(kind in Ship.KINDS, "kind must be real Ship.KINDS")
	check(frame_count >= 32 and frame_count <= 256, "frames must be 32..256")
	check(trajectory in ["cruise-turn", "stopped"], "trajectory must be cruise-turn or stopped")
	check(not gpu or DisplayServer.get_name() != "headless", "--gpu requires a real display/rendering driver")
	return failures.is_empty()

func native_route_probe() -> Dictionary:
	var original_us: Array[float] = []
	var native_us: Array[float] = []
	var max_full_error := 0.0
	var max_native_error := 0.0
	var checksum := 0.0
	var near_checksum := 0.0
	for index: int in 256:
		var offshore: bool = index < 128
		var x := 10000.0 + float(index) * .23 if offshore else -220.0 + float(index - 128) * .23
		var z := 10000.0 + sin(float(index) * .19) * 12.0 if offshore else -80.0 + sin(float(index) * .19) * 12.0
		var seconds := float(index) * DT
		var start := Time.get_ticks_usec()
		var raw: float = waves.sample_height(x, z, seconds)
		original_us.append(float(Time.get_ticks_usec() - start))
		start = Time.get_ticks_usec()
		var actual: float = native_waves.sample_height(x, z, seconds)
		native_us.append(float(Time.get_ticks_usec() - start))
		max_full_error = maxf(max_full_error, absf(raw - float(waves.sample(x, z, seconds).height)))
		max_native_error = maxf(max_native_error, absf(actual - float(native_waves.sample(x, z, seconds).height)))
		if offshore: checksum += actual
		else: near_checksum += actual
	check(max_full_error <= 1.0e-10, "five-wave sample_height matches full scalar height")
	check(max_native_error <= 1.0e-10, "native Coastal sample_height matches full Coastal height")
	return {"samples":256,"originalFiveWaveUsec":stats(original_us),"nativeCoastalAndHeightUsec":stats(native_us),"maximumHeightError":max_full_error,"maximumNativeHeightError":max_native_error,"offshoreChecksum":checksum,"nearTrialChecksum":near_checksum,"heightProvider":"HeightField.configure_ports(LegacyCatalog.DATA.PORTS,false,ReferenceGeography.source_options())","runtimeRoute":"LegacyRuntime.sample_water_height -> CoastalWaveField.sample_height -> original five-wave WaveField.sample_height + HeightField.sample_height; source water sea mask additionally samples HeightField"}

func setup_gpu() -> void:
	root.size = Vector2i(1200, 900)
	root.content_scale_size = root.size
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.12, .27, .40)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .7
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	world.add_child(sun)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 45.0
	camera.far = 3000.0
	world.add_child(camera)
	ocean = Ocean.new()
	world.add_child(ocean)
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(.5, .5, 1.0))
	ocean.configure(camera, ImageTexture.create_from_image(image), 48, 2400.0)
	ocean.set_wave_descriptors(Descriptor.original_descriptors())
	# Benchmark arena is deep offshore; same original wave math as CPU sampler.
	ocean.material_override.set_shader_parameter("coastal_attenuation", false)

func state_at(index: int, tick: int) -> Dictionary:
	var seconds := float(tick) * DT
	var theta := .45 + .16 * sin(seconds * .7)
	var speed := 3.086
	var travel_time := minf(seconds, float(WARMUP)*DT) if trajectory == "stopped" else seconds
	var position := Vector3(10000.0 + float(index % 5) * 28.0 + speed * cos(.45) * travel_time, 0.0, 10000.0 + float(index / 5) * 40.0 + speed * sin(.45) * travel_time)
	# Actual five-wave displacement drives boat float; independent small heave
	# and pitch make real finite-height contact enter and leave the forebody.
	position.y = plain_height(position.x, position.z, seconds) + .18 * sin(seconds * 2.6 + float(index) * .2)
	if trajectory == "stopped" and tick >= WARMUP: speed = 0.0
	return {"id":"profile-ship-%d" % index,"kind":kind,"time":seconds,"hull":100.0,"maxHull":100.0,"sail":100.0,"maxSail":100.0,"crew":0,"sailDeployment":1.0 if speed > 0.0 else 0.0,"visual":{"position":{"x":position.x,"y":position.y,"z":position.z},"heading":theta,"velocity":{"x":cos(theta) * speed,"z":sin(theta) * speed},"pitch":.07 * sin(seconds * 1.9),"heel":.10 * cos(seconds * 1.3)}}

func packet_at(actor: Node3D, state: Dictionary, tick: int, index: int) -> Dictionary:
	var attachment: Dictionary = actor.source_water_attachment()
	var unit := float(attachment.sourceToWorld)
	var marker: Vector3 = attachment.bow / unit
	return {"surfaceProfile":attachment.surfaceProfile,"sourceBowPosition":[marker.x,-marker.z,marker.y],"sourceToWorld":unit,"worldOrigin":[0.0,0.0,0.0],"epoch":"profile-fixed-v1","sourceCallIndex":tick,"targetSpeed":Vector2(float(state.visual.velocity.x),float(state.visual.velocity.z)).length(),"targetVelocity":[float(state.visual.velocity.x),0.0,float(state.visual.velocity.z)],"enabled":float(state.sailDeployment)>0.0,"targetCameraDistance":distance,"seed":166100+index,"sourceCamera":{"right":[1.0,0.0,0.0],"up":[0.0,0.0,1.0],"direction":[0.0,-1.0,0.0],"targetDistance":distance}}

func percentile(values: Array[float], quantile: float) -> float:
	if values.is_empty(): return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[mini(ordered.size() - 1, maxi(0, ceili(quantile * ordered.size()) - 1))]

func stats(values: Array[float]) -> Dictionary:
	var total := 0.0
	var maximum := 0.0
	var minimum := INF
	for value: float in values:
		total += value
		maximum = maxf(maximum, value)
		minimum = minf(minimum, value)
	return {"count":values.size(),"mean":total / float(values.size()) if not values.is_empty() else 0.0,"p50":percentile(values,.5),"p95":percentile(values,.95),"p99":percentile(values,.99),"maximum":maximum,"minimum":minimum if not values.is_empty() else 0.0}

func run() -> void:
	if not parse_arguments(): quit(1); return
	check(waves.configure(Descriptor.original_descriptors()), "original five-wave descriptor accepted")
	var route_evidence: Dictionary = {}
	if native_route or route_probe:
		check(heights.configure_ports(Catalog.DATA.PORTS,false,Geography.source_options()), "production Height provider configures")
		check(native_waves.configure(heights.sample_height), "production Coastal provider configures")
		if route_probe: route_evidence = native_route_probe()
	world = Node3D.new()
	root.add_child(world)
	if gpu: setup_gpu()
	var script_path := BASELINE if phase == "baseline" else CANDIDATE
	var module: Script = load(script_path)
	var loaded_module_sha := FileAccess.get_sha256(script_path)
	check(module != null, "selected contact module loads")
	if not failures.is_empty(): world.free(); quit(1); return
	var profile_manifest: Array = []
	for index: int in ship_count:
		var actor: Node3D = Ship.new()
		world.add_child(actor)
		check(actor.configure(kind), "real model configures: " + kind)
		actor.apply_snapshot(state_at(index,0),{},0.0)
		var attachment: Dictionary = actor.source_water_attachment()
		check(attachment.has("surfaceProfile"), "real model profile exists")
		if not attachment.has("surfaceProfile"): continue
		var profile: Dictionary = attachment.surfaceProfile
		profile_manifest.append({"kind":kind,"source":attachment.sourceResourceName,"sections":profile.sections.size(),"verticalRings":profile.get("verticalSections",[]).size(),"profileSHA256":JSON.stringify({"sections":profile.sections,"verticalSections":profile.get("verticalSections",[])}).sha256_text()})
		var contact: RefCounted = module.new()
		check(bool(contact.configure(world,0,166100+index).get("ok",false)), "contact configures")
		ships.append(actor)
		contacts.append(contact)
		prior_geometry_counts.append({"mesh_rebuilds":0,"region_updates":0})
	if not failures.is_empty(): cleanup(); quit(1); return
	var times: Array[float] = []
	var queries: Array[float] = []
	var active_drops: Array[float] = []
	var frame_wall: Array[float] = []
	var draw_calls: Array[float] = []
	var rebuilds := 0
	var region_updates := 0
	var surface_clears := 0
	var query_mismatch := 0
	var diagnostics_last: Array = []
	var records: Array = []
	var canary_sum := 0.0
	var checksum := 0.0
	var input_digest := HashingContext.new()
	input_digest.start(HashingContext.HASH_SHA256)
	input_digest.update(JSON.stringify({"ships":ship_count,"distance":distance,"kind":kind,"frames":frame_count,"warmup":WARMUP,"trajectory":trajectory,"waves":Descriptor.original_components(),"profiles":profile_manifest,"nativeRoute":native_route,"nativeScoped":native_scoped}).to_utf8_buffer())
	for tick: int in WARMUP + frame_count:
		var wall_start := Time.get_ticks_usec()
		var packets: Array[Dictionary] = []
		for index: int in ship_count:
			var state := state_at(index,tick)
			ships[index].apply_snapshot(state,{},0.0)
			var packet := packet_at(ships[index],state,tick,index)
			packets.append(packet)
			input_digest.update(JSON.stringify({"state":state,"packet":packet}).to_utf8_buffer())
			canary_sum += plain_height(float(state.visual.position.x)+.8,float(state.visual.position.z)-.3,float(tick)*DT)
		if gpu:
			var target: Vector3 = ships[0].position
			camera.position = target + Vector3(distance * .72, distance * .12, distance * .68)
			camera.look_at(target + Vector3(0,1.0,0))
			ocean.set_simulation_time(float(tick)*DT)
			if ocean.has_method("update_projection"): ocean.update_projection()
		query_count = 0
		query_sum = 0.0
		var sea_before := sea_count
		var start := Time.get_ticks_usec()
		var sampling_scope: RefCounted = heights.begin_sampling_scope() if native_scoped else null
		for index: int in ship_count: contacts[index].apply_snapshot(packets[index],float(tick)*DT,sampled,sea)
		if sampling_scope != null: sampling_scope.finish()
		var elapsed := float(Time.get_ticks_usec()-start)
		var declared_queries := 0
		var drops := 0
		var tick_rebuilds := 0
		var tick_regions := 0
		diagnostics_last.clear()
		for index: int in contacts.size():
			var contact: RefCounted = contacts[index]
			var diagnostics: Dictionary = contact.diagnostics()
			diagnostics_last.append(diagnostics)
			declared_queries += int(diagnostics.get("water_samples",0))
			drops += int(diagnostics.get("target_droplets",0))
			if phase == "baseline":
				# Frozen _submit clears 2 ribbons when strength>0.001, plus spray.
				var ribbons := int(diagnostics.get("target_ribbons",0))
				tick_rebuilds += ribbons + (1 if int(diagnostics.get("target_droplets",0)) > 0 else 0)
				if tick >= WARMUP: surface_clears += (2 if float(diagnostics.get("strength",0.0)) > .001 else 0) + 1
			else:
				var rebuild_count := int(diagnostics.get("mesh_rebuilds",0))
				var region_count := int(diagnostics.get("region_updates",diagnostics.get("region_uploads",0)))
				tick_rebuilds += rebuild_count - int(prior_geometry_counts[index].mesh_rebuilds)
				tick_regions += region_count - int(prior_geometry_counts[index].region_updates)
				prior_geometry_counts[index] = {"mesh_rebuilds":rebuild_count,"region_updates":region_count}
		if declared_queries != query_count: query_mismatch += 1
		if gpu:
			await process_frame
			await RenderingServer.frame_post_draw
		if tick >= WARMUP:
			times.append(elapsed)
			queries.append(float(query_count))
			active_drops.append(float(drops))
			checksum += query_sum
			rebuilds += tick_rebuilds
			region_updates += tick_regions
			if gpu:
				frame_wall.append(float(Time.get_ticks_usec()-wall_start))
				draw_calls.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			records.append({"tick":tick,"acceptedTime":float(tick)*DT,"contactCPUUsec":elapsed,"waterQueries":query_count,"seaMaskQueries":sea_count-sea_before,"activeDrops":drops,"meshRebuilds":tick_rebuilds,"regionUpdates":tick_regions})
		if not gpu and tick % 16 == 15: await process_frame
	check(query_mismatch == 0, "instrumented water calls match module diagnostics")
	check(sampler_nonfinite == 0, "all sampled five-wave heights finite")
	check(loaded_module_sha == FileAccess.get_sha256(script_path), "module source remains frozen throughout measurement")
	var result := {"version":2,"phase":phase,"mode":"gpu" if gpu else "headless-cpu","engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"renderer":RenderingServer.get_video_adapter_name() if gpu else "dummy headless","ships":ship_count,"distanceMetres":distance,"kind":kind,"trajectory":trajectory,"acceptedRateHz":32,"warmupAcceptedFrames":WARMUP,"measuredAcceptedFrames":frame_count,"contactCPUUsec":stats(times),"waterQueriesPerAcceptedFleetFrame":stats(queries),"activeDropsPerAcceptedFleetFrame":stats(active_drops),"meshRebuilds":rebuilds,"regionUpdates":region_updates,"baselineSurfaceClears":surface_clears,"geometryCountMethod":"frozen baseline source _submit branches and actual visible carriers" if phase == "baseline" else "candidate cumulative diagnostics deltas per accepted call","sampler":"production Coastal + Height provider" if native_route else "original five-wave WaveField.sample_height","nativeSamplingScope":native_scoped,"samplerQueriesAgree":query_mismatch==0,"samplerFinite":sampler_nonfinite==0,"queryHeightSum":checksum,"fixedCanaryHeightSum":canary_sum,"inputSHA256":input_digest.finish().hex_encode(),"moduleSHA256":loaded_module_sha,"toolSHA256":FileAccess.get_sha256("res://tools/profile-hull-contact.gd"),"waveSHA256":FileAccess.get_sha256("res://modules/physics_engine/ocean/wave_field.gd"),"profileManifest":profile_manifest,"routeProbe":route_evidence,"lastDiagnostics":diagnostics_last.duplicate(true),"renderedFrameWallUsec":stats(frame_wall),"renderDrawCalls":stats(draw_calls),"scope":"Fixed accepted 32Hz model/13-ring replay. Contact CPU excludes model pose, packet, validation and diagnostics; --native-scoped includes begin_sampling_scope/finish around contact, matching the production water wrapper for this isolated local layer. Headless has no FPS/GPU claim. --gpu includes actual ProjectedOcean and model rendering but remains an isolated controlled arena, not normal-entry/product FPS. CPU timing includes counter/checksum wrapper overhead equally in both phases.","failures":failures,"records":records}
	var native_suffix := "-native-scoped" if native_scoped else "-native" if native_route else ""
	var name := "%s-%s-%s-%dships-%dm-%s%s.json" % [phase,"gpu" if gpu else "cpu",kind,ship_count,roundi(distance),trajectory,native_suffix]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var file := FileAccess.open(OUT+"/"+name,FileAccess.WRITE)
	check(file != null, "evidence file opens")
	if file != null: file.store_string(JSON.stringify(result,"\t")); file.close()
	cleanup()
	print("HULL_CONTACT_PROFILE ",JSON.stringify({"phase":phase,"ships":ship_count,"distance":distance,"kind":kind,"CPUUsec":result.contactCPUUsec,"queries":result.waterQueriesPerAcceptedFleetFrame,"inputSHA256":result.inputSHA256,"evidence":OUT+"/"+name,"failures":failures}))
	quit(1 if not failures.is_empty() else 0)

func cleanup() -> void:
	for contact: RefCounted in contacts: contact.dispose()
	for ship: Node3D in ships: ship.dispose()
	contacts.clear()
	ships.clear()
	if is_instance_valid(world): world.free()
