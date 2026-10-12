extends SceneTree
const HeightField = preload("res://modules/scene_engine/terrain/height_field.gd")
const Geography = preload("res://game/scenes/common/reference_geography.gd")
const StaticIslands = preload("res://modules/scene_engine/fidelity_island/static_islands.gd")
const Coordinates = preload("res://modules/scene_engine/fidelity_island/source_coordinates.gd")
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
	check(field.configure_ports(ports,true,Geography.source_options()),"real finite source profiles configure with explicit source comparison geography")
	var profiles: Array = field.reference_profiles()
	var materials: Array = []
	for profile: Dictionary in profiles: materials.append(StandardMaterial3D.new())
	var builder := StaticIslands.new()
	check(builder.configure(profiles,field.sample_height,materials),"real harbor coverage regression builds static source geometry")
	var xiamen: Dictionary = profiles[0]
	var dock: Vector2 = xiamen.dock
	var inward: Vector2 = xiamen.inward
	var witness := dock+inward*54.0
	var source_pixel := Coordinates.world_to_source_pixel(witness,xiamen)
	check(source_pixel.y<0 and absf(field.sample_height(witness.x,witness.y)-2.375)<.0001,"actual Xiamen dock+54m is positive authoritative land outside the original source grid")
	check(is_finite(builder.sample_mesh_height(witness.x,witness.y)) and absf(builder.sample_mesh_height(witness.x,witness.y)-2.375)<.001,"positive harbor apron outside source row zero has a real cached terrain triangle")
	check(builder.supports(witness,0),"finite render coverage includes the real positive harbor apron witness")
	var positive := 0
	var outside := 0
	var missing := 0
	var max_height_error := 0.0
	var max_added_height_error := 0.0
	var witnesses: Array = []
	# Scan actual authority values throughout all finite harbor windows. Positive
	# probes are the demanded geometry; negative approaches remain water physics.
	for profile: Dictionary in profiles:
		var origin: Vector2 = profile.dock
		var axis: Vector2 = profile.inward
		var across := Vector2(-axis.y,axis.x)
		var local_outside := 0
		for along in range(20,96):
			for lateral in range(-35,36):
				var point := origin+axis*float(along)+across*float(lateral)
				var height := field.sample_height(point.x,point.y)
				if height <= 0: continue
				positive += 1
				var pixel := Coordinates.world_to_source_pixel(point,profile)
				var beyond_native: bool = pixel.x<0 or pixel.y<0 or pixel.x>int(profile.width)-1 or pixel.y>int(profile.height)-1
				if beyond_native:
					outside += 1
					local_outside += 1
				var rendered := builder.sample_mesh_height(point.x,point.y)
				if not is_finite(rendered): missing += 1
				else:
					max_height_error=maxf(max_height_error,absf(rendered-height))
					if beyond_native: max_added_height_error=maxf(max_added_height_error,absf(rendered-height))
		witnesses.append({"id":profile.id,"positiveOutsideSource":local_outside})
	check(outside>0,"full harbor-window audit observes actual positive land beyond native source bounds")
	check(missing==0,"all positive authoritative harbor-window probes have cached render geometry: missing="+str(missing))
	check(max_added_height_error<.1,"added harbor triangle interpolation preserves authoritative land within one-pixel precision: max error="+str(max_added_height_error))
	if builder.diagnostics().has("renderBounds"):
		_verify_grid(builder,field,profiles)
	else:
		check(false,"static geometry reports distinct source and render bounds")
	var calls: int = builder.diagnostics().sampleCalls
	var geometry_id: int = builder.get_meshes()[0].get_instance_id()
	check(builder.configure(profiles,field.sample_height,materials) and builder.get_meshes()[0].get_instance_id()==geometry_id and builder.diagnostics().sampleCalls==calls,"expanded finite harbor geometry remains cached across identical configure calls")
	var witness_height := builder.sample_mesh_height(witness.x,witness.y)
	print("STATIC_HARBOR_COVERAGE_GEOMETRY ",JSON.stringify({"witnessWorld":witness,"witnessSourcePixel":source_pixel,"witnessAuthority":field.sample_height(witness.x,witness.y),"witnessRender":witness_height if is_finite(witness_height) else null,"positiveProbes":positive,"positiveOutsideSource":outside,"missingRenderProbes":missing,"maxTriangleError":max_height_error,"maxAddedTriangleError":max_added_height_error,"profiles":witnesses,"bounds":builder.diagnostics().get("renderBounds",[])}))
	builder.dispose()
	check(builder.get_meshes().is_empty() and not builder.supports(witness,0) and is_nan(builder.sample_mesh_height(witness.x,witness.y)),"expanded harbor geometry obeys existing disposal lifecycle")
	print("STATIC_HARBOR_COVERAGE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)

func _verify_grid(builder: RefCounted, field: RefCounted, profiles: Array) -> void:
	var bounds: Array = builder.diagnostics().renderBounds
	var checked_vertices := 0
	var max_vertex_error := 0.0
	var added_vertices := 0
	var native_vertices := 0
	for index in profiles.size():
		var profile: Dictionary = profiles[index]
		var island: MeshInstance3D = builder.get_meshes()[index]
		var data: Array = island.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX]
		var uv: PackedVector2Array = data[Mesh.ARRAY_TEX_UV]
		var info: Dictionary = bounds[index]
		var lower: Vector2i = info.pixelMin
		var upper: Vector2i = info.pixelMax
		var width: int = upper.x-lower.x+1
		var height: int = upper.y-lower.y+1
		check(vertices.size()==width*height and indices.size()==(width-1)*(height-1)*6,"source and harbor extension form one complete connected integer grid: "+str(profile.id))
		var uv_valid := true
		for vertex_index in vertices.size():
			var column: int = lower.x+vertex_index%width
			var row: int = lower.y+vertex_index/width
			var native: bool = column>=0 and row>=0 and column<int(profile.width) and row<int(profile.height)
			if native: native_vertices += 1
			else:
				added_vertices += 1
				var point: Vector3 = vertices[vertex_index]+island.position
				max_vertex_error=maxf(max_vertex_error,absf(point.y-field.sample_height(point.x,point.z)))
				checked_vertices += 1
			var expected := Vector2((float(column)+.5)/float(profile.width),(float(row)+.5)/float(profile.height))
			if uv[vertex_index].distance_to(expected)>.000001: uv_valid=false
		check(uv_valid,"native pixels and harbor extension share the same immutable source UV basis: "+str(profile.id))
		if lower.y<0:
			var seam_column := clampi(int(profile.width/2),lower.x+1,upper.x-1)
			var seam_vertex: int = -lower.y*width+seam_column-lower.x
			var touches_outside := false
			var touches_inside := false
			for cursor in range(0,indices.size(),3):
				if seam_vertex not in [indices[cursor],indices[cursor+1],indices[cursor+2]]: continue
				for offset in 3:
					var row: int = indices[cursor+offset]/width+lower.y
					if row<0: touches_outside=true
					if row>0: touches_inside=true
			check(touches_outside and touches_inside,"native row-zero border and harbor extension reuse the identical indexed seam vertex: "+str(profile.id))
	check(added_vertices>0 and checked_vertices==added_vertices and max_vertex_error<.00005,"all added source-aligned harbor vertices use the exact retained height authority: max error="+str(max_vertex_error))
	var expected_native := 0
	for profile: Dictionary in profiles: expected_native+=int(profile.width)*int(profile.height)
	check(native_vertices==expected_native,"complete original H grids remain present with no lost or duplicated source pixels")
