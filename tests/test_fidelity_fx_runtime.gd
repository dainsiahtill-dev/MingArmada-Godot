extends SceneTree

var checks := 0
var failures := 0
var MathScript
var PoolScript
var EmitterScript
var RuntimeScript
var failure_kinds := {}
const SOURCE := "res://assets/data/fidelity_fx/particles/"

func _init() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		failure_kinds[message] = int(failure_kinds.get(message,0))+1
		if failure_kinds[message] == 1: printerr("FAIL fidelity FX runtime: " + message)

func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _native_json(path: String) -> Dictionary:
	# Godot decimal JSON reader can differ one double ULP from exact binary32 data.
	# Fixtures are original float stores; restore their wire precision before use.
	return _wire_floats(_json(path))

func _wire_floats(value):
	if value is Dictionary:
		for key in value: value[key] = _wire_floats(value[key])
	elif value is Array:
		for i in value.size(): value[i] = _wire_floats(value[i])
	elif value is float and value != floor(value): return MathScript.f32(value)
	return value

func _same(actual, expected, tolerance := 0.0) -> bool:
	if actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size(): return false
		for key in expected:
			if not actual.has(key) or not _same(actual[key],expected[key],tolerance): return false
		return true
	if actual is Array and expected is Array:
		if actual.size() != expected.size(): return false
		for i in expected.size():
			if not _same(actual[i],expected[i],tolerance): return false
		return true
	if (actual is float or actual is int) and (expected is float or expected is int):
		if tolerance == 0.0 and float(expected) != floor(float(expected)):
			return MathScript.f32(float(actual)) == MathScript.f32(float(expected))
		return absf(float(actual)-float(expected)) <= tolerance
	return actual == expected

func _pool_state(pool) -> Dictionary:
	return {"numActive":pool.num_active,"pendingCount":pool.pending_count,"pendingStart":pool.pending_start,"active":pool.active()}

