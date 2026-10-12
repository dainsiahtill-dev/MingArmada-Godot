extends SceneTree
## Consumer contracts for Pirates source vessels in the playable naval renderer.
## Catches wrong source routing, reversed course/side, visual fire detached from
## authoritative guns, absent deck crews, and presentation rewriting native state.

const PROVIDER_PATH := "res://modules/scene_engine/assets/ship_model_provider.gd"
const ShipView = preload("res://game/presentation/ships/ship_view.gd")
const CrewView = preload("res://game/presentation/crew/crew_view.gd")
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
const Practice = preload("res://game/scenes/naval_practice/naval_practice.gd")
const CASES := [
	{"kind":"fuchuan", "source":"barque", "length":32.0, "width":9.0, "guns":4},
	{"kind":"fisherman", "source":"sloop1", "length":14.0, "width":4.2, "guns":0},
	{"kind":"merchant", "source":"ship_merman", "length":36.0, "width":10.0, "guns":0},
	{"kind":"voc", "source":"frigate", "length":40.0, "width":11.0, "guns":4},
	{"kind":"patrol", "source":"ship_brigantine", "length":24.0, "width":6.0, "guns":3},
	{"kind":"heavy", "source":"treasure_galleon", "length":52.0, "width":14.5, "guns":8},
]
var assertions := 0
var failures := 0
var _original_muzzles: Dictionary = {}

func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", detail)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	check(ResourceLoader.exists(PROVIDER_PATH), "playable ships require the Pirates source provider")
	if not ResourceLoader.exists(PROVIDER_PATH):
		_finish()
		return
	var library := Library.new()
	for row: Dictionary in CASES:
		_test_vessel(row, library)
		print("REFERENCE_SHIP_GAME_PHASE model=", row.kind, " elapsed_ms=", Time.get_ticks_msec())
	library.dispose()
	await _test_playable_entries()
	_finish()

func _encounter(kind: String, heading: float = 0.0) -> RefCounted:
	# Heading zero points +X. At PI/2 it points +Z; starboard is respectively
	# +Z and -X. These literal positions put the target on the real broadside.
	var target := {"x":12.5, "z":76.0} if heading == 0.0 else {"x":-97.5, "z":-34.0}
	return Encounter.new({"referenceHandling":true, "referenceGunnery":true,
		"ships":[{"id":"player", "kind":kind, "team":"player", "heading":heading,
			"position":{"x":12.5, "z":-34.0}, "sailDeployment":0.0},
			{"id":"enemy", "kind":"voc", "team":"hostile", "position":target, "sailDeployment":0.0}],
		"wind":{"direction":{"x":1.0, "y":0.0}, "speed":0.0}, "oceanWaves":[],
		"sampleTerrainHeight":func(_x: float, _z: float)->float:return -80.0})

