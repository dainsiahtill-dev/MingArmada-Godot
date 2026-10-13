extends SceneTree
## Actual caller work/ownership contracts; counters and payloads, never wall time.
const Presentation = preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
const Runtime = preload("res://modules/scene_engine/fidelity_fx/particle_runtime.gd")
class SnapshotRuntime:
	extends "res://modules/scene_engine/fidelity_fx/particle_runtime.gd"
	var snapshot_calls := 0
	func snapshot() -> Array:
		snapshot_calls += 1
		return super.snapshot()
class RuntimeTrace extends RefCounted:
	# Real Runtime under a stable facade. The optional second argument is accepted
	# here without changing a baseline override signature or inventing an API RED.
	var actual: RefCounted
	var seek_calls := 0
	var mesh_calls := 0
	func seek(input: float, publish_snapshot: bool = true) -> Array:
		seek_calls += 1
		return actual.call("seek",input) if publish_snapshot else actual.call("seek",input,false)
	func meshes(camera: Dictionary) -> Array:
		mesh_calls += 1
		return actual.call("meshes",camera)
	func diagnostics() -> Dictionary: return actual.call("diagnostics")
	func source_state() -> Dictionary: return actual.call("source_state")
class TracingPresentation:
	extends "res://modules/scene_engine/fidelity_fx/presentation.gd"
	var render_calls := 0
	func _render(meshes: Array) -> void:
		render_calls += 1
		super._render(meshes)

var assertions := 0
var failures := 0
var _water_calls := 0
var _wet := true
var _camera: Camera3D

func check(ok: bool, detail: String) -> bool:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL fidelity FX presentation work: ",detail)
	return ok
func _initialize() -> void: _run.call_deferred()

func _water(_x: float,_z: float,time: float) -> float:
	_water_calls += 1
	return time*0.2
func _surface(_x: float,_z: float) -> bool: return _wet

func _trace(effect: Node3D, source: String, seed: int) -> RuntimeTrace:
	# Configure a fresh actual Runtime from the same unmodified source asset.
	# No set_script, shared replay state, fabricated particles or fake mesh data.
	var runtime := SnapshotRuntime.new()
	var asset: Dictionary = Presentation._asset(source)
	if not check(runtime.configure(asset,seed),"fresh actual traced Runtime accepts the real source asset"): return null
	var trace := RuntimeTrace.new(); trace.actual = runtime
	effect.set("_replay",trace)
	return trace

func _work(effect: TracingPresentation, trace: RuntimeTrace) -> Dictionary:
	return {"seek":trace.seek_calls,"meshes":trace.mesh_calls,"render":effect.render_calls,"snapshot":trace.actual.get("snapshot_calls")}

func _payload(effect: Node3D) -> Dictionary:
	var resources: Array[int] = []
	var frames: Array = []
	var visible := 0
	for node: MeshInstance3D in effect.get("_geometry").values():
		if node.mesh == null: continue
		resources.append(node.mesh.get_instance_id())
		var surfaces: Array = []
		for index in node.mesh.get_surface_count(): surfaces.append(node.mesh.surface_get_arrays(index))
		frames.append({"position":node.global_position,"visible":node.visible,"surfaces":surfaces})
		if node.visible: visible += 1
	return {"resourceIds":resources,"geometryHash":hash(frames),"visible":visible}

func _source_state(trace: RuntimeTrace) -> Dictionary: return trace.source_state()

