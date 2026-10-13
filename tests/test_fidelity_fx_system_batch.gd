extends SceneTree
## Detects regression to per-particle carriers, changed native bytes/order and
## mutable worker payload reuse. Expectations use x86 fixtures and public replay.
const Fx = preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
const Runtime = preload("res://modules/scene_engine/fidelity_fx/particle_runtime.gd")
const Math = preload("res://modules/scene_engine/fidelity_fx/native_particle_math.gd")
const BATCH_PATH := "res://modules/scene_engine/fidelity_fx/cpu_particle_batch.gd"
const CASES := [{"source":"fx_cannon_fire_01.nif","capacity":435,"systems":11},{"source":"cannon_ball_splash_01.nif","capacity":82,"systems":8},{"source":"cannon_ball_splash_02.nif","capacity":85,"systems":8},{"source":"cannon_ball_splash_03.nif","capacity":79,"systems":8}]
const AGES := [0.0,.02,.061,.18,.4,.72]

class CameraInputFx:
	extends "res://modules/scene_engine/fidelity_fx/presentation.gd"
	var invalid_native_camera := false
	func _camera_native() -> Dictionary:
		# Only the boundary input is varied. The actual Runtime validation,
		# native pool/CRT/bounds, worker and source presentation remain real.
		var camera: Dictionary = super._camera_native()
		if invalid_native_camera: camera.right[0] = NAN
		return camera

var assertions := 0
var failures := 0
var _camera: Camera3D
var _wet := true
var _seen_failures: Dictionary = {}

func check(ok: bool, detail: String) -> bool:
	assertions += 1
	if not ok:
		failures += 1
		if not _seen_failures.has(detail): printerr("FAIL FX system batch: ",detail)
		_seen_failures[detail] = true
	return ok

func _initialize() -> void: _run.call_deferred()
func _sea(_x: float, _z: float) -> bool: return _wet
func _water(x: float, z: float, time: float) -> float: return .07*x+.03*z+.1*time
func _options(seed: int = 17) -> Dictionary:
	return {"origin":Vector3(8,2,-12),"direction":Vector3(.2,0,-1),"seed":seed,"scale":1.0,"camera":_camera,"water":_water,"sea":_sea,"clock_mode":"native","render_unit":"system"}
func _state(fx: Node3D) -> PackedByteArray: return var_to_bytes(fx.get("_replay").source_state())

func _oracle_bytes(vertices: Array) -> PackedByteArray:
	var result := PackedByteArray(); result.resize(144)
	for i in 4:
		var v: Dictionary = vertices[i]
		for c in 3:
			result.encode_float(i*36+c*4,float(v.position[c]))
			result.encode_float(i*36+12+c*4,float(v.normal[c]))
		result.encode_u32(i*36+24,int(v.argb))
		result.encode_float(i*36+28,float(v.uv[0])); result.encode_float(i*36+32,float(v.uv[1]))
	return result

