extends SceneTree
# Frozen source geometry oracle. Ordinary/default hero entry remains covered separately.
const Reference=preload("res://modules/scene_engine/assets/ship_model_provider.gd")
## Exact pose oracle is the frozen pre-convergence ShipView, not a duplicate rewrite.
const Ship = preload("res://game/presentation/ships/ship_view.gd")
const Crew = preload("res://game/presentation/crew/crew_view.gd")
const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
const BASELINE := "res://docs/research/evidence/architecture-convergence-2026-10-21/baseline/source/game/presentation/ships/ship_view.gd.txt"
var assertions := 0
var failures := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var source := FileAccess.get_file_as_string("res://game/presentation/ships/ship_view.gd")
	var pose_source := source.substr(source.find("func apply_snapshot("))
	pose_source = pose_source.left(pose_source.find("\nfunc "))
	check(not pose_source.contains("find_children("), "ordinary ship pose updates do not rediscover the three LOD scene trees")
	var baseline := GDScript.new(); baseline.source_code = FileAccess.get_file_as_string(BASELINE)
	check(baseline.reload() == OK, "frozen production pose oracle compiles")
	if not baseline.can_instantiate(): _finish(); return
	var library := Library.new()
	var candidate := Ship.new(); root.add_child(candidate)
	var oracle: Node3D = baseline.new(); root.add_child(oracle)
	var prior: WeakRef
	for kind: String in Ship.KINDS:
		check(candidate.configure(kind,library,Reference.new()) and oracle.configure(kind,library), "both source model compositions configure: " + kind)
		if prior != null: check(prior.get_ref() == null, "reconfigure releases the previous model and its cached role references")
		prior = weakref(candidate.get("_models")[0])
		var subtree_nodes := 0
		var bound_roles := 0
		for model: Node3D in candidate.get("_models"): subtree_nodes += model.find_children("*","Node3D",true,false).size()
		for property: Dictionary in candidate.get_property_list():
			if String(property.name).begins_with("_pose_"): bound_roles += candidate.get(property.name).size()
		print("SHIP_ROLE_WORK kind=",kind," originalSubtreeNodesPerPose=",subtree_nodes," boundRoleVisitsPerPose=",bound_roles)
		var crew := Crew.new(); candidate.add_child(crew)
		check(crew.configure(kind,candidate.get_model(),library), "real crew binds the initial model: " + kind)
		crew.set_allocation(2)
		var state := {"id":"role-fixture","time":1.0,"hull":100.0,"maxHull":100.0,"sail":100.0,"maxSail":100.0,"sailDeployment":0.35,"sailAngle":0.27,"rudder":-0.4,"crew":20.0,"visual":{"position":{"x":3.0,"y":2.0,"z":5.0},"heading":0.3,"pitch":0.04,"heel":-0.08,"velocity":{"x":1.0,"z":0.0}}}
		var wind := {"direction":{"x":0.6,"y":0.8},"speed":12.0}
		for phase in 4:
			state.time = 1.0 + float(phase)*0.25
			state.sailAngle = 0.27 - float(phase)*0.11
			state.sailDeployment = 0.35 + float(phase)*0.15
			if phase == 1: candidate._fire("starboard",null); oracle._fire("starboard",null)
			candidate.apply_snapshot(state,wind,0.25); oracle.apply_snapshot(state,wind,0.25)
			check(_pose(candidate) == _pose(oracle), "all LOD mast/rudder/flag/furl/inflate/recoil poses equal frozen production: " + kind + " phase=" + str(phase))
		for lod in 3:
			candidate.set_lod_distance([0.0,300.0,700.0][lod]); oracle.set_lod_distance([0.0,300.0,700.0][lod])
			check(crew.set_ship_model(candidate.get_model()), "crew deck reload accepts the posed LOD: " + kind + " lod=" + str(lod))
			crew.apply_snapshot(state,wind,0.0)
			check(_pose(candidate) == _pose(oracle), "LOD visibility preserves frozen pose output: " + kind + " lod=" + str(lod))
		state.time = 3.0; state.sail = 0.0
		candidate.apply_snapshot(state,wind,0.25); oracle.apply_snapshot(state,wind,0.25)
		state.time = 4.0
		candidate.apply_snapshot(state,wind,1.0); oracle.apply_snapshot(state,wind,1.0)
		check(_pose(candidate) == _pose(oracle), "cached roles retain accepted mast-break and rig assembly animation: " + kind)
		state.time = 0.5; state.sail = 100.0
		candidate.set_reduced_motion(true); oracle.set_reduced_motion(true)
		candidate.apply_snapshot(state,wind,0.0); oracle.apply_snapshot(state,wind,0.0)
		check(_pose(candidate) == _pose(oracle), "rewind and reduced-motion reset preserve source poses: " + kind)
		candidate.set_reduced_motion(false); oracle.set_reduced_motion(false)
		crew.dispose(); crew.free()
	candidate.dispose(); oracle.dispose()
	check(prior.get_ref() == null, "dispose releases the final cached model Nodes")
	for property: Dictionary in candidate.get_property_list():
		if String(property.name).begins_with("_pose_"): check(candidate.get(property.name).is_empty(), "dispose clears every role binding: " + property.name)
	check(not candidate.configure("invalid",library), "invalid reconfigure cannot retain earlier role bindings")
	candidate.apply_snapshot({"time":9.0},{},0.0)
	check(candidate.get("_models").is_empty(), "late presentation cannot revive disposed bindings")
	candidate.free(); oracle.free(); library.dispose()
	_finish()
func _pose(view: Node3D) -> Dictionary:
	var result := {}
	for model: Node3D in view.get("_models"):
		result[str(model.name)] = {"transform":model.transform,"visible":model.visible}
		for node: Node3D in model.find_children("*","Node3D",true,false):
			var row := {"transform":node.transform,"visible":node.visible}
			if node is MeshInstance3D and node.mesh:
				row.morphs = []
				for index in node.mesh.get_blend_shape_count(): row.morphs.append(node.get_blend_shape_value(index))
			result[str(model.name)+"/"+str(model.get_path_to(node))] = row
	return result
func _finish() -> void:
	print("SHIP_POSE_ROLE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
