extends "res://tools/verify-interactive-wake-production-gpu.gd"
const Raw=preload("res://modules/physics_engine/ocean/wave_field.gd")
const Profile=preload("res://game/presentation/ships/hull_waterline_profile.gd")
var raw:=Raw.new()
var history:Array=[]
var surface_image:Image
var surface_bounds:Vector4
var relative_candidate:=false
func sample_gpu_height(p:Vector3,t:float)->float:
	var uv:=Vector2((p.x-surface_bounds.x)/(surface_bounds.z-surface_bounds.x),(p.z-surface_bounds.y)/(surface_bounds.w-surface_bounds.y))
	var height:=-20.0
	if uv.x>=0 and uv.x<=1 and uv.y>=0 and uv.y<=1:
		var px:=uv*Vector2(surface_image.get_size()-Vector2i.ONE)
		var i:=Vector2i(mini(int(floor(px.x)),surface_image.get_width()-2),mini(int(floor(px.y)),surface_image.get_height()-2))
		var f:=px-Vector2(i)
		height=lerpf(lerpf(surface_image.get_pixel(i.x,i.y).r,surface_image.get_pixel(i.x+1,i.y).r,f.x),lerpf(surface_image.get_pixel(i.x,i.y+1).r,surface_image.get_pixel(i.x+1,i.y+1).r,f.x),f.y)
	return raw.sample_height(p.x,p.z,t)*smoothstep(0.0,8.0,-height)
func inspect_geometry()->Dictionary:
	var native:Dictionary=scene.runtime.snapshot().naval
	var ship:Node3D=scene.sea.ships[native.playerId]
	var water:MeshInstance3D=scene.sea.world.get_ocean()
	var arrays:Array=water.mesh.surface_get_arrays(0)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var displaced:=PackedVector3Array()
	for p:Vector3 in vertices:
		var wp:Vector3=water.global_transform*p
		wp.y=sample_gpu_height(wp,native.time);displaced.append(wp)
	var cpu_min:=INF;var rendered_min:=INF;var discrepancy:=0.0;var point_count:=0
	var bins:Dictionary={}
	var model:Node3D=ship.get_model()
	for node:Node in model.find_children("*","MeshInstance3D",true,false):
		if str(node.get_meta("damage_surface",""))!="hull":continue
		for surface in node.mesh.get_surface_count():
			for p:Vector3 in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var local:Vector3=model.transform*Profile._relative_transform(node,model)*p
				var bin:=int(floor(local.z))
				if not bins.has(bin) or local.y<bins[bin].y:bins[bin]=local
	for p:Vector3 in bins.values():
		var wp:Vector3=ship.global_transform*p
		var level:float=scene.runtime.sample_water_height(wp.x,wp.z,native.time)
		cpu_min=minf(cpu_min,wp.y-level)
		for k in range(0,indices.size(),3):
			var a:=displaced[indices[k]];var b:=displaced[indices[k+1]];var c:=displaced[indices[k+2]]
			var v0:=Vector2(b.x-a.x,b.z-a.z);var v1:=Vector2(c.x-a.x,c.z-a.z);var v2:=Vector2(wp.x-a.x,wp.z-a.z)
			var det:=v0.cross(v1)
			if absf(det)<.000001:continue
			var u:=v2.cross(v1)/det;var v:=v0.cross(v2)/det
			if u>=0 and v>=0 and u+v<=1:
				var rendered:=a.y+u*(b.y-a.y)+v*(c.y-a.y)
				rendered_min=minf(rendered_min,wp.y-rendered)
				discrepancy=maxf(discrepancy,absf(rendered-level));point_count+=1;break
	return {"time":native.time,"cpu_min_keel_clearance":cpu_min,"rendered_min_keel_clearance":rendered_min,"max_surface_discrepancy":discrepancy,"matched_keel_points":point_count,"ship":native.ships[0],"camera":str(scene.sea.camera.global_transform),"shader_time":water.material_override.get_shader_parameter("simulation_time"),"scope":"Exact uploaded sea triangles reconstructed from shader height texture, excluding bounded +/-0.25m interactive displacement."}
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg=="--relative-candidate":relative_candidate=true
	check(not output.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"fresh output")
	if not failures.is_empty():finish();return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output));output_owned=true;frozen=hashes()
	root.mode=Window.MODE_WINDOWED;root.unresizable=true;root.size=Vector2i(1280,900);root.content_scale_size=root.size
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT;root.gui_disable_input=true;root.unfocusable=true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene=Practice.new();scene.startup_options={"mode":"sail","staged":true};scene.settings_storage=Settings.new("user://tests/buoyancy-%d.json"%OS.get_process_id())
	root.add_child(scene);await process_frame;await process_frame
	scene.set_process(false);scene.set_physics_process(false);isolate_input(scene)
	check(scene.startup_receipt.get("ok",false),"actual practice initialized")
	if not failures.is_empty():finish();return
	scene.activate_entry();scene.interface.visible=false
	var native:RefCounted=scene.runtime.simulation.encounter
	var player:Dictionary=native._ship("player")
	if relative_candidate:player.core=load("res://game/research/candidates/water_relative_ship_dynamics.gd").new()
	var start:={"x":-314.0,"z":-38.0}
	player.core.configure({"kind":"fuchuan","position":start,"heading":PI/2,"sailDeployment":0.0},scene.heights.sample_height,native.ocean)
	player.state.sailDeployment=0.0;player.previous=native._visual_core(player.core)
	scene.sea.set_camera_controller(func():
		var p:Vector3=scene.sea.ships["player"].global_position
		scene.sea.camera.global_position=Vector3(p.x+32,12,p.z+16);scene.sea.camera.look_at(Vector3(p.x,1,p.z)))
	var ocean:MeshInstance3D=scene.sea.world.get_ocean()
	surface_image=ocean._shore_texture.get_image();surface_bounds=ocean._shore_bounds
	for i in 13:
		if i>0:await ticks(180)
		await settle()
		var row:=inspect_geometry();history.append(row)
		await capture("shore-%02d"%i)
		print("BUOYANCY_GPU_SAMPLE ",JSON.stringify(row))
	var file:=FileAccess.open(output+"/GEOMETRY.json",FileAccess.WRITE);file.store_string(JSON.stringify(history,"\t"));file.close()
	finish()
