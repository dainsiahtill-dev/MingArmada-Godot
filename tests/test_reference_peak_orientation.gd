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

func landing_triangle(island: MeshInstance3D, field: RefCounted, point: Vector2) -> Dictionary:
	# Independent oracle: search the submitted index buffer in world XZ and use
	# scalar barycentric weights. Do not call either production triangle sampler
	# or its source-pixel/parity interpolation helper.
	var arrays: Array = island.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var x := float(point.x)-float(island.position.x)
	var z := float(point.y)-float(island.position.z)
	for cursor in range(0,indices.size(),3):
		var a := vertices[indices[cursor]]
		var b := vertices[indices[cursor+1]]
		var c := vertices[indices[cursor+2]]
		if x<minf(a.x,minf(b.x,c.x)) or x>maxf(a.x,maxf(b.x,c.x)) or z<minf(a.z,minf(b.z,c.z)) or z>maxf(a.z,maxf(b.z,c.z)): continue
		var denominator: float = (float(b.z)-c.z)*(float(a.x)-c.x)+(float(c.x)-b.x)*(float(a.z)-c.z)
		if absf(denominator)<.000000001: continue
		var wa: float = ((float(b.z)-c.z)*(x-c.x)+(float(c.x)-b.x)*(z-c.z))/denominator
		var wb: float = ((float(c.z)-a.z)*(x-c.x)+(float(a.x)-c.x)*(z-c.z))/denominator
		var wc := 1.0-wa-wb
		if minf(wa,minf(wb,wc))<-.00000001: continue
		var corners := []
		for vertex: Vector3 in [a,b,c]:
			var world := Vector2(vertex.x,vertex.z)+Vector2(island.position.x,island.position.z)
			var authored: float = field.sample_original_reference_height(world.x,world.y)
			check(absf(vertex.y-authored)<.0001,"submitted landing triangle vertex retains original authored source height")
			corners.append({"world":world,"renderHeight":vertex.y,"authoringHeight":authored})
		return {"height":wa*a.y+wb*b.y+wc*c.y,"weights":[wa,wb,wc],"corners":corners}
	return {}

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
		# The analytic harbor profile reaches 2.1m at along=43. The retained
		# Float32 source mesh interpolates adjacent vertices across this knee;
		# an interior triangle point need not equal the analytic curve there.
		check(absf(field.sample_original_reference_height(landing.x,landing.y)-2.1)<.0001,"original source rotation retains the pier's 2.1 metre authoring target: "+id)
		var triangle := landing_triangle(meshes.get_meshes()[index],field,landing)
		check(not triangle.is_empty(),"pier landing lies inside an actual submitted source triangle: "+id)
		if not triangle.is_empty():
			check(absf(field.sample_height(landing.x,landing.y)-float(triangle.height))<.0001,"physical landing retains the independent indexed mesh triangle height: "+id)
			check(absf(meshes.sample_mesh_height(landing.x,landing.y)-float(triangle.height))<.0001,"render query retains the independent indexed mesh triangle height: "+id)
		records.append({"id":id,"sourcePeak":PEAKS[id],"worldPeak":world,"height":peak_height,"inlandDistance":(world-island_center).dot(inward),"landingHeight":field.sample_height(landing.x,landing.y),"landingTriangle":triangle})
	print("REFERENCE_PEAK_ORIENTATION_GEOMETRY ",JSON.stringify(records))
	meshes.dispose()
	print("REFERENCE_PEAK_ORIENTATION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
