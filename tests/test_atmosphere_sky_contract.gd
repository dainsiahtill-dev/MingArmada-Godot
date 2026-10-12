extends SceneTree
const Atmosphere = preload("res://modules/scene_engine/fidelity_fx/atmosphere.gd")
const Native = preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
const World = preload("res://modules/scene_engine/world/world_view.gd")
var assertions:=0
var failures:=0
func check(value:bool,reason:String)->void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL atmosphere sky: ",reason)
func _initialize()->void: _run.call_deferred()
func _run()->void:
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_fx/manifest.json"))
	var host:=Node3D.new(); root.add_child(host)
	var camera:=Camera3D.new(); host.add_child(camera); camera.fov=55; camera.near=.5; camera.far=4000
	camera.position=Vector3(33,27,-39); camera.look_at(Vector3(0,3,0)); camera.current=true
	var world:=World.new(); host.add_child(world)
	check(world.configure(func(_x:float,_z:float)->float:return -80.0,[],{"camera":camera,"resolution":8,"chunk_radius":0,"vegetation":false,"island_details":false}),"real World owns cloud placement")
	world.apply_snapshot({"time":0.0})
	var clouds:Node3D=world.get_node("OriginalCloudAndFog")
	var on_screen:=0
	var low:=INF
	var viewport:=Rect2(Vector2.ZERO,root.get_visible_rect().size)
	for mesh:MeshInstance3D in clouds.get_children():
		if not String(mesh.name).begins_with("OriginalCloud_"):continue
		check(mesh.material_override.get_shader_parameter("source_billboard_enabled") == true,"each actual cloud binds source per-view billboard frame")
		var box:=Rect2(); var initialized:=false
		for vertex:Vector3 in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var point:=mesh.global_transform*vertex; low=minf(low,point.y)
			if camera.is_position_behind(point):continue
			var screen:=camera.unproject_position(point)
			if not initialized:box=Rect2(screen,Vector2.ZERO); initialized=true
			else:box=box.expand(screen)
		if initialized and box.intersects(viewport):on_screen+=1
	check(on_screen>=3,"ordinary captain camera receives several real source cloud patches, current="+str(on_screen))
	check(low>60.0,"adapted whole cloud groups remain above fleet navigation")
	var asset:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(manifest.atmosphere.assets[0].data_path))
	var source_camera:Dictionary=Atmosphere._camera_basis(camera)
	var meshes:Array=Native.original_meshes(asset,0.0,{},false,source_camera)
	check(meshes[0].has("billboard"),"source traversal exposes actual pre-billboard parent and original descendant transform for each render camera")
	if meshes[0].has("billboard"):
		for state:Dictionary in meshes:
			var frame:Dictionary=state.billboard.parent.duplicate(true)
			frame.rotation=Native.billboard_mode0(frame.rotation,source_camera)
			var recovered:Dictionary=Native.compose_transform(frame,state.billboard.relative)
			check(recovered==state.world,"declared draw frame reconstructs actual original main-camera mesh pose")
	var fog_renderer:=Atmosphere.new()
	check(fog_renderer.configure(host,manifest,{"fog_placements":[Transform3D.IDENTITY]}).get("ok",false),"original fog prototype configures for sampler border contract")
	fog_renderer.apply_snapshot({"time":24.4},camera)
	var fog_nodes:Node3D=host.get_node("OriginalCloudAndFog")
	var clamped:=0
	for mesh:MeshInstance3D in fog_nodes.get_children():
		if not String(mesh.name).begins_with("OriginalGroundFog_"):continue
		var texture:Variant=mesh.material_override.get_shader_parameter("original_clamped_texture")
		check(texture is Texture2D,"each original CC fog material binds a real hardware-clamped texture for every mip")
		if texture is Texture2D:
			clamped+=1
			check(texture.get_image().get_mipmap_count()==8,"clamped hardware sampler preserves all nine original fog mips")
	check(clamped==20,"all original fog meshes receive clamped sampler rather than base-level half-texel UV wrapping")
	fog_renderer.dispose()
	world.dispose();host.free()
	var result:Dictionary={"assertions":assertions,"failures":failures,"projectedCloudMeshes":on_screen,"minimumCloudY":low}
	var output:=FileAccess.open("res://Temp/atmosphere-sky-contract.json",FileAccess.WRITE);output.store_string(JSON.stringify(result,"  "));output.close()
	print("ATMOSPHERE_SKY_CONTRACT assertions=",assertions," failures=",failures);quit(1 if failures else 0)