func _cannon_caller() -> void:
	var source := "fx_cannon_fire_01.nif"
	var effect := TracingPresentation.new(); root.add_child(effect)
	if not check(effect.configure(source,{"camera":_camera,"seed":17,"render_profile":"game_cannon"}),"actual eleven-layer cannon presentation configures"):
		effect.free(); return
	var trace := _trace(effect,source,17)
	if trace == null: effect.free(); return
	check(effect.apply_snapshot(0.061,10.061),"actual presentation produces an accepted non-grid endpoint")
	var first: Dictionary = _work(effect,trace)
	var payload: Dictionary = _payload(effect)
	var state: Dictionary = _source_state(trace)
	var endpoint_id: int = trace.actual.get("_replay").get_instance_id()
	check(first.seek == 1 and first.meshes == 1 and first.render == 1 and payload.visible > 0,"first actual caller performs one seek, mesh build and nonempty render")
	check(first.snapshot == 0,"presentation render seek never requests the unused public particle snapshot")
	for frame in 3: check(effect.apply_snapshot(0.061,10.061),"identical accepted presentation remains successful")
	check(_work(effect,trace) == first,"identical age, absolute time and camera skip seek, meshes, render and snapshot work")
	check(trace.actual.get("_replay").get_instance_id() == endpoint_id and _source_state(trace) == state,"repeated caller retains the exact replay endpoint and native/RNG state")
	check(_payload(effect) == payload,"repeated caller retains the same mesh resources and complete geometry payload")

	_camera.position.x += 5.0; _camera.look_at(Vector3.ZERO,Vector3.UP)
	check(effect.apply_snapshot(0.061,10.061),"camera change updates actual source billboards")
	var moved: Dictionary = _work(effect,trace)
	check(moved.seek == first.seek and moved.snapshot == 0 and moved.meshes == first.meshes+1 and moved.render == first.render+1,"camera-only change rebuilds billboard meshes once without requesting seek or snapshot")
	check(_source_state(trace) == state and trace.actual.get("_replay").get_instance_id() == endpoint_id,"camera-only render cannot advance native particles, endpoint or RNG")
	var moved_payload: Dictionary = _payload(effect)
	check(moved_payload.geometryHash != payload.geometryHash,"real camera basis change changes drawn source geometry")
	check(effect.apply_snapshot(0.061,10.061) and _work(effect,trace) == moved and _payload(effect) == moved_payload,"stable changed camera subsequently reuses its exact drawn payload")

	# Reconfiguration can have identical age/absolute/camera, but a new origin.
	var renders: int = effect.render_calls
	check(effect.configure(source,{"camera":_camera,"seed":17,"origin":Vector3(100,0,0),"render_profile":"game_cannon"}),"same object reconfigures real source at a different birth origin")
	var replacement := _trace(effect,source,17)
	if replacement != null:
		check(effect.apply_snapshot(0.061,10.061) and effect.render_calls == renders+1,"configure invalidates old same-age presentation memo")
		check(_payload(effect).geometryHash != moved_payload.geometryHash,"new source origin is reflected in actual drawn world geometry")
		var changed: Dictionary = _work(effect,replacement)
		check(effect.apply_snapshot(0.061,10.061) and _work(effect,replacement) == changed,"reconfigured source acquires its own stable work memo")
		effect.dispose()
		check(effect.get("_geometry").is_empty() and not effect.apply_snapshot(0.061,10.061),"dispose releases geometry and cannot reuse a cached accepted frame")
		renders = effect.render_calls
		check(effect.configure(source,{"camera":_camera,"seed":17}),"disposed object accepts a fresh source lifecycle")
		var fresh := _trace(effect,source,17)
		if fresh != null: check(effect.apply_snapshot(0.061,10.061) and effect.render_calls == renders+1 and fresh.seek_calls == 1,"fresh lifecycle seeks and draws rather than reusing disposed memo")
	effect.dispose(); effect.free()

