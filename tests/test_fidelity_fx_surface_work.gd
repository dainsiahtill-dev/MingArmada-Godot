extends SceneTree
## Real source rendering: one pure sea decision per exact X/Z in this render.
## Complete payload equivalence stays in test_fidelity_fx_mesh_reuse's Legacy.
const Fx = preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
const Runtime = preload("res://modules/scene_engine/fidelity_fx/particle_runtime.gd")
const Waves = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const SOURCES := ["fx_cannon_fire_01.nif","cannon_ball_splash_01.nif","cannon_ball_splash_02.nif","cannon_ball_splash_03.nif"]
const AGES := [.1,.35,.8]
class CountingPureSea extends RefCounted:
	var counts: Dictionary = {}
	var calls := 0
	var cutoff := 8.0
	func reset() -> void: counts.clear(); calls = 0
	func sample(x: float,z: float) -> bool:
		var point := Vector2(x,z)
		counts[point] = int(counts.get(point,0))+1; calls += 1
		return x < cutoff+.1*sin(z*.1)

var assertions := 0
var failures := 0
var _camera: Camera3D
var _waves: RefCounted
var _total_calls := 0
var _total_points := 0
func check(ok: bool,detail: String) -> bool:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL FX surface work: ",detail)
	return ok
func _initialize() -> void: _run.call_deferred()
func _height(_x: float,_z: float) -> float: return -80.0
func _state(runtime: RefCounted) -> PackedByteArray: return var_to_bytes(runtime.call("source_state"))

func _budget(sea: CountingPureSea,water: bool,label: String) -> void:
	_total_calls += sea.calls; _total_points += sea.counts.size()
	if not water:
		check(sea.calls == 0,"cannon render never queries a water-only sea filter: "+label)
		return
	check(sea.calls > 0 and not sea.counts.is_empty(),"fresh actual water render checks real source triangle positions: "+label)
	var repeated := 0
	for count: int in sea.counts.values(): repeated += maxi(0,count-1)
	check(repeated == 0 and sea.calls == sea.counts.size(),"one sea query per exact X/Z within this render: "+label)

func _case(source: String) -> void:
	var water := source.begins_with("cannon_ball")
	var sea := CountingPureSea.new()
	var effect := Fx.new(); root.add_child(effect)
	_camera.position = Vector3(0,12,25); _camera.look_at(Vector3(8,0,-7),Vector3.UP)
	if not check(effect.configure(source,{"origin":Vector3(8,0,-7),"seed":17,"clock_mode":"native","camera":_camera,"water":_waves.sample_height,"sea":sea.sample}),"actual source configures "+source): effect.free(); return
	var runtime: RefCounted = effect.get("_replay")
	var oracle := Runtime.new(); oracle.configure(Fx._asset(source),17); oracle.advance_native(0.0,false)
	for age: float in AGES:
		var label := source+"/"+str(age)
		sea.reset()
		check(effect.apply_snapshot(age,10.0+age),"accepted native source age draws "+label)
		oracle.advance_native(age,false)
		check(_state(runtime) == _state(oracle),"sea clipping/render work preserves the full original native pool/RNG/world/bounds: "+label)
		_budget(sea,water,label)
		var first_points: Dictionary = sea.counts.duplicate()
		var before := _state(runtime)
		sea.reset()
		check(effect.apply_snapshot(age,10.0+age) and sea.calls == 0 and _state(runtime) == before,"identical accepted inputs reuse existing entire presentation without sea or native work")
		_camera.position.x += 2.0; _camera.look_at(Vector3(8,0,-7),Vector3.UP)
		sea.reset()
		check(effect.apply_snapshot(age,10.0+age) and _state(runtime) == before,"changed real camera reprojects without advancing native particles")
		_budget(sea,water,label+"/camera")
		sea.reset()
		check(effect.apply_snapshot(age,11.0+age) and _state(runtime) == before,"new absolute wave phase reprojects without advancing native particles")
		_budget(sea,water,label+"/water-time")
		# Provider state changes behind the exact same Callable. The explicit
		# setter invalidates presentation; no point decision survives this render.
		sea.cutoff = 8.4; effect.configure_surface_filter(sea.sample); sea.reset()
		check(effect.apply_snapshot(age,11.0+age) and _state(runtime) == before,"changed filter provider invalidates the accepted display without changing source state")
		_budget(sea,water,label+"/filter")
		if water:
			check(first_points.keys().any(func(point: Vector2): return sea.counts.has(point)),"real repeated world X/Z points are queried again by later renders")
			check(effect.diagnostics().rendered_triangles > 0,"mixed shoreline keeps visible original source triangles")
		sea.cutoff = 8.0; effect.configure_surface_filter(sea.sample)
	effect.dispose(); effect.free()

func _run() -> void:
	_waves = Waves.new()
	if not check(_waves.configure(_height),"actual CoastalWaveField uses original wave descriptors"):
		print("FIDELITY_FX_SURFACE_WORK_TESTS assertions=",assertions," failures=",failures); quit(1); return
	_camera = Camera3D.new(); root.add_child(_camera)
	for source: String in SOURCES: _case(source)
	_camera.free()
	print("FIDELITY_FX_SURFACE_WORK_SCOPE sea_calls=",_total_calls," exact_points=",_total_points," frame_local=true pure_predicate=true")
	print("FIDELITY_FX_SURFACE_WORK_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
