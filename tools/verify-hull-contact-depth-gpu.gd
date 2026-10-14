extends SceneTree
## The new local materials only; no tail shader or game entry is changed.
var failures:Array=[]
func _initialize()->void:run.call_deferred()
func quad(parent:Node3D,material:Material,z:float,left:float=-1.0,right:float=1.0)->MeshInstance3D:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(left,-1,z),Vector3(right,-1,z),Vector3(right,1,z),Vector3(left,1,z)])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(.5,.5),Vector2(.5,.5),Vector2(.5,.5),Vector2(.5,.5)])
	arrays[Mesh.ARRAY_COLOR]=PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=material;parent.add_child(node);return node
func pixels(view:SubViewport)->Image:
	for _i in 6:await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL CONTACT DEPTH: ",label)
func run()->void:
	var phase:="current"
	var output_override:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--red":phase="red"
		elif arg.begins_with("--output="):output_override=arg.trim_prefix("--output=")
	var output:="res://docs/migration/evidence/hull-contact-redesign-2026-10-14/depth/"+phase
	if not output_override.is_empty():output=output_override
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output));var records:Array=[]
	for role:String in ["foam","spray"]:
		var view:=SubViewport.new();view.size=Vector2i(128,128);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
		var world:=Node3D.new();view.add_child(world)
		var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.0;camera.near=.1;camera.far=10.0;world.add_child(camera);camera.position=Vector3(0,0,4);camera.look_at(Vector3.ZERO);camera.current=true
		var ocean:=ShaderMaterial.new();var sea_shader:=Shader.new();sea_shader.code="shader_type spatial; render_mode unshaded,cull_disabled,depth_draw_always; void fragment(){ALBEDO=vec3(.02,.12,.5);ALPHA=1.0;}";ocean.shader=sea_shader;quad(world,ocean,.2)
		var opaque:=ShaderMaterial.new();var opaque_shader:=Shader.new();opaque_shader.code="shader_type spatial;render_mode unshaded,cull_disabled;void fragment(){ALBEDO=vec3(0,1,0);}"
		opaque.shader=opaque_shader;var hull:=quad(world,opaque,.4,-.8,-.2)
		var material:=ShaderMaterial.new();material.shader=load("res://modules/scene_engine/water/hull_contact_"+role+".gdshader")
		if phase=="red":var shader:=Shader.new();shader.code=material.shader.code.replace("depth_test_disabled,","");material.shader=shader
		material.render_priority=3;material.set_shader_parameter("strength",1.0);var contact:=quad(world,material,0.0)
		contact.visible=false;var baseline:=await pixels(view);contact.visible=true
		var image:=await pixels(view);image.save_png(output+"/"+role+".png")
		var foam:Color=image.get_pixel(96,64);var hull_color:Color=image.get_pixel(32,64);var base:Color=baseline.get_pixel(96,64)
		check(foam.r>base.r+.015,role+" survives transparent depth-writing ocean")
		check(hull_color.r<.05 and hull_color.g>.95 and hull_color.b<.05,role+" hidden by opaque hull")
		hull.position.z=-.8;var behind:=await pixels(view);behind.save_png(output+"/"+role+"-behind.png")
		check(behind.get_pixel(32,64).r>base.r+.015,role+" survives opaque geometry behind it")
		records.append({"role":role,"base":base.to_html(true),"contact":foam.to_html(true),"opaqueFront":hull_color.to_html(true),"opaqueBehind":behind.get_pixel(32,64).to_html(true)})
		view.free()
	var file:=FileAccess.open(output+"/VERIFICATION.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"records":records,"renderer":RenderingServer.get_current_rendering_method()},"\t"));file.close()
	print("HULL_CONTACT_DEPTH_GPU failures=",failures.size());quit(0 if failures.is_empty() else 1)
