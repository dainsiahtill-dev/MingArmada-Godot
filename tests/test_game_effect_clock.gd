extends SceneTree
## Game source consumers must select the original variable appTime clock.
## No fake replay/pool/mesh. Fire is a real public Practice command. Splash
## events below are labelled presentation fixtures, not ballistic-impact proof.
const Effects = preload("res://game/presentation/combat/combat_effects.gd")
const SourceFx = preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
const ActualRuntime = preload("res://modules/scene_engine/fidelity_fx/particle_runtime.gd")
const PracticeRuntime = preload("res://game/runtime/naval_practice_runtime.gd")
const STEP := 1.0/60.0
var assertions := 0
var failures := 0
var _camera: Camera3D
var _water_calls := 0
var _practice: RefCounted
var _effects: Node3D

func check(ok: bool, detail: String) -> bool:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL game effect clock: ",detail)
	return ok
func _initialize() -> void: _run.call_deferred()
func _height(_x: float,_z: float) -> float: return -80.0
func _water(_x: float,_z: float,time: float) -> float:
	_water_calls += 1
	return time*.2
func _sea(_x: float,_z: float) -> bool: return true

func _state(source: Node3D) -> Dictionary:
	var replay: RefCounted = source.get("_replay")
	return replay.call("source_state")
func _payload(source: Node3D) -> int:
	var result: Array = []
	for node: MeshInstance3D in source.get("_geometry").values():
		if node.visible and node.mesh != null:
			var surfaces: Array = []
			for index in node.mesh.get_surface_count(): surfaces.append(node.mesh.surface_get_arrays(index))
			result.append([node.global_transform,surfaces])
	return hash(result)

func _generic_water_payload() -> Dictionary:
	var water: Node3D = _effects.get("_water_splashes")
	var resources: Array = []
	var values: Array = []
	for splash: Dictionary in water.get("_splashes"):
		for key: String in ["ring","column","shell"]:
			var node: MeshInstance3D = splash[key]
			resources.append(node.mesh.get_instance_id() if node.mesh != null else 0)
			if node.mesh != null:
				for index in node.mesh.get_surface_count(): values.append(node.mesh.surface_get_arrays(index))
		var drops: MultiMesh = splash.drops.multimesh
		for index in drops.instance_count: values.append([drops.get_instance_transform(index),drops.get_instance_color(index)])
	return {"resources":resources,"geometry":hash(values),"accepted_time":water.get("_time")}

func _source_is_native(source: Node3D,label: String) -> bool:
	var diagnostics: Dictionary = source.call("diagnostics")
	check(diagnostics.get("render_unit", "") == "system", label+" uses one render carrier per original particle system")
	return check(String(diagnostics.get("time_input",{}).get("kind","")).begins_with("original variable-dt"),label+" selects original variable appTime rather than the offline observer")

func _tick(count: int) -> Dictionary:
	for i in count: _practice.advance(STEP)
	var native: Dictionary = _practice.snapshot().naval
	_effects.call("apply_snapshot",native,count*STEP)
	_effects.call("apply_events",_practice.drain_events())
	return native

func _public_fire() -> Dictionary:
	var receipt: Dictionary = _practice.command({"type":"fire","side":"port"})
	if not check(receipt.get("ok",false),"actual public Practice port-fire command is accepted"): return {}
	_practice.advance(STEP)
	var native: Dictionary = _practice.snapshot().naval
	var events: Array = _practice.drain_events()
	_effects.call("apply_snapshot",native,STEP)
	_effects.call("apply_events",events)
	var fires: Array = events.filter(func(event: Dictionary): return event.get("type") == "fire")
	if not check(not fires.is_empty() and not native.projectiles.is_empty(),"actual Encounter emits fire and retains authoritative projectiles"): return {}
	var owned: Array = _effects.get("_source_fire")
	if not check(not owned.is_empty(),"actual Effects.fire creates an owned eleven-layer SourceFx"): return {}
	return {"node":owned[0].node,"born":float(owned[0].time),"source":"fx_cannon_fire_01.nif","capacity":435,"native":native}

func _fixture_id(variant: int) -> String:
	for number in 100:
		var id := "game-clock-splash-fixture-%d"%number
		if 1+posmod(absi(id.hash()),3) == variant: return id
	return ""