func _test_vessel(row: Dictionary, library: RefCounted) -> void:
	var encounter := _encounter(row.kind)
	var native: Dictionary = encounter.snapshot()
	var vessel: Dictionary = native.ships[0].duplicate(true)
	vessel.time = native.time
	var view := ShipView.new()
	root.add_child(view)
	var loaded := view.configure(row.kind, library)
	check(loaded, "actual game model loads: " + row.kind)
	if not loaded:
		view.free()
		return
	check(view.has_method("source_kind"), "playable renderer exposes its confirmed source: " + row.kind)
	if view.has_method("source_kind"):
		check(view.call("source_kind") == row.source, "game kind selects its distinct real source: " + row.kind)
	var model: Node3D = view.get_model()
	check(model.get_meta("source_family", "") == row.source and model.get_meta("model_origin", "") == "pirates_native_lowend", "actual rendered model carries source provenance: " + row.kind)
	check(model.get_meta("source_path", "") == "res://assets/models/fidelity_naval/%s.glb" % row.source, "rendered source resolves to converted original geometry: " + row.kind)
	check(_triangle_count(model) > 100, "real source geometry renders rather than an empty proxy: " + row.kind)
	_test_source_sail_inflation(model, row.kind)
	_test_original_cannon_rest(model, row.kind, library)
	check(vessel.dimensions.length == row.length and vessel.dimensions.width == row.width and vessel.cannonsPerSide == row.guns, "appearance selection preserves authoritative dimensions and battery: " + row.kind)
	var untouched := vessel.duplicate(true)
	view.apply_snapshot(vessel, native.wind, 0.0)
	var point: Dictionary = vessel.visual.position
	check(view.position.is_equal_approx(Vector3(point.x, point.y, point.z)), "source waterline uses the actual authoritative pose: " + row.kind)
	check((view.basis * Vector3.FORWARD * -1.0).is_equal_approx(Vector3.RIGHT), "heading zero places source bow on world +X: " + row.kind)
	check((view.basis * Vector3.LEFT).is_equal_approx(Vector3.BACK), "heading zero places source starboard on world +Z: " + row.kind)
	var crosswind := {"direction":{"x":0.0, "y":1.0}, "speed":18.0}
	var saved_wind := crosswind.duplicate(true)
	view.apply_snapshot(vessel, crosswind, 0.0)
	view.apply_snapshot(vessel, {"direction":{"x":0.0, "y":-1.0}, "speed":18.0}, 0.0)
	check(vessel == untouched and crosswind == saved_wind and encounter.snapshot() == native, "wind and rendering cannot rewrite native motion, rig, crew or damage: " + row.kind)
	var pose := view.transform
	view.apply_snapshot(vessel, crosswind, 0.0)
	check(view.transform.is_equal_approx(pose), "paused repeated presentation keeps authoritative pose: " + row.kind)
	var crew := CrewView.new()
	view.add_child(crew)
	var has_deck := crew.configure(row.kind, view.get_model(), library)
	check(has_deck, "actual source deck accepts visible native crew: " + row.kind)
	if has_deck:
		crew.apply_snapshot(vessel, native.wind, 0.0)
		check(crew.get_visible_count() > 0 and crew.get_visible_count() <= 24, "actual source produces bounded deck personnel: " + row.kind)
		var original_triangles := _rendered_deck_triangles(model)
		check(not original_triangles.is_empty(), "actual renderer exposes original structural deck triangles: " + row.kind)
		for instance: Dictionary in crew.get_instances():
			# Read the submitted original meshes independently of Crew.sample_deck.
			# A flat fabricated support returned by the adapter cannot satisfy this.
			var feet: Vector3 = instance.root.global_position
			var height := _original_triangle_height(original_triangles, feet)
			check(is_finite(height), "drawn crew retain source triangle contact: " + row.kind)
			if is_finite(height):
				check(absf(feet.y - height - 0.005) < 0.05, "drawn feet occupy actual transformed original deck: " + row.kind)
	for distance: float in [300.0, 700.0, 0.0]:
		var previous := view.get_model()
		view.set_lod_distance(distance)
		var active: Node3D = view.get_model()
		check(active.get_meta("source_family", "") == row.source and active.visible and _triangle_count(active) > 100, "distance retains actual source rendering: %s %s" % [row.kind, distance])
		if has_deck:
			check(crew.set_ship_model(active), "LOD keeps source deck contact available: " + row.kind)
		if distance == 300.0:
			check(active != previous, "each source LOD owns an independent active model: " + row.kind)
	crew.dispose()
	crew.free()
	_test_real_fire(view, encounter, row)
	var quarter := _encounter(row.kind, PI / 2.0)
	var quarter_ship: Dictionary = quarter.snapshot().ships[0]
	quarter_ship.time = 1.0
	view.apply_snapshot(quarter_ship, quarter.snapshot().wind, 0.0)
	check((view.basis * Vector3.BACK).is_equal_approx(Vector3.BACK), "heading PI/2 places source bow on world +Z: " + row.kind)
	check((view.basis * Vector3.LEFT).is_equal_approx(Vector3.LEFT), "heading PI/2 places source starboard on world -X: " + row.kind)
	_test_real_fire(view, quarter, row)
	var damaged := quarter_ship.duplicate(true)
	damaged.time = 2.0
	damaged.sail = 0.0
	var damage_input := damaged.duplicate(true)
	view.apply_snapshot(damaged, quarter.snapshot().wind, 0.0)
	var sails: Array[Node] = view.get_model().find_children("sail_*", "MeshInstance3D", true, false)
	check(not sails.is_empty(), "actual source has damageable original sail panels: " + row.kind)
	for sail: MeshInstance3D in sails:
		for surface in sail.mesh.get_surface_count():
			var material := sail.get_active_material(surface)
			check(material is ShaderMaterial and material.get_shader_parameter("damage_stage") == 4.0, "authoritative sail loss damages every visible original material slot: " + row.kind)
	check(damaged == damage_input, "source sail damage consumes state without settling damage twice: " + row.kind)
	view.dispose()
	view.free()

