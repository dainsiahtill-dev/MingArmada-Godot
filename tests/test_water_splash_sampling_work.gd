extends SceneTree
## Real public cannon events, complete render/state bytes, deterministic work
## budgets. Legacy bypasses only the owner memo seam; source rules stay shared.
const Water = preload("res://game/presentation/water/water_splashes.gd")
const Runtime = preload("res://game/runtime/naval_practice_runtime.gd")
const STEP := 1.0/60.0

class Queries:
	extends RefCounted
	var mode := "all"
	var cutoff := 1.5
	var scope := "outside"
	var calls := 0
	var keys := {}
	var scopes := {}
	func reset() -> void: calls = 0; keys.clear(); scopes.clear(); scope = "outside"
	func sea(x: float,z: float) -> bool:
		# Keys retain exact double components; this observes calls without
		# imposing any quantized spatial key on the production implementation.
		var key := PackedByteArray(); key.resize(16)
		key.encode_double(0,x); key.encode_double(8,z)
		calls += 1; keys[key] = true
		if not scopes.has(scope): scopes[scope] = {"calls":0,"keys":{}}
		scopes[scope].calls += 1; scopes[scope].keys[key] = true
		return true if mode == "all" else (false if mode == "none" else x < cutoff)

class ObservedOwner:
	extends "res://game/presentation/water/water_splashes.gd"
	var query: Queries
	var serial := 0
	func _update(splash: Dictionary,age: float) -> void:
		var previous := query.scope
		query.scope = "update-%d"%serial; serial += 1
		super._update(splash,age)
		query.scope = previous

class LegacyOwner:
	extends ObservedOwner
	# Extra method is harmless before implementation: the current production
	# does not call it, so missing memo produces counted RED, not parser errors.
	func _sample_sea(x: float,z: float) -> bool:
		return not _surface_filter.is_valid() or bool(_surface_filter.call(x,z))

var assertions := 0
var failures := 0
var _runtime: RefCounted
var _camera: Camera3D
var _events: Array = []
var _authority: PackedByteArray

