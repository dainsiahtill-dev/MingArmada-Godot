extends SceneTree
## Actual native sources/owners: same-frame worker completion, never FPS or a
## wall-time threshold. Splash fixtures exercise presentation, not collisions.
const Fx = preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
const Runtime = preload("res://modules/scene_engine/fidelity_fx/particle_runtime.gd")
const Effects = preload("res://game/presentation/combat/combat_effects.gd")
const Water = preload("res://game/presentation/water/water_splashes.gd")
const Practice = preload("res://game/runtime/naval_practice_runtime.gd")
const Waves = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const SOURCES := ["fx_cannon_fire_01.nif","cannon_ball_splash_01.nif","cannon_ball_splash_02.nif","cannon_ball_splash_03.nif"]
const CAPACITIES := [435,82,85,79]
const AGES := [0.0,.061,.18,.72]

class Marker extends RefCounted:
	var mutex := Mutex.new()
	var ran := false
	func mark() -> void:
		mutex.lock(); ran = true; mutex.unlock()
	func read() -> bool:
		mutex.lock(); var value := ran; mutex.unlock(); return value

class RuntimeTrace extends RefCounted:
	# Real provider forwarding only. The gate proves main work can occur before
	# completion without sleeps, timing thresholds, Node callbacks or fake state.
	var actual: RefCounted
	var gate := Semaphore.new()
	var marker := Marker.new()
	var gate_once := false
	var saw_marker := false
	var native_threads: Array = []
	var mesh_threads: Array = []
	var done := 0
	func advance_native(age: float,include_snapshot: bool = true) -> Array:
		native_threads.append(Thread.is_main_thread())
		if gate_once:
			gate_once = false; gate.wait(); saw_marker = marker.read()
		var result: Array = actual.call("advance_native",age,include_snapshot)
		done += 1; return result
	func display_meshes(camera: Dictionary) -> Array:
		mesh_threads.append(Thread.is_main_thread()); return actual.call("display_meshes",camera)
	func meshes(camera: Dictionary) -> Array: return actual.call("meshes",camera)
	func seek(age: float,include_snapshot: bool = true) -> Array: return actual.call("seek",age,include_snapshot)
	func get_last_error() -> String: return actual.call("get_last_error")
	func get_playback_duration() -> float: return actual.call("get_playback_duration")
	func diagnostics() -> Dictionary: return actual.call("diagnostics")
	func source_state() -> Dictionary: return actual.call("source_state")

class ProbeFx:
	extends "res://modules/scene_engine/fidelity_fx/presentation.gd"
	var render_threads: Array = []
	func _render(records: Array) -> void:
		render_threads.append(Thread.is_main_thread()); super._render(records)

class Providers extends RefCounted:
	var waves: RefCounted
	var threads: Array = []
	var wet := true
	func water(x: float,z: float,time: float) -> float:
		threads.append(Thread.is_main_thread()); return float(waves.call("sample_height",x,z,time))
	func sea(_x: float,_z: float) -> bool:
		threads.append(Thread.is_main_thread()); return wet

var assertions := 0
var failures := 0
var _camera: Camera3D
var _providers := Providers.new()
func check(ok: bool,detail: String) -> bool:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL FX parallel work: ",detail)
	return ok
func _initialize() -> void: _run.call_deferred()
func _height(_x: float,_z: float) -> float: return -80.0
func _options(seed: int = 17) -> Dictionary:
	return {"seed":seed,"clock_mode":"native","camera":_camera,"water":_providers.water,"sea":_providers.sea}
func _state(effect: Node3D) -> PackedByteArray:
	var replay: RefCounted = effect.get("_replay")
	return var_to_bytes(replay.call("source_state")) if replay != null else PackedByteArray()
func _material(material: Material) -> Dictionary:
	if material is ShaderMaterial:
		var parameters: Dictionary = {}
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			var value: Variant = material.get_shader_parameter(uniform.name)
			if value is Resource: value = [value.get_class(),value.resource_path,value.get_instance_id()]
			parameters[uniform.name] = value
		return {"shader":material.shader.code,"parameters":parameters,"priority":material.render_priority}
	return {"class":material.get_class(),"color":material.albedo_color} if material is StandardMaterial3D else {}
func _mesh(node: MeshInstance3D) -> Dictionary:
	var arrays: Array = []
	if node.mesh != null:
		for surface in node.mesh.get_surface_count(): arrays.append(node.mesh.surface_get_arrays(surface))
	var bounds := AABB()
	if node.mesh != null:
		bounds = node.custom_aabb
		if bounds.size == Vector3.ZERO and node.mesh is ArrayMesh: bounds = node.mesh.custom_aabb
		if bounds.size == Vector3.ZERO: bounds = node.mesh.get_aabb()
	return {"transform":node.global_transform,"visible":node.visible,"arrays":arrays,"bounds":bounds,"shadow":node.cast_shadow,"material":_material(node.material_override)}
