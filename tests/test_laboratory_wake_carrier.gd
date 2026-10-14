extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool,detail: String) -> void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL wake carrier: ",detail)
func _initialize() -> void:run.call_deferred()
func check_projection(demo: Node3D) -> void:
	var ocean: MeshInstance3D=demo.get("_ocean")
	var camera: Camera3D=demo.get("_camera")
	check(ocean.mesh is ArrayMesh and ocean.mesh==ocean.get("_projected_mesh"),"displayed mesh is actual production projected owner")
	if not ocean.mesh is ArrayMesh:return
	var arrays: Array=ocean.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var resolution: int=demo.inspection_snapshot().parameters.get("projected_resolution",0)
	check(vertices.size()==(resolution+1)*(resolution+1),"declared resolution equals actual projected vertex inventory")
	var center_index:=int(resolution/2)*(resolution+1)+int(resolution/2)
	var ray:=camera.project_ray_normal(camera.get_viewport().get_visible_rect().size*.5)
	var eye:=camera.global_position
	var expected:=eye+ray*(-eye.y/ray.y)
	check(ocean.to_global(vertices[center_index]).distance_to(expected)<.01,"grid center follows actual Camera3D water-plane projection")
	var finite := true;var maximum_radius:=0.0
	for vertex: Vector3 in vertices:
		finite=finite and vertex.is_finite()
		maximum_radius=maxf(maximum_radius,ocean.to_global(vertex).distance_to(eye))
	check(finite and maximum_radius>384.0,"side-view grid reaches beyond the finite384m comparison edge")
	check(ocean.material_override.get_shader_parameter("wave_count")==5,"carrier change retains authoritative five-wave material")
	check(ocean.get_projection_work_diagnostics().rayCount==vertices.size(),"actual projection work is observable")
func run() -> void:
	var demo=load("res://game/research/demos/wake_flow_experiment.gd").new()
	check(demo.get_default_options().get("carrier_mode")=="projected","wake experiment defaults to real production carrier")
	check(not demo.configure({"carrier_mode":"sphere"}).ok,"unknown carrier mode rejected")
	check(demo.configure({"camera_mode":"side","zoom":.65}).ok,"real side-view fixture configures")
	var viewport:=SubViewport.new();viewport.size=Vector2i(1200,760);viewport.own_world_3d=true;root.add_child(viewport);viewport.add_child(demo)
	check_projection(demo)
	var initial: Dictionary=demo.inspection_snapshot()
	check(initial.get("carrier",{}).get("mode")=="projected" and initial.get("carrier",{}).get("resolution")==80,"receipt identifies actual production-default80 projected carrier")
	var ocean: MeshInstance3D=demo.get("_ocean")
	if ocean.mesh is ArrayMesh:
		var before: PackedVector3Array=ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		demo.set_paused(true);demo.orbit_camera(.15,.02)
		var after: PackedVector3Array=ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		check(before!=after and demo.inspection_snapshot().time==initial.time,"paused orbit reprojects actual mesh without advancing simulation")
		check_projection(demo)
	var configured: Dictionary=demo.reset_experiment({"carrier_mode":"plane","carrier_extent":384.0,"orbit_yaw":0.0,"orbit_pitch":0.0})
	check(configured.ok,"historical plane is an explicit comparison")
	if configured.ok:
		check(demo.get("_ocean").mesh is PlaneMesh and demo.inspection_snapshot().get("carrier",{}).get("mode")=="plane","plane selection reports and shows real finite plane")
		check(demo.inspection_snapshot().camera_transform==initial.camera_transform and demo.inspection_snapshot().native_ship==initial.native_ship,"carrier selection preserves observer and actual native initial state")
	var projected: Dictionary=demo.reset_experiment({"carrier_mode":"projected","projected_resolution":96,"field_enabled":true})
	check(projected.ok,"bounded projected resolution comparison configures with field candidate")
	if projected.ok:
		check_projection(demo)
		check(demo.inspection_snapshot().camera_transform==initial.camera_transform,"field candidate shares baseline projection camera")
		check(demo.set_parameter("projected_resolution",160).get("reset_required",false),"resolution control uses reset instead of replacing live field ownership")
	demo.dispose();viewport.free()
	print("LABORATORY_WAKE_CARRIER_PASS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