func _test_real_fire(view: Node3D, encounter: RefCounted, row: Dictionary) -> void:
	var before: Dictionary = encounter.snapshot()
	var receipt: Dictionary = encounter.command({"type":"fire", "side":"starboard"})
	var events: Array = encounter.drain_events().filter(func(event: Dictionary)->bool:return event.type == "fire" and event.shipId == "player")
	if row.guns == 0:
		check(not receipt.ok and events.is_empty() and encounter.snapshot() == before, "unarmed game kind cannot gain cannons from western appearance: " + row.kind)
		return
	check(receipt.ok and events.size() == 1, "actual authoritative broadside supplies its first original-model shot: " + row.kind)
	if events.is_empty():
		return
	var ship: Dictionary = encounter.snapshot().ships[0]
	ship.time = before.time
	view.apply_snapshot(ship, before.wind, 0.0)
	var barrels: Array[Node] = view.get_model().find_children("barrel_starboard_*", "Node3D", true, false)
	var rests: Dictionary = {}
	var global_rests: Dictionary = {}
	for barrel: Node3D in barrels:
		rests[barrel.get_instance_id()] = barrel.transform
		global_rests[barrel.get_instance_id()] = barrel.global_position
	var immutable_events := events.duplicate(true)
	view.apply_events(events)
	var changed: Array[Node3D] = []
	for barrel: Node3D in barrels:
		if not barrel.transform.is_equal_approx(rests[barrel.get_instance_id()]):
			changed.append(barrel)
	check(changed.size() == 1, "one actual shot recoils one source cannon: " + row.kind)
	if changed.size() == 1:
		var barrel := changed[0]
		check(_triangle_count(barrel) > 0, "recoiling node carries visible original cannon geometry: " + row.kind)
		var recoil_delta: Vector3 = barrel.global_position - global_rests[barrel.get_instance_id()]
		var velocity: Dictionary = events[0].velocity
		var shot_horizontal := Vector3(velocity.x, 0.0, velocity.z).normalized()
		check(recoil_delta.length() > 0.05 and recoil_delta.normalized().dot(shot_horizontal) < -0.95, "source cannon recoils against actual ballistic direction: " + row.kind)
		var socket := barrel.get_parent().find_child(String(barrel.name).replace("barrel_", "socket_smoke_"), true, false) as Node3D
		var event_point: Dictionary = events[0].position
		check(socket != null and socket.global_position.distance_to(Vector3(event_point.x, event_point.y, event_point.z)) < 0.05, "logical event socket meets actual authoritative muzzle: " + row.kind)
		check(view.has_method("source_fire_position"), "actual fire exposes original rendered cannon mouth: " + row.kind)
		if socket and view.has_method("source_fire_position"):
			var key: String = str(row.source) + ":" + String(socket.name)
			var actual_muzzle: Variant = view.call("source_fire_position", events[0])
			check(_original_muzzles.has(key) and actual_muzzle is Vector3 and actual_muzzle.distance_to(view.get_model().global_transform * _original_muzzles[key]) < 0.01, "rendered fire mouth remains at untouched original gun: " + row.kind)
		var recoiled := barrel.transform
		view.apply_events(events)
		check(barrel.transform.is_equal_approx(recoiled), "duplicate actual fire cannot accumulate recoil: " + row.kind)
	check(events == immutable_events, "model cannon adaptation preserves actual event payload: " + row.kind)