func _source(effect: Node3D) -> Dictionary:
	var geometry: Dictionary = effect.get("_geometry")
	var keys: Array = geometry.keys(); keys.sort()
	var payload: Dictionary = {}
	for key: Variant in keys: payload[key] = _mesh(geometry[key])
	return {"state":_state(effect),"geometry":payload,"order":effect.get("_draw_order").duplicate(true),"age":effect.get("_age"),"absolute":effect.get("_absolute_time")}
func _joined(effect: Node3D,label: String) -> void:
	check(not bool(effect.call("has_pending_snapshot")),label+" has no unjoined snapshot")
	var worker: Dictionary = effect.call("diagnostics").get("worker",{})
	check(worker.has("dispatched") and worker.has("joined") and int(worker.get("dispatched",-1)) == int(worker.get("joined",-2)) and int(worker.get("pending",-1)) == 0,label+" joins every dispatched task exactly once")

func _sources() -> void:
	for index in SOURCES.size():
		var sync := ProbeFx.new(); var paired := ProbeFx.new()
		root.add_child(sync); root.add_child(paired)
		if not check(sync.configure(SOURCES[index],_options()) and paired.configure(SOURCES[index],_options()),"both actual sources configure "+SOURCES[index]): sync.free(); paired.free(); continue
		var oracle := Runtime.new(); oracle.configure(Fx._asset(SOURCES[index]),17); oracle.advance_native(0.0,false)
		for age: float in AGES:
			if age != 0.0: oracle.advance_native(age,false)
			var accepted := sync.apply_snapshot(age,4.0+age)
			check(paired.call("begin_snapshot",age,4.0+age),"paired begin accepts source age without delayed-frame display")
			check(bool(paired.call("finish_snapshot")) == accepted,"same-frame finish has the synchronous result")
			check(_source(sync) == _source(paired),"all actual source meshes/materials/order/state equal synchronous path "+SOURCES[index]+"/"+str(age))
			check(_state(paired) == var_to_bytes(oracle.source_state()),"complete native pool/RNG/world/bounds equal independent original appTime oracle")
			var state: Dictionary = oracle.source_state(); var capacity := 0
			for system: Dictionary in state.systems:
				capacity += int(system.capacity); check(system.particles.size() == int(system.capacity),"all authored capacity slots retained")
			check(capacity == CAPACITIES[index],"original source capacity is preserved")
			_joined(paired,"source frame")
		var frozen := _state(paired)
		for change: String in ["repeat","camera","absolute","filter"]:
			if change == "camera": _camera.position.x += 3.0; _camera.look_at(Vector3.ZERO,Vector3.UP)
			if change == "filter":
				_providers.wet = false; sync.configure_surface_filter(_providers.sea); paired.configure_surface_filter(_providers.sea)
			var absolute := 5.72 if change in ["absolute","filter"] else 4.72
			sync.apply_snapshot(.72,absolute); paired.call("begin_snapshot",.72,absolute); paired.call("finish_snapshot")
			check(_source(sync) == _source(paired) and _state(paired) == frozen,"same-age "+change+" preserves complete native state and actual output")
		_joined(paired,"camera/filter frame")
		check(not sync.render_threads.has(false) and not paired.render_threads.has(false),"all Node/render/material work runs on main thread")
		_providers.wet = true; sync.free(); paired.free()