func _test_native_fixtures() -> void:
	for fixture in _native_json(SOURCE+"birth-x86.json").cases:
		var input: Dictionary = fixture.input
		var pool = PoolScript.new({"num_vertices":input.capacity,"num_active":0})
		var rng = MathScript.CrtRand.new(int(input.seed))
		pool.emit(input.emitter,{"timestamp":input.timestamp,"count":input.ages.size(),"ages":input.ages},MathScript.compose(MathScript.inverse(input.systemWorld),input.emitterWorld),rng)
		_check(pool.pending_count == fixture.native.pendingCount,"x86 birth pending count")
		_check(rng.draws == fixture.native.rngDraws and rng.state == fixture.native.rngState,"x86 shipped CRT stream")
		_check(_same(pool.particles.slice(0,pool.pending_count),fixture.native.particles),"x86 birth full records")
	for fixture in _native_json(SOURCE+"pool-x86.json").cases:
		var input: Dictionary = fixture.input
		var pool = PoolScript.new({"num_vertices":input.capacity,"num_active":0})
		pool.num_active = int(input.numActive)
		pool.pending_count = int(input.pendingCount)
		pool.pending_start = int(input.pendingStart)
		pool.particles = input.particles.duplicate(true)
		pool.commit()
		_check(_same(_pool_state(pool),fixture.committed),"x86 pending promotion and gap deletion")
		pool.age_death(input.now,{"spawn_on_death":false})
		_check(_same(_pool_state(pool),fixture.aged),"x86 strict age death and swapped-slot skip")
		pool.position(input.now)
		_check(_same(_pool_state(pool),fixture.positioned),"x86 position float stores")
	for fixture in _native_json(SOURCE+"schedule-x86.json").fixtures:
		var controller = EmitterScript.new(fixture.controller,fixture.data)
		for step in fixture.steps:
			var packets: Array = controller.step_mapped(step.mapped,step.appTime,step.systemPreviousTime)
			var actual := []
			for packet in packets: actual.append({"timestamp":packet.timestamp,"count":packet.count,"ages":packet.ages})
			_check(_same(actual,step.calls),"x86 visibility/rate schedule " + fixture.name)
	for fixture in _native_json(SOURCE+"gravity-x86.json").cases:
		var input: Dictionary = fixture.input
		var particle := {"position":input.position,"velocity":input.velocity,"lastUpdate":input.lastUpdate}
		var actual: Dictionary = MathScript.sphere_gravity({"force_type":1,"turbulence":0,"decay":input.decay,"strength":input.strength},particle,fixture.origin,input.now)
		_check(_same(actual.velocity,fixture.native_velocity),"x86 sphere gravity stores")
	for fixture in _native_json(SOURCE+"planar-x86.json").cases:
		var input: Dictionary = fixture.input
		var relative: Dictionary = MathScript.compose(MathScript.inverse(input.system),input.gravity)
		var axis: Array = MathScript.normalize(MathScript.transform_vector(relative.rotation,input.axis))
		var actual: Dictionary = MathScript.planar_gravity({"force_type":0,"turbulence":0,"decay":input.decay,"strength":input.strength},{"position":input.position,"velocity":input.velocity,"lastUpdate":input.lastUpdate},relative.translation,axis,input.now)
		_check(_same(actual.velocity,fixture.native_velocity),"x86 planar transformed axis")
	for fixture in _native_json(SOURCE+"bounds-x86.json").cases:
		var actual: Dictionary = MathScript.bounds(fixture.vertices)
		_check(_same(actual.center+[actual.radius],fixture.native),"x86 bounds center/radius")
	for fixture in _native_json(SOURCE+"quad-x86.json").cases:
		var input: Dictionary = fixture.input
		var actual: Dictionary = MathScript.particle_quad({"position":input.position,"radius":input.radius,"size":input.size,"color":input.color},{"rotation":input.rotation,"scale":input.scale},{"right":input.cameraRight,"up":input.cameraUp})
		for i in 4:
			_check(_same(actual.vertices[i],fixture.native_vertices[i].position) and actual.argb == fixture.native_vertices[i].argb and _same(actual.uvs[i],fixture.native_vertices[i].uv),"x86 particle quad and nearest-even ARGB")
	var animation := _native_json(SOURCE+"animation-x86.json")
	for fixture in animation.rotations:
		var q: Array = MathScript.euler_quaternion(fixture.data.xyz_rotations,int(fixture.data.rotation_order),fixture.time)
		_check(_same(q,fixture.quaternion,0.000001) and _same(MathScript.quaternion_matrix(q),fixture.matrix,0.000001),"x86 source Euler order/quaternion/matrix")
	for fixture in animation.vectors:
		_check(_same(MathScript.vector_key(fixture.group,fixture.time),fixture.value),"x86 vector X/Y/Z store order")
	for fixture in _json(SOURCE+"material-source-x86.json").cases:
		_check(_same(MathScript.material_source_state(fixture.input),{"calls":fixture.calls,"sourceAfter":fixture.sourceAfter,"useSceneLights":fixture.useSceneLights}),"x86 material source state branches")

