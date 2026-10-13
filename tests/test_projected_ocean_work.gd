extends SceneTree
## Actual Camera3D is the oracle; no replacement projection math in the test.
## Root alone runs this test. Missing cache diagnostic is an explicit baseline RED.
const Ocean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const FLOAT_EPSILON := 1.1920928955078125e-7
var assertions := 0
var failures := 0
var exact_vertices := 0
var total_vertices := 0
var maximum_error := 0.0

func check(ok: bool, detail: String) -> bool:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)
	return ok

func _initialize() -> void: _run.call_deferred()

func _work(ocean: MeshInstance3D) -> Dictionary:
	if not ocean.has_method("get_projection_work_diagnostics"): return {"rayCacheBuilds":-1,"rayCount":0}
	return ocean.call("get_projection_work_diagnostics")

func _cache_count(ocean: MeshInstance3D, expected: int, detail: String) -> void:
	if ocean.has_method("get_projection_work_diagnostics"):
		check(int(_work(ocean).rayCacheBuilds)==expected,detail)

func _geometry(ocean: MeshInstance3D,camera: Camera3D,label: String) -> void:
	var arrays: Array = ocean.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var padding: float = ocean.get("_projection_padding")
	var eye := camera.global_position
	var passed := vertices.size() == uvs.size()
	var case_error := 0.0
	for index in vertices.size():
		var padded := (uvs[index]-Vector2(0.5,0.5))*(1.0+padding*2.0)+Vector2(0.5,0.5)
		var screen := Vector2(padded.x*viewport_size.x,(1.0-padded.y)*viewport_size.y)
		var direction := camera.project_ray_normal(screen)
		var distance: float = ocean.get("_fallback_distance")
		if absf(direction.y) >= 1.0e-4:
			var intersection := -eye.y/direction.y
			if intersection>0.0 and is_finite(intersection):
				distance=minf(intersection,float(ocean.get("_maximum_distance"))) if ocean.get("_has_maximum_distance") else intersection
		var world_point := eye+direction*distance; world_point.y = 0.0
		var expected := ocean.to_local(world_point)
		var error := expected.distance_to(vertices[index])
		# Preserve exact output where arithmetic permits it; at most eight
		# Float32 relative epsilons otherwise (about 3mm at a 3km radius).
		var tolerance := maxf(0.0001,expected.length()*8.0*FLOAT_EPSILON)
		passed = passed and vertices[index].is_finite() and error<=tolerance
		if vertices[index] == expected: exact_vertices += 1
		total_vertices += 1; case_error=maxf(case_error,error)
	maximum_error=maxf(maximum_error,case_error)
	check(passed,"actual camera-ray geometry, "+label+", max error="+str(case_error))

func _layout_change(ocean: MeshInstance3D,camera: Camera3D,label: String) -> void:
	var before: int = _work(ocean).rayCacheBuilds
	ocean.update_projection()
	_cache_count(ocean,before+1,"changed projection layout rebuilds local rays exactly once: "+label)
	_geometry(ocean,camera,label)

