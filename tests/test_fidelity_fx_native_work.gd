extends SceneTree
## Actual game-only allocation/ownership budgets, never a wall-time threshold.
const Fx = preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
const Runtime = preload("res://modules/scene_engine/fidelity_fx/particle_runtime.gd")
const Waves = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const SOURCES := ["fx_cannon_fire_01.nif","cannon_ball_splash_01.nif","cannon_ball_splash_02.nif","cannon_ball_splash_03.nif"]
const PATH := [0.0,0.02,0.06,0.35,1.0]
const CAMERA := {"right":[1.0,0.0,0.0],"up":[0.0,0.5,0.8660254037844386],"direction":[0.0,-0.8660254037844386,0.5]}

class RuntimeTrace extends RefCounted:
	# Every operation delegates to the original real provider. No fake particles,
	# replacement scripts or snapshots; missing new display API has a safe RED.
	var actual: RefCounted
	var owned_calls := 0
	var display_calls := 0
	var native_calls := 0
	func meshes(camera: Dictionary) -> Array:
		owned_calls += 1; return actual.call("meshes",camera)
	func display_meshes(camera: Dictionary) -> Array:
		display_calls += 1
		return actual.call("display_meshes",camera) if actual.has_method("display_meshes") else actual.call("meshes",camera)
	func advance_native(time: float,include_snapshot: bool = true) -> Array:
		native_calls += 1; return actual.call("advance_native",time,include_snapshot)
	func seek(time: float,include_snapshot: bool = true) -> Array: return actual.call("seek",time,include_snapshot)
	func get_last_error() -> String: return actual.call("get_last_error")
	func get_playback_duration() -> float: return actual.call("get_playback_duration")
	func diagnostics() -> Dictionary: return actual.call("diagnostics")
	func source_state() -> Dictionary: return actual.call("source_state")

class ResetTrace:
	extends "res://modules/scene_engine/fidelity_fx/particle_runtime.gd"
	var reset_calls := 0
	func reset() -> void:
		reset_calls += 1; super.reset()

class MeshTrace:
	extends "res://modules/scene_engine/fidelity_fx/native_particle_replay.gd"
	var last_records: Array = []
	func meshes(camera: Dictionary) -> Array:
		last_records = super.meshes(camera); return last_records

var assertions := 0
var failures := 0
var _camera: Camera3D
var _waves: RefCounted
var _wet := true
func check(ok: bool,detail: String) -> bool:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL native FX work: ",detail)
	return ok
func _initialize() -> void: _run.call_deferred()
func _height(_x: float,_z: float) -> float: return -80.0
func _sea(_x: float,_z: float) -> bool: return _wet
func _bytes(runtime: RefCounted) -> PackedByteArray: return var_to_bytes(runtime.call("source_state"))
func _options(seed: int) -> Dictionary:
	return {"seed":seed,"clock_mode":"native","camera":_camera,"water":_waves.sample_height,"sea":_sea}

func _caller(source: String,native: bool) -> void:
	var effect := Fx.new(); var sibling := Fx.new()
	root.add_child(effect); root.add_child(sibling)
	var options := _options(17)
	if not native: options.erase("clock_mode")
	if not check(effect.configure(source,options),"actual caller configures "+source): effect.free(); sibling.free(); return
	var provider: RefCounted = effect.get("_replay")
	var blueprint := var_to_bytes(provider.get("_asset"))
	if native:
		check(provider.get("_canonical") == null,"game native caller never allocates an unused canonical observer: "+source)
		if check(sibling.configure(source,_options(53)),"second actual native lifecycle configures "+source):
			var other: RefCounted = sibling.get("_replay")
			check(is_same(provider.get("_asset"),other.get("_asset")) and is_same(provider.get("_blocks"),other.get("_blocks")),"same-source native lifecycles share prepared immutable asset/index: "+source)
	var trace := RuntimeTrace.new(); trace.actual = provider
	# Configure already performed the unique birth update at zero. The first
	# traced frame is .061, so changing this provider ID cannot duplicate it.
	effect.set("_replay",trace)
	check(effect.apply_snapshot(.061,10.061),"actual caller draws original non-grid native/Study records")
	if native:
		check(trace.display_calls == 1 and trace.owned_calls == 0,"native Presentation uses borrowed display records, no final owned clone: "+source)
		check(trace.native_calls == 1,"first accepted native display follows the one configure birth anchor")
	else: check(trace.display_calls == 0 and trace.owned_calls == 1,"Study default keeps deep-owned mesh publication")
	var before := _bytes(provider)
	var budget := [trace.display_calls,trace.owned_calls,trace.native_calls]
	check(effect.apply_snapshot(.061,10.061) and budget == [trace.display_calls,trace.owned_calls,trace.native_calls],"same accepted caller inputs consume no replay/mesh work")
	_camera.position.x += 3.0; _camera.look_at(Vector3.ZERO,Vector3.UP)
	check(effect.apply_snapshot(.061,10.061) and _bytes(provider) == before,"camera-only redraw keeps complete original particle state")
	check(effect.apply_snapshot(.061,11.061) and _bytes(provider) == before,"absolute water reprojection keeps source state")
	_wet = false; effect.configure_surface_filter(_sea)
	check(effect.apply_snapshot(.061,11.061) and _bytes(provider) == before,"filter revision keeps source state and borrowed records read-only")
	_wet = true
	check(var_to_bytes(provider.get("_asset")) == blueprint,"render/camera/filter leave prepared blueprint bytes unchanged")
	effect.dispose(); sibling.dispose(); effect.free(); sibling.free()