func _native_bytes() -> void:
	if not check(FileAccess.file_exists(BATCH_PATH),"native packed CPU batch exists"): return
	var batch_script: Script = load(BATCH_PATH)
	if not check(batch_script != null,"native packed CPU batch loads"): return
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_fx/particles/quad-x86.json"))
	check(fixture.source_sha256 == "0da87d60243280dea5965dbb23d099bcd0727db344de35886a5207e487a7e120" and fixture.cases.size() == 100,"all original x86 oracle cases are present")
	var batch: RefCounted = batch_script.new(3)
	for index in fixture.cases.size():
		var c: Dictionary = fixture.cases[index]
		# Match the original float32 source stores/JS typed-array oracle inputs.
		# Godot's decimal JSON reader can differ by one double ULP; the existing
		# native fixture loader and production configure restore this wire boundary.
		var input: Dictionary = Runtime._wire_floats(c.input)
		var particle := {"position":input.position,"radius":input.radius,"size":input.size,"color":input.color}
		var world := {"rotation":input.rotation,"scale":input.scale,"translation":[0.0,0.0,0.0]}
		var camera := {"right":input.cameraRight,"up":input.cameraUp}
		check(bool(batch.call("fill",[particle],1,world,camera)),"valid x86 input fills original active prefix")
		check(batch.get("vertex_bytes").slice(0,144) == _oracle_bytes(c.native_vertices),"all 144 packed position/normal/ARGB/UV bytes equal x86 case "+str(index))
		check([batch.get("vertex_count"),batch.get("index_count"),batch.get("triangle_count")] == [4,6,2],"single particle submits exactly one original quad")
	var particles := [{"position":[0.0,0.0,0.0],"radius":1.0,"size":1.0,"color":[1.0,0.0,0.0,1.0]},{"position":[10.0,0.0,0.0],"radius":1.0,"size":1.0,"color":[0.0,1.0,0.0,1.0]},{"position":[20.0,0.0,0.0],"radius":1.0,"size":1.0,"color":[0.0,0.0,1.0,1.0]}]
	var world := Math.identity_transform(); var camera := {"right":[1.0,0.0,0.0],"up":[0.0,0.0,1.0]}
	batch.call("fill",particles,3,world,camera)
	check(batch.get("indices").slice(0,18) == PackedInt32Array([0,1,2,0,2,3,4,5,6,4,6,7,8,9,10,8,10,11]),"multi-particle indices preserve native active-array order")
	check(batch.get("vertex_bytes").decode_u32(24) == 0xffff0000 and batch.get("vertex_bytes").decode_u32(168) == 0xff00ff00 and batch.get("vertex_bytes").decode_u32(312) == 0xff0000ff,"three particle colors retain native source order")
	var prior: PackedByteArray = batch.get("vertex_bytes").duplicate()
	check(not bool(batch.call("fill",particles,4,world,camera)) and batch.get("vertex_bytes") == prior,"invalid active range cannot truncate or overwrite accepted native bytes")
	check(bool(batch.call("fill",particles,0,world,camera)) and batch.get("vertex_bytes") == prior and int(batch.get("index_count")) == 0,"zero active skips draw and retains full capacity storage")
	check(batch.get("vertices").size() == 12 and batch.get("vertex_bytes").size() == 432,"changing active count keeps original CPU capacity reservation")
	particles[0].color = [.5,Math.f32(1.5/255.0),Math.f32(2.5/255.0),.5]
	batch.call("fill",particles,1,world,camera)
	check(batch.get("vertex_bytes").decode_u32(24) == 0x80800202,"original FISTP nearest-even half bytes remain exact")
	batch.call("fill",particles,1,world,camera,[],false)
	check(batch.get("vertex_bytes").decode_u32(24) == 0xffffffff,"absent native colors use original opaque white")
	var ids := PackedInt32Array([10,20,30,40,50,60,70,-1]); var depths := PackedFloat32Array([3,3,3,3,3,3,3,-999])
	check(bool(batch_script.call("sort_transparent",ids,depths,7)) and ids == PackedInt32Array([50,40,70,60,20,10,30,-1]) and depths[7] == -999,"original transparent quicksort retains x86 unstable equal-depth swaps and inactive tail")

func _capture(fx: Node3D) -> Dictionary:
	var geometry: Dictionary = {}
	for key: Variant in fx.get("_geometry"):
		var node: MeshInstance3D = fx.get("_geometry")[key]
		geometry[key] = {"transform":node.transform,"visible":node.visible,"block":node.get_meta("source_block",-1),"kind":node.get_meta("source_kind",""),"sort_origin":node.sorting_use_aabb_center,"bounds":node.custom_aabb,"arrays":node.mesh.surface_get_arrays(0),"material":node.material_override.shader.code,"texture":node.material_override.get_shader_parameter("source_texture")}
	return {"geometry":geometry,"order":fx.get("_draw_order").duplicate(true),"state":_state(fx)}