func _test_completed_source() -> void:
	var oracle := _json("res://build/fidelity-fx-work/runtime/source-oracle.json")
	var runtimes := {}
	for fixture in oracle.cases:
		var replay
		if not runtimes.has(fixture.file):
			replay = RuntimeScript.new()
			var configured: bool = replay.configure(_json(SOURCE+"assets-json/"+fixture.file),1)
			_check(configured,"accept complete source " + fixture.file + " " + str(replay.diagnostics().last_error))
			if not configured: continue
			runtimes[fixture.file] = replay
		else: replay = runtimes[fixture.file]
		replay.seek(fixture.time)
		var actual: Dictionary = replay.source_state()
		_check(_same(actual.rng,fixture.rng),"source replay CRT exact " + fixture.file)
		_check(_same(actual.systems,fixture.systems),"source replay all capacity slots " + fixture.file + " @ " + str(fixture.time))
		_check(_same(replay.meshes(oracle.camera),fixture.meshes,0.000002),"source ordinary mesh/quad/UV/material records " + fixture.file + " @ " + str(fixture.time))
	for file in runtimes:
		var replay = runtimes[file]
		replay.seek(0.35)
		var expected: Dictionary = replay.source_state()
		for path in [[0.06,0.35],[0.35,0.35],[0.6,0.1,0.35],[0.013,0.061,0.179,0.263,0.35]]:
			for time in path: replay.seek(time)
			_check(_same(replay.source_state(),expected),"canonical full-pool path/pause/rewind equality " + file)
		var before: Dictionary = replay.source_state()
		for bad in [NAN,INF,-1.0,1000000000.0]:
			_check(replay.seek(bad).is_empty() and _same(replay.source_state(),before),"bad seek atomic rejection")
		_check(replay.diagnostics().system_count == (11 if file.begins_with("fx_cannon") else 8),"all native system resources")
		var exposed: Array = replay.meshes(oracle.camera)
		if not exposed.is_empty():
			exposed[0].triangles[0][0] = 999
			_check(replay.meshes(oracle.camera)[0].triangles[0][0] != 999,"mesh records do not expose retained source data")
		for mesh in exposed:
			if mesh.get("kind","") == "authored mesh":
				mesh.triangles[0][0] = 999
				mesh.material.alpha = 999.0
				var fresh: Array = replay.meshes(oracle.camera)
				for record in fresh:
					if record.block == mesh.block and record.get("kind","") == "authored mesh":
						_check(record.triangles[0][0] != 999 and record.material.alpha != 999.0,"authored record buffers/material isolated")
				break
		var particles: Array = replay.snapshot()
		if not particles.is_empty():
			particles[0].position[0] = 999.0
			_check(_same(replay.source_state(),before),"particle snapshot isolates replay state")
	for fixture in oracle.nativeCases:
		var replay = RuntimeScript.new()
		_check(replay.configure(_json(SOURCE+"assets-json/"+fixture.file),1),"native contract complete source")
		for time in fixture.path: replay.advance_native(time)
		_check(_same(replay.source_state(),{"rng":fixture.rng,"systems":fixture.systems}),"explicit variable-dt original state " + fixture.file + str(fixture.path))
		_check(str(replay.diagnostics().time_input.kind).begins_with("original variable-dt"),"native time contract disclosed")
	var invalid := _json(SOURCE+"assets-json/fx_cannon_fire_01.nif.json")
	for block in invalid.blocks:
		if block.type == "NiPSysGravityModifier":
			block.fields.turbulence = 1.0
			break
	var rejected = RuntimeScript.new()
	_check(not rejected.configure(invalid,1),"unsupported turbulence guard")
	_check(not rejected.configure({},1),"empty asset guard")
	_check(not rejected.configure(_json(SOURCE+"assets-json/fx_cannon_fire_01.nif.json"),-1),"explicit uint32 CRT seed guard")

func _run() -> void:
	var native_only: bool = "--native-only" in OS.get_cmdline_user_args()
	var files := ["native_particle_math.gd","native_particle_pool.gd","native_emitter_controller.gd"]
	if not native_only: files.append("particle_runtime.gd")
	for file in files:
		_check(FileAccess.file_exists("res://modules/scene_engine/fidelity_fx/"+file),"missing implementation " + file)
	if failures == 0:
		MathScript = load("res://modules/scene_engine/fidelity_fx/native_particle_math.gd")
		PoolScript = load("res://modules/scene_engine/fidelity_fx/native_particle_pool.gd")
		EmitterScript = load("res://modules/scene_engine/fidelity_fx/native_emitter_controller.gd")
		_check(MathScript != null and MathScript.can_instantiate(),"math script compiles")
		_check(PoolScript != null and PoolScript.can_instantiate(),"pool script compiles")
		_check(EmitterScript != null and EmitterScript.can_instantiate(),"emitter script compiles")
		if failures == 0: _test_native_fixtures()
		if not native_only:
			RuntimeScript = load("res://modules/scene_engine/fidelity_fx/particle_runtime.gd")
			_test_completed_source()
	print("FIDELITY_FX_RUNTIME_TESTS assertions=",checks," failures=",failures)
	if failures: print(JSON.stringify(failure_kinds))
	quit(0 if failures == 0 else 1)