func _unstarted(child: RefCounted,label: String) -> void:
	var replay: RefCounted = child.get("_native")
	if not check(replay != null and child.get("_canonical") == null,"factory owns one actual native replay and no observer: "+label): return
	check(replay.get("time") == null,"factory leaves the native appTime unstarted for the owner's sole zero anchor")
	var initial := _bytes(child)
	check(child.call("display_meshes",CAMERA).is_empty() and child.call("meshes",CAMERA).is_empty() and _bytes(child) == initial,"unstarted owner safely exposes no pre-birth meshes without modifying its complete pool")
	check(child.call("source_state").get("systems",[]).size() == replay.get("systems").size(),"unstarted source_state exposes all actual initialized capacity pools")
	check(child.call("advance_native",NAN,false).is_empty() and _bytes(child) == initial and replay.get("time") == null,"invalid native appTime cannot start or mutate a prepared owner")
	for system: Dictionary in replay.get("systems"):
		check(system.lastUpdate == null and system.lastResetMapped == null and system.controller.last_app == null and not system.controller.clock.started,"factory cannot advance any system/emitter clock before birth")
		check(system.pool.particles.size() == int(system.pool.capacity),"factory retains every original capacity slot")

func _factory(source: String) -> void:
	var raw: Dictionary = Fx._asset(source).duplicate(true)
	var template := ResetTrace.new()
	if not check(template.call("configure",raw,1,false),"prepare-only validates and owns the complete source "+source): return
	check(template.reset_calls == 0 and template.get("_canonical") == null and template.get("_native") == null and template.get("_replay") == null,"prepare-only builds neither replay/pool/fork nor canonical reset")
	var prepared := var_to_bytes(template.get("_asset"))
	var indexed := var_to_bytes(template.get("_blocks"))
	raw.name = "caller-mutated-source"
	raw.blocks[0].name = "caller-mutated-root"
	check(var_to_bytes(template.get("_asset")) == prepared,"prepare owns source data independently of raw caller mutation")
	var children: Array = []
	for seed: int in [1,53]:
		var child: RefCounted = template.call("spawn_native",seed)
		if not check(child != null,"valid uint32 seed spawns actual native owner"): continue
		children.append(child); _unstarted(child,source+"/"+str(seed))
		check(is_same(child.get("_asset"),template.get("_asset")) and is_same(child.get("_blocks"),template.get("_blocks")),"spawn borrows the one owned prepared immutable blueprint")
		var old := Runtime.new(); old.configure(Fx._asset(source),seed)
		for time: float in PATH:
			child.call("advance_native",time,false); old.advance_native(time,false)
			check(_bytes(child) == _bytes(old),"factory full pool/RNG/world/bounds match default original native path "+source+"/"+str(seed)+"/"+str(time))
		child.call("seek",.35,false); old.seek(.35,false)
		check(_bytes(child) == _bytes(old),"lazy observer initializes its original canonical state")
		child.call("advance_native",.4,false); old.advance_native(.4,false)
		check(_bytes(child) == _bytes(old),"native history survives lazy native-to-seek-to-native switching")
		child.call("reset"); old.reset()
		for time: float in [0.0,.06,.35]: child.call("advance_native",time,false); old.advance_native(time,false)
		check(_bytes(child) == _bytes(old),"explicit reset retains the old clear-and-restart semantics")
	if children.size() == 2:
		var a: RefCounted = children[0].get("_native"); var b: RefCounted = children[1].get("_native")
		check(not is_same(a,b) and not is_same(a.get("rng"),b.get("rng")),"spawned native replay and RNG owners are independent")
		var sa: Array = a.get("systems"); var sb: Array = b.get("systems")
		for index in sa.size():
			check(not is_same(sa[index].pool,sb[index].pool) and not is_same(sa[index].controller,sb[index].controller) and not is_same(sa[index].controller.clock,sb[index].controller.clock),"each original layer owns independent pool/controller/clock")
		var b_before := _bytes(children[1]); children[0].call("advance_native",.4,false)
		check(_bytes(children[1]) == b_before,"one owner's real native step cannot alter another owner's full state")
	for seed: int in [-1,0x100000000]: check(template.call("spawn_native",seed) == null,"factory rejects seed outside explicit uint32 CRT state")
	check(var_to_bytes(template.get("_asset")) == prepared and var_to_bytes(template.get("_blocks")) == indexed,"advance/seek/reset leave shared prepared asset/index completely immutable")
	var bad := ResetTrace.new()
	check(not bad.call("configure",{},1,false) and bad.call("spawn_native",1) == null,"failed preparation cannot produce or cache a replay owner")
	check(bad.get("_canonical") == null and bad.get("_native") == null and bad.get("_replay") == null,"failed preparation allocates no source pool")

