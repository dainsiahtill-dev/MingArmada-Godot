extends SceneTree
## Integration contracts: detached wave injection, actual hull samples and the
## accepted clock used by water-attached presentation and native Jolt impacts.
const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")
const Waves = preload("res://modules/physics_engine/ocean/wave_field.gd")
const Coastal = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Uniforms = preload("res://modules/scene_engine/ocean/wave_uniforms.gd")
const Runtime = preload("res://game/runtime/naval_practice_runtime.gd")
const Wakes = preload("res://game/presentation/water/wake_trails.gd")
const ImpactPool = preload("res://modules/physics_engine/impacts/impact_pool.gd")
const ImpactBone = preload("res://modules/physics_engine/impacts/impact_bone.gd")
const Types = preload("res://modules/contracts/physics_types.gd")
var assertions := 0
var failures := 0

func check(ok: bool, description: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", description)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_test_descriptor_injection()
	await _test_actual_water_consumers()
	print("SEA_PHYSICS_INTEGRATION_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)

func _test_descriptor_injection() -> void:
	var zero := [{"amplitude":1.0,"wavelength":TAU,"speed":0.5,"direction":{"x":0.0,"z":0.0}}]
	check(not Descriptor.valid_descriptors(zero), "shared contract rejects a zero direction before both CPU and GPU")
	var raw: RefCounted = Waves.new()
	check(raw.has_method("configure"), "CPU wave field accepts the same detached descriptors as the renderer")
	if not raw.has_method("configure"): return
	var source := [{"amplitude":2.0,"wavelength":TAU,"speed":0.5,"direction":{"x":3.0,"z":4.0}}]
	check(raw.configure(source), "non-unit direction is normalized through the shared descriptor contract")
	var uploaded := Uniforms.components(source)
	check(not uploaded.is_empty(), "the same source descriptors are accepted by the real GPU uniform adapter")
	source[0].amplitude = 99.0
	for time: float in [-2.0,0.0,1.25,18.0]:
		for point: Vector2 in [Vector2.ZERO,Vector2(1.25,-2.5),Vector2(-41.0,8.0)]:
			var phase := 0.6*point.x+0.8*point.y+0.5*time
			var expected := 2.0*sin(phase)
			var sampled: Dictionary = raw.sample(point.x,point.y,time)
			check(absf(sampled.height-expected)<1.0e-12, "CPU uses detached normalized direction and signed source phase")
			check(raw.sample_height(point.x,point.y,time)==sampled.height, "scalar contact and full buoyancy samples share one surface")
			check(sampled.normal.distance_to(Vector3(-1.2*cos(phase),1.0,-1.6*cos(phase)).normalized())<1.0e-6, "configured wave analytic normal matches its injected height")
			var gpu_height := float(uploaded[0].x)*sin(float(uploaded[0].y)*point.x+float(uploaded[0].z)*point.y+float(uploaded[0].w)*time)
			check(absf(sampled.height-gpu_height)<3.0e-6, "CPU and actual uploaded float32 shader parameters describe the same wave")
	var before: float = raw.sample_height(2.0,3.0,4.0)
	check(not raw.configure(zero) and raw.sample_height(2.0,3.0,4.0)==before, "rejected descriptor injection keeps the accepted CPU surface intact")
	var coastal: RefCounted = Coastal.new()
	var accepts_descriptors := false
	for method: Dictionary in coastal.get_script().get_script_method_list():
		if method.name == "configure": accepts_descriptors = method.args.size() == 2
	check(accepts_descriptors, "coastal sampler accepts terrain and the same optional descriptor profile")
	if not accepts_descriptors: return
	var slope := func(x: float,_z: float) -> float: return -4.0+x*0.2
	var waves := [{"amplitude":2.0,"wavelength":TAU,"speed":0.5,"direction":{"x":3.0,"z":4.0}}]
	check(coastal.configure(slope,waves), "injected coastal profile is accepted atomically")
	for time: float in [-1.5,0.0,2.75]:
		for point: Vector2 in [Vector2(-40.0,2.0),Vector2.ZERO,Vector2(1.5,2.0),Vector2(25.0,-1.0)]:
			var depth := -float(slope.call(point.x,point.y))
			var ratio := clampf(depth/8.0,0.0,1.0)
			var expected := 2.0*sin(0.6*point.x+0.8*point.y+0.5*time)*ratio*ratio*(3.0-2.0*ratio)
			check(absf(coastal.sample_height(point.x,point.y,time)-expected)<1.0e-12, "configured shallow-water height preserves the established 8m attenuation")
			var center: Dictionary = coastal.sample(point.x,point.y,time)
			var epsilon := 0.001
			var dx: float = (coastal.sample_height(point.x+epsilon,point.y,time)-coastal.sample_height(point.x-epsilon,point.y,time))/(2.0*epsilon)
			var dz: float = (coastal.sample_height(point.x,point.y+epsilon,time)-coastal.sample_height(point.x,point.y-epsilon,time))/(2.0*epsilon)
			check(center.gradient.distance_to(Vector2(dx,dz))<1.0e-6, "shallow-water normal differentiates the same configured attenuated surface")
	before = coastal.sample_height(2.0,3.0,4.0)
	check(not coastal.configure(func(_x: float,_z: float)->float:return -100.0,zero) and coastal.sample_height(2.0,3.0,4.0)==before, "invalid wave profile cannot replace accepted terrain or waves")
	check(raw.configure([]) and raw.sample_height(1.0,2.0,3.0)==0.0, "an explicitly empty profile represents calm water")
	check(raw.configure(Descriptor.original_descriptors()), "original wave descriptor profile can be restored")
	var original := Waves.new()
	check(raw.sample_height(-171.4158,-32.72906,19.5)==original.sample_height(-171.4158,-32.72906,19.5), "default five-wave expansion retains the original double scalar arithmetic")

func _test_actual_water_consumers() -> void:
	var runtime := Runtime.new()
	var ground := func(_x: float,_z: float)->float:return -24.0
	check(runtime.configure(ground,{"mode":"sail"}).ok, "actual sailing practice initializes its authoritative coastal water")
	var initial: Dictionary = runtime.snapshot().naval
	check(initial.oceanWaves==Descriptor.original_descriptors().map(func(w): w.direction={"x":w.direction.x,"y":w.direction.z}; return w), "encounter snapshots expose the original five-wave profile in the existing save-compatible shape")
	for step in 240:
		runtime.advance(1.0/60.0)
		var native: Dictionary = runtime.snapshot().naval
		for vessel: Dictionary in runtime.simulation.encounter.ships:
			var core: Dictionary = vessel.core.get_snapshot()
			check(core.time==native.time, "real ship dynamics consume the same accepted encounter clock")
			for point: Dictionary in vessel.core.get_wave_debug().points:
				check(point.y==runtime.sample_water_height(point.x,point.z,native.time), "all four actual hull buoyancy probes sample the injected world water")
			var freeboard: float = Types.ship_spec(core.kind).freeboard
			check(core.position.y+freeboard>runtime.sample_water_height(core.position.x,core.position.z,native.time), "healthy ship center deck stays above the sampled surface without a rendering y offset")
	var accepted: Dictionary = runtime.snapshot().naval
	check(runtime.set_pause("player",true).ok and runtime.advance(30.0)==0.0, "pause does not consume simulation time")
	check(runtime.snapshot().naval==accepted and runtime.render_snapshot().time==accepted.time, "paused hulls and interpolated renderer retain the same frozen clock")
	runtime.set_pause("player",false)
	runtime.advance(-1.0); runtime.advance(NAN)
	check(runtime.snapshot().naval==accepted, "rejected negative and nonfinite frame times do not alter boats or water")
	runtime.advance(1.0/120.0)
	var interpolated: Dictionary = runtime.render_snapshot()
	var expected_field := Coastal.new(); expected_field.configure(ground)
	check(runtime.sample_water_height(0.5,-0.2,interpolated.time)==expected_field.sample_height(0.5,-0.2,interpolated.time), "render interpolation time is explicitly sampled instead of reading a hidden physics or wall clock")
	var wakes := Wakes.new(); root.add_child(wakes); wakes.configure(runtime.sample_water_height)
	var vessel: Dictionary = interpolated.ships[0].duplicate(true)
	vessel.visual.velocity={"x":3.0,"y":0.0,"z":0.0}; vessel.visual.heading=0.0
	var snap := {"time":interpolated.time,"ships":[vessel]}
	wakes.apply_snapshot(snap)
	for index in 6:
		snap.time+=0.1; vessel.visual.position.x+=0.3; wakes.apply_snapshot(snap)
	check(not wakes._trails.is_empty(), "existing stern history creates a real native wake ribbon")
	for trail: Dictionary in wakes._trails.values():
		var vertices: PackedVector3Array = trail.node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for point: Vector3 in vertices:
			check(absf(point.y-runtime.sample_water_height(point.x,point.z,snap.time)-Wakes.SURFACE_OFFSET)<3.0e-6, "wake vertices follow the same accepted water surface used by hulls")
	var frozen_mesh: Mesh = wakes._trails.values()[0].node.mesh
	wakes.apply_snapshot(snap)
	check(wakes._trails.values()[0].node.mesh==frozen_mesh, "paused wake samples cannot advance or rebuild from wall time")
	snap.time=0.0; wakes.apply_snapshot(snap)
	check(wakes._trails.is_empty(), "rewinding the accepted clock clears stale wake history")
	var pool := ImpactPool.new(); root.add_child(pool); pool.set_environment(runtime.sample_water_height)
	check(pool._water==runtime.sample_water_height, "native Jolt impact pool receives the identical injected water callable")
	pool.advance(0.1,7.0); pool.advance(2.0,7.0)
	check(pool._phase==7.0, "native impact contacts retain the explicitly supplied paused water phase")
	pool.advance(0.0,2.0)
	check(pool._phase==2.0, "native impact contact phase follows an explicit rewind")
	await _test_native_water_contact(runtime)
	pool.dispose(); pool.free(); wakes.dispose(); wakes.free(); runtime.dispose()

func _test_native_water_contact(runtime: RefCounted) -> void:
	check(ProjectSettings.get_setting("physics/3d/physics_engine")=="Jolt Physics", "water contact check executes under the configured native Jolt solver")
	var observed: Array = []
	var bone := ImpactBone.new()
	bone.custom_integrator=true; bone.freeze=true; bone.can_sleep=false
	bone.collision_layer=2; bone.collision_mask=0
	var collision := CollisionShape3D.new(); var sphere := SphereShape3D.new()
	sphere.radius=bone.radius; collision.shape=sphere; bone.add_child(collision)
	root.add_child(bone)
	var phase := 5.5
	bone.position=Vector3(0.5,runtime.sample_water_height(0.5,-0.2,phase)+bone.radius+0.001,-0.2)
	PhysicsServer3D.body_set_state(bone.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,bone.transform)
	bone.simulation_velocity=Vector3(0.0,-3.0,0.0); bone.phase=phase
	bone.water_sampler=func(x: float,z: float,time: float)->float:
		var value: float=runtime.sample_water_height(x,z,time)
		observed.append({"x":x,"z":z,"time":time,"height":value})
		return value
	bone.request_step(1.0/60.0,phase+1.0/60.0)
	for _frame in 3: await physics_frame; await process_frame
	check(observed.size()==2, "actual Jolt force integration samples previous and current accepted water phases once")
	if observed.size()==2:
		check(observed[0].time==phase and observed[1].time==phase+1.0/60.0, "falling body queries its two supplied simulation clocks instead of wall time")
		for sample: Dictionary in observed:
			check(sample.height==runtime.sample_water_height(sample.x,sample.z,sample.time), "actual falling-body query returns the same hull and wake surface")
	check(bone.contact=="water", "falling body physically reaches the sampled water surface in the native integration path")
	bone.request_step(0.0,phase+1.0/60.0)
	var paused_transform: Transform3D=PhysicsServer3D.body_get_state(bone.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	var count := observed.size()
	for _frame in 3: await physics_frame; await process_frame
	check(observed.size()==count and PhysicsServer3D.body_get_state(bone.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)==paused_transform, "paused native impact neither samples a later surface nor drifts in wall-clock physics frames")
	bone.free()
