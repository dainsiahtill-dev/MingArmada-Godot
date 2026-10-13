extends SceneTree
## Real source states and operation budgets. Original Math entry points stay
## independent references; no identity-only algebra or wall-time threshold.
const Runtime = preload("res://modules/scene_engine/fidelity_fx/particle_runtime.gd")
const Replay = preload("res://modules/scene_engine/fidelity_fx/native_particle_replay.gd")
const Math = preload("res://modules/scene_engine/fidelity_fx/native_particle_math.gd")
const Placement = preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
const SOURCE := "res://assets/data/fidelity_fx/particles/assets-json/"
const ORACLE := "res://build/fidelity-fx-work/runtime/source-oracle.json"

class LegacyReplay:
	extends "res://modules/scene_engine/fidelity_fx/native_particle_replay.gd"
	const OriginalMath = preload("res://modules/scene_engine/fidelity_fx/native_particle_math.gd")
	func _particle_quad_context(world: Dictionary,camera: Dictionary) -> Dictionary:
		return {"world":world,"camera":camera}
	func _particle_quad_from_context(particle: Dictionary,context: Dictionary) -> Dictionary:
		return OriginalMath.particle_quad(particle,context.world,context.camera)
	func _particle_uv_template(desc: Dictionary,values: Dictionary) -> Array:
		var result := []
		for uv: Array in [[0,1],[1,1],[1,0],[0,0]]: result.append(OriginalMath.texture_uv(uv,desc,values))
		return result

class TracedReplay:
	extends "res://modules/scene_engine/fidelity_fx/native_particle_replay.gd"
	const OriginalMath = preload("res://modules/scene_engine/fidelity_fx/native_particle_math.gd")
	var _math: RefCounted = OriginalMath.new()
	var context_calls := 0
	var uv_calls := 0
	var particle_calls := 0
	var prepared_contexts := 0
	var prepared_uvs := 0
	func reset_counts() -> void:
		context_calls = 0; uv_calls = 0; particle_calls = 0; prepared_contexts = 0; prepared_uvs = 0
	func _particle_quad_context(world: Dictionary,camera: Dictionary) -> Dictionary:
		context_calls += 1
		var context := {"world":world,"camera":camera}
		# Dynamic guard keeps the pre-implementation RED a counted semantic
		# failure instead of a parser error for a missing new Math entry point.
		if _math.has_method("particle_quad_context"):
			var value: Variant = _math.call("particle_quad_context",world,camera)
			if value is Dictionary:
				context.prepared = value
				prepared_contexts += 1
		return context
	func _particle_quad_from_context(particle: Dictionary,context: Dictionary) -> Dictionary:
		particle_calls += 1
		if context.has("prepared") and _math.has_method("particle_quad_prepared"):
			var value: Variant = _math.call("particle_quad_prepared",particle,context.prepared)
			if value is Dictionary: return value
		return OriginalMath.particle_quad(particle,context.world,context.camera)
	func _particle_uv_template(desc: Dictionary,values: Dictionary) -> Array:
		uv_calls += 1
		if _math.has_method("particle_uv_template"):
			var value: Variant = _math.call("particle_uv_template",desc,values)
			if value is Array:
				prepared_uvs += 1
				return value
		var result := []
		for uv: Array in [[0,1],[1,1],[1,0],[0,0]]: result.append(OriginalMath.texture_uv(uv,desc,values))
		return result

var assertions := 0
var failures := 0

func check(ok: bool, detail: String) -> bool:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL FX geometry work: ",detail)
	return ok

func _same(actual: Variant,expected: Variant,tolerance: float = 0.0) -> bool:
	if actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size(): return false
		for key: Variant in expected:
			if not actual.has(key) or not _same(actual[key],expected[key],tolerance): return false
		return true
	if actual is Array and expected is Array:
		if actual.size() != expected.size(): return false
		for index in expected.size():
			if not _same(actual[index],expected[index],tolerance): return false
		return true
	if (actual is int or actual is float) and (expected is int or expected is float):
		if tolerance == 0.0 and float(expected) != floor(float(expected)):
			return Math.f32(float(actual)) == Math.f32(float(expected))
		return absf(float(actual)-float(expected)) <= tolerance
	return actual == expected

func _cameras(oracle: Dictionary) -> Array:
	var basis := Basis.from_euler(Vector3(0.31,0.73,-0.24))
	return [oracle.camera,{"right":Placement.godot_to_native(basis.x),
		"up":Placement.godot_to_native(basis.y),"direction":Placement.godot_to_native(basis.z)}]