func _display_ownership(source: String) -> void:
	var raw: Dictionary = Fx._asset(source).duplicate(true)
	var runtime := Runtime.new(); runtime.configure(raw,1)
	var owned_asset := var_to_bytes(runtime.get("_asset"))
	raw.blocks[0].name = "default-caller-mutated-root"
	check(var_to_bytes(runtime.get("_asset")) == owned_asset,"default public configure still deeply owns raw caller data")
	var traced := MeshTrace.new(runtime.get("_asset"),1,runtime.get("_blocks"))
	for time: float in [0.0,.02,.06,.35]: traced.advance(time)
	# The replacement is an actual NativeReplay subclass with real source state;
	# it observes returned-record identity only, never fabricates mesh contents.
	runtime.set("_native",traced); runtime.set("_replay",traced)
	var before := _bytes(runtime); var blueprint := var_to_bytes(runtime.get("_asset"))
	var display: Array = runtime.call("display_meshes",CAMERA)
	check(not display.is_empty() and is_same(display,traced.last_records),"display returns the exact real replay records without a final deep clone: "+source)
	var expected := var_to_bytes(display)
	var owned: Array = runtime.meshes(CAMERA)
	check(not is_same(owned,traced.last_records) and var_to_bytes(owned) == expected,"public meshes retains detached, byte-identical publication")
	for record: Dictionary in owned:
		if not record.get("vertices",[]).is_empty(): record.vertices[0][0] += 333.0
		if not record.get("uvs",[]).is_empty(): record.uvs[0][0] += 44.0
		if not record.get("triangles",[]).is_empty(): record.triangles[0][0] = 999
		if record.has("material"): record.material.alpha = 999.0
		if record.has("vertexColors") and not record.vertexColors.is_empty(): record.vertexColors[0].r = 999.0
	check(var_to_bytes(runtime.meshes(CAMERA)) == expected and _bytes(runtime) == before and var_to_bytes(runtime.get("_asset")) == blueprint,"public vertex/UV/index/material mutation cannot alter replay or immutable blueprint")
	for bad: Dictionary in [{},{"right":[NAN,0.0,0.0],"up":[0.0,1.0,0.0],"direction":[0.0,0.0,1.0]}]:
		check(runtime.call("display_meshes",bad).is_empty() and _bytes(runtime) == before,"borrowed display validates finite explicit camera atomically")

func _failed_cache() -> void:
	var fx_script: Script = load("res://modules/scene_engine/fidelity_fx/presentation.gd")
	var saved: Variant = fx_script.get("_prepared_sources")
	if not check(saved is Dictionary,"native preparation cache owns actual templates"): return
	var source := "fx_cannon_fire_01.nif"
	var cache: Dictionary = saved.duplicate(); cache.erase(source)
	var asset: Dictionary = Fx._asset(source)
	fx_script.set("_prepared_sources",cache)
	Fx._assets[source] = {"name":source,"blocks":[],"roots":[]}
	var bad := Fx.new(); root.add_child(bad)
	check(not bad.configure(source,_options(17)) and not cache.has(source),"failed actual source preparation is never inserted into the native cache")
	Fx._assets[source] = asset
	var good := Fx.new(); root.add_child(good)
	check(good.configure(source,_options(17)) and cache.has(source),"repaired actual source successfully retries after a failed prepare")
	bad.dispose(); good.dispose(); bad.free(); good.free()
	fx_script.set("_prepared_sources",saved)

func _run() -> void:
	_waves = Waves.new(); _waves.configure(_height)
	_camera = Camera3D.new(); root.add_child(_camera); _camera.position = Vector3(0,12,25); _camera.look_at(Vector3.ZERO,Vector3.UP)
	for source: String in SOURCES: _caller(source,true)
	_caller("fx_cannon_fire_01.nif",false)
	var guard := Runtime.new()
	var factory_ready := check(guard.has_method("spawn_native"),"Runtime exposes native prepared factory")
	var display_ready := check(guard.has_method("display_meshes"),"Runtime exposes validated borrowed display records")
	if factory_ready and display_ready:
		for source: String in SOURCES: _factory(source); _display_ownership(source)
		_failed_cache()
	_camera.free()
	print("FIDELITY_FX_NATIVE_WORK_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