func _verify_frame(fx: Node3D, oracle: RefCounted, fixture: Dictionary) -> void:
	check(_state(fx) == var_to_bytes(oracle.source_state()),"full authored capacities/CRT/particles/world/native bounds remain byte-identical")
	var state: Dictionary = oracle.source_state(); var capacity := 0
	for s: Dictionary in state.systems: capacity += int(s.capacity)
	check(capacity == int(fixture.capacity) and state.systems.size() == int(fixture.systems),"all original authored system/capacity slots retained")
	var camera: Dictionary = fx.call("_camera_native")
	var expected: Array = oracle.meshes(camera)
	var records: Array = fx.get("_display_meshes")
	var particle_records := 0; var active := 0
	for record: Dictionary in records:
		if record.get("kind","") != "particle system": continue
		particle_records += 1
		check(not record.has("particle") and record.get("batch") is RefCounted,"formal runtime publishes one pure Ref batch per system with no per-particle wrappers")
		var matching: Array = expected.filter(func(v: Dictionary): return v.get("block",-1) == record.block and v.has("particle"))
		var batch: RefCounted = record.batch; var count: int = batch.get("count"); active += count
		check(count == matching.size(),"system batch includes complete native active particle prefix")
		for p in count:
			var e: Dictionary = matching[p]
			for v in 4:
				var local: Vector3 = batch.get("vertices")[p*4+v]
				var wp: Array = Math.point(record.world,[local.x,local.y,local.z])
				check(wp == e.vertices[v],"every quad position and original active-array order equals public source oracle")
				check(batch.get("uvs")[p*4+v] == Vector2(e.uvs[v][0],e.uvs[v][1]),"original DDS UV controller remains exact")
				check(batch.get("vertex_bytes").decode_u32((p*4+v)*36+24) == int(e.argb),"every native packed ARGB matches source oracle")
	var geometry: Dictionary = fx.get("_geometry"); var drawn_particles := 0
	for node: MeshInstance3D in geometry.values():
		if not node.visible or node.get_meta("source_kind","") != "particle system": continue
		drawn_particles += 1
		var block: int = node.get_meta("source_block",-1)
		var native: Array = state.systems.filter(func(s: Dictionary): return int(s.block) == block)
		if not check(native.size() == 1,"carrier is associated with exactly one original system"): continue
		var n: int = native[0].numActive
		check(node.mesh.surface_get_array_len(0) == 4*n and node.mesh.surface_get_array_index_len(0) == 6*n,"GPU mesh actually draws only 4N vertices/2N triangles; no dead capacity triangles")
		var source: Array = expected.filter(func(v: Dictionary): return int(v.get("block",-1)) == block and v.has("particle"))
		var actual: Array = node.mesh.surface_get_arrays(0)
		for p in source.size():
			for v in 4:
				var want: Vector3 = fx.get("_origin")+fx.get("_orientation")*Fx.native_to_godot(source[p].vertices[v])*(.01*float(fx.get("_size")))
				check((node.global_transform*actual[Mesh.ARRAY_VERTEX][p*4+v]).distance_to(want) <= .00001,"every actual system carrier vertex preserves native world and game placement exactly within float32 recenter tolerance")
				check(actual[Mesh.ARRAY_TEX_UV][p*4+v] == Vector2(source[p].uvs[v][0],source[p].uvs[v][1]),"actual GPU adapter UV array matches original DDS/controller output")
				var argb: int = source[p].argb
				var rgba := Color(float((argb >> 16)&255)/255.0,float((argb >> 8)&255)/255.0,float(argb&255)/255.0,float((argb >> 24)&255)/255.0)
				check(actual[Mesh.ARRAY_COLOR][p*4+v].is_equal_approx(rgba),"actual GPU adapter color array preserves original quantized ARGB")
			var base := p*4
			check(actual[Mesh.ARRAY_INDEX].slice(p*6,p*6+6) == PackedInt32Array([base,base+1,base+2,base,base+2,base+3]),"actual index prefix preserves source particle-array order without individual depth sort")
		var bound: Array = Math.point(native[0].world,native[0].bounds.center)
		var origin: Vector3 = fx.get("_origin")+fx.get("_orientation")*Fx.native_to_godot(bound)*(.01*float(fx.get("_size")))
		check(node.position == origin and not node.sorting_use_aabb_center,"engine transparent system origin is original world-bound center")
	check(drawn_particles == particle_records and particle_records <= int(fixture.systems),"formal render owns at most one particle carrier per original system")
	check(active == int(oracle.diagnostics().active),"batching preserves complete live particle count")
	check(int(fx.diagnostics().owned_nodes) <= int(fixture.systems)+expected.filter(func(v: Dictionary): return v.get("kind","") == "authored mesh").size(),"node count is bounded by source systems plus separate authored splash meshes")

