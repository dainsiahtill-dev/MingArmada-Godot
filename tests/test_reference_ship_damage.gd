extends SceneTree

var failures: Array[String] = []
var assertions := 0

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var script = load("res://game/presentation/ships/ship_view.gd")
	var view = script.new()
	root.add_child(view)
	check(view.configure("fuchuan"), "real ship GLBs load")
	check(view.has_method("damage_diagnostics"), "ship exposes state driven damage diagnostics")
	if view.has_method("damage_diagnostics"):
		_test_damage(view)
		_test_all_kinds(script)
	_test_sail_mask()
	view.dispose()
	view.free()
	print("REFERENCE_SHIP_DAMAGE assertions=", assertions, " failures=", failures.size())
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_damage(view) -> void:
	var events: Array = []
	view.presentation_event.connect(func(event): events.append(event))
	var state := {"id": "damaged", "time": 10.0, "hull": 100.0, "maxHull": 100.0, "sail": 100.0, "maxSail": 100.0, "sailDeployment": 1.0, "visual": {"position": {"x": 3.0, "y": 4.0, "z": 5.0}}}
	view.apply_snapshot(state, {}, 0.0)
	check(view.damage_diagnostics().hull_stage == 0, "healthy hull has no damage stage")
	state.hull = 59.0
	state.sail = 63.0
	var authoritative := state.duplicate(true)
	view.apply_snapshot(state, {}, 0.0)
	var damage: Dictionary = view.damage_diagnostics()
	check(damage.hull_stage == 2, "41 percent hull damage quantizes to stage two")
	check(damage.sail_quantized == 36 and damage.sail_stage == 1, "37 percent sail damage quantizes to 36 then subtype stage one")
	for lod in 3:
		view.set_lod_distance([0.0, 300.0, 800.0][lod])
		var model: Node3D = view.get_model()
		var hull := _first_surface(model, "hull")
		var sail := _first_surface(model, "sail")
		check(hull != null and hull.get_active_material(0) is ShaderMaterial, "each real LOD hull has damage shader")
		check(sail != null and sail.get_active_material(0) is ShaderMaterial, "each real LOD sail has holes and scorch shader")
		if sail != null and sail.get_active_material(0) is ShaderMaterial:
			check(sail.get_active_material(0).get_shader_parameter("damage_stage") == 1.0, "LOD changes preserve sail holes")
	check(state == authoritative, "presentation never writes authority damage")
	state.time = 11.0
	state.sail = 0.0
	view.apply_snapshot(state, {}, 1.0)
	check(view.damage_diagnostics().mast_age == 0.0, "sail loss starts one accepted timeline")
	state.time = 12.0
	view.apply_snapshot(state, {}, 1.0)
	var mast := view.get_model().find_child("mast_01", true, false) as Node3D
	check(mast.basis.y.dot(Vector3.UP) < 0.99, "destroyed sail falls on authored mast node")
	check(events.size() == 1 and events[0].type == "mast-break", "crossing mast text key emits once")
	var paused := mast.transform
	view.apply_snapshot(state, {}, 0.0)
	view.apply_events([{"id": "repeat-hit", "type": "hit", "targetId": "damaged", "damage": {"sail": 999.0}}])
	check(mast.transform.is_equal_approx(paused) and events.size() == 1, "paused tick and repeated hit do not restart state timeline")
	state.time = 13.0
	state.hull = 0.0
	view.apply_snapshot(state, {}, 1.0)
	state.time = 15.0
	view.apply_snapshot(state, {}, 2.0)
	check(events.size() == 3, "large accepted step crosses both destruction keys once")
	check(events[1].type == "destruction-explosion" and events[2].type == "sinking-froth", "destruction events preserve text key order")
	check(is_equal_approx(float(events[1].time), 13.25) and is_equal_approx(float(events[2].time), 14.41666794), "effects receive true scheduled accepted birth time")
	check(view.position.is_equal_approx(Vector3(3, 4, 5)), "visual sinking never overwrites authority root pose")
	check(view.get_model().position.y < -1.0, "sinking moves presentation model below original root")
	for distance in [0.0, 300.0, 800.0]:
		view.set_lod_distance(distance)
		check(view.get_model().position.y < -1.0, "all LODs share sinking offset")
	state.time = 20.0
	view.apply_snapshot(state, {}, 5.0)
	check(not view.get_model().visible and events.size() == 3, "end of sinking hides all ship LODs without replay")
	view.set_lod_distance(0.0)
	check(not view.get_model().visible, "LOD switch cannot resurrect sunk model")
	state.time = 5.0
	state.hull = 100.0
	state.sail = 100.0
	view.apply_snapshot(state, {}, 0.0)
	check(view.get_model().visible and view.get_model().position.is_equal_approx(Vector3.ZERO), "accepted time rollback clears old sinking state")
	check(events.size() == 3, "rollback does not replay historical effects")
	view.dispose()
	check(view.damage_diagnostics().material_count == 0, "disposal releases cached damage materials")

