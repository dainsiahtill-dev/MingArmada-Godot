extends SceneTree
## Real projected mesh against Camera3D's screen mapping. A mean-plane-only
## footprint must fail the crest coverage and above-horizon fold fixtures.
const Ocean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const Waves = preload("res://modules/contracts/wave_descriptor.gd")
const Coverage = preload("res://modules/scene_engine/ocean/projected_grid_coverage.gd")
var assertions := 0
var failures := 0
var maximum_equivalence_error := 0.0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, why: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",why)

func footprint(ocean: MeshInstance3D,camera: Camera3D,height: float) -> PackedVector2Array:
	var vertices: PackedVector3Array=ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var result := PackedVector2Array()
	for index in vertices.size():
		if index<=ocean._segments or index%(ocean._segments+1) in [0,ocean._segments]:
			var p := ocean.to_global(vertices[index]); p.y=height
			if not camera.is_position_behind(p): result.append(camera.unproject_position(p))
	return Geometry2D.convex_hull(result)

func candidate_equivalence_oracle(ocean: MeshInstance3D,camera: Camera3D,bound: float) -> void:
	# Frozen first GPU candidate: native cached camera rays, affine screen
	# mapping, then one basis transform and normalization per vertex. This is
	# the previous implementation oracle, not the optimized row/column formula.
	var bounds := Coverage.screen_bounds(camera,bound,ocean._projection_padding)
	var arrays: Array=ocean.mesh.surface_get_arrays(0)
	var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var eye := camera.get_camera_transform().origin
	var rays: PackedVector3Array=ocean._local_rays
	var down_left := rays[0];var down_right := rays[ocean._segments];var top_left := rays[ocean._segments*(ocean._segments+1)]
	down_left/=maxf(-down_left.z,0.0001);down_right/=maxf(-down_right.z,0.0001);top_left/=maxf(-top_left.z,0.0001)
	var padding: float=ocean._projection_padding
	var step_x := (down_right-down_left)/(1.0+2.0*padding)
	var step_y := (down_left-top_left)/(1.0+2.0*padding)
	var origin := down_left+step_x*padding-step_y*(1.0+padding)
	var maximum_error := 0.0
	for index in vertices.size():
		var u := uv[index].x;var v := uv[index].y
		var screen := Vector2(lerpf(bounds.position.x,0.5,u*2.0) if u<=0.5 else lerpf(0.5,bounds.end.x,u*2.0-1.0),lerpf(bounds.end.y,0.5,v*2.0) if v<=0.5 else lerpf(0.5,bounds.position.y,v*2.0-1.0))
		var ray := (camera.get_camera_transform().basis*(origin+step_x*screen.x+step_y*screen.y)).normalized()
		var horizontal := Vector2(ray.x,ray.z)
		var radius: float=ocean._fallback_distance
		if ray.y<-0.0001:
			radius=(-eye.y/ray.y)*horizontal.length()
			if ocean._has_maximum_distance:radius=minf(radius,ocean._maximum_distance)
		var expected := Vector2(eye.x,eye.z)+horizontal.normalized()*radius
		maximum_error=maxf(maximum_error,ocean.to_global(vertices[index]).distance_to(Vector3(expected.x,0.0,expected.y)))
	check(maximum_error<0.006,"optimized candidate matches accepted normalized candidate within6mm at3km: "+str(maximum_error))
	maximum_equivalence_error=maxf(maximum_equivalence_error,maximum_error)

func run() -> void:
	var viewport := SubViewport.new(); viewport.size=Vector2i(1260,449); viewport.own_world_3d=true;root.add_child(viewport)
	var camera := Camera3D.new(); viewport.add_child(camera);camera.fov=45.0;camera.far=4000.0;camera.current=true
	var ocean := Ocean.new();viewport.add_child(ocean)
	ocean.configure(camera,null,80,3000.0);ocean.set_projection_padding(0.10)
	var bound := 0.0
	for wave: Dictionary in Waves.original_descriptors(): bound+=absf(float(wave.amplitude))
	for pose: Vector3 in [Vector3(0,9,45),Vector3(0,4.5,90),Vector3(0,38,65)]:
		camera.position=pose;camera.look_at(Vector3.ZERO);ocean.update_projection()
		candidate_equivalence_oracle(ocean,camera,bound)
		for level: float in [-bound,bound]:
			var polygon := footprint(ocean,camera,level)
			for point: Vector2 in [Vector2(2,447),Vector2(630,447),Vector2(1258,447),Vector2(2,350),Vector2(1258,350)]:
				check(Geometry2D.is_point_in_polygon(point,polygon),"wave slab must cover visible near/side point "+str(point)+" eye="+str(pose)+" level="+str(level))
		var vertices: PackedVector3Array=ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var previous := 0.0
		var monotone := true
		for row in ocean._segments+1:
			var p: Vector3=ocean.to_global(vertices[row*(ocean._segments+1)+ocean._segments/2])
			var radius := Vector2(p.x-camera.position.x,p.z-camera.position.z).length()
			monotone=monotone and radius+0.005>=previous
			previous=radius
		check(monotone,"above-horizon rows must not fold back toward observer "+str(pose))
	var before: PackedVector3Array=ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	ocean.set_simulation_time(8.0);ocean.update_projection()
	check(before==ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],"accepted time does not rebuild geometry or change conservative envelope")
	viewport.size=Vector2i(900,1000);ocean.update_projection()
	var polygon := footprint(ocean,camera,bound)
	check(Geometry2D.is_point_in_polygon(Vector2(450,998),polygon),"portrait resize retains crest near coverage")
	viewport.size=Vector2i(1260,449);camera.position=Vector3(0,9,45);camera.look_at(Vector3.ZERO);ocean.update_projection()
	var cache_builds: int=ocean.get_projection_work_diagnostics().rayCacheBuilds
	ocean.set_projection_guard_enabled(false);ocean.update_projection()
	check(not Geometry2D.is_point_in_polygon(Vector2(630,447),footprint(ocean,camera,bound)),"retained baseline reproduces original crest gap")
	ocean.set_projection_guard_enabled(true);ocean.update_projection()
	check(Geometry2D.is_point_in_polygon(Vector2(630,447),footprint(ocean,camera,bound)),"same-time candidate restores coverage via production seam")
	check(ocean.get_projection_work_diagnostics().rayCacheBuilds==cache_builds,"same lens baseline/candidate uses same cached native rays")
	var changed := Waves.original_descriptors();changed[0].amplitude=2.0
	check(ocean.set_wave_descriptors(changed),"new valid physical amplitudes accepted")
	ocean.update_projection()
	check(is_equal_approx(ocean.get_projection_work_diagnostics().waveAmplitudeBound,4.5),"accepted descriptors invalidate conservative bound")
	check(Geometry2D.is_point_in_polygon(Vector2(630,447),footprint(ocean,camera,4.5)),"larger accepted wave profile still covers screen")
	camera.h_offset=2.0;camera.v_offset=1.0;ocean.update_projection()
	check(Geometry2D.is_point_in_polygon(Vector2(630,447),footprint(ocean,camera,4.5)),"camera optical offsets use the actual render eye")
	ocean.transform=Transform3D(Basis(Vector3.UP,0.31).scaled(Vector3(1.2,0.8,1.4)),Vector3(12,-3,7));ocean.update_projection()
	candidate_equivalence_oracle(ocean,camera,4.5)
	viewport.free()
	print("VOYAGE_PROJECTION_COVERAGE_TESTS assertions=",assertions," failures=",failures," maxCandidateError=",maximum_equivalence_error)
	quit(1 if failures else 0)
