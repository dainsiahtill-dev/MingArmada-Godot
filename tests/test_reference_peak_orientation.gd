extends SceneTree
const Profile = preload("res://modules/scene_engine/terrain/reference_island_profile.gd")
const HeightField = preload("res://modules/scene_engine/terrain/height_field.gd")
const StaticIslands = preload("res://modules/scene_engine/fidelity_island/static_islands.gd")
const Coordinates = preload("res://modules/scene_engine/fidelity_island/source_coordinates.gd")
# Fixed observations from the immutable original H rasters, not derived from
# profile diagnostics or a production peak-selection/normalization helper.
const PEAKS := {"coastal2":Vector2(122,121),"cat_island":Vector2(85,106),"virgin_islands":Vector2(72,46)}
const MIN_PEAK_HEIGHTS := {"coastal2":17.0,"cat_island":13.0,"virgin_islands":6.0}
const ART := {"sea_index":127.5,"height_gain":.35,"smoothing_radius":1,"border_rounding":.30,"border_fade_pixels":14.0}
var assertions := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",reason)

func _run() -> void:
	var ports: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var field := HeightField.new()
	var options := {"reference_islands":true,"reference_profiles":{"xiamen":"coastal2","kinmen":"cat_island","forward-supply":"virgin_islands"},"reference_art":ART}
	check(field.configure_ports(ports,true,options),"physical game-art options compose with retained source height authority")
	var profiles: Array = field.reference_profiles()
	var materials: Array = []
	for profile: Dictionary in profiles: materials.append(StandardMaterial3D.new())
	var meshes := StaticIslands.new()
	check(meshes.configure(profiles,field.sample_height,materials),"source-peak regression uses actual cached render geometry")
	var records: Array = []
	for index in profiles.size():
		var info: Dictionary = profiles[index]
		var id := str(info.id)
		var world := Coordinates.source_pixel_to_world(PEAKS[id],info)
		var peak_height := field.sample_height(world.x,world.y)
		var inward: Vector2 = info.inward
		var island_center: Vector2 = info.islandCenter
		var dock := Vector2(float(ports[index].x),float(ports[index].z))
		# Heights catch the observed failure: old Cat peak48 became2.076 and
		# Virgin peak28 became2.366 when their mountain was aimed at the dock.
		check(peak_height > float(MIN_PEAK_HEIGHTS[id]),"original source mountain survives local harbor apron: "+id+" height="+str(peak_height))
		check((world-island_center).dot(inward)>0.0 and world.distance_to(dock)>island_center.distance_to(dock),"highest original mountain lies inland beyond source island center: "+id)
		check(absf(meshes.sample_mesh_height(world.x,world.y)-peak_height)<.0001,"actual static triangle height preserves the source mountain owned by navigation/physics: "+id)
		var across := Vector2(-inward.y,inward.x)
		for along: float in [-40.0,0.0,12.0,20.0]:
			for lateral: float in [-12.0,0.0,12.0]:
				var point := dock+inward*along+across*lateral
				check(field.sample_height(point.x,point.y)<=-7.9,"source rotation retains actual navigable dock approach: "+id)
		var landing := dock+inward*43.0
		check(absf(field.sample_height(landing.x,landing.y)-2.1)<.0001,"source rotation retains the pier's 2.1 metre landing height: "+id)
		records.append({"id":id,"sourcePeak":PEAKS[id],"worldPeak":world,"height":peak_height,"inlandDistance":(world-island_center).dot(inward),"landingHeight":field.sample_height(landing.x,landing.y)})
	print("REFERENCE_PEAK_ORIENTATION_GEOMETRY ",JSON.stringify(records))
	meshes.dispose()
	print("REFERENCE_PEAK_ORIENTATION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