func _worker_and_lifecycle() -> void:
	var effect := ProbeFx.new(); root.add_child(effect); effect.configure(SOURCES[0],_options())
	var trace := RuntimeTrace.new(); trace.actual = effect.get("_replay"); trace.gate_once = true
	effect.set("_replay",trace)
	var before := _source(effect)
	check(effect.call("begin_snapshot",.061,2.061),"begin returns while the real native advance is gated")
	check(bool(effect.call("has_pending_snapshot")) and effect.render_threads.is_empty(),"begin dispatches without rendering or joining on main")
	# A stand-in marker for already-tested actual actor updates, not fake particles.
	trace.marker.mark(); trace.gate.post()
	check(effect.call("finish_snapshot"),"finish waits and presents this same accepted frame")
	check(trace.native_threads == [false] and trace.mesh_threads == [false] and trace.saw_marker and trace.done == 1,"real advance and mesh generation ran off-main after main actor marker")
	check(_source(effect) != before and not effect.render_threads.has(false),"current-frame real geometry is rendered only after join on main")
	var budget := [trace.native_threads.size(),trace.mesh_threads.size()]
	var held := _state(effect)
	effect.call("begin_snapshot",.061,2.061); effect.call("finish_snapshot")
	check([trace.native_threads.size(),trace.mesh_threads.size()] == budget and _state(effect) == held,"same inputs do not dispatch or repeat advance")
	_camera.position.z += 2.0; _camera.look_at(Vector3.ZERO,Vector3.UP)
	effect.call("begin_snapshot",.061,2.061); effect.call("finish_snapshot")
	check(trace.native_threads.size() == 1 and trace.mesh_threads.size() == 2 and not trace.mesh_threads.has(true) and _state(effect) == held,"camera-only worker generates meshes without advancing native clocks")
	check(not effect.call("begin_snapshot",NAN,2.0) and _state(effect) == held,"invalid age cannot dispatch or pollute the accepted frame")
	_joined(effect,"repeat/camera/invalid")
	for action: String in ["diagnostics","camera","filter","reconfigure","dispose"]:
		effect.call("begin_snapshot",.18,2.18)
		check(bool(effect.call("has_pending_snapshot")),"actual pending task exists before "+action)
		match action:
			"diagnostics": effect.call("diagnostics")
			"camera": effect.set_camera(null)
			"filter": effect.configure_surface_filter(_providers.sea)
			"reconfigure": check(effect.configure(SOURCES[2],_options(53)),"reconfigure drains old source before new independent lifecycle")
			"dispose": effect.dispose()
		_joined(effect,"lifecycle "+action)
		if action in ["reconfigure","dispose"]:
			check(effect.get("_geometry").is_empty(),"new/cleared lifecycle cannot render an old worker payload")
			if action == "dispose": check(effect.get("_replay") == null,"disposed source retains no replay/task owner")
			else:
				var fresh := Runtime.new(); fresh.configure(Fx._asset(SOURCES[2]),53); fresh.advance_native(0.0,false)
				check(_state(effect) == var_to_bytes(fresh.source_state()),"new lifecycle retains only its unique zero birth anchor")
		else: effect.set_camera(_camera)
		# A distinct source age is required to create the next real task.
		if action not in ["reconfigure","dispose"]: effect.apply_snapshot(.061,2.061)
	effect.configure(SOURCES[0],_options()); effect.call("begin_snapshot",effect.get_playback_duration()+.1,5.0)
	check(not effect.call("finish_snapshot") and int(effect.diagnostics().rendered_meshes) == 0,"finite controller clip joins and hides every carrier")
	_joined(effect,"expired clip"); effect.free()
	var study := ProbeFx.new(); root.add_child(study); var options := _options(); options.erase("clock_mode")
	study.configure(SOURCES[0],options); study.apply_snapshot(.061,2.061)
	var observer := Runtime.new(); observer.configure(Fx._asset(SOURCES[0]),17); observer.seek(.061,false)
	check(_state(study) == var_to_bytes(observer.source_state()) and String(study.diagnostics().time_input.kind).begins_with("canonical float32 120Hz"),"Study default keeps its complete synchronous canonical observer")
	check(int(study.diagnostics().get("worker",{}).get("dispatched",-1)) == 0,"observer path never schedules native worker work")
	study.free()

func _id(variant: int) -> String:
	for index in 100:
		var value := "parallel-splash-%d"%index
		if 1+posmod(absi(value.hash()),3) == variant: return value
	return ""
func _splash_events(time: float) -> Array:
	var events: Array = []
	for variant in range(1,4): events.append({"type":"splash","id":_id(variant),"time":time,"position":{"x":variant*8.0,"y":0.0,"z":-9.0},"scale":1.0})
	return events
func _water_capture(owner: Node3D) -> Dictionary:
	var result: Array = []
	for splash: Dictionary in owner.get("_splashes"):
		var item: Dictionary = {"time":splash.time,"origin":splash.origin,"drops":[]}
		for key: String in ["ring","spray","mist","column","shell"]: item[key] = _mesh(splash[key])
		var drops: MultiMesh = splash.drops.multimesh
		for index in drops.instance_count: item.drops.append([drops.get_instance_transform(index),drops.get_instance_color(index)])
		if splash.has("reference"): item.source = _source(splash.reference)
		result.append(item)
	return {"time":owner.get("_time"),"splashes":result,"seen":owner.get("_seen").duplicate(true)}
func _owner_capture(owner: Node3D,water_only: bool) -> Dictionary:
	if water_only: return _water_capture(owner)
	var result: Dictionary = {"time":owner.get("_time"),"seen":owner.get("_seen").duplicate(true),"sources":[],"balls":{},"puffs":[],"water":_water_capture(owner.get("_water_splashes"))}
	for source: Dictionary in owner.get("_source_fire"): result.sources.append(_source(source.node))
	for id: Variant in owner.get("_balls"): result.balls[id] = _mesh(owner.get("_balls")[id])
	for puff: Dictionary in owner.get("_puffs"): result.puffs.append(_mesh(puff.node))
	return result
