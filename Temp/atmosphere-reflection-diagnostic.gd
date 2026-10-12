extends SceneTree
const World=preload("res://modules/scene_engine/world/world_view.gd")
const Atmosphere=preload("res://modules/scene_engine/fidelity_fx/atmosphere.gd")
const Native=preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var host:=Node3D.new();root.add_child(host)
	var camera:=Camera3D.new();host.add_child(camera);camera.fov=55;camera.far=4000
	camera.position=Vector3(33,27,-39);camera.look_at(Vector3(0,3,0))
	var world:=World.new();host.add_child(world)
	world.configure(func(_x:float,_z:float)->float:return -80.0,[],{"camera":camera,"resolution":8,"chunk_radius":0,"vegetation":false,"island_details":false})
	world.apply_snapshot({"time":0.0})
	var reflection:Camera3D=world.get_ocean().get_reflection_camera()
	var lower:=INF;var outside:=0;var checked:=0
	for mesh:MeshInstance3D in world.get_node("OriginalCloudAndFog").get_children():
		var material:=mesh.material_override as ShaderMaterial
		if not bool(material.get_shader_parameter("source_billboard_enabled")):continue
		var rotation:Basis=material.get_shader_parameter("source_billboard_rotation")
		var original:Basis=Atmosphere.AXES.inverse()*rotation*Atmosphere.AXES
		var rows:Array=[original.x.x,original.y.x,original.z.x,original.x.y,original.y.y,original.z.y,original.x.z,original.y.z,original.z.z]
		var adjusted:Basis=Atmosphere._rotation(Native.billboard_mode0(rows,Atmosphere._camera_basis(reflection)))
		var origin:Vector3=material.get_shader_parameter("source_billboard_origin")
		var relative:Transform3D=material.get_shader_parameter("source_billboard_relative")
		var scale:float=material.get_shader_parameter("source_billboard_scale")
		for point:Vector3 in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var world_point:=origin+adjusted*(relative*point)*scale
			lower=minf(lower,world_point.y);checked+=1
			if not mesh.custom_aabb.grow(0.001).has_point(mesh.global_transform.affine_inverse()*world_point):outside+=1
	var data:Dictionary={"expectedSourceReflectionMinimumY":lower,"verticesChecked":checked,"outsideSourceSphere":outside,"gpuRendered":false}
	var output:=FileAccess.open("res://Temp/atmosphere-reflection-diagnostic.json",FileAccess.WRITE);output.store_string(JSON.stringify(data,"  "));output.close();print(JSON.stringify(data))
	world.dispose();host.free();quit(1 if outside>0 else 0)