func _actual_sources() -> void:
	for fixture: Dictionary in CASES:
		var sync := Fx.new(); var worker := Fx.new(); root.add_child(sync); root.add_child(worker)
		if not check(sync.configure(fixture.source,_options()) and worker.configure(fixture.source,_options()),"both formal system paths configure"): sync.free(); worker.free(); continue
		var oracle := Runtime.new(); oracle.configure(Fx._asset(fixture.source),17); oracle.advance_native(0.0,false)
		for age: float in AGES:
			if age != 0.0: oracle.advance_native(age,false)
			check(sync.apply_snapshot(age,4.0+age),"synchronous system frame accepts source time")
			check(worker.begin_snapshot(age,4.0+age) and worker.finish_snapshot(),"worker system frame joins and presents same accepted frame")
			check(_capture(sync) == _capture(worker),"independent sync/worker batches have identical arrays/order/native state")
			_verify_frame(worker,oracle,fixture)
		var frozen := _state(worker)
		for change: String in ["camera","absolute","filter"]:
			if change == "camera": _camera.position.x += 3.0; _camera.look_at(Vector3.ZERO,Vector3.UP)
			if change == "filter": _wet = false; sync.configure_surface_filter(_sea); worker.configure_surface_filter(_sea)
			sync.apply_snapshot(.72,5.72); worker.begin_snapshot(.72,5.72); worker.finish_snapshot()
			check(_capture(sync) == _capture(worker) and _state(worker) == frozen,"camera/time/filter-only display changes preserve native state and worker equality")
			if change == "filter" and String(fixture.source).begins_with("cannon_ball"): check(worker.diagnostics().rendered_triangles == 0,"dry surface has no stale particle or authored splash triangles")
		_wet = true
		worker.begin_snapshot(.8,5.8); worker.dispose()
		check(not worker.has_pending_snapshot() and worker.get_child_count() == 0 and worker.get("_replay") == null,"pending dispose joins worker and releases all carriers/provider")
		check(not sync.apply_snapshot(sync.get_playback_duration()+.1,7.0) and int(sync.diagnostics().rendered_meshes) == 0,"expiry hides all system and authored carriers")
		sync.free(); worker.free()

func _independent_instances() -> void:
	var a := Fx.new(); var b := Fx.new(); root.add_child(a); root.add_child(b)
	a.configure(CASES[0].source,_options(17)); b.configure(CASES[0].source,_options(53))
	a.begin_snapshot(.18,2.18); b.begin_snapshot(.061,2.061); b.finish_snapshot(); a.finish_snapshot()
	var frozen := _capture(b); var records: Array = b.get("_display_meshes")
	var bytes: Array = []
	for record: Dictionary in records:
		if record.get("kind","") == "particle system": bytes.append(record.batch.get("vertex_bytes").duplicate())
	a.begin_snapshot(.4,2.4); a.finish_snapshot()
	check(_capture(b) == frozen,"advancing another effect cannot mutate retained worker/display/native output")
	var index := 0
	for record: Dictionary in records:
		if record.get("kind","") == "particle system":
			check(record.batch.get("vertex_bytes") == bytes[index],"each effect owns independent native typed storage")
			index += 1
	a.free(); b.free()