func _splash_sources(native: Dictionary) -> Array:
	var events: Array = []
	for variant in range(1,4):
		# Canonical presentation-event fixture at the real accepted native time;
		# it exercises consumer/configuration ownership, not projectile collision.
		events.append({"type":"splash","id":_fixture_id(variant),"time":native.time,"position":{"x":variant*8.0,"y":0.0,"z":-9.0},"scale":1.0})
	_effects.call("apply_events",events)
	var water: Node3D = _effects.get("_water_splashes")
	var sources: Array = []
	for splash: Dictionary in water.get("_splashes"):
		if not splash.has("fidelity"): continue
		var source: Node3D = splash.reference
		var name: String = source.get("_source")
		var capacity: int = {"cannon_ball_splash_01.nif":82,"cannon_ball_splash_02.nif":85,"cannon_ball_splash_03.nif":79}.get(name,-1)
		sources.append({"node":source,"born":float(splash.time),"source":name,"capacity":capacity})
	check(sources.size() == 3,"actual Effects.splash route configures all three FidelityReferenceSplash source assets")
	var names: Array = []
	for entry: Dictionary in sources: names.append(entry.source)
	names.sort()
	check(names == ["cannon_ball_splash_01.nif","cannon_ball_splash_02.nif","cannon_ball_splash_03.nif"],"splash fixtures exercise each of the three distinct original assets")
	return sources

func _compare(sources: Array,native: Dictionary) -> void:
	for entry: Dictionary in sources:
		var source: Node3D = entry.node
		var age: float = float(native.time)-float(entry.born)
		if age != float(entry.oracle_last_age):
			entry.oracle.advance_native(age)
			entry.oracle_last_age = age
		var actual := _state(source)
		check(actual == entry.oracle.source_state(),"accepted native age %.6f matches direct original Runtime full capacity/RNG/world/bounds for %s"%[age,entry.source])
		var capacity := 0
		for system: Dictionary in actual.systems:
			capacity += int(system.capacity)
			check(system.particles.size() == int(system.capacity),"complete authored pool slots retained "+String(entry.source))
		check(capacity == int(entry.capacity),"game clock preserves original authored capacity "+String(entry.source))

func _study_default() -> void:
	var study := SourceFx.new(); root.add_child(study)
	if check(study.configure("fx_cannon_fire_01.nif",{"seed":17,"camera":_camera}),"Study default actual Presentation configures"):
		check(study.apply_snapshot(.1,.1),"Study default draws a bounded observer frame")
		check(String(study.diagnostics().time_input.kind).begins_with("canonical float32 120Hz"),"Study default keeps canonical observer mode")
		var observer := ActualRuntime.new(); observer.configure(SourceFx._asset("fx_cannon_fire_01.nif"),17); observer.seek(.1)
		check(_state(study) == observer.source_state(),"Study default still matches complete canonical observer state")
	study.dispose(); study.free()