func _triangle_count(model: Node3D) -> int:
	var count := 0
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.push_front(model)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh:
			count += mesh.mesh.get_faces().size() / 3
	return count

func _test_source_sail_inflation(model: Node3D, kind: String) -> void:
	# A named morph with all-zero vertex deltas cannot display accepted wind.
	# Inspect submitted relative deltas, rather than the adapter's declarations.
	var maximum := 0.0
	var panels := 0
	for sail: MeshInstance3D in model.find_children("sail_*", "MeshInstance3D", true, false):
		if not sail.mesh is ArrayMesh:
			continue
		var mesh := sail.mesh as ArrayMesh
		for morph in mesh.get_blend_shape_count():
			if mesh.get_blend_shape_name(morph) != &"inflate":
				continue
			panels += 1
			for surface in mesh.get_surface_count():
				var shape: Array = mesh.surface_get_blend_shape_arrays(surface)[morph]
				for delta: Vector3 in shape[Mesh.ARRAY_VERTEX]:
					maximum = maxf(maximum, delta.length())
	check(panels > 0 and maximum > 0.01, "actual source sail inflation has visible original-mesh displacement: " + kind + " max=" + str(maximum))

func _rendered_deck_triangles(model: Node3D) -> PackedVector3Array:
	var triangles := PackedVector3Array()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh and mesh.get_meta("deck_support", false):
			for vertex: Vector3 in mesh.mesh.get_faces():
				triangles.append(mesh.global_transform * vertex)
	return triangles

func _test_original_cannon_rest(model: Node3D, kind: String, library: RefCounted) -> void:
	# Frozen physics muzzle dimensions do not authorize moving the submitted
	# original cannon meshes away from the original hull's ports and carriage.
	var original: Node3D = library.instantiate_model(str(model.get_meta("source_path", "")))
	check(original != null, "actual cannon comparison loads untouched source geometry: " + kind)
	if original == null:
		return
	root.add_child(original)
	for socket: Node3D in original.find_children("socket_smoke_*", "Node3D", true, false):
		_original_muzzles[str(model.get_meta("source_family", "")) + ":" + String(socket.name)] = original.global_transform.affine_inverse() * socket.global_position
	for source: Node3D in original.find_children("cannon_*", "Node3D", true, false):
		var actual := model.find_child(String(source.name), true, false) as Node3D
		check(actual != null, "original visible cannon group remains present: " + kind)
		if actual != null:
			var source_frame := original.global_transform.affine_inverse() * source.global_transform
			var actual_frame := model.global_transform.affine_inverse() * actual.global_transform
			check(source_frame.is_equal_approx(actual_frame), "rendered source gun remains at original hull port: " + kind + " " + String(source.name))
	original.free()

func _original_triangle_height(triangles: PackedVector3Array, feet: Vector3) -> float:
	var highest := -INF
	for index in range(0, triangles.size(), 3):
		var a := triangles[index]
		var b := triangles[index + 1]
		var c := triangles[index + 2]
		if absf((b - a).cross(c - a).normalized().y) < 0.5:
			continue
		var contact = Geometry3D.ray_intersects_triangle(feet + Vector3.UP * 100.0, Vector3.DOWN, a, b, c)
		if contact != null:
			highest = maxf(highest, contact.y)
	return highest

