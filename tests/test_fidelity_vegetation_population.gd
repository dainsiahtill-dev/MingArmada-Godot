extends SceneTree
const Vegetation = preload("res://modules/scene_engine/fidelity_island/vegetation.gd")
const Field = preload("res://modules/scene_engine/terrain/height_field.gd")
const Geography = preload("res://game/scenes/common/reference_geography.gd")
const Coordinates = preload("res://modules/scene_engine/fidelity_island/source_coordinates.gd")
var assertions := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",message)
func _initialize() -> void: _run.call_deferred()
func sea(_x: float,_z: float) -> float: return -3.0
func counts(anchors: Array) -> Dictionary:
	var result: Dictionary = {}
	for anchor: Dictionary in anchors: result[anchor.profile_id] = int(result.get(anchor.profile_id,0))+1
	return result
func coverage(field: RefCounted, anchors: Array) -> Dictionary:
	# Independent 3m land probes measure geometry crown-footprint coverage.
	# This is not a claim about green GPU pixels through alpha/fog.
	var result: Dictionary = {}
	for profile: Dictionary in field.reference_profiles():
		var root_candidates: Array = []
		for anchor: Dictionary in anchors:
			if anchor.profile_id == profile.id: root_candidates.append(anchor)
		var eligible := 0; var covered := 0; var dry := 0
		var step := 3.0/float(profile.scale)
		for row in int(ceil(float(profile.height-2)/step)):
			for column in int(ceil(float(profile.width-2)/step)):
				var pixel := Vector2(1.0+(float(column)+0.5)*step,1.0+(float(row)+0.5)*step)
				var point := Coordinates.source_pixel_to_world(pixel,profile)
				var height: float = field.sample_height(point.x,point.y)
				if height < 0.45: continue
				dry += 1
				var offset: Vector2 = point-profile.dock
				var across := Vector2(-profile.inward.y,profile.inward.x)
				if offset.dot(profile.inward)>-100.0 and offset.dot(profile.inward)<90.0 and absf(offset.dot(across))<29.0: continue
				var safe := true
				for delta: Vector2 in [Vector2(.9,0),Vector2(-.9,0),Vector2(0,.9),Vector2(0,-.9)]:
					var neighboring: float = field.sample_height(point.x+delta.x,point.y+delta.y)
					if neighboring<0.12 or absf(neighboring-height)/.9>2.5: safe = false; break
				if not safe: continue
				eligible += 1
				for anchor: Dictionary in root_candidates:
					if point.distance_to(Vector2(anchor.position.x,anchor.position.z)) <= float(anchor.crown_radius): covered += 1; break
		result[profile.id] = {"dryProbes":dry,"eligibleProbes":eligible,"coveredProbes":covered,"footprintCoverage":float(covered)/maxf(1.0,float(eligible))}
	return result
func _run() -> void:
	var geography: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var field := Field.new()
	check(field.configure_ports(geography,true,Geography.source_options()),"explicit original source comparison terrain configures")
	var plants := Vegetation.new(); root.add_child(plants)
	check(plants.configure(field,field.sample_height,{"adaptive_population":false}),"original template baseline configures on actual game terrain")
	var baseline: Dictionary = counts(plants.diagnostics().anchors)
	var baseline_total: int = plants.diagnostics().accepted_tree_count
	check(plants.configure(field,field.sample_height,{"adaptive_population":true}),"mapped adaptive source-model forest configures")
	var audit: Dictionary = plants.diagnostics()
	check(audit.get("population_mode","") == "adaptive","diagnostics distinguish product population from original reference layout")
	var per_profile: Dictionary = {}
	var min_height := INF; var max_height := -INF
	for anchor: Dictionary in audit.anchors:
		per_profile[anchor.profile_id] = int(per_profile.get(anchor.profile_id,0))+1
		var point: Vector3 = anchor.position
		var ground := field.sample_height(point.x,point.z)
		check(point.is_finite() and ground >= 0.12 and absf(point.y-ground)<0.001,"every adaptive real-tree root sits on authoritative dry terrain")
		min_height = minf(min_height,ground); max_height = maxf(max_height,ground)
	var measured_coverage := coverage(field,audit.anchors)
	print("POPULATION_METRICS ",JSON.stringify({"baseline":baseline,"baselineTotal":baseline_total,"perProfile":per_profile,"total":audit.accepted_tree_count,"coverage":measured_coverage,"minHeight":min_height,"maxHeight":max_height,"spacing":audit.get("forest_spacing",0.0)}))
	check(per_profile.size() == 3,"canopy population covers all three actual source profiles")
	for id: String in per_profile:
		check(per_profile[id] >= maxf(6.0,float(baseline.get(id,0))*1.75),"each island population improves relative to its actual template baseline: "+id)
		check(measured_coverage[id].eligibleProbes > 0 and measured_coverage[id].footprintCoverage >= 0.6,"eligible non-harbor terrain has continuous modeled crown coverage: "+id)
	check(audit.accepted_tree_count >= baseline_total*3,"actual islands have substantially more authored tree geometry than the sparse template")
	check(max_height-min_height > 10.0,"population occupies lowlands and elevated inland terrain")
	var frozen_anchors: Array = audit.anchors
	var frozen_nodes: int = audit.owned_nodes
	plants.apply_snapshot({"time":15.0,"focus":Vector2(800,1000)})
	plants.apply_snapshot({"time":15.0,"focus":Vector2(-800,-1000)})
	check(plants.diagnostics().anchors == frozen_anchors and plants.diagnostics().owned_nodes == frozen_nodes,"opposite camera focus keeps deterministic population and lifecycle")
	check(plants.configure(field,field.sample_height,{"adaptive_population":true}),"deterministic repeat configures")
	check(plants.diagnostics().anchors == frozen_anchors,"repeat population has identical native tree prototypes and roots")
	var site := {"position":Vector3.ZERO,"radius":100000.0}
	check(plants.configure(field,field.sample_height,{"adaptive_population":true,"existing_buildings":[site]}),"retained building footprint filter configures")
	check(plants.diagnostics().accepted_tree_count == 0,"building footprints exclude entire real-tree crowns")
	check(plants.configure(field,sea,{"adaptive_population":true}),"sea-only authority configures without artificial land")
	check(plants.diagnostics().accepted_tree_count == 0,"no adaptive trees are fabricated in open sea")
	check(plants.configure({},Callable(),{"mode":"exact"}),"exact source reference still configures")
	check(plants.diagnostics().accepted_tree_count == 57 and plants.diagnostics().canopy_patch_count == 3,"exact source retains 57 original groups and three patches")
	plants.dispose(); plants.free()
	print("FIDELITY_VEGETATION_POPULATION_COMPLETE assertions=%d failures=%d" % [assertions,failures])
	quit(0 if failures == 0 else 1)