func _game() -> void:
	_practice = PracticeRuntime.new()
	if not check(_practice.configure(_height,{"mode":"sail"}).get("ok",false),"actual continuous deep-water Practice configures"): return
	_effects = Effects.new(); root.add_child(_effects)
	_effects.call("set_camera",_camera); _effects.call("set_water_sampler",_water); _effects.call("set_surface_filter",_sea)
	var fire := _public_fire()
	if fire.is_empty(): return
	var sources: Array = [fire]
	sources.append_array(_splash_sources(fire.native))
	var native_count := 0
	for entry: Dictionary in sources:
		if _source_is_native(entry.node,String(entry.source)): native_count += 1
	# Semantic RED: no missing-field/method crash and no invented source state.
	if native_count != 4: return
	for entry: Dictionary in sources:
		var oracle := ActualRuntime.new()
		check(oracle.configure(SourceFx._asset(String(entry.source)),int(entry.node.get("_seed"))),"direct actual Runtime accepts unmodified source and event seed")
		oracle.advance_native(0.0) # Real game creation first records visibility.
		entry.oracle = oracle
		entry.oracle_last_age = 0.0
	check(absf(float(fire.native.time)-float(fire.born)-STEP) < 1.0e-10,"real fire event at native time zero first displays at accepted age about .0167")
	_compare(sources,fire.native) # Fire age STEP; splashes born at this snapshot have age 0.
	var native: Dictionary = _tick(1)
	check(absf(float(native.time)-float(fire.born)-2.0*STEP) < 1.0e-10,"one later native tick takes real fire age about .0333")
	_compare(sources,native)
	native = _tick(4); check(absf(float(native.time)-float(fire.born)-.1) < 1.0e-10,"third source frame takes real accepted age .1"); _compare(sources,native)
	native = _tick(18); check(absf(float(native.time)-float(fire.born)-.4) < 1.0e-10,"fourth source frame takes real accepted age .4"); _compare(sources,native)
	check(_practice.set_pause("player",true).get("ok",false),"actual Runtime accepts player pause")
	var frozen: Dictionary = _practice.snapshot()
	var states: Array = []; var payloads: Array = []
	for entry: Dictionary in sources: states.append(_state(entry.node)); payloads.append(_payload(entry.node))
	check(_practice.advance(1.0) == 0.0 and _practice.snapshot() == frozen,"wall interval under real pause leaves authoritative native state frozen")
	_effects.call("apply_snapshot",frozen.naval,1.0)
	for i in sources.size(): check(_state(sources[i].node) == states[i],"paused repeated owner presentation freezes complete source and bounds counter")
	var generic_water: Dictionary = _generic_water_payload()
	_camera.position.x += 6.0; _camera.look_at(Vector3.ZERO,Vector3.UP)
	# Actual game owner route: paused camera input must reach fidelity source
	# billboards without re-running generic water volume or native simulation.
	_effects.call("apply_snapshot",frozen.naval,0.0)
	for i in range(1,sources.size()):
		check(_payload(sources[i].node) != payloads[i],"same-time actual Effects owner forwards changed camera to splash billboard meshes "+String(sources[i].source))
		check(_state(sources[i].node) == states[i],"paused owner camera redraw preserves complete splash particles/RNG/world/bounds")
	check(_generic_water_payload() == generic_water,"same-time owner camera redraw reuses generic ring/column/shell mesh resources and droplet data")
	check(_practice.snapshot() == frozen,"owner camera redraw leaves actual paused native authority unchanged")
	var changed := false
	for i in sources.size():
		var entry: Dictionary = sources[i]
		check(entry.node.apply_snapshot(float(native.time)-float(entry.born),float(native.time)),"same-age real source redraw accepts changed camera")
		check(_state(entry.node) == states[i],"camera-only redraw never calls native advance or changes world/bounds/RNG")
		changed = changed or _payload(entry.node) != payloads[i]
	check(changed,"changed actual camera basis reprojects drawn source meshes")
	var water_changed := false
	var water_calls := _water_calls
	for i in range(1,sources.size()):
		var entry: Dictionary = sources[i]
		var before := _payload(entry.node)
		# Isolated SourceFx contract: accepted absolute water phase changes while
		# each source keeps its actual local age. This does not advance paused authority.
		check(entry.node.apply_snapshot(float(native.time)-float(entry.born),float(native.time)+1.0),"same particle age accepts a later explicit absolute water phase")
		check(_state(entry.node) == states[i],"absolute water reprojection freezes complete original particle state")
		water_changed = water_changed or _payload(entry.node) != before
	check(_water_calls > water_calls and water_changed,"actual authored splash meshes sample new water phase and move without particle advancement")
	check(_practice.snapshot() == frozen,"camera and water projection checks leave actual paused authority unchanged")
	var old_nodes: Array = []
	for entry: Dictionary in sources: old_nodes.append(entry.node)
	var old_battle: String = native.battleId
	check(_practice.command({"type":"restart"}).get("ok",false),"actual public restart creates new Practice epoch")
	var restarted: Dictionary = _practice.snapshot().naval
	check(restarted.time == 0.0 and restarted.battleId != old_battle,"new epoch restarts actual native clock and identity")
	_effects.call("apply_snapshot",restarted,0.0)
	check(_effects.call("diagnostics").source_fire == 0 and _effects.call("diagnostics").splashes == 0,"new native epoch clears both actual effect owners")
	for node: Variant in old_nodes: check(not is_instance_valid(node),"new epoch releases old source object and particle state")
	var fresh := _public_fire()
	if not fresh.is_empty():
		check(_source_is_native(fresh.node,"new-epoch fire"),"fresh epoch source keeps original clock mode")
		var oracle := ActualRuntime.new(); oracle.configure(SourceFx._asset("fx_cannon_fire_01.nif"),int(fresh.node.get("_seed"))); oracle.advance_native(0.0)
		var fresh_age: float = float(fresh.native.time)-float(fresh.born)
		if fresh_age != 0.0: oracle.advance_native(fresh_age)
		check(_state(fresh.node) == oracle.source_state(),"new epoch matches fresh visibility anchor followed by its actual first accepted fire age without prior particles/counters")
		var fresh_splashes: Array = _splash_sources(fresh.native)
		_tick(240)
		check(_effects.call("diagnostics").source_fire == 0 and not is_instance_valid(fresh.node),"finite source clip releases actual fire owner and its mesh/pool state")
		for entry: Dictionary in fresh_splashes: check(not is_instance_valid(entry.node),"finite splash lifetime releases its actual source owner and complete pool")

func _run() -> void:
	_camera = Camera3D.new(); root.add_child(_camera); _camera.position = Vector3(0,12,25); _camera.look_at(Vector3.ZERO,Vector3.UP)
	_game(); _study_default()
	if is_instance_valid(_effects): _effects.call("dispose"); _effects.free()
	if _practice: _practice.dispose()
	_camera.free()
	print("GAME_EFFECT_CLOCK_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