func _same_age_worker_camera_recovery() -> void:
	var sync := CameraInputFx.new(); var worker := CameraInputFx.new()
	root.add_child(sync); root.add_child(worker)
	check(sync.configure(CASES[0].source,_options()) and worker.configure(CASES[0].source,_options()),"camera-recovery sources use actual native/system runtime")
	check(sync.apply_snapshot(.061,2.061) and worker.begin_snapshot(.061,2.061) and worker.finish_snapshot(),"camera recovery starts from matching accepted native source frame")
	sync.invalid_native_camera = true; worker.invalid_native_camera = true
	check(not sync.apply_snapshot(.18,2.18),"actual Runtime rejects nonfinite camera while synchronous native advance succeeds")
	check(worker.begin_snapshot(.18,2.18) and not worker.finish_snapshot(),"actual worker reports rejected nonfinite camera after successful native advance")
	check(not String(sync.diagnostics().render_error).is_empty() and not String(worker.diagnostics().render_error).is_empty(),"batch display errors are visible to both actual source owners")
	var held := _state(worker)
	check(held == _state(sync),"rejected display camera leaves the same complete native history in sync and worker")
	sync.invalid_native_camera = false; worker.invalid_native_camera = false
	# A real camera-key change asks for new billboard data at unchanged age.
	_camera.position.x += 1.0; _camera.look_at(Vector3.ZERO,Vector3.UP)
	check(sync.apply_snapshot(.18,2.18),"synchronous same-age valid camera recovers without native advance")
	check(worker.begin_snapshot(.18,2.18) and worker.finish_snapshot(),"worker same-age valid camera recovers from display error without requiring clock advance")
	check(_state(sync) == held and _state(worker) == held,"same-age error recovery consumes no CRT draws or native age/bounds update")
	check(_capture(sync) == _capture(worker),"recovered worker output/order matches synchronous actual source at the same native age")
	sync.free(); worker.free()

func _game_flash_stable_carriers() -> void:
	var sync := Fx.new(); var worker := Fx.new(); root.add_child(sync); root.add_child(worker)
	var options := _options(); options.render_profile = "game_cannon"
	check(sync.configure(CASES[0].source,options) and worker.configure(CASES[0].source,options),"actual game_cannon native/system owners configure complete source and flash adapter")
	var oracle := Runtime.new(); oracle.configure(Fx._asset(CASES[0].source),17); oracle.advance_native(0.0,false)
	var first_flash_ids: Array = []; var system_counts: Dictionary = {}
	for age: float in [0.0,.02,.061,.1,.139,.14]:
		if age != 0.0: oracle.advance_native(age,false)
		check(sync.apply_snapshot(age,2.0+age) and worker.begin_snapshot(age,2.0+age) and worker.finish_snapshot(),"actual game flash presents synchronously and through worker")
		check(_state(sync) == var_to_bytes(oracle.source_state()) and _state(worker) == _state(sync),"game flash adapter never changes complete original source state/CRT/bounds")
		check(_capture(sync) == _capture(worker),"game flash system output/materials/order remains identical through worker")
		var flash_ids: Array = []; var visible_flash := 0
		for node: MeshInstance3D in worker.get("_geometry").values():
			if node.get_meta("display_role","") != "game_flash": continue
			flash_ids.append(node.get_instance_id())
			if node.visible: visible_flash += 1
		flash_ids.sort()
		if age == 0.0: first_flash_ids = flash_ids.duplicate()
		check(flash_ids.size() == 2 and flash_ids == first_flash_ids,"both game flash carriers retain identity while original active-system count changes")
		check(visible_flash == (2 if age < .14 else 0),"both complete game flash quads retain original adapter duration without stale visibility")
		check(int(worker.diagnostics().owned_nodes) <= 13,"formal fire owns at most eleven original systems plus exactly two reused flash adapters including hidden carriers")
		var systems := 0
		for record: Dictionary in worker.get("_display_meshes"):
			if record.get("kind","") == "particle system": systems += 1
		system_counts[systems] = true
	check(system_counts.size() > 1,"real source frames change native active-system count during flash lifecycle")
	sync.free(); worker.free()

func _run() -> void:
	_camera = Camera3D.new(); root.add_child(_camera); _camera.position = Vector3(21,12,31); _camera.look_at(Vector3.ZERO,Vector3.UP)
	_native_bytes()
	var probe := Runtime.new()
	var ready := check(probe.has_method("batch_meshes"),"Runtime exposes native per-system packed batch path")
	if ready: _actual_sources(); _independent_instances(); _same_age_worker_camera_recovery(); _game_flash_stable_carriers()
	_camera.free()
	print("FIDELITY_FX_SYSTEM_BATCH_TESTS assertions=",assertions," failures=",failures," scope=100 x86 packed byte oracles, full source state, actual active-prefix carriers, worker/lifecycle ownership; GPU/FPS acceptance owned by root")
	quit(1 if failures else 0)