func _run() -> void:
	var viewport := SubViewport.new(); viewport.size=Vector2i(1600,900); viewport.own_world_3d=true; root.add_child(viewport)
	var camera := Camera3D.new(); viewport.add_child(camera); camera.current=true
	camera.position=Vector3(30,38,60); camera.look_at(Vector3.ZERO)
	var ocean: MeshInstance3D=Ocean.new(); viewport.add_child(ocean)
	ocean.configure(camera,null,80,3000.0)
	ocean.configure_reflection(camera); ocean.enable_surface_optics(true)
	_geometry(ocean,camera,"baseline perspective oracle before cache guard")
	check(ocean.has_method("get_projection_work_diagnostics"),"projection caches expose rayCacheBuilds/rayCount; current per-vertex reconstruction is RED")
	var initial := _work(ocean)
	if ocean.has_method("get_projection_work_diagnostics"):
		check(initial.get("rayCount",0)==6561 and initial.get("rayCacheBuilds",0)>0,"default 81x81 layout has one cached ray per original vertex")
	var topology: PackedInt32Array=ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var normals: PackedVector3Array=ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array=ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var original_mesh := ocean.mesh
	var original_rays: int = initial.rayCacheBuilds
	for pose: Vector3 in [Vector3(32,39,63),Vector3(-170,65,105),Vector3(80,0.002,-20)]:
		camera.position=pose; camera.look_at(Vector3(20,0,-30)); ocean.update_projection()
		_cache_count(ocean,original_rays,"moving/rotating camera reuses exact local ray layout")
		_geometry(ocean,camera,"camera pose "+str(pose))
	for target: Vector3 in [Vector3(0,61,-1000),Vector3(0,160,-1),Vector3(80,-1000,-40)]:
		camera.position=Vector3(0,60,0); camera.look_at(target); ocean.update_projection()
		_cache_count(ocean,original_rays,"extreme camera angles retain cached local ray layout")
		_geometry(ocean,camera,"horizon/up/down angle "+str(target))
	ocean.transform=Transform3D(Basis(Vector3.UP,0.31).scaled(Vector3(1.2,0.8,1.4)),Vector3(12,-3,7)); ocean.update_projection()
	_cache_count(ocean,original_rays,"transformed ocean hoists inverse without rebuilding camera rays")
	_geometry(ocean,camera,"translated rotated scaled ocean")
	camera.fov=71.0; _layout_change(ocean,camera,"fov")
	camera.keep_aspect=Camera3D.KEEP_WIDTH; _layout_change(ocean,camera,"keep aspect")
	viewport.size=Vector2i(900,1600); _layout_change(ocean,camera,"viewport portrait resize")
	viewport.size_2d_override=Vector2i(480,720); viewport.size_2d_override_stretch=false
	_layout_change(ocean,camera,"fixed viewport override without stretch")
	viewport.size=Vector2i(1800,1600); camera.position.x+=3.0
	_layout_change(ocean,camera,"actual render size changes behind fixed visible override")
	viewport.size_2d_override=Vector2i.ZERO; viewport.size=Vector2i(900,1600)
	_layout_change(ocean,camera,"restore original viewport dimensions")
	camera.near=1.25; _layout_change(ocean,camera,"near plane")
	camera.far=5000.0; _layout_change(ocean,camera,"far plane")
	camera.set_frustum(4.0,Vector2(0.23,-0.17),0.7,4500.0); _layout_change(ocean,camera,"frustum mode and offset")
	camera.frustum_offset=Vector2(-0.31,0.21); _layout_change(ocean,camera,"changed frustum offset")
	camera.set_orthogonal(140.0,0.7,4500.0); _layout_change(ocean,camera,"orthogonal")
	camera.size=190.0; _layout_change(ocean,camera,"orthogonal size")
	ocean.set_projection_padding(0.10); _layout_change(ocean,camera,"padding")
	var rays_before_time: int=_work(ocean).rayCacheBuilds
	for seconds: float in [12.25,12.25,8.0]:
		ocean.set_simulation_time(seconds); ocean.update_projection()
		var material: ShaderMaterial=ocean.material_override
		check(material.get_shader_parameter("simulation_time")==seconds and material.get_shader_parameter("u_time")==seconds,"native accepted time including pause/rewind reaches original material")
		check(ocean.get_surface_optics_diagnostics().accepted_time==seconds,"real reflection retains accepted time")
	_cache_count(ocean,rays_before_time,"time/rewind cannot rebuild unchanged camera-local rays")
	var after: Array=ocean.mesh.surface_get_arrays(0)
	check(ocean.mesh==original_mesh and after[Mesh.ARRAY_INDEX]==topology and after[Mesh.ARRAY_NORMAL]==normals and after[Mesh.ARRAY_TEX_UV]==uv,"mesh identity, topology, normals and UV layout retained")
	check(ocean.get_surface_optics_diagnostics().reflection_enabled and ocean.get_reflection_viewport().size==Vector2i(768,1365),"requested native reflection target/quality remains active at resized aspect")
	# Keep the original distance clip and unbounded/horizon fallback algorithm.
	camera.set_perspective(55.0,0.1,8000.0); camera.position=Vector3(0,60,0); camera.look_at(Vector3(0,61,-1000))
	ocean.configure(camera,null,16,INF); ocean.set_projection_padding(0.10); ocean.update_projection()
	_geometry(ocean,camera,"unbounded positive-plane intersection and horizon fallback")
	ocean.configure(camera,null,16,20.0); ocean.update_projection()
	_geometry(ocean,camera,"short bounded distance clip")
	viewport.free(); _finish()

func _finish() -> void:
	print("PROJECTED_OCEAN_WORK_TESTS assertions=",assertions," failures=",failures," exactVertices=",exact_vertices," totalVertices=",total_vertices," maxVertexError=",maximum_error," tolerance=8*float32-epsilon-relative-or-0.1mm")
	quit(1 if failures else 0)