func _water_caller() -> void:
	var source := "cannon_ball_splash_01.nif"
	var effect := TracingPresentation.new(); root.add_child(effect)
	_wet = true; _water_calls = 0
	if not check(effect.configure(source,{"camera":_camera,"seed":21,"origin":Vector3(4,0,-8),"water":_water,"sea":_surface}),"actual splash source with time-sensitive water and sea filter configures"):
		effect.free(); return
	var trace := _trace(effect,source,21)
	if trace == null: effect.free(); return
	check(effect.apply_snapshot(0.35,3.0),"actual authored splash geometry is placed on the injected accepted wave phase")
	var first: Dictionary = _work(effect,trace); var payload: Dictionary = _payload(effect)
	var calls: int = _water_calls; var state: Dictionary = _source_state(trace)
	check(calls > 0 and payload.visible > 0,"water fixture exercises real ring projection and real drawable source meshes")
	check(first.snapshot == 0,"water presentation also avoids unused particle snapshot publication")
	check(effect.apply_snapshot(0.35,3.0) and _work(effect,trace) == first and _water_calls == calls and _payload(effect) == payload,"identical splash inputs reuse work and actual wave-projected payload")
	check(effect.apply_snapshot(0.35,4.0),"same particle age with a later absolute wave phase remains renderable")
	var absolute: Dictionary = _work(effect,trace)
	check(absolute.seek == first.seek and absolute.snapshot == 0 and absolute.render == first.render+1,"absolute-time-only water change rerenders once without advancing particle seek")
	check(_water_calls > calls and _payload(effect).geometryHash != payload.geometryHash and _source_state(trace) == state,"new absolute time moves real water geometry but preserves native/RNG particle state")

	# Same Callable object, changed provider state: explicit setter revision must
	# invalidate even when age/time/camera and Callable equality remain unchanged.
	_wet = false; effect.configure_surface_filter(_surface)
	check(effect.apply_snapshot(0.35,4.0),"changed surface filter updates the same accepted splash frame")
	check(effect.render_calls == absolute.render+1 and _payload(effect).visible == 0,"dry filter invalidation hides all real source triangles instead of reusing wet geometry")
	check(trace.seek_calls == first.seek and _source_state(trace) == state,"surface filter changes cannot advance source replay or RNG")
	var dry: Dictionary = _work(effect,trace)
	check(effect.apply_snapshot(0.35,4.0) and _work(effect,trace) == dry,"unchanged dry-filter input is subsequently memoized")
	_wet = true; effect.configure_surface_filter(_surface)
	check(effect.apply_snapshot(0.35,4.0) and effect.render_calls == dry.render+1 and _payload(effect).visible > 0,"restored wet filter redraws retained real source data")
	effect.dispose(); effect.free()

func _public_runtime_ownership() -> void:
	var runtime := Runtime.new()
	if not check(runtime.configure(Presentation._asset("fx_cannon_fire_01.nif"),17),"public actual Runtime configures for default API ownership checks"): return
	var particles: Array = runtime.seek(0.061)
	if not check(not particles.is_empty(),"default public seek still returns real particle records"): return
	var state: Dictionary = runtime.source_state()
	particles[0].position[0] = 987654.0
	check(runtime.source_state() == state and runtime.snapshot()[0].position[0] != 987654.0,"seek default returns deep-owned records isolated from retained native state")
	var camera: Dictionary = {"right":[1.0,0.0,0.0],"up":[0.0,1.0,0.0],"direction":[0.0,0.0,1.0]}
	var meshes: Array = runtime.meshes(camera)
	if not check(not meshes.is_empty(),"public meshes still returns real source quad/mesh records"): return
	meshes[0].vertices[0][0] = 987654.0; meshes[0].triangles[0][0] = 999999
	var fresh: Array = runtime.meshes(camera)
	check(fresh[0].vertices[0][0] != 987654.0 and fresh[0].triangles[0][0] != 999999 and runtime.source_state() == state,"public meshes remains deeply isolated after render-only caller optimization")

func _run() -> void:
	_camera = Camera3D.new(); root.add_child(_camera)
	_camera.position = Vector3(0,2,12); _camera.look_at(Vector3.ZERO,Vector3.UP)
	_cannon_caller(); _water_caller(); _public_runtime_ownership()
	_camera.free()
	print("FIDELITY_FX_PRESENTATION_WORK_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
