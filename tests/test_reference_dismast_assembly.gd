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
	for kind in ["fuchuan", "fisherman", "merchant", "voc", "patrol", "heavy"]:
		var view = script.new()
		root.add_child(view)
		check(view.configure(kind), "actual rig loads for " + kind)
		view.set_reduced_motion(true)
		var state := {"id": kind, "time": 10.0, "hull": 100.0, "sail": 100.0, "sailAngle": 0.3, "sailDeployment": 0.57}
		view.apply_snapshot(state, {}, 0.0)
		var before: Array = []
		for distance in [0.0, 300.0, 800.0]:
			view.set_lod_distance(distance)
			var model: Node3D = view.get_model()
			var masts: Array = model.find_children("mast_*", "Node3D", true, false).filter(func(node): return String(node.name).trim_prefix("mast_").is_valid_int())
			var attachments: Array = []
			var flags: Array = []
			var fixed_flags: Array = []
			for flag: Node3D in model.find_children("flag_*", "Node3D", true, false):
				if flag.get_meta("source_fixed_attachment", false):
					fixed_flags.append({"node":flag,"rest":flag.global_transform})
				else: flags.append(flag)
			check(not flags.is_empty() and not masts.is_empty(), "source masthead flags and real mast pivots are available: " + kind)
			if flags.is_empty() or masts.is_empty(): continue
			var flag: Node3D = flags[0]
			for mast: Node3D in masts:
				for child: Node3D in mast.get_children():
					attachments.append({"node": child, "mast": mast, "local": child.transform})
			var nearest: Node3D = masts[0]
			for mast: Node3D in masts:
				if mast.is_ancestor_of(flag):
					nearest = mast
			before.append({"height": _highest(model), "flag": flag, "flag_rest": model.global_transform.affine_inverse() * flag.global_position, "pivot": nearest.position, "model": model, "attachments": attachments, "fixed_flags": fixed_flags})
		state.time = 11.0
		state.sail = 0.0
		view.apply_snapshot(state, {}, 1.0)
		state.time = 14.0
		view.apply_snapshot(state, {}, 3.0)
		for row: Dictionary in before:
			check(_highest(row.model) < float(row.height) * 0.60, "fallen rig has no upright shrouds or high flags: " + kind + " " + _highest_detail(row.model) + " original=" + str(row.height))
			var fall := Basis(Vector3.BACK, 1.45)
			var expected: Vector3 = row.pivot + fall * (row.flag_rest - row.pivot)
			var actual: Vector3 = row.model.global_transform.affine_inverse() * row.flag.global_position
			check(actual.distance_to(expected) < 0.015, "masthead flag falls about same deck pivot: " + kind)
			for attachment: Dictionary in row.attachments:
				check(attachment.node.transform.is_equal_approx(attachment.local), "sail/timber/yard attachment remains coherent: " + kind)
			for flag: Dictionary in row.fixed_flags:
				check(flag.node.global_transform.is_equal_approx(flag.rest), "fixed stern flag stays on its own hull attachment: " + kind)
		if before.is_empty():
			view.dispose(); view.free(); continue
		var paused: Transform3D = before[0].flag.global_transform
		view.apply_snapshot(state, {}, 0.0)
		check(before[0].flag.global_transform.is_equal_approx(paused), "paused damaged rig does not accumulate fall transform")
		state.time = 4.0
		state.sail = 100.0
		view.apply_snapshot(state, {}, 0.0)
		check(is_equal_approx(_highest(before[0].model), float(before[0].height)), "rewind restores original rig height without mesh drift")
		view.dispose()
		view.free()
	for failure in failures:
		printerr("FAIL: ", failure)
	print("REFERENCE_DISMAST_ASSEMBLY assertions=", assertions, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _highest(model: Node3D) -> float:
	var highest := -INF
	var inverse := model.global_transform.affine_inverse()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.visible:
			continue
		var frame := inverse * mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				highest = maxf(highest, (frame * vertex).y)
	return highest

func _highest_detail(model: Node3D) -> String:
	var highest := -INF; var label := ""
	var inverse := model.global_transform.affine_inverse()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.visible: continue
		var frame := inverse * mesh.global_transform
		for point: Vector3 in mesh.mesh.get_faces():
			var height := (frame * point).y
			if height > highest: highest = height; label = str(mesh.name) + " parent=" + str(mesh.get_parent().name)
	return label + " y=" + str(highest)