func _owners(water_only: bool) -> void:
	var sync: Node3D = Water.new() if water_only else Effects.new()
	var paired: Node3D = Water.new() if water_only else Effects.new()
	root.add_child(sync); root.add_child(paired)
	var runtime := Practice.new(); runtime.configure(_height,{"mode":"sail"})
	check(runtime.command({"type":"fire","side":"port"}).get("ok",false),"actual public Practice fire is accepted")
	runtime.advance(1.0/60.0); var native: Dictionary = runtime.snapshot().naval
	var events: Array = runtime.drain_events(); events.append_array(_splash_events(float(native.time)))
	for owner: Node3D in [sync,paired]:
		if water_only:
			owner.call("configure",_providers.water); owner.call("configure_reference_backend",_camera); owner.call("configure_surface_filter",_providers.sea)
			owner.call("apply_snapshot",float(native.time))
			for event: Dictionary in events:
				if event.type == "splash": owner.call("add_event",event)
		else:
			owner.call("set_camera",_camera); owner.call("set_water_sampler",_providers.water); owner.call("set_surface_filter",_providers.sea)
			owner.call("apply_snapshot",native,0.0); owner.call("apply_events",events)
	check(_owner_capture(sync,water_only) == _owner_capture(paired,water_only),"real paired owners create the same immediate fire/splash birth frame")
	for delta: float in [.061,.18,.72,0.0]:
		runtime.advance(delta); native = runtime.snapshot().naval
		if delta == 0.0: _camera.position.x += 2.0; _camera.look_at(Vector3.ZERO,Vector3.UP)
		if water_only:
			sync.call("apply_snapshot",float(native.time)); paired.call("begin_snapshot",float(native.time))
		else:
			sync.call("apply_snapshot",native,delta); paired.call("begin_snapshot",native,delta)
		check(bool(paired.call("has_pending_snapshot")),"actual owner retains this frame between begin and finish")
		paired.call("finish_snapshot")
		check(not bool(paired.call("has_pending_snapshot")) and _owner_capture(sync,water_only) == _owner_capture(paired,water_only),"real owner paired output/state exactly equals synchronous current frame")
	# Disposal must join real tasks for the next actually accepted native frame.
	runtime.advance(.1); native = runtime.snapshot().naval
	if water_only: paired.call("begin_snapshot",float(native.time))
	else: paired.call("begin_snapshot",native,.1)
	paired.call("dispose")
	check(not bool(paired.call("has_pending_snapshot")),"actual owner disposal joins all source jobs")
	check(paired.get("_splashes").is_empty() if water_only else paired.get("_source_fire").is_empty(),"actual owner disposal releases all living source owners")
	sync.free(); paired.free(); runtime.dispose()

func _run() -> void:
	_camera = Camera3D.new(); root.add_child(_camera); _camera.position = Vector3(0,12,25); _camera.look_at(Vector3.ZERO,Vector3.UP)
	_providers.waves = Waves.new(); check(_providers.waves.call("configure",_height),"real CoastalWaveField configures original descriptors")
	var source := Fx.new(); var water := Water.new(); var effects := Effects.new()
	var source_ready := check(source.has_method("begin_snapshot") and source.has_method("finish_snapshot") and source.has_method("has_pending_snapshot"),"SourceFx exposes safe same-frame begin/finish/pending contract")
	var water_ready := check(water.has_method("begin_snapshot") and water.has_method("finish_snapshot") and water.has_method("has_pending_snapshot"),"actual Water owner exposes paired contract")
	var effects_ready := check(effects.has_method("begin_snapshot") and effects.has_method("finish_snapshot") and effects.has_method("has_pending_snapshot"),"actual CombatEffects owner exposes paired contract")
	source.free(); water.free(); effects.free()
	if source_ready:
		_sources(); _worker_and_lifecycle()
		if water_ready: _owners(true)
		if water_ready and effects_ready: _owners(false)
		var sea := FileAccess.get_file_as_string("res://game/presentation/world/naval_world_view.gd")
		var begin := sea.find("effects.begin_snapshot("); var actor := sea.find("view.apply_snapshot(timed,",begin)
		var finish := sea.find("effects.finish_snapshot()",actor); var events := sea.find("effects.apply_events(presented_events)",finish)
		check(begin >= 0 and actor > begin and finish > actor and events > finish,"formal Sea dispatches before actual actors and joins before newborn event presentation")
	check(not _providers.threads.has(false),"all real water/sea Callables stay on main thread")
	_camera.free()
	print("FIDELITY_FX_PARALLEL_WORK_TESTS assertions=",assertions," failures=",failures," scope=actual sources/owners, full native state and mesh equality; worker dispatch/join without FPS thresholds")
	quit(1 if failures else 0)
