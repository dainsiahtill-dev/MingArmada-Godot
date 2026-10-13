extends SceneTree
## Actual six source hulls and real destruction events. Missing new APIs fail
## semantically; every expected anchor is derived independently from deck support.
const Ship = preload("res://game/presentation/ships/ship_view.gd")
const Deck = preload("res://game/presentation/crew/deck_stations.gd")
const Effects = preload("res://game/presentation/combat/combat_effects.gd")
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
const KINDS := ["fuchuan", "fisherman", "merchant", "voc", "patrol", "heavy"]
const BORN := 2.25
const LIFT := 0.35
var assertions := 0
var failures := 0

func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL destruction birth anchor: ", detail)

func _initialize() -> void:
	_run.call_deferred()

func wire(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}

func point(value: Dictionary) -> Vector3:
	return Vector3(value.x, value.y, value.z)

func _base(kind: String) -> Dictionary:
	return Encounter.new({"ships": [{"id": "player", "kind": kind, "team": "player", "position": {"x": 0.0, "z": 0.0}, "sailDeployment": 0.0}], "wind": {"direction": {"x": 1.0, "y": 0.0}, "speed": 0.0}, "oceanWaves": [], "sampleTerrainHeight": func(_x: float, _z: float) -> float: return -80.0}).snapshot().ships[0]

func _state(base: Dictionary, seconds: float, index: int, dead: bool = false) -> Dictionary:
	var ship := base.duplicate(true)
	ship.time = seconds
	ship.hull = 0.0 if dead else base.maxHull
	ship.visual.position = wire(Vector3(3.0 + index * 0.8, 0.4 + index * 0.1, -2.0 - index * 0.3))
	ship.visual.heading = 0.43
	ship.visual.pitch = 0.08
	ship.visual.heel = -0.11
	return ship

func _watch(view: Node3D) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	view.presentation_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	return events

func _event(events: Array[Dictionary], kind: String) -> Dictionary:
	var matching: Array = events.filter(func(event: Dictionary): return event.type == kind)
	check(matching.size() == 1, kind + " is emitted exactly once")
	return matching[0] if matching.size() == 1 else {}