func _test_playable_entries() -> void:
	# Each invocation exercises one real scene: source import/model/deck checks
	# take ~2s; each complete ordinary terrain scene takes ~26s headless.
	# Run sail/fleet separately with the same file and distinct receipts.
	var selected := OS.get_environment("MING_ARMADA_SHIP_CONTRACT_ENTRY")
	if selected.is_empty():
		selected = "duel"
	check(selected in ["sail", "duel", "fleet"], "ordinary source vessel entry is recognized")
	if selected not in ["sail", "duel", "fleet"]:
		return
	for mode: String in [selected]:
		print("REFERENCE_SHIP_GAME_PHASE entry_start=", mode, " elapsed_ms=", Time.get_ticks_msec())
		var scene := Practice.new()
		scene.startup_options = {"mode":mode, "staged":true}
		root.add_child(scene)
		await process_frame
		scene.set_physics_process(false)
		check(scene.startup_receipt.get("ok", false), "ordinary game entry starts with converted vessels: " + mode)
		if scene.startup_receipt.get("ok", false):
			var native: Dictionary = scene.runtime.snapshot().naval
			check(scene.sea.ships.size() == native.ships.size() and scene.sea.sailors.size() == native.ships.size(), "ordinary entry renders its actual fleet and native crew: " + mode)
			for vessel: Dictionary in native.ships:
				var actual: Node3D = scene.sea.ships[vessel.id].get_model()
				check(actual.get_meta("model_origin", "") == "pirates_native_lowend", "ordinary entry reaches source vessel renderer: %s %s" % [mode, vessel.id])
			if mode == "duel":
				scene.runtime.set_pause("loading", false)
				check(scene.runtime.command({"type":"fire", "side":"starboard"}).ok, "ordinary duel launches an actual authoritative shot")
				scene.runtime.advance(1.0 / 60.0)
				var shots: Array = scene.runtime.drain_events()
				var unchanged_shots := shots.duplicate(true)
				var presented: Array = scene.sea.apply_snapshot(scene.runtime.snapshot().naval, shots, 0.0)
				var rendered_shots: Array = presented.filter(func(event: Dictionary)->bool:return event.get("type") == "fire" and event.get("shipId") == native.playerId)
				var original_shots: Array = shots.filter(func(event: Dictionary)->bool:return event.get("type") == "fire" and event.get("shipId") == native.playerId)
				check(shots == unchanged_shots, "actual naval presentation preserves input fire events")
				check(rendered_shots.size() == 1 and original_shots.size() == 1, "actual duel renders one player launch alongside independent enemy fire: actual=" + str(rendered_shots.size()) + " original=" + str(original_shots.size()))
				if not rendered_shots.is_empty() and not original_shots.is_empty():
					var fire: Dictionary = rendered_shots[0]
					check(fire.position == original_shots[0].position and fire.velocity == original_shots[0].velocity, "visual fire adaptation preserves authoritative position and ballistic velocity")
					check(fire.has("source_muzzle_position"), "actual sea supplies original rendered muzzle to fire effects")
					if fire.has("source_muzzle_position"):
						var model: Node3D = scene.sea.ships[fire.shipId].get_model()
						var value: Dictionary = fire.source_muzzle_position
						var point := Vector3(value.x, value.y, value.z)
						var matched := false
						for key: String in _original_muzzles:
							if key.begins_with(str(model.get_meta("source_family", "")) + ":") and point.distance_to(model.global_transform * _original_muzzles[key]) < 0.01:
								matched = true
						check(matched, "actual fire effect receives an untouched original cannon mouth")
		scene.free()
		await process_frame
		await process_frame
		await create_timer(0.08).timeout
		print("REFERENCE_SHIP_GAME_PHASE entry_done=", mode, " elapsed_ms=", Time.get_ticks_msec())

func _finish() -> void:
	print("REFERENCE_SHIP_GAME_CONTRACT_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
