extends SceneTree
## Catches misplaced rocks, navigational obstruction, nondeterministic rebuilding,
## unbounded allocation, absent native geometry, and destructive cleanup.
var assertions := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void: _run.call_deferred()
func ground(x: float, z: float) -> float:
	var center := Vector2.ZERO if x < 300.0 else Vector2(600.0, 0.0)
	return 12.0 - Vector2(x, z).distance_to(center) * 0.18
func ports() -> Array:
	return [{"id":"east", "x":90.0,"z":0.0,"islandX":0.0,"islandZ":0.0,"radius":100.0},
		{"id":"west", "x":510.0,"z":0.0,"islandX":600.0,"islandZ":0.0,"radius":100.0}]
func fingerprints(placements: Array, id: String) -> Array:
	var result: Array = []
	for placement: Dictionary in placements:
		if placement.port_id == id: result.append([placement.kind, placement.position, placement.scale])
	return result
func _run() -> void:
	var path := "res://modules/scene_engine/world/island_details.gd"
	var script = load(path) if ResourceLoader.exists(path) else null
	check(script != null, "native IslandDetails renderer exists")
	if script:
		var details = script.new(); root.add_child(details)
		var unrelated := Node3D.new(); details.add_child(unrelated)
		check(details.configure(ground, ports(), {"seed":13,"max_instances":800}), "valid analytical sampler configures details")
		var audit: Dictionary = details.diagnostics()
		check(audit.instance_count > 100 and audit.instance_count <= 800, "layered details fit explicit global budget")
		check(audit.group_count > 10 and audit.mesh_count > 8, "native geometry includes several coast and harbor silhouettes")
		var kinds: Dictionary = {}
		var library=load("res://modules/scene_engine/assets/coastal_detail_library.gd").new()
		for placement: Dictionary in audit.placements:
			kinds[placement.kind] = true
			var point: Vector3 = placement.position
			var height := ground(point.x, point.z)
			check(point.is_finite(), "all accepted anchors are finite")
			if placement.zone == "land":
				check(height >= 0.12 and absf(point.y - height) < 0.001, "land meshes anchor on authoritative positive ground")
			elif placement.zone == "reef":
				check(height >= -2.6 and height <= -0.18 and absf(point.y - height) < 0.001, "reefs settle only on sampled shallow sea bed")
			else:
				check(absf(point.y - 4.45) < 0.001, "dock cargo sits on actual pier deck top")
				check(absf(placement.pier_local.x) >= 1.8 and absf(placement.pier_local.x) <= 3.2, "pier center walking/loading lane stays open")
				if placement.kind in ["crate","barrel"]:
					var cargo_bounds: AABB=library.get_mesh(placement.kind).get_aabb()
					check(cargo_bounds.size.y*placement.scale.y>1.3,"cargo volumetric silhouette is tall enough to read from ship camera")
			if placement.zone != "dock":
				var local: Vector2 = placement.pier_local
				check(not (absf(local.x) < 13.0 and local.y > -110.0 and local.y < 65.0), "shore props leave pier and approach corridor clear")
				check(not (point.x > 66.0 and point.x < 534.0 and absf(point.z) < 24.0), "inter-port navigation lane stays clear")
		check(kinds.has("outcrop") and kinds.has("pebble") and kinds.has("reef") and kinds.has("beach_grass") and kinds.has("shrub"), "coast has broken rock, beach and underwater layers")
		check(kinds.has("barrel") and kinds.has("crate") and kinds.has("rope_coil") and kinds.has("cargo_net") and kinds.has("basket"), "harbor has cargo, fishing and rope silhouettes")
		for group: MultiMeshInstance3D in details.find_children("*", "MultiMeshInstance3D", true, false):
			check(group.multimesh.mesh is ArrayMesh and group.multimesh.mesh.get_surface_count() > 0, "each group owns real native triangle geometry")
			var bounds: AABB = group.multimesh.mesh.get_aabb()
			check(bounds.size.x > 0.05 and bounds.size.y > 0.05 and bounds.size.z > 0.05, "detail geometry has volumetric silhouette")
			check(group.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() > 12, "mesh contains modeled detail instead of one flat rectangle")
			var material: StandardMaterial3D=group.multimesh.mesh.surface_get_material(0)
			check(group.material_override==material,"MultiMesh binds the authored palette material explicitly")
			check(material.albedo_color.r<0.9 and material.albedo_color.b<0.7,"authored palette supplies color at the material boundary without a white fallback")
			var colors: PackedColorArray=group.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var neutral:=true
			for color: Color in colors:
				if absf(color.r-color.g)>=0.001 or absf(color.g-color.b)>=0.001: neutral=false
			check(neutral,"vertex shade stays grayscale so material hue isn't multiplied twice")
			if String(group.name).contains("_crate_") or String(group.name).contains("_barrel_"):
				# Dummy headless RenderingServer does not expose live GPU instance colors.
				# Assert the bound material boundary; integrated capture checks pixels.
				var albedo: Color=material.albedo_color.srgb_to_linear()
				check(albedo.r>albedo.g*1.4 and albedo.g>albedo.b*1.6,"bound cargo material retains warm wood hue")
		var east := fingerprints(audit.placements, "east")
		var reordered := ports(); reordered.reverse()
		details.configure(ground, reordered, {"seed":13,"max_instances":800})
		check(east == fingerprints(details.diagnostics().placements, "east"), "port identity remains deterministic independent of input order")
		details.configure(ground, ports(), {"seed":14,"max_instances":800})
		check(east != fingerprints(details.diagnostics().placements, "east"), "distinct seeds vary actual coast placement")
		var count: int = details.diagnostics().instance_count
		var groups: int = details.diagnostics().group_count
		for index in 40:
			details.apply_snapshot({"time":8.0,"focus":Vector2(index * 150.0,0.0)}, 0.0)
			check(details.diagnostics().instance_count == count and details.diagnostics().group_count == groups, "focus windows never allocate repeated geometry")
		check(details.diagnostics().visible_group_count < groups, "distant island groups cull outside focus range")
		details.apply_snapshot({"time":0.0,"focus":Vector2.ZERO}, 0.0)
		check(details.diagnostics().simulation_time == 0.0, "accepted zero time resets optional animation without wall time")
		for index in 4:
			details.configure(ground, ports(), {"max_instances":120,"quality":"high"})
			check(details.diagnostics().instance_count <= 120 and details.get_child_count() <= 30, "reconfiguration honors small global budget without resource remnants")
		details.dispose(); details.dispose()
		check(is_instance_valid(unrelated) and unrelated.get_parent() == details, "dispose preserves caller-owned nodes")
		check(details.diagnostics().instance_count == 0 and details.diagnostics().mesh_count == 0 and details.get_child_count() == 1, "dispose releases owned nodes and resource cache")
		check(not details.configure(Callable(), ports()), "invalid height authority rejected")
		check(not details.configure(ground, [{"id":"invalid","radius":NAN}]), "malformed geography rejected without fabricated ground")
		# The real height field contains an offshore shelf as well as steep islands.
		# Catch contour assumptions which work on radial fixtures but fail in runtime.
		var field=load("res://modules/scene_engine/terrain/height_field.gd").new()
		var geography: Array=JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
		field.configure_ports(geography)
		check(details.configure(field.sample_height,geography), "actual three-island height authority configures native art")
		var real_audit: Dictionary=details.diagnostics()
		var port_counts: Dictionary={}; var reef_count:=0; var coast_count:=0
		var interior_counts: Dictionary={}
		for placement: Dictionary in real_audit.placements:
			port_counts[placement.port_id]=int(port_counts.get(placement.port_id,0))+1
			if placement.zone=="reef":
				reef_count+=1
				check(placement.position.y+placement.scale.y*1.1<0.0,"real submerged reef remains below mean water surface")
			if placement.kind=="outcrop": coast_count+=1
			if placement.zone=="land" and placement.position.y>6.0 and placement.kind in ["shrub","beach_grass","outcrop"]:
				interior_counts[placement.port_id]=int(interior_counts.get(placement.port_id,0))+1
				if placement.kind in ["shrub","beach_grass"]:
					check(placement.scale.x>=2.4,"interior understory has overview-readable world scale")
		check(port_counts.size()==3 and reef_count>5 and coast_count>8,"all real islands have harbor detail and visible geological coast layers")
		check(interior_counts.size()==3,"each real island has visible interior understory beyond its narrow shoreline")
		for id: String in interior_counts: check(interior_counts[id]>=10,"interior detail forms useful patches rather than one token bush")
		print("ISLAND_DETAILS_REAL instances=",real_audit.instance_count," groups=",real_audit.group_count," meshes=",real_audit.mesh_count," vertices=",real_audit.mesh_vertices," reefs=",reef_count," outcrops=",coast_count)
		check(real_audit.instance_count<=2200 and real_audit.mesh_count<=18 and real_audit.mesh_vertices<24000,"three-island real geometry stays within reusable mesh budget")
		# Oversized global requests must still fit the hard upper bound.
		var dense: Array=[]
		for index in 64:
			dense.append({"id":"dense-%d"%index,"x":90.0,"z":0.0,"islandX":0.0,"islandZ":0.0,"radius":100.0})
		check(details.configure(ground,dense,{"max_instances":999999,"quality":"high"}),"maximum accepted island catalog configures")
		check(details.diagnostics().instance_count<=4096,"global hard cap survives many overlapping islands and oversized options")
		var too_many:=dense.duplicate(true); too_many.append(dense[0])
		check(not details.configure(ground,too_many) and details.diagnostics().owned_nodes==0,"oversized catalog rejected and old resources released")
		details.free()
	print("ISLAND_DETAILS_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