func _models(view: Node3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for model: Node3D in view.get("_models"): result.append(model.transform)
	return result

func _pure_transform(view: Node3D, at: float, expected: Transform3D, label: String) -> void:
	var damage: RefCounted = view.get("_damage")
	check(damage.has_method("model_transform_at"), label + " exposes the pure birth-time model transform resolver")
	if not damage.has_method("model_transform_at"): return
	var before := _models(view)
	var diagnostics: Dictionary = view.damage_diagnostics()
	var sent: Dictionary = damage.get("_sent").duplicate(true)
	var resolved: Variant = damage.call("model_transform_at", view.get("_models")[0], at)
	check(resolved is Transform3D, label + " resolves a real model transform instead of mutating its node")
	if resolved is Transform3D:
		check(resolved.is_equal_approx(expected), label + " analytical sinking pose matches the independently presented source model at that time")
	check(_models(view) == before and view.damage_diagnostics() == diagnostics and damage.get("_sent") == sent, label + " birth-time query preserves every current model pose, damage clock and event receipt")

func _exercise(kind: String, library: RefCounted) -> void:
	var host := Node3D.new()
	host.transform = Transform3D(Basis.from_euler(Vector3(0.17, -0.31, 0.23)).scaled_local(Vector3(1.2, 0.9, 1.1)), Vector3(12.0, 4.0, -9.0))
	root.add_child(host)
	var eager := Ship.new()
	var delayed := Ship.new()
	host.add_child(eager)
	host.add_child(delayed)
	check(eager.configure(kind, library) and delayed.configure(kind, library), "actual source models configure for " + kind)
	if eager.get_model() == null or delayed.get_model() == null:
		eager.dispose(); delayed.dispose(); host.free()
		return
	for view: Node3D in [eager, delayed]:
		view.scale = Vector3(0.9, 1.2, 1.05)
		view.get("_models")[0].transform = Transform3D(Basis.from_euler(Vector3(0.04, 0.13, -0.08)).scaled_local(Vector3(0.96, 1.04, 0.98)), Vector3(0.3, 0.7, -0.2))
		view.get("_damage").configure(view.get("_models"))
	var model: Node3D = eager.get("_models")[0]
	var rest := model.transform
	_pure_transform(eager, 50.0, rest, kind + " healthy rest")
	var deck := Deck.new()
	check(deck.configure(kind, model), kind + " provides actual source hull support")
	var support: Dictionary = deck.sample(0.0, 0.0)
	check(not support.is_empty(), kind + " centre samples a real source hull triangle")
	if support.is_empty():
		eager.dispose(); delayed.dispose(); host.free()
		return
	var anchor: Vector3 = support.point + Vector3.UP * LIFT
	check(absf(anchor.y - float(support.point.y) - 0.35) < 1.0e-6, kind + " lift is relative to sampled support rather than a fixed world +3m")
	var base := _base(kind)
	var eager_events := _watch(eager)
	var late_events := _watch(delayed)
	for view: Node3D in [eager, delayed]:
		view.apply_snapshot(_state(base, 0.0, 0), {}, 0.0)
		view.apply_snapshot(_state(base, 2.0, 0, true), {}, 0.0)
	var displayed := delayed.global_transform
	var model_displayed := _models(delayed)
	var damage_before: Dictionary = delayed.damage_diagnostics()
	var expected := Vector3.ZERO
	var born_model := Transform3D.IDENTITY
	var history_frame := Transform3D.IDENTITY
	for index in range(1, 7):
		var seconds := 2.0 + index * 0.05
		var state := _state(base, seconds, index, true)
		eager.apply_snapshot(state, {}, 0.05)
		if index == 4: history_frame = eager.global_transform
		if index == 5:
			born_model = eager.get("_models")[0].transform
			expected = eager.global_transform * born_model * anchor
		# Deliberately omit the exact birth sample: its ship frame must be
		# interpolated between 2.20 and 2.30 while the damage pose is analytical.
		else:
			var immutable := state.duplicate(true)
			delayed.remember_authoritative_pose(state, seconds)
			check(state == immutable, kind + " accepted pose history preserves the native snapshot")
	check(delayed.global_transform == displayed and _models(delayed) == model_displayed and delayed.damage_diagnostics() == damage_before, kind + " pose-only capture does not advance drawn models or damage")
	var record: Dictionary = {}
	for entry: Dictionary in delayed.get("_source_poses"):
		if absf(float(entry.time) - 2.2) < 1.0e-8: record = entry
	check(record.get("ship_transform") is Transform3D, kind + " accepted history keeps the separate authoritative global ship frame")
	if record.get("ship_transform") is Transform3D:
		check(record.ship_transform.is_equal_approx(history_frame), kind + " remembered ship frame includes the actual parent, scale and heel without a model-root offset")
	var on_time := _event(eager_events, "destruction-explosion")
	check(on_time.has("source_effect_position"), kind + " on-time destruction carries a captured source effect point")
	if on_time.has("source_effect_position"):
		check(point(on_time.source_effect_position).distance_to(expected) < 0.001, kind + " on-time smoke comes from sampled deck support in its born sinking model frame")
	var late_state := _state(base, 2.6, 13, true)
	late_state.visual.heading = 0.91
	late_state.visual.pitch = -0.22
	late_state.visual.heel = 0.28
	delayed.apply_snapshot(late_state, {}, 0.6)
	var late := _event(late_events, "destruction-explosion")
	check(late.has("source_effect_position"), kind + " delayed destruction retains its captured birth point")
	if late.has("source_effect_position"):
		check(point(late.source_effect_position).distance_to(expected) < 0.001, kind + " delayed smoke matches on-time birth despite changed ship transform, heel and current sinking pose")
	if not late.is_empty():
		check(absf(float(late.time) - BORN) < 1.0e-8 and point(late.position).distance_to(delayed.global_position) < 0.001, kind + " presentation adaptation preserves original event time and current native root fallback")
	check((delayed.global_transform * delayed.get("_models")[0].transform * anchor).distance_to(expected) > 0.1, kind + " fixture distinguishes the wrong current model frame from the original birth frame")
	_pure_transform(delayed, BORN, born_model, kind + " delayed past birth")
	delayed.apply_snapshot(_state(base, 3.5, 17, true), {}, 0.9)
	var froth := _event(late_events, "sinking-froth")
	check(not froth.has("source_effect_position"), kind + " surface froth keeps its separate water placement contract")
	delayed.apply_snapshot(_state(base, 0.5, -2), {}, 0.0)
	check(delayed.call("_source_pose_at", BORN) == null, kind + " rewind discards future source pose history")
	check(delayed.configure(kind, library), kind + " explicit reconfigure succeeds")
	check(delayed.get("_source_poses").is_empty(), kind + " reconfigure clears previous source history")
	late_events.clear()
	delayed.apply_snapshot(_state(base, 10.0, 2, true), {}, 0.0)
	check(late_events.is_empty(), kind + " loading an already dead hull does not invent historical destruction events")
	# Let real accepted history expire beyond its existing four-second bound.
	check(delayed.configure(kind, library), kind + " bounded-history fixture reconfigures")
	late_events.clear()
	delayed.apply_snapshot(_state(base, 0.0, 0), {}, 0.0)
	delayed.apply_snapshot(_state(base, 2.0, 0, true), {}, 0.0)
	for index in range(1, 46):
		delayed.remember_authoritative_pose(_state(base, 2.0 + index * 0.1, index, true), 2.0 + index * 0.1)
	delayed.apply_snapshot(_state(base, 6.5, 45, true), {}, 4.5)
	var missing_history := _event(late_events, "destruction-explosion")
	check(not missing_history.has("source_effect_position"), kind + " an unavailable old birth frame does not fabricate a captured effect point")
	if not missing_history.is_empty(): check(point(missing_history.position).distance_to(delayed.global_position) < 0.001, kind + " missing history retains the explicit current root fallback")
	eager.dispose(); delayed.dispose(); host.free()

func _water(_x: float, _z: float, _seconds: float) -> float:
	return 0.0

func _effects_contract() -> void:
	var effects := Effects.new()
	root.add_child(effects)
	effects.set_water_sampler(_water)
	effects.apply_snapshot({"time": 20.06, "projectiles": []}, 0.0)
	var native := Vector3(1.0, 0.2, 2.0)
	var captured := Vector3(6.0, 8.0, 10.0)
	var event := {"id": "captured-destruction", "type": "destruction-explosion", "time": 20.0, "position": wire(native), "source_effect_position": wire(captured)}
	var immutable := event.duplicate(true)
	effects.apply_events([event, event])
	check(effects.get("_puffs").size() == 9, "captured destruction still creates the original finite flash and eight smoke nodes once")
	for puff: Dictionary in effects.get("_puffs"):
		check(puff.origin.distance_to(captured) < 0.001, "actual destruction flash and smoke consume the captured source effect position")
	check(event == immutable and point(event.position) == native, "CombatEffects preserves native destruction position and payload")
	var hit := {"id": "native-hit", "type": "hit", "time": 20.0, "position": wire(native), "source_effect_position": wire(captured)}
	effects.apply_events([hit])
	for index in range(9, effects.get("_puffs").size()):
		check(effects.get("_puffs")[index].origin == native, "hit fragments are not shifted by the destruction-only field")
	var muzzle := Vector3(12.0, 3.0, 15.0)
	effects.apply_events([{"id": "native-fire", "type": "fire", "time": 20.0, "position": wire(native), "source_muzzle_position": wire(muzzle), "source_effect_position": wire(captured), "velocity": {"x": 0.0, "y": 0.0, "z": 20.0}}])
	var sources: Array = effects.diagnostics().source_effects
	check(sources.size() == 1 and sources[0].origin == muzzle, "cannon fire keeps its established captured source muzzle contract")
	effects.apply_events([{"id": "native-froth", "type": "sinking-froth", "time": 20.0, "position": wire(native), "source_effect_position": wire(captured)}])
	var splashes: Array = effects.get("_water_splashes").get("_splashes")
	check(splashes.size() == 1 and splashes[0].origin == Vector2(native.x, native.z), "surface-only sinking froth keeps native horizontal water coordinates")
	var captured_only := {"id": "captured-without-native-root", "type": "destruction-explosion", "time": 20.0, "source_effect_position": wire(captured)}
	var captured_only_before := captured_only.duplicate(true)
	var puffs_before: int = effects.get("_puffs").size()
	effects.apply_events([captured_only])
	var puffs_after: Array = effects.get("_puffs")
	check(puffs_after.size() == puffs_before + 9, "captured destruction without optional native position creates all nine finite puffs")
	for index in range(puffs_before, puffs_after.size()):
		check(puffs_after[index].origin.distance_to(captured) < 0.001, "optional-root destruction uses the captured origin for each new flash and smoke layer")
	check(captured_only == captured_only_before and not captured_only.has("position"), "captured-only destruction keeps its immutable payload and absent optional native position")
	effects.dispose(); effects.free()

func _run() -> void:
	var library := Library.new()
	for kind: String in KINDS: _exercise(kind, library)
	library.dispose()
	_effects_contract()
	print("DESTRUCTION_BIRTH_ANCHOR_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