func _budget(replay: RefCounted) -> Vector2i:
	var nonempty := 0
	var particles := 0
	for system: Dictionary in replay.get("systems"):
		var active := int(system.pool.num_active)
		if active > 0: nonempty += 1
		particles += active
	return Vector2i(nonempty,particles)

func _uv_ownership(records: Array,label: String) -> void:
	for first: Dictionary in records:
		if not first.has("particle"): continue
		for other: Dictionary in records:
			if other.get("block") != first.block or other.get("particle",-1) == first.particle or not other.has("particle"): continue
			var bytes := var_to_bytes(other.uvs)
			first.uvs[0][0] += 9.0
			check(var_to_bytes(other.uvs) == bytes,"UV template reuse keeps different particle output records independent: "+label)
			return
	check(false,"real geometry fixture supplies two particles in one system: "+label)

func _source(oracle: Dictionary,file: String) -> void:
	var asset: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE+file))
	var runtime := Runtime.new()
	if not check(runtime.configure(asset,1),"real source configures geometry fixture: "+file): return
	runtime.seek(0.35)
	for expected: Dictionary in oracle.cases:
		if expected.file != file or float(expected.time) != 0.35: continue
		check(_same(runtime.source_state(),{"rng":expected.rng,"systems":expected.systems}),"canonical source full-pool/RNG oracle remains exact: "+file)
		check(_same(runtime.meshes(oracle.camera),expected.meshes,0.000002),"original source mesh/UV/packed-color oracle remains valid: "+file)
		break
	var prepared: Dictionary = runtime.get("_asset")
	var index: Dictionary = runtime.get("_blocks")
	var immutable_before := var_to_bytes(prepared)
	var cameras := _cameras(oracle)
	for seed: int in [1,23]:
		var production := Replay.new(prepared,seed,index)
		var reference := LegacyReplay.new(prepared,seed,index)
		var traced := TracedReplay.new(prepared,seed,index)
		for age: float in [0.0,0.06,0.35,1.0]:
			# Both use the existing direct native call sequence. Geometry work must
			# remain equivalent for every legal source state, regardless of cadence.
			production.advance(age); reference.advance(age); traced.advance(age)
			var before := var_to_bytes(production.source_state())
			check(before == var_to_bytes(reference.source_state()) and before == var_to_bytes(traced.source_state()),
				"geometry owners start with identical actual native state: %s/%d/%.2f"%[file,seed,age])
			for camera_index in cameras.size():
				var camera: Dictionary = cameras[camera_index]
				var label := "%s/%d/%.2f/camera%d"%[file,seed,age,camera_index]
				var expected: Array = reference.meshes(camera)
				var actual: Array = production.meshes(camera)
				traced.reset_counts()
				var observed: Array = traced.meshes(camera)
				var budget := _budget(traced)
				check(var_to_bytes(actual) == var_to_bytes(expected) and var_to_bytes(observed) == var_to_bytes(expected),
					"prepared system geometry exactly matches independent original Math output bytes: "+label)
				check(traced.context_calls == budget.x and traced.uv_calls == budget.x and traced.particle_calls == budget.y and traced.prepared_contexts == budget.x and traced.prepared_uvs == budget.x,
					"one quad-camera context and UV template per nonempty system, then one prepared quad per particle: "+label)
				check(var_to_bytes(production.source_state()) == before and var_to_bytes(traced.source_state()) == before,
					"geometry preparation cannot advance source time, consume CRT or alter any pool byte: "+label)
				check(var_to_bytes(production.meshes(camera)) == var_to_bytes(actual),"same-time mesh evaluation returns identical bytes: "+label)
				if age == 0.35 and camera_index == 1: _uv_ownership(actual,label)
	check(var_to_bytes(prepared) == immutable_before,"geometry preparation leaves immutable native blueprint untouched: "+file)

func _run() -> void:
	if not check(FileAccess.file_exists(ORACLE),"existing full source oracle is available"):
		_finish(); return
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ORACLE))
	if not check(oracle.has_all(["cases","camera"]),"source oracle provides actual source frames and camera basis"):
		_finish(); return
	for file: String in ["fx_cannon_fire_01.nif.json","cannon_ball_splash_01.nif.json","cannon_ball_splash_02.nif.json","cannon_ball_splash_03.nif.json"]:
		_source(oracle,file)
	_finish()

func _finish() -> void:
	print("FIDELITY_FX_GEOMETRY_WORK_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)

func _initialize() -> void: _run.call_deferred()