func _test_all_kinds(script) -> void:
	for kind in ["fuchuan", "fisherman", "merchant", "voc", "patrol", "heavy"]:
		var view = script.new()
		root.add_child(view)
		check(view.configure(kind), "damage binds actual " + kind + " models")
		var events: Array = []
		view.presentation_event.connect(func(event): events.append(event))
		for row: Array in [[100.0, 0], [81.0, 0], [80.0, 1], [60.0, 2], [40.0, 3], [20.0, 4], [0.0, 5]]:
			view.apply_snapshot({"id": kind, "time": 100.0, "hull": row[0], "maxHull": 100.0, "sail": 0.0, "maxSail": 100.0}, {}, 0.0)
			check(view.damage_diagnostics().hull_stage == row[1], "actual damage boundary follows health for " + kind)
		for distance in [0.0, 300.0, 800.0]:
			view.set_lod_distance(distance)
			var model: Node3D = view.get_model()
			var hull := _first_surface(model, "hull")
			check(hull != null and hull.get_active_material(0) is ShaderMaterial and hull.get_active_material(0).get_shader_parameter("damage_stage") == 5.0, "all source hull LOD instances retain final stage")
			for sail: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				if sail.get_meta("damage_surface", "") != "sail": continue
				for surface in sail.mesh.get_surface_count():
					var material := sail.get_active_material(surface)
					check(material is ShaderMaterial and material.get_shader_parameter("damage_stage") == 4.0, "each authored sail material receives full perforation stage")
		check(events.is_empty(), "first loaded destroyed sail cannot replay historical mast effect")
		view.dispose()
		view.configure(kind)
		view.apply_snapshot({"id": kind, "time": 500.0, "hull": 0.0, "sail": 0.0}, {}, 0.0)
		check(not view.get_model().visible, "restored sunk ship seeks finished state without replay")
		check(events.is_empty(), "restored terminal snapshot emits no past destruction effects")
		view.dispose()
		view.free()

func _first_surface(model: Node3D, kind: String) -> MeshInstance3D:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.get_meta("damage_surface", "") == kind and mesh.mesh != null:
			return mesh
	return null

func _test_sail_mask() -> void:
	var helper = load("res://game/presentation/ships/ship_damage.gd").new()
	check(helper.has_method("sail_tears"), "sail mask exposes real bounded irregular tear clusters")
	if not helper.has_method("sail_tears"):
		return
	var previous_area := 0.0
	for stage in 5:
		var tears: PackedVector4Array = helper.sail_tears(stage, 1)
		check(tears.size() < 20, "sail damage uses sparse clusters, not uniform dot grid")
		var area := 0.0
		for tear in tears:
			check(tear.x > 0.04 and tear.x < 0.96 and tear.y > 0.04 and tear.y < 0.96 and tear.z > 0.0, "tears remain finite and inside authored cloth UV")
			area += PI * tear.z * tear.z * 0.42 * 1.5
		check(area < 0.15, "damage leaves meaningful cloth between localized tears")
		if stage == 0:
			check(tears.is_empty(), "healthy sail has no holes")
		elif stage == 1:
			check(area > 0.003 and area < 0.025, "first damage stage has few significant tears")
		else:
			check(area > previous_area, "higher quantized stage expands localized damage")
		previous_area = area
	check(helper.sail_tears(3, 1) == helper.sail_tears(3, 1), "accepted pause preserves deterministic mask")
	check(helper.sail_tears(3, 1) != helper.sail_tears(3, 2), "different authored sail panels avoid repeated identical patterns")