func check(ok: bool,detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL water sampling work: ",detail)
func _ground(_x: float,_z: float) -> float: return -80.0
func _actual_events() -> void:
	_runtime = Runtime.new()
	check(_runtime.configure(_ground,{"mode":"sail"}).get("ok",false),"actual three-ship public free-sail fixture configures")
	for i: int in 60: _runtime.advance(STEP); _runtime.drain_events()
	check(_runtime.command({"type":"fire","side":"port"}).get("ok",false),"public Runtime accepts actual healthy four-cannon broadside")
	var fires := []
	for i: int in 600:
		_runtime.advance(STEP)
		for event: Dictionary in _runtime.drain_events():
			if event.get("type") == "fire": fires.append(event)
			if event.get("type") == "splash": _events.append(event)
		if _events.size() == 4: break
	check(fires.size() == 4 and _events.size() == 4,"four actual scheduled guns produce four original splash payloads")
	for event: Dictionary in _events:
		check(fires.any(func(f: Dictionary): return f.projectileId == event.projectileId),"measured splash retains public cannon projectile lineage")
	_authority = var_to_bytes(_runtime.snapshot())

func _uniforms(material: Material) -> Dictionary:
	var values := {}
	if not material is ShaderMaterial or material.shader == null: return values
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		var name := String(uniform.name)
		var value: Variant = material.get_shader_parameter(name)
		if value is Resource: value = {"class":value.get_class(),"path":value.resource_path}
		values[name] = value
	return values
func _walk(node: Node,records: Array) -> void:
	if node is Node3D:
		var record := {"class":node.get_class(),"transform":node.transform,"visible":node.visible,"children":node.get_child_count()}
		if node is MeshInstance3D:
			var surfaces := []
			if node.mesh:
				for i: int in node.mesh.get_surface_count(): surfaces.append(node.mesh.surface_get_arrays(i))
			record.surfaces = surfaces
			record.material = _uniforms(node.material_override) if node.material_override else {}
		if node is MultiMeshInstance3D and node.multimesh:
			var instances := []
			for i: int in node.multimesh.instance_count: instances.append([node.multimesh.get_instance_transform(i),node.multimesh.get_instance_color(i)])
			record.instances = instances
		records.append(record)
	for child: Node in node.get_children(): _walk(child,records)
func _geometry(owner: Node3D) -> PackedByteArray:
	var records := []
	for child: Node in owner.get_children(): _walk(child,records)
	return var_to_bytes(records)
func _state(owner: Node3D) -> PackedByteArray:
	var records := []
	for splash: Dictionary in owner.get("_splashes"):
		var state := {"origin":splash.origin,"time":splash.time,"birth":splash.birth_origin,"seed":splash.seed,"scale":splash.scale,"activeDrops":splash.active_drops,"dropletPositions":splash.droplet_positions}
		if splash.has("fidelity"):
			var source: RefCounted = splash.reference.get("_replay")
			state.native = source.call("source_state")
		records.append(state)
	return var_to_bytes(records)
func _pair() -> Dictionary:
	var a := ObservedOwner.new(); var b := LegacyOwner.new()
	var qa := Queries.new(); var qb := Queries.new()
	a.query = qa; b.query = qb; root.add_child(a); root.add_child(b)
	for owner: Node3D in [a,b]:
		owner.configure(_runtime.sample_water_height); owner.configure_reference_backend(_camera)
	a.configure_surface_filter(qa.sea); b.configure_surface_filter(qb.sea)
	for event: Dictionary in _events:
		for owner: Node3D in [a,b]: owner.apply_snapshot(float(event.time)); owner.add_event(event)
	check(a.get("_splashes").size() == 4 and b.get("_splashes").size() == 4,"actual Water owners retain four original impacts and full reference children")
	return {"memo":a,"legacy":b,"memoQueries":qa,"legacyQueries":qb}
func _budgets(pair: Dictionary,label: String,require_repeated_legacy: bool) -> void:
	var qa: Queries = pair.memoQueries; var qb: Queries = pair.legacyQueries
	check(qa.keys == qb.keys,label+" queries exactly the same original XZ set")
	var legacy_repeated := false
	for scope: String in qa.scopes:
		var stats: Dictionary = qa.scopes[scope]
		check(int(stats.calls) == stats.keys.size(),label+" original predicate is called once per exact XZ within "+scope)
	for scope: String in qb.scopes:
		var stats: Dictionary = qb.scopes[scope]
		if scope.begins_with("update-") and int(stats.calls) > stats.keys.size(): legacy_repeated = true
	if require_repeated_legacy: check(legacy_repeated,label+" legacy fixture exercises repeated ring/column/shell/drop/source sea requests")
func _round(pair: Dictionary,now: float,label: String,repeated: bool = true) -> void:
	pair.memoQueries.reset(); pair.legacyQueries.reset()
	pair.memo.apply_snapshot(now); pair.legacy.apply_snapshot(now)
	check(_geometry(pair.memo) == _geometry(pair.legacy),label+" complete mesh/UV/color/instance/transform/material bytes match legacy")
	check(_state(pair.memo) == _state(pair.legacy),label+" complete source pool/RNG/bounds and droplets match legacy")
	_budgets(pair,label,repeated)
func _visible_sources(owner: Node3D) -> int:
	var count := 0
	for splash: Dictionary in owner.get("_splashes"):
		if not splash.has("fidelity"): continue
		for node: MeshInstance3D in splash.reference.get("_geometry").values():
			if node.visible: count += 1
	return count
func _dispose(pair: Dictionary) -> void:
	for owner: Node3D in [pair.memo,pair.legacy]:
		owner.dispose(); owner.dispose(); check(owner.get_child_count() == 0,"idempotent disposal releases all owned source/carrier geometry")
		owner.free()
func _run() -> void:
	_actual_events()
	if _events.size() != 4: _finish(); return
	var original_events := var_to_bytes(_events)
	_camera = Camera3D.new(); root.add_child(_camera)
	_camera.position = Vector3(33.0,27.0,43.0); _camera.look_at(Vector3(0.0,0.0,-220.0),Vector3.UP)
	var pair := _pair()
	var born: float = _events[-1].time
	_round(pair,born+0.2,"new accepted .2")
	_round(pair,born+0.4,"next accepted .4")
	_round(pair,born+0.6,"next accepted .6")
	var frozen_geometry := _geometry(pair.memo); var frozen_state := _state(pair.memo)
	_round(pair,born+0.6,"unchanged accepted input",false)
	check(pair.memoQueries.calls == 0 and pair.legacyQueries.calls == 0,"paused unchanged camera makes no additional sea queries")
	check(_geometry(pair.memo) == frozen_geometry and _state(pair.memo) == frozen_state,"unchanged pause freezes geometry and full source state")
	_camera.position += Vector3(3.0,2.0,0.0); _camera.look_at(Vector3(0.0,0.0,-220.0),Vector3.UP)
	_round(pair,born+0.6,"paused camera-only reprojection",false)
	check(pair.memoQueries.calls > 0,"camera-only source render obtains fresh predicate results rather than using prior snapshot memo")
	check(_state(pair.memo) == frozen_state,"camera-only sampling does not advance source RNG/pools or droplets")
	pair.memoQueries.mode = "coast"; pair.legacyQueries.mode = "coast"
	pair.memo.configure_surface_filter(pair.memoQueries.sea); pair.legacy.configure_surface_filter(pair.legacyQueries.sea)
	_round(pair,born+0.7,"hard partial coastline")
	check(_visible_sources(pair.memo) > 0,"partial hard coastline retains some original source meshes")
	pair.memoQueries.mode = "none"; pair.legacyQueries.mode = "none"
	pair.memo.configure_surface_filter(pair.memoQueries.sea); pair.legacy.configure_surface_filter(pair.legacyQueries.sea)
	_round(pair,born+0.7,"same-time replacement with dry filter",false)
	check(pair.memoQueries.calls > 0 and _visible_sources(pair.memo) == 0,"new filter revision at same age freshly hides all source geometry")
	_round(pair,born+0.8,"accepted fully dry filter",false)
	for splash: Dictionary in pair.memo.get("_splashes"):
		check(splash.ring.mesh.get_surface_count() == 0 and int(splash.active_drops) == 0,"fully dry predicate rejects ring triangles and every visible generic droplet")
	pair.memoQueries.mode = "all"; pair.legacyQueries.mode = "all"
	pair.memo.configure_surface_filter(pair.memoQueries.sea); pair.legacy.configure_surface_filter(pair.legacyQueries.sea)
	_round(pair,born+0.8,"same-time restore sea filter",false)
	check(pair.memoQueries.calls > 0 and _visible_sources(pair.memo) > 0,"same-time restored predicate does not reuse cached dry answers")
	pair.memo.configure_surface_filter(Callable()); pair.legacy.configure_surface_filter(Callable())
	_round(pair,born+0.9,"invalid filter preserves unfiltered path",false)
	check(pair.memoQueries.calls == 0 and pair.legacyQueries.calls == 0,"invalid external filter skips predicate calls entirely")
	_round(pair,born-1.0,"native rewind clears owners",false)
	check(pair.memo.get_child_count() == 0,"rewind clears all cached source/carrier ownership")
	_dispose(pair)
	check(var_to_bytes(_events) == original_events,"all original authority event payloads remain immutable")
	check(var_to_bytes(_runtime.snapshot()) == _authority,"all sampling work preserves Runtime authority and native time")
	_finish()
func _finish() -> void:
	if _runtime: _runtime.dispose()
	if is_instance_valid(_camera): _camera.free()
	print("WATER_SPLASH_SAMPLING_WORK assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
func _initialize() -> void: _run.call_deferred()
